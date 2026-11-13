import { test } from 'node:test';
import assert from 'node:assert/strict';
import Arcanum from './load.js';

const { BridgeClient, PORTS } = Arcanum;
const { commitment, derive, fromB64, generateKeyPair, importKey, open, seal, toB64 } = Arcanum;

class MemoryStorage {
  constructor(init = {}) { this.data = { ...init }; }
  async get(k) { return this.data[k]; }
  async set(k, v) { this.data[k] = v; }
  async remove(k) { delete this.data[k]; }
}

/** Fake fetch: handlers[port](body) -> {status, json}; missing port = connection refused. */
function fakeFetch(handlers) {
  const calls = [];
  const fetch = async (url, init) => {
    const port = Number(new URL(url).port);
    const body = JSON.parse(init.body);
    calls.push({ port, body });
    const h = handlers[port];
    if (!h) throw new TypeError('Failed to fetch');
    const { status = 200, json } = await h(body);
    return { status, ok: status >= 200 && status < 300, json: async () => json };
  };
  return { fetch, calls };
}

const arcanumHello = async (b) => (b.type === 'hello' ? { json: { app: 'arcanum', protocol: 1, pairing: false } } : { status: 400, json: { error: 'bad_request' } });

const KEY = new Uint8Array(32).fill(4);
const paired = async () => new MemoryStorage({ pairing: { client: 'c1', key: KEY.slice() } });

/** A fake app on `port` that decrypts with KEY and answers with `reply(body)`. */
function fakeApp(reply, { echoId = true } = {}) {
  return async (b) => {
    if (b.type === 'hello') return arcanumHello(b);
    const key = await importKey(KEY);
    const env = JSON.parse(await open(key, b.client, 'req', b.ct));
    const out = { id: echoId ? env.id : 'other', body: await reply(env.body) };
    return { json: { ct: await seal(key, b.client, 'res', JSON.stringify(out)) } };
  };
}

const opts = (fetch, storage) => ({ fetch, storage, sleep: async () => {}, now: () => 1000, randomId: () => 'rid' });

test('skips a foreign service on the first port', async () => {
  const { fetch } = fakeFetch({
    [PORTS[0]]: async () => ({ json: { hello: 'world' } }),
    [PORTS[1]]: arcanumHello,
  });
  const storage = new MemoryStorage();
  const c = new BridgeClient(opts(fetch, storage));
  assert.equal((await c.hello()).app, 'arcanum');
  assert.equal(storage.data.port, PORTS[1]);
});

test('remembers the port', async () => {
  const { fetch, calls } = fakeFetch({ [PORTS[2]]: arcanumHello });
  const c = new BridgeClient(opts(fetch, new MemoryStorage({ port: PORTS[2] })));
  await c.hello();
  assert.deepEqual(calls.map((x) => x.port), [PORTS[2]]);
});

test('app not running throws not_running', async () => {
  const { fetch } = fakeFetch({});
  const c = new BridgeClient(opts(fetch, new MemoryStorage()));
  await assert.rejects(c.hello(), { code: 'not_running' });
});

test('encrypted request round trip', async () => {
  const { fetch } = fakeFetch({ [PORTS[0]]: fakeApp(async (body) => ({ echo: body.op })) });
  const c = new BridgeClient(opts(fetch, await paired()));
  assert.deepEqual(await c.request({ op: 'status' }), { echo: 'status' });
});

test('an error body is thrown with its code', async () => {
  const { fetch } = fakeFetch({ [PORTS[0]]: fakeApp(async () => ({ error: 'locked' })) });
  const c = new BridgeClient(opts(fetch, await paired()));
  await assert.rejects(c.request({ op: 'list', url: 'https://x' }), { code: 'locked' });
});

test('unknown_client clears the pairing', async () => {
  const { fetch } = fakeFetch({
    [PORTS[0]]: async (b) => (b.type === 'hello' ? arcanumHello(b) : { status: 401, json: { error: 'unknown_client' } }),
  });
  const storage = await paired();
  const c = new BridgeClient(opts(fetch, storage));
  await assert.rejects(c.request({ op: 'status' }), { code: 'not_paired' });
  assert.equal(storage.data.pairing, undefined);
});

test('a response for another request id is rejected', async () => {
  const { fetch } = fakeFetch({ [PORTS[0]]: fakeApp(async () => ({}), { echoId: false }) });
  const c = new BridgeClient(opts(fetch, await paired()));
  await assert.rejects(c.request({ op: 'status' }), { code: 'bad_response' });
});

test('request without pairing is not_paired', async () => {
  const { fetch } = fakeFetch({ [PORTS[0]]: arcanumHello });
  const c = new BridgeClient(opts(fetch, new MemoryStorage()));
  await assert.rejects(c.request({ op: 'status' }), { code: 'not_paired' });
});

test('re-probes when the remembered port stops answering', async () => {
  const { fetch } = fakeFetch({ [PORTS[1]]: fakeApp(async () => ({ ok: 1 })) });
  const storage = await paired();
  storage.data.port = PORTS[0];
  const c = new BridgeClient(opts(fetch, storage));
  assert.deepEqual(await c.request({ op: 'status' }), { ok: 1 });
  assert.equal(storage.data.port, PORTS[1]);
});

