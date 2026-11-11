// Pairing and envelope crypto, mirroring core/arcanum-bridge with WebCrypto:
// X25519 + HKDF-SHA256 for pairing, AES-256-GCM for messages.

const enc = new TextEncoder();
const dec = new TextDecoder();
const subtle = globalThis.crypto.subtle;

const PAIR_LABEL = enc.encode('pm/bridge-pair/v1');
const KEY_INFO = enc.encode('pm/bridge-key/v1');
const CODE_INFO = enc.encode('pm/bridge-code/v1');
const AAD_LABEL = { req: 'pm/bridge-req/v1', res: 'pm/bridge-res/v1' };

// PKCS#8 header for a raw X25519 private key (RFC 8410).
const PKCS8_X25519 = Uint8Array.from([0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x6e, 0x04, 0x22, 0x04, 0x20]);

const concat = (...parts) => {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let o = 0;
  for (const p of parts) {
    out.set(p, o);
    o += p.length;
  }
  return out;
};

export const fromHex = (hex) => Uint8Array.from(hex.match(/../g) ?? [], (b) => parseInt(b, 16));
export const toB64 = (bytes) => btoa(String.fromCharCode(...bytes));
export const fromB64 = (b64) => Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));

async function withPublic(privateKey) {
  const jwk = await subtle.exportKey('jwk', privateKey);
  const pub = fromB64(jwk.x.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (jwk.x.length % 4)) % 4));
  return { privateKey, publicRaw: pub };
}

/** Fresh ephemeral X25519 key pair: { privateKey, publicRaw (32 bytes) }. */
export async function generateKeyPair() {
  const kp = await subtle.generateKey({ name: 'X25519' }, true, ['deriveBits']);
  return { privateKey: kp.privateKey, publicRaw: new Uint8Array(await subtle.exportKey('raw', kp.publicKey)) };
}

/** Key pair from a fixed scalar, for test vectors only. */
export async function keyPairFromScalar(scalar) {
  const key = await subtle.importKey('pkcs8', concat(PKCS8_X25519, scalar), { name: 'X25519' }, true, ['deriveBits']);
  return withPublic(key);
}

/**
 * Derives the message key and the 6-digit code. `extPub`/`appPub` fix the
 * transcript order; `peer` is the other side's public key.
 */
export async function derive(privateKey, extPub, appPub, peer) {
  const peerKey = await subtle.importKey('raw', peer, { name: 'X25519' }, false, []);
  const shared = await subtle.deriveBits({ name: 'X25519', public: peerKey }, privateKey, 256);
  const th = new Uint8Array(await subtle.digest('SHA-256', concat(PAIR_LABEL, extPub, appPub)));
  const ikm = await subtle.importKey('raw', shared, 'HKDF', false, ['deriveBits']);
  const hkdf = (info, bits) => subtle.deriveBits({ name: 'HKDF', hash: 'SHA-256', salt: th, info }, ikm, bits);
  const keyRaw = new Uint8Array(await hkdf(KEY_INFO, 256));
  const codeNum = new DataView(await hkdf(CODE_INFO, 32)).getUint32(0) % 1_000_000;
  return { keyRaw, key: await importKey(keyRaw), code: String(codeNum).padStart(6, '0') };
}

export function importKey(raw) {
  return subtle.importKey('raw', raw, 'AES-GCM', false, ['encrypt', 'decrypt']);
}

const aad = (client, dir) => enc.encode(AAD_LABEL[dir] + client);

/** base64(nonce ‖ ciphertext ‖ tag). `nonce` only for test vectors. */
export async function seal(key, client, dir, plaintext, nonce = crypto.getRandomValues(new Uint8Array(12))) {
  const ct = await subtle.encrypt({ name: 'AES-GCM', iv: nonce, additionalData: aad(client, dir) }, key, enc.encode(plaintext));
  return toB64(concat(nonce, new Uint8Array(ct)));
}

export async function open(key, client, dir, b64) {
  const raw = fromB64(b64);
  if (raw.length < 28) throw new Error('bad ciphertext');
  const pt = await subtle.decrypt({ name: 'AES-GCM', iv: raw.slice(0, 12), additionalData: aad(client, dir) }, key, raw.slice(12));
  return dec.decode(pt);
}
