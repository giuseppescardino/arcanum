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

## Secret Key and Emergency Kit

- 128 random bits generated at sign-up, shown as `PM1-XXXXXX-XXXXX-XXXXX-XXXXX-XXXXX` (base32).
- When reading it back, parsing tolerates upper/lower case, dashes, spaces and the `0/O`, `1/I`, `8/B` mix-ups.
- It is stored only on the devices (system keychain) and on the printed Emergency Kit. **It is never sent to the server.**
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
- **Attempt limit:** with OPAQUE it is the client that notices a wrong password, so the server counts every well-formed `login/start` as an attempt and resets the count only after a successful sign-in (10 attempts every 15 minutes per login id). Malformed OPAQUE messages are rejected without counting, and only existing accounts are tracked, so random login ids can't fill the limiter. Since the login id can't be guessed, the limit only matters to someone holding a stolen Emergency Kit.
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
- **Windows** (there is no system autofill API): `Ctrl+Alt+P` brings the vault to the front with search active; Enter copies the password of the first result, which is cleared from the clipboard after 30 seconds, and minimizes the window.
- **iOS/macOS:** the AutoFill Credential Provider extension is not implemented yet, because it needs a Mac with Xcode.

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
