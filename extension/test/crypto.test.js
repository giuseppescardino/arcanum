import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import Arcanum from './load.js';

const { derive, generateKeyPair, importKey, keyPairFromScalar, open, seal, fromHex } = Arcanum;

const v = JSON.parse(readFileSync(new URL('./vectors.json', import.meta.url)));

test('reproduces the Rust pairing vectors', async () => {
  const ext = await keyPairFromScalar(fromHex(v.ext_scalar));
  assert.equal(Buffer.from(ext.publicRaw).toString('hex'), v.ext_pub);
  const r = await derive(ext.privateKey, fromHex(v.ext_pub), fromHex(v.app_pub), fromHex(v.app_pub));
  assert.equal(Buffer.from(r.keyRaw).toString('hex'), v.key);
  assert.equal(r.code, v.code);
});

test('reproduces the Rust request ciphertext and opens the response', async () => {
  const key = await importKey(fromHex(v.key));
  const ct = await seal(key, v.client, 'req', v.plaintext, fromHex(v.nonce));
  assert.equal(ct, v.request_ct);
  assert.equal(await open(key, v.client, 'res', v.response_ct), v.plaintext);
});

test('wrong direction is rejected', async () => {
  const key = await importKey(fromHex(v.key));
  await assert.rejects(open(key, v.client, 'req', v.response_ct));
});

test('fresh key pairs agree with each other', async () => {
  const a = await generateKeyPair();
  const b = await generateKeyPair();
  assert.equal(a.publicRaw.length, 32);
  const x = await derive(a.privateKey, a.publicRaw, b.publicRaw, b.publicRaw);
  const y = await derive(b.privateKey, a.publicRaw, b.publicRaw, a.publicRaw);
  assert.equal(x.code, y.code);
  assert.deepEqual(x.keyRaw, y.keyRaw);
  assert.match(x.code, /^\d{6}$/);
});

test('random nonces differ', async () => {
  const key = await importKey(new Uint8Array(32));
  assert.notEqual(await seal(key, 'c', 'req', 'x'), await seal(key, 'c', 'req', 'x'));
});
