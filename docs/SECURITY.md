# Security — threat model and cryptographic design

Reference implementation: `core/arcanum-crypto`.

## Goals

1. **Zero-knowledge**: the server stores only encrypted data. A full compromise of the server (database, code, TLS) reveals neither passwords nor vault contents.
2. **Resistance to offline brute force**: even with a weak master password, a stolen database cannot be attacked thanks to the *Secret Key*.
3. **Integrity and context**: the server cannot modify, move, swap or replay old versions of ciphertexts without the client noticing.
4. **No backdoor**: access can be recovered only with the Emergency Kit.

## Out of scope

- A compromised user device while the vault is unlocked (malware with memory access, keyloggers).
- Sophisticated physical attacks on secure hardware (Secure Enclave, StrongBox, TPM).
- Deletion of data by the server (detectable, not preventable: mitigated by the local copy).

## Primitives

| Purpose | Algorithm | Crate |
|---|---|---|
| Password stretching | Argon2id v1.3 (default 64 MiB, t=3, p=1) | `argon2` |
| Key combination | HKDF-SHA256 | `hkdf`, `sha2` |
| Authenticated encryption | XChaCha20-Poly1305, random 192-bit nonce | `chacha20poly1305` |
| Randomness | Operating system CSPRNG | `rand_core::OsRng` |
| Memory hygiene | zeroing on drop | `zeroize` |

## Key hierarchy

```
master password ──Argon2id(salt)──┐
                                  ├─ HKDF-SHA256(salt) ─┬─ info "pm/muk/v1"  ─► MUK
Secret Key (128 bit, device only) ┘                     └─ info "pm/auth/v1" ─► Auth Key (login only)
MUK          ──wrap──► Account Key (256 bit, random)
Account Key  ──wrap──► Vault Key   (one per vault)
Vault Key    ──wrap──► Item Key    (one per item)
Item Key     ──encrypt─► item contents
```

- **Password change**: re-encrypts only the Account Key with a new salt, without re-encrypting the data (`account::change_password`).
- **KDF parameters**: stored on the server together with the encrypted Account Key. The client **rejects** values below the OWASP minimum (19 MiB, t=2) or above reasonable limits, so a malicious server can force neither a downgrade nor a DoS.

## Ciphertext format

```
version (1 B) ‖ nonce (24 B) ‖ ciphertext ‖ Poly1305 tag (16 B)
```

The version byte is authenticated. The associated data (AAD) is built with `Aad`: a domain label followed by length-prefixed fields.

| Object | Label | Bound fields |
|---|---|---|
| Account Key | `pm/account-key/v1` | account_id |
| Vault Key | `pm/vault-key/v1` | vault_id |
| Item Key | `pm/item-key/v1` | vault_id, item_id |
| Item | `pm/item/v1` | vault_id, item_id, revision |
| Server link (URL, token) | `pm/sync-link/v1` | account_id |
| Device name | `pm/device-name/v1` | account_id |

As a result, a ciphertext cannot be moved to another vault or item. Nor can it be replayed as a different revision or swapped with a ciphertext of another type.

An item's optional expiry date (`expires_on`) is stored inside the encrypted item blob like every other field, and is omitted when unset, so the server cannot see which items expire or when. An older app version that rewrites an item drops the field, so update all devices together. The encrypted backup carries the expiry date; CSV export and import do not.

## Secret Key and Emergency Kit

- 128 random bits generated at sign-up, shown as `PM1-XXXXXX-XXXXX-XXXXX-XXXXX-XXXXX` (base32).
- When reading it back, parsing tolerates upper/lower case, dashes, spaces and the `0/O`, `1/I`, `8/B` mix-ups.
- It is stored only on the devices (system keychain; on Linux the Secret Service, e.g. GNOME Keyring or KWallet, through libsecret) and on the printed Emergency Kit. **It is never sent to the server.**
- A new device gets it via QR code from an already authorized device, or from the Emergency Kit.

## Login identifier

