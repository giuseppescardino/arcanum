// Talks to the Arcanum desktop app on 127.0.0.1 (see
// docs/superpowers/specs/2026-11-11-browser-extension-design.md).
// Classic script (no import/export) so it loads in every browser's
// background (importScripts), popup and tests; sets globalThis.Arcanum.

(() => {
globalThis.Arcanum ??= {};
const { commitment, derive, fromB64, generateKeyPair, importKey, open, seal, toB64 } = globalThis.Arcanum;

const PORTS = [47613, 47614, 47615];
const PAIRING_TIMEOUT_MS = 130_000;
const POLL_MS = 1000;

class BridgeError extends Error {
  constructor(code) {
    super(code);
    this.code = code;
  }
}

const randomId = () => {
  const b = crypto.getRandomValues(new Uint8Array(16));
  return toB64(b);
};

/**
 * storage: async key/value { get(k), set(k, v), remove(k) } holding `port`.
 * keyStore: the same interface holding `pairing` ({ client, key }), where
 * key is the 32 key bytes; in the extension it is IndexedDB of the
 * extension's own origin, which content scripts cannot open. Bytes, not a
 * CryptoKey: Safari's background hangs structured-cloning a CryptoKey into
 * IndexedDB. Each request imports them as a non-extractable key.
 */
class BridgeClient {
  constructor({ fetch = globalThis.fetch.bind(globalThis), storage, keyStore, now = Date.now, sleep, randomId: rid = randomId }) {
    this.fetch = fetch;
    this.storage = storage;
    this.keyStore = keyStore ?? storage;
    this.now = now;
    this.sleep = sleep ?? ((ms) => new Promise((r) => setTimeout(r, ms)));
    this.randomId = rid;
  }

  async _post(port, body) {
    const res = await this.fetch(`http://127.0.0.1:${port}/v1`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(body),
    });
    let json = {};
    try {
      json = await res.json();
    } catch {
      // empty or non-JSON body
    }
    return { status: res.status, json };
  }

  /** Finds the app's port, remembered first, and returns its hello. */
  async _probe() {
    const saved = await this.storage.get('port');
    const order = saved ? [saved, ...PORTS.filter((p) => p !== saved)] : PORTS;
    for (const port of order) {
      try {
        const r = await this._post(port, { type: 'hello' });
        if (r.status === 200 && r.json.app === 'arcanum') {
          if (port !== saved) await this.storage.set('port', port);
          return { port, hello: r.json };
        }
      } catch {
        // nothing listening: try the next port
      }
    }
    await this.storage.remove('port');
    throw new BridgeError('not_running');
  }

  /** POSTs to the remembered port, re-probing once if it stopped answering. */
  async _send(body) {
    const saved = await this.storage.get('port');
    if (saved) {
      try {
        return { ...(await this._post(saved, body)), port: saved };
      } catch {
        // the app restarted on another port, or is gone
      }
    }
    const { port } = await this._probe();
    try {
      return { ...(await this._post(port, body)), port };
    } catch {
      throw new BridgeError('not_running');
    }
  }

  async _isArcanum(port) {
    try {
      const r = await this._post(port, { type: 'hello' });
      return r.status === 200 && r.json.app === 'arcanum';
    } catch {
      return false;
    }
  }

  async hello() {
    return (await this._probe()).hello;
  }

  async isPaired() {
    return Boolean(await this.keyStore.get('pairing'));
  }

  async unpair() {
    await this.keyStore.remove('pairing');
  }

  /**
   * Pairs with the app; `onCode(code)` shows the 6 digits the user types in
   * the app. The key is committed before the app's key is known and revealed
   * only afterwards.
   */
  async pair(name, onCode) {
    const kp = await generateKeyPair();
    const nonce = crypto.getRandomValues(new Uint8Array(32));
    const commit = await commitment(kp.publicRaw, nonce);
    const start = await this._send({ type: 'pair_start', name, commit: toB64(commit) });
    if (start.status !== 200) throw new BridgeError(start.json.error || 'bad_response');
    const appPub = fromB64(start.json.pub);
    const reveal = await this._send({
      type: 'pair_reveal',
      pairing: start.json.pairing,
      pub: toB64(kp.publicRaw),
      nonce: toB64(nonce),
    });
    if (reveal.status !== 200) throw new BridgeError('pairing_rejected');
    const { keyRaw, code } = await derive(kp.privateKey, kp.publicRaw, appPub, appPub);
    onCode(code);
    const deadline = this.now() + PAIRING_TIMEOUT_MS;
    while (this.now() <= deadline) {
      const r = await this._send({ type: 'pair_status', pairing: start.json.pairing });
      if (r.json.state === 'approved') {
        await this.keyStore.set('pairing', { client: r.json.client, key: keyRaw });
        return;
      }
      if (r.json.state !== 'pending') throw new BridgeError('pairing_rejected');
      await this.sleep(POLL_MS);
    }
    throw new BridgeError('pairing_rejected');
  }

  /** Sends an encrypted request; returns the reply body or throws its error. */
  async request(body) {
    const pairing = await this.keyStore.get('pairing');
    if (!pairing) throw new BridgeError('not_paired');
    const { client } = pairing;
    const key = await importKey(pairing.key);
    const id = this.randomId();
    const ct = await seal(key, client, 'req', JSON.stringify({ id, ts: this.now(), body }));
    const msg = { type: 'msg', client, ct };
    let r = await this._send(msg);
    if (!(r.status === 200 && typeof r.json.ct === 'string') && !(await this._isArcanum(r.port))) {
      // Something else answers on the remembered port: find the app again.
      await this.storage.remove('port');
      r = await this._send(msg);
    }
    if (r.status === 401 && r.json.error === 'unknown_client') {
      await this.unpair();
      throw new BridgeError('not_paired');
    }
    if (r.status !== 200 || typeof r.json.ct !== 'string') {
      throw new BridgeError(r.json.error || 'bad_response');
    }
    let reply;
    try {
      reply = JSON.parse(await open(key, client, 'res', r.json.ct));
    } catch {
      throw new BridgeError('bad_response');
    }
    if (reply.id !== id || typeof reply.body !== 'object' || reply.body === null) {
      throw new BridgeError('bad_response');
    }
    if (reply.body.error) throw new BridgeError(reply.body.error);
    return reply.body;
  }
}

Object.assign(globalThis.Arcanum, { PORTS, BridgeError, BridgeClient });
})();
