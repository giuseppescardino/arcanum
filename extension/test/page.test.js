import { test } from 'node:test';
import assert from 'node:assert/strict';
import Arcanum from './load.js';

const { sendToBackground, iconInset } = Arcanum;

// Safari's `browser.runtime.sendMessage` takes no callback: a function in
// second position is ignored and only the returned promise settles.
const safariExt = (reply) => ({
  runtime: {
    sendMessage: (msg, opts) => {
      if (typeof opts === 'function') return new Promise(() => {});
      return Promise.resolve(reply);
    },
  },
});

test('resolves with the reply where only the promise settles (Safari)', async () => {
  assert.deepEqual(await sendToBackground(safariExt({ logins: [] }), { kind: 'list' }), { logins: [] });
});

test('an empty reply becomes an error', async () => {
  assert.deepEqual(await sendToBackground(safariExt(undefined), { kind: 'list' }), { error: 'error' });
});

test('a rejected or throwing send becomes an error', async () => {
  const rejecting = { runtime: { sendMessage: () => Promise.reject(new Error('gone')) } };
  const throwing = { runtime: { sendMessage: () => { throw new Error('invalidated'); } } };
  assert.deepEqual(await sendToBackground(rejecting, {}), { error: 'error' });
  assert.deepEqual(await sendToBackground(throwing, {}), { error: 'error' });
});

test('a reply that never comes times out as an error', async () => {
  const silent = { runtime: { sendMessage: () => new Promise(() => {}) } };
  assert.deepEqual(await sendToBackground(silent, {}, 20), { error: 'error' });
});

test('in Safari the icon sits left of Safari\'s own AutoFill button', () => {
  const safari = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15';
  const opera = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36 OPR/124.0.0.0';
  assert.ok(iconInset(safari) > iconInset(opera) + 20);
  assert.equal(iconInset(opera), 28);
});