- The server knows an account only by its **login id**: `HKDF-SHA256(IKM = Secret Key, info "pm/login-id/v1")`, 32 bytes in base64url (`kdf::login_id`). No email or username is stored.
- There is nothing extra to remember: every new device already needs the Secret Key, and the login id is recomputed from it.
- It carries the Secret Key's 128 bits of entropy, so it can't be guessed. That rules out account enumeration, squatting someone else's name, and lockouts aimed at a specific user (blocking an account requires its Secret Key).
- HKDF is one-way: the login id reveals nothing about the Secret Key, and its label keeps it independent of the MUK and the Auth Key.
- Losing the Secret Key already meant losing the account; the login id adds no new way to lose it.

## Server authentication

- **OPAQUE** (`opaque-ke` 4, Ristretto255 + TripleDH + SHA-512 suite). The OPAQUE "password" is the **Auth Key**, derived from the same Argon2id run but with an HKDF label different from the MUK's.
  - The server never receives the master password or the Secret Key.
  - Nor does it receive a hash that can be brute-forced: the Auth Key contains the 128 bits of the Secret Key.
  - Since the Auth Key is already hardened by Argon2id, OPAQUE's internal stretching function is the identity.
- **Role separation:** knowing the Auth Key does not help compute the MUK. The OPAQUE session key and export key are not used to encrypt anything.
- **Prelogin:** returns the KDF parameters and salt for the login id. For non-existent ids it answers with fake but deterministic values (HMAC with a server secret). Login fails the same way for an unknown account, a wrong password or a wrong Secret Key.
- **Attempt limit:** with OPAQUE it is the client that notices a wrong password, so the server counts every well-formed `login/start` as an attempt and resets the count only after a successful sign-in (10 attempts every 15 minutes per login id). Malformed OPAQUE messages are rejected without counting. Since the login id can't be guessed, the limit only matters to someone holding a stolen Emergency Kit.
- **Per-IP limits** (in memory, bounded; IPv6 addresses are grouped by /64): 60 requests per minute on prelogin and login, 20 per hour on registration, 600 per minute on the whole API. Unauthenticated request bodies are capped at 64 KiB (32 MiB only for item uploads), requests time out after 30 seconds and at most 256 run at once.
- **Registration policy** (`ARCANUM_REGISTRATION`): `invite` (default: single-use codes created by the operator, stored as SHA-256 hashes, consumed in the same transaction that creates the account), `open` (public instances) or `closed`. A per-account item quota (`ARCANUM_MAX_ITEMS_PER_ACCOUNT`) bounds what an open registration can cost.
- **Sessions:** random 256-bit bearer tokens. The server stores only their SHA-256 hash, with a 90-day expiry renewed on every use.
  - Each session corresponds to a device and can be revoked. The device name is encrypted by the client with the Account Key, so the server can't read it (it is set right after sign-in, once a new device has the key).
  - A password change signs out every other device.
  - On the client the token is stored encrypted with the Account Key.
- **TLS required:** the client accepts plain HTTP only towards local development hosts. URLs are analyzed with a real parser and those carrying credentials are rejected, to prevent tricks like `http://localhost@evil.com`.

## Synchronization

- For each item the server stores: id, vault, revision, encrypted Item Key, ciphertext, deletion flag and modification date. It sees no titles, usernames, URLs, passwords or notes.
- **Pull:** uses a monotonic cursor (a global sequence). Pushes from the same account are serialized with an advisory lock, so a concurrent read cannot skip changes.
- **Push:** optimistic concurrency. A write is accepted only if the client's base revision matches the server's; otherwise the server returns its own copy as a conflict.
- **Conflicts:** resolved on the client, after decryption:
  - an edit wins over a deletion;
  - between two edits the most recent wins, and the other version is kept as a new "… (conflitto)" item, so no data is lost.
- **Tampered remote copies:** a copy that does not decrypt (AEAD failure) is ignored and overwritten by the local version.
- **Password changed on another device:** when a device reconnects, it accepts the account's new keys only if they open **the same** Account Key. The server therefore cannot replace the keys with its own.

## Quick unlock (biometrics)

