import { test } from 'node:test';
import assert from 'node:assert/strict';
import '../lib/forms.js';

const { classifyFields } = globalThis.ArcanumForms;

const f = (type, extra = {}) => ({ type, name: '', id: '', autocomplete: '', placeholder: '', visible: true, ...extra });

test('login form: username before password', () => {
  const r = classifyFields([f('text', { name: 'q' }), f('email', { name: 'email' }), f('password', { name: 'pass' })]);
  assert.deepEqual(r, { username: 1, passwords: [2], newPassword: false });
});

test('autocomplete=username wins over position', () => {
  const r = classifyFields([f('text', { autocomplete: 'username' }), f('text', { name: 'otp' }), f('password')]);
  assert.equal(r.username, 0);
});

test('without hints the closest text field before the password is the username', () => {
  const r = classifyFields([f('text', { name: 'a' }), f('text', { name: 'b' }), f('password')]);
  assert.equal(r.username, 1);
});

test('signup with confirmation is a new-password context', () => {
  const r = classifyFields([f('email'), f('password', { name: 'password' }), f('password', { name: 'confirm' })]);
  assert.deepEqual(r, { username: 0, passwords: [1, 2], newPassword: true });
});

test('autocomplete=new-password is a new-password context', () => {
  assert.equal(classifyFields([f('password', { autocomplete: 'new-password' })]).newPassword, true);
});

test('current-password beats a "new" hint', () => {
  const r = classifyFields([f('password', { autocomplete: 'current-password', id: 'new-login-pass' })]);
  assert.equal(r.newPassword, false);
});

test('register hint on the form makes it new-password', () => {
  const r = classifyFields([f('text'), f('password')], { id: 'register-form' });
  assert.equal(r.newPassword, true);
});

test('hidden fields are ignored', () => {
  const r = classifyFields([f('text', { name: 'user', visible: false }), f('password', { visible: false }), f('password')]);
  assert.deepEqual(r, { username: null, passwords: [2], newPassword: false });
});

test('password-only form has no username', () => {
  assert.equal(classifyFields([f('password')]).username, null);
});

test('form without password fields has no passwords', () => {
  assert.deepEqual(classifyFields([f('text'), f('search')]).passwords, []);
});
