// Talks to the Arcanum desktop app on 127.0.0.1 (see
// docs/superpowers/specs/2026-11-11-browser-extension-design.md).

import { derive, fromB64, generateKeyPair, importKey, open, seal, toB64 } from './crypto.js';

export const PORTS = [47613, 47614, 47615];
const PAIRING_TIMEOUT_MS = 130_000;
const POLL_MS = 1000;

export class BridgeError extends Error {
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
 * storage: async key/value { get(k), set(k, v), remove(k) } holding
 * `port` and `pairing` ({ client, key: base64 }).
 */
export class BridgeClient {
  constructor({ fetch = globalThis.fetch.bind(globalThis), storage, now = Date.now, sleep, randomId: rid = randomId }) {
    this.fetch = fetch;
    this.storage = storage;
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
        return await this._post(saved, body);
      } catch {
        // the app restarted on another port, or is gone
      }
    }
    const { port } = await this._probe();
    try {
      return await this._post(port, body);
    } catch {
      throw new BridgeError('not_running');
    }
  }

  async hello() {
    return (await this._probe()).hello;
  }

  async isPaired() {
    return Boolean(await this.storage.get('pairing'));
  }

  async unpair() {
    await this.storage.remove('pairing');
  }

  /** Pairs with the app; `onCode(code)` shows the 6 digits to compare. */
  async pair(name, onCode) {
    const kp = await generateKeyPair();
    const start = await this._send({ type: 'pair_start', name, pub: toB64(kp.publicRaw) });
    if (start.status !== 200) throw new BridgeError(start.json.error || 'bad_response');
    const appPub = fromB64(start.json.pub);
    const { keyRaw, code } = await derive(kp.privateKey, kp.publicRaw, appPub, appPub);
    onCode(code);
    const deadline = this.now() + PAIRING_TIMEOUT_MS;
    while (this.now() <= deadline) {
      const r = await this._send({ type: 'pair_status', pairing: start.json.pairing });
      if (r.json.state === 'approved') {
        await this.storage.set('pairing', { client: r.json.client, key: toB64(keyRaw) });
        return;
      }
      if (r.json.state !== 'pending') throw new BridgeError('pairing_rejected');
      await this.sleep(POLL_MS);
    }
    throw new BridgeError('pairing_rejected');
  }

  /** Sends an encrypted request; returns the reply body or throws its error. */
  async request(body) {
    const pairing = await this.storage.get('pairing');
    if (!pairing) throw new BridgeError('not_paired');
    const key = await importKey(fromB64(pairing.key));
    const id = this.randomId();
    const ct = await seal(key, pairing.client, 'req', JSON.stringify({ id, ts: this.now(), body }));
    const r = await this._send({ type: 'msg', client: pairing.client, ct });
    if (r.status === 401) {
      await this.unpair();
      throw new BridgeError('not_paired');
    }
    if (r.status !== 200 || typeof r.json.ct !== 'string') {
      throw new BridgeError(r.json.error || 'bad_response');
    }
    let reply;
    try {
      reply = JSON.parse(await open(key, pairing.client, 'res', r.json.ct));
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
