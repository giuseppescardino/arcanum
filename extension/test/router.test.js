import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRouter, PENDING_TTL_MS } from '../lib/router.js';
import { BridgeError } from '../lib/client.js';

class MemoryStorage {
  constructor() { this.data = {}; }
  async get(k) { return this.data[k]; }
  async set(k, v) { this.data[k] = v; }
  async remove(k) { delete this.data[k]; }
}

/** Fake client: replies[op] is a value or a function(body); BridgeError codes as {throw: code}. */
function fakeClient(replies) {
  const calls = [];
  return {
    calls,
    async request(body) {
      calls.push(body);
      const r = typeof replies[body.op] === 'function' ? replies[body.op](body) : replies[body.op];
      if (r?.throw) throw new BridgeError(r.throw);
      return r ?? {};
    },
    async hello() { return { app: 'arcanum' }; },
    async isPaired() { return true; },
  };
}

const tab = (id = 7, url = 'https://www.example.com/login') => ({ tab: { id, url } });

function setup(replies, start = 1_000_000) {
  const client = fakeClient(replies);
  const session = new MemoryStorage();
  let now = start;
  const route = createRouter({ client, session, now: () => now, resolveTab: async (id) => ({ id, url: 'https://popup.example/' }) });
  return { client, session, route, advance: (ms) => { now += ms; } };
}

test('list uses the sender tab url, not one from the message', async () => {
  const { client, route } = setup({ list: { logins: [] } });
  await route({ kind: 'list', url: 'https://evil.com/' }, tab());
  assert.equal(client.calls[0].url, 'https://www.example.com/login');
});

test('popup requests resolve the tab url through the browser', async () => {
  const { client, route } = setup({ list: { logins: [] } });
  await route({ kind: 'list', tabId: 3 }, {});
  assert.equal(client.calls[0].url, 'https://popup.example/');
});

test('errors come back as {error}', async () => {
  const { route } = setup({ list: { throw: 'locked' } });
  assert.deepEqual(await route({ kind: 'list' }, tab()), { error: 'locked' });
});

test('submitted with the same password is not kept', async () => {
  const { session, route } = setup({ check: { state: 'same' } });
  assert.deepEqual(await route({ kind: 'submitted', username: 'a', password: 'p' }, tab()), { pending: false });
  assert.deepEqual(session.data, {});
});

test('submitted without a password is ignored', async () => {
  const { client, route } = setup({});
  assert.deepEqual(await route({ kind: 'submitted', username: 'a', password: '' }, tab()), { pending: false });
  assert.equal(client.calls.length, 0);
});

test('a new login is kept per tab and offered without its password', async () => {
  const { route } = setup({ check: { state: 'new' } });
  assert.deepEqual(await route({ kind: 'submitted', username: 'a', password: 'p' }, tab(7)), { pending: true });
  assert.deepEqual(await route({ kind: 'pending' }, tab(7, 'https://example.com/home')), {
    pending: { host: 'example.com', username: 'a', state: 'new' },
  });
  assert.deepEqual(await route({ kind: 'pending' }, tab(8)), { pending: null });
});

test('pending expires after 120 s', async () => {
  const { route, advance } = setup({ check: { state: 'new' } });
  await route({ kind: 'submitted', username: 'a', password: 'p' }, tab());
  advance(PENDING_TTL_MS + 1);
  assert.deepEqual(await route({ kind: 'pending' }, tab()), { pending: null });
});

test('save while locked keeps the pending login and reports locked', async () => {
  const { route } = setup({ check: { state: 'new' }, save: { throw: 'locked' } });
  await route({ kind: 'submitted', username: 'a', password: 'p' }, tab());
  assert.deepEqual(await route({ kind: 'save' }, tab()), { error: 'locked' });
  assert.equal((await route({ kind: 'pending' }, tab())).pending.username, 'a');
});

test('submitted while locked is kept and checked again at save', async () => {
  let locked = true;
  const { client, route } = setup({
    check: () => (locked ? { throw: 'locked' } : { state: 'new' }),
    save: { id: '1' },
  });
  assert.deepEqual(await route({ kind: 'submitted', username: 'a', password: 'p' }, tab()), { pending: true });
  assert.equal((await route({ kind: 'pending' }, tab())).pending.state, 'unknown');
  locked = false;
  assert.deepEqual(await route({ kind: 'save' }, tab()), { saved: true });
  assert.deepEqual(client.calls.map((c) => c.op), ['check', 'check', 'save']);
});

test('a successful save clears the pending login', async () => {
  const { client, route } = setup({ check: { state: 'new' }, save: { id: '1' } });
  await route({ kind: 'submitted', username: 'a', password: 'p' }, tab());
  assert.deepEqual(await route({ kind: 'save' }, tab()), { saved: true });
  assert.deepEqual(client.calls[1], { op: 'save', url: 'https://www.example.com/login', username: 'a', password: 'p' });
  assert.deepEqual(await route({ kind: 'pending' }, tab()), { pending: null });
});

test('update is used when check says update', async () => {
  const { client, route } = setup({ check: { state: 'update', id: 'i1' }, update: {} });
  await route({ kind: 'submitted', username: 'a', password: 'new' }, tab());
  assert.equal((await route({ kind: 'pending' }, tab())).pending.state, 'update');
  await route({ kind: 'save' }, tab());
  assert.deepEqual(client.calls[1], { op: 'update', id: 'i1', url: 'https://www.example.com/login', password: 'new' });
});

test('dismiss forgets the pending login', async () => {
  const { route } = setup({ check: { state: 'new' } });
  await route({ kind: 'submitted', username: 'a', password: 'p' }, tab());
  await route({ kind: 'dismiss' }, tab());
  assert.deepEqual(await route({ kind: 'pending' }, tab()), { pending: null });
});

test('non-http tabs never reach the app', async () => {
  const { client, route } = setup({ list: { logins: [{ id: 'x' }] } });
  assert.deepEqual(await route({ kind: 'list' }, tab(1, 'chrome://settings')), { logins: [] });
  assert.deepEqual(await route({ kind: 'submitted', username: 'a', password: 'p' }, tab(1, 'about:blank')), { pending: false });
  assert.equal(client.calls.length, 0);
});