- **How it works:** when you enable it, the core generates a random 256-bit secret and uses it to encrypt the Account Key (label `pm/quick-unlock/v1`). The secret does not stay in the database: the app hands it to the system's protected storage.
  - **iOS/macOS:** a keychain item protected by the Secure Enclave and bound to the fingerprints or face enrolled at that moment (`biometryCurrentSet`). If a new fingerprint or face is enrolled, the secret becomes unusable.
  - **Android:** a Keystore key that requires strong (class 3) biometrics on every use.
  - **Windows:** the secret is encrypted with DPAPI (bound to the Windows user) and released after a Windows Hello check. This is a **consent confirmation**, not a hardware binding: malware running as the signed-in user could read it. The same malware, however, could also log keystrokes while you type the master password.
  - **Linux:** not available. There is no common biometric API on Linux desktops, so the option is not offered and the vault is always unlocked with the master password.
- **Master password still required:** it is asked for at least every 14 days anyway, and quick unlock is turned off automatically on every password change, whether local or synced from another device.
- **Invalid secret:** if the stored secret no longer matches (for example after re-enabling), quick unlock is turned off and the app falls back to the password.

## Autofill

- **Android:** the autofill service (`ArcanumAutofillService`) never reads the vault. It recognizes login fields (autofill hints, HTML attributes in browsers, input type, ids and labels) and offers a single entry, "Sblocca Arcanum" (Unlock Arcanum).
  - Tapping it opens `AutofillActivity`: there the user unlocks, with password or biometrics, and **explicitly chooses** which credential to use. Only the chosen credential goes back to the requesting app.
  - Only credentials with a saved URL on the same domain, or on a subdomain of it with a label boundary, are "suggested": `evil-example.com` does not match `example.com`. For native apps the meaningful parts of the package name count.
  - Filling a site for which the credential is not saved requires an explicit confirmation: this is the defense against phishing.
  - The app's own screens are never filled.
  - It is enabled from Android Settings → Passwords & autofill, or from the "Attiva compilazione automatica" (Enable autofill) entry in the app menu. In Chrome you also have to pick *Settings → Autofill services → Autofill using another service*.
  - Verified on the emulator (Android 16, Chrome) with a login page: unlock, choice of the suggested credential, filling of email and password.
- **Windows and Linux** (there is no system autofill API): `Ctrl+Alt+P` brings the vault to the front with search active; Enter copies the password of the first result, which is cleared from the clipboard after 30 seconds, and minimizes the window. On Linux the global shortcut needs X11 (keybinder); under Wayland it is not registered and the app works without it.
- **iOS/macOS:** the AutoFill Credential Provider extension is not implemented yet, because it needs a Mac with Xcode.
- **Browsers (Chrome, Opera, Safari):** through the Arcanum extension and the desktop app, described in the next section.

## Browser extension

The extension (`extension/`) fills saved logins, suggests generated passwords and offers to save new or changed ones. It holds **no vault data and no vault keys**: every credential comes from the running desktop app on macOS, Windows or Linux, and only while the vault is unlocked. Unlocking, sync and storage stay in the app and the Rust core.

- **Transport:** the app listens on `127.0.0.1` only (ports 47613–47615), never on other interfaces. Native messaging is not used: a sandboxed macOS app cannot install its manifests into browser profiles, and a native host would still have to authenticate whoever launches it.
- **No TLS, end-to-end encryption instead:** a certificate for a loopback address would have to be self-signed and trusted system-wide. Every request and response after pairing is **AES-256-GCM** under a per-browser 256-bit key, with a random 96-bit nonce. The associated data binds the direction (`pm/bridge-req/v1` or `pm/bridge-res/v1`) and the browser's id, so a request cannot be replayed as a response or redirected to another browser. Reading loopback traffic (which already needs root/admin) shows only ciphertext.
- **Pairing** (`core/arcanum-bridge`):
  - It starts only from the app ("Browser collegati" → "Collega browser"). That opens a 120-second window that accepts a single pending request; outside it, pairing requests are refused.
  - Browser and app run an ephemeral **X25519** exchange. Both derive, with HKDF-SHA256 over a transcript hash of the two public keys, the key (`pm/bridge-key/v1`) and a 6-digit code (`pm/bridge-code/v1`).
  - **Commit, then reveal:** the browser first sends only `SHA-256("pm/bridge-commit/v1" ‖ its public key ‖ 32 random bytes)`. It reveals the key and the nonce only after it has received the app's key, and the app checks them against the commitment. A man in the middle therefore has to fix its keys before it can see the other side's, and gets a matching code with probability 10⁻⁶. Without the commitment it could try about a million keys in seconds until the codes matched.
  - **The code is typed, not compared:** the browser shows the code and the user types it into the app, which never displays it. It accepts three attempts, then rejects the pairing. A local process that starts a pairing before the real browser cannot get approved: the user has no code of its to type.
  - The key is never shown or typed, so it cannot be brute-forced offline or online.
  - X25519 was preferred to P-256 because the RustCrypto P-256 version compatible with this workspace would bring `crypto-bigint` 0.5 (RUSTSEC-2026-0387, non-constant-time) onto a live path.
