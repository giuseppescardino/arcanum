import { test } from 'node:test';
import assert from 'node:assert/strict';
import Arcanum from './load.js';

const { httpHost } = Arcanum;

test('drops www and port', () => {
  assert.equal(httpHost('https://www.example.com/login?x=1'), 'example.com');
  assert.equal(httpHost('http://localhost:3000/'), 'localhost');
  assert.equal(httpHost('HTTPS://Accounts.Example.COM'), 'accounts.example.com');
});

test('non-http urls have no host', () => {
  for (const u of ['chrome://settings', 'about:blank', 'file:///tmp/x.html', 'safari-web-extension://x/popup.html', 'not a url', '']) {
    assert.equal(httpHost(u), null, u);
  }
});