test('pairing: commits, reveals, shows the code and stores the key once approved', async () => {
  const app = await generateKeyPair();
  let derived;
  let commit;
  let polls = 0;
  const order = [];
  const { fetch } = fakeFetch({
    [PORTS[0]]: async (b) => {
      order.push(b.type);
      if (b.type === 'hello') return { json: { app: 'arcanum', protocol: 1, pairing: true } };
      if (b.type === 'pair_start') {
        assert.equal(b.pub, undefined, 'the key must not be sent before the app answers');
        commit = b.commit;
        return { json: { pairing: 'p1', pub: toB64(app.publicRaw) } };
      }
      if (b.type === 'pair_reveal') {
        const extPub = fromB64(b.pub);
        assert.equal(toB64(await commitment(extPub, fromB64(b.nonce))), commit);
        derived = await derive(app.privateKey, extPub, app.publicRaw, extPub);
        return { json: {} };
      }
      if (b.type === 'pair_status') {
        return { json: ++polls < 3 ? { state: 'pending' } : { state: 'approved', client: 'c9' } };
      }
    },
  });
  const storage = new MemoryStorage();
  const c = new BridgeClient(opts(fetch, storage));
  let shown;
  await c.pair('Chrome', (code) => { shown = code; });
  assert.deepEqual(order.filter((t) => t !== 'hello').slice(0, 3), ['pair_start', 'pair_reveal', 'pair_status']);
  assert.equal(shown, derived.code);
  assert.equal(storage.data.pairing.client, 'c9');
  // Stored as plain bytes: Safari hangs structured-cloning a CryptoKey
  // into IndexedDB from the background. Imported non-extractable on use.
  assert.ok(storage.data.pairing.key instanceof Uint8Array);
  assert.deepEqual([...storage.data.pairing.key], [...derived.keyRaw]);
});

test('a refused reveal ends the pairing', async () => {
  const app = await generateKeyPair();
  const { fetch } = fakeFetch({
    [PORTS[0]]: async (b) => {
      if (b.type === 'hello') return arcanumHello(b);
      if (b.type === 'pair_start') return { json: { pairing: 'p1', pub: toB64(app.publicRaw) } };
      return { status: 400, json: { error: 'bad_request' } };
    },
  });
  const c = new BridgeClient(opts(fetch, new MemoryStorage()));
  let shown = false;
  await assert.rejects(c.pair('Chrome', () => { shown = true; }), { code: 'pairing_rejected' });
  assert.equal(shown, false);
});

test('pairing closed in the app', async () => {
  const { fetch } = fakeFetch({
    [PORTS[0]]: async (b) => (b.type === 'hello' ? arcanumHello(b) : { status: 403, json: { error: 'pairing_closed' } }),
  });
  const c = new BridgeClient(opts(fetch, new MemoryStorage()));
  await assert.rejects(c.pair('Chrome', () => {}), { code: 'pairing_closed' });
});

test('pairing rejected in the app', async () => {
  const app = await generateKeyPair();
  const { fetch } = fakeFetch({
    [PORTS[0]]: async (b) => {
      if (b.type === 'hello') return arcanumHello(b);
      if (b.type === 'pair_start') return { json: { pairing: 'p1', pub: toB64(app.publicRaw) } };
      if (b.type === 'pair_reveal') return { json: {} };
      return { json: { state: 'rejected' } };
    },
  });
  const storage = new MemoryStorage();
  const c = new BridgeClient(opts(fetch, storage));
  await assert.rejects(c.pair('Chrome', () => {}), { code: 'pairing_rejected' });
  assert.equal(storage.data.pairing, undefined);
});

test('a foreign service on the remembered port is re-probed', async () => {
  const { fetch } = fakeFetch({
    [PORTS[0]]: async () => ({ status: 404, json: undefined }),
    [PORTS[1]]: fakeApp(async () => ({ ok: 1 })),
  });
  const storage = await paired();
  storage.data.port = PORTS[0];
  const c = new BridgeClient(opts(fetch, storage));
  assert.deepEqual(await c.request({ op: 'status' }), { ok: 1 });
  assert.equal(storage.data.port, PORTS[1]);
});

test("a foreign service's 401 does not unpair", async () => {
  const { fetch } = fakeFetch({
    [PORTS[0]]: async () => ({ status: 401, json: { error: 'unknown_client' } }),
    [PORTS[1]]: fakeApp(async () => ({ ok: 1 })),
  });
  const storage = await paired();
  storage.data.port = PORTS[0];
  const c = new BridgeClient(opts(fetch, storage));
  assert.deepEqual(await c.request({ op: 'status' }), { ok: 1 });
  assert.equal(storage.data.pairing.client, 'c1');
});

test('keys can live in a separate store', async () => {
  const { fetch } = fakeFetch({ [PORTS[0]]: fakeApp(async () => ({ ok: 1 })) });
  const keyStore = await paired();
  const storage = new MemoryStorage();
  const c = new BridgeClient({ ...opts(fetch, storage), keyStore });
  assert.deepEqual(await c.request({ op: 'status' }), { ok: 1 });
  assert.equal(storage.data.pairing, undefined);
});