- **Replay:** each request carries a random id and a timestamp. The app rejects timestamps more than 60 seconds away and ids already seen. The extension discards a response whose id is not its request's.
- **Web pages:**
  - Pages can send requests to `127.0.0.1`, but the app refuses any `Origin` that is not a `chrome-extension://` or `safari-web-extension://` origin.
  - It refuses any `Host` other than `127.0.0.1:<port>`, which stops DNS rebinding.
  - A page cannot produce a valid ciphertext anyway: at most it learns that the app is running.
  - No extension file is web-accessible. The extension's element (`<arcanum-ui>`) is added only to pages where it shows an icon or a banner, so a page can detect the extension only once it has a login form the user interacts with.
- **Scripted events are ignored:**
  - A submit, click or Enter counts only when the browser dispatched it (`isTrusted`) and the page has a recent user gesture (`navigator.userActivation`). A page cannot submit guesses to learn whether they match a saved password, nor queue an update with a password of its choice.
  - Clicks on the extension's own icon, menu and banner must be trusted too, and the banner's host is styled inline with `!important` (re-asserted on change), so a page cannot hide it over a decoy button.
  - Buttons inside a form never trigger a capture (its submit event does), so an eye toggle never saves a half-typed password.
  - **Residual:** for a few seconds after a genuine click, a page script still has the gesture and could submit values of its choice. The result is only a banner the user must still confirm.
- **Auto-lock:** only actions that follow a click in the extension's UI (`fill`, `save`, `update`) count as activity. Listing and checking, which a page can cause, do not postpone the vault's auto-lock.
- **Port squatting:** another process on a port cannot decrypt requests and cannot complete a pairing. The extension only trusts a port that answers as Arcanum, re-probes when a reply is not the app's, and forgets its pairing only on `unknown_client` from a port that answers as Arcanum.
- **Phishing:**
  - The page URL always comes from the browser, never from the page. A content script always acts on its own tab, and only the popup may name the tab it acts on.
  - Only logins whose saved URL matches that host, or a subdomain on a label boundary, are listed or filled, and `fill` and `update` are refused for any other site.
  - Filling happens only on a click in the extension's own menu or popup, never on page load, and only in the top frame. The menu lives in a closed shadow root that the page cannot read.
  - A fill started from the popup goes from the background straight to the tab's top frame, bound to the host it was checked against. If the tab has navigated meanwhile, the content script drops it, and the password never goes back to the popup.
- **Saving:** a submitted username and password are kept in the browser's session storage (memory only) for at most 120 seconds. Expired entries are swept on every message, and a tab's entry is dropped when the tab closes. Only the background sends them to the app, encrypted.
- **Keys:**
  - On the app side, browser keys live in the system keychain.
  - In the browser, the key's 32 bytes are kept in IndexedDB of the extension's own origin and imported as a **non-extractable** WebCrypto key for each request. Content scripts, which run in the page's renderer, can read `storage.local` but cannot open that database. The bytes are stored rather than a `CryptoKey` because Safari's background hangs when it structured-clones a `CryptoKey` into IndexedDB; Chrome writes a stored `CryptoKey`'s key material to disk unencrypted anyway, so on disk the protection is the same: the user's account and file permissions.
  - "Revoca" in the app deletes the browser's key. Its next request gets `unknown_client`, and the extension forgets the pairing.
- **Residual risk:** malware running as the user can use the extension's key through its profile and ask for credentials while the vault is unlocked. That is the "compromised device" case, already out of scope, and the same holds for any native-messaging design.

## Import and export

- **Encrypted backup:** a JSON file holding one XChaCha20-Poly1305 envelope. Its key is `HKDF-SHA256(salt, Argon2id(password, salt), info = "pm/backup/v1")`, with a random 16-byte salt and the same Argon2id parameters as the account (64 MiB, t=3), stored in the file.
  - The key depends on the backup password **only**, not on the Secret Key: the file has to be restorable into any account. Its password is therefore the only thing protecting it, and it is chosen at export time (at least 10 characters).
  - On import, KDF parameters outside the accepted range are refused, so a crafted file can neither downgrade the derivation nor exhaust memory. The envelope's associated data binds the format version and the salt.
- **Plain CSV:** readable by browsers and other password managers, and by anyone who gets the file. The app says so before saving it. Nothing is written until the user picks a destination in the system's save dialog.
- **Import:** files exported by Arcanum, Chrome/Edge/Opera, Bitwarden (JSON, CSV), 1Password (CSV) and KeePass (CSV, KeePass 2 XML) are parsed in the Rust core, in memory. The app shows how many items are new before adding anything; items already in the vault are skipped. Imported items are encrypted and synced like any other.
- **Android/iOS:** the vault normally locks as soon as the app goes to the background. While the system's file dialog is open on the user's request it stays unlocked, otherwise the import or export could not complete; the inactivity timer still applies.

## Site icons

- **Source:** for a login with a URL, the app asks the site itself for `https://<host>/favicon.ico`. No third-party icon service is involved, so nobody else learns the list of sites; each site sees one request from the device's IP address, the same it sees when the user visits it.
- **Limits:** HTTPS only; redirects are followed only within the same site; at most 256 KiB; the body must start like an image (ICO, PNG, JPEG, GIF, BMP, WebP). IP addresses and single-label hosts (`localhost`, intranet names) are never asked.
- **No disk cache:** icons live in memory and are dropped when the vault locks. A cache on disk would tell anyone who can read the disk which sites are in the vault, which the encrypted database does not.
- **Opt-out:** "Nascondi icone dei siti" (Hide site icons) in the app menu stops every request.

## Generator and TOTP

- **Generator:** uses the system CSPRNG with uniform sampling (rejection sampling, no modulo bias). Every selected character set appears at least once. Passphrases use the EFF Large Wordlist (7776 words, about 12.9 bits per word).
- **TOTP:** 2FA keys are item fields, so they are encrypted and synced like everything else. Codes are computed locally per RFC 6238, verified against the official test vectors. Keys shorter than 80 bits are rejected.

## Known residual risks

- **Session token theft:** whoever holds the token can read the ciphertexts and write bogus data, which clients will discard because it does not decrypt. They **cannot** change the password: `/password/finish` also requires a fresh OPAQUE login with the current password, verified by the server.
- **Stolen Emergency Kit:** it reveals the login id, so the thief can try master passwords online, slowed down by the per-account and per-IP limits. Choose a strong master password and keep the kit safe.
- **Open registration:** on `open` servers anyone can create accounts. They can't touch other people's data, and quotas and per-IP limits bound the cost; the operator removes abusive accounts with `arcanum-server account delete`.
- **Metadata:** the server still sees client IP addresses, request times, item counts and ciphertext sizes. Its logs contain IP addresses (personal data under the GDPR): keep them only as long as needed.
- **Modification dates come from the client:** a malicious server could alter them and influence which version wins a conflict, but the losing version is still kept as a copy.
- **Rate limits are in memory:** with multiple server instances they must move to the database or the reverse proxy.

## Development requirements

- `unsafe_code = "forbid"` applies across the workspace, and `clippy::unwrap_used` is denied outside tests.
- Decryption errors are indistinguishable (`CryptoError::Decrypt`) so as not to create oracles.
- Every new data format requires a new, versioned domain label.
- CI runs `cargo deny` (advisories, licenses, sources; policy in `deny.toml`) and `cargo audit` on both workspaces; Dependabot proposes weekly updates. Still to add: fuzzing (`cargo fuzz`) on `aead::open` and on parsing.
