// Field classification over plain descriptors, so it runs without a DOM:
// { type, name, id, autocomplete, placeholder, visible } per input, in
// document order, plus optional form-level { id, name, action }.
//
// Loaded both as a classic content script (before content/ui.js) and as an
// ES module by the tests, so it has no import/export: it sets
// globalThis.ArcanumForms. This keeps every extension file out of
// web_accessible_resources, where pages could probe for them.

(() => {

const TEXT_TYPES = new Set(['text', 'email', 'tel', '']);
const USER_HINT = /user|e-?mail|login|account|identifier|utente|accesso/i;
const NEW_HINT = /new|confirm|repeat|retype|signup|sign-up|register|registr|create|nuova|conferma|ripeti/i;

const tokens = (f) => (f.autocomplete || '').toLowerCase().split(/\s+/);
const hintText = (f) => `${f.name || ''} ${f.id || ''} ${f.placeholder || ''}`;

/**
 * @returns {{username: number|null, passwords: number[], newPassword: boolean}}
 *   indexes into `fields`.
 */
function classifyFields(fields, form = {}) {
  const passwords = [];
  fields.forEach((f, i) => {
    if (f.visible && f.type === 'password') passwords.push(i);
  });
  return {
    username: passwords.length ? findUsername(fields, passwords[0]) : null,
    passwords,
    newPassword: passwords.length > 0 && isNewPassword(fields, passwords, form),
  };
}

function findUsername(fields, firstPassword) {
  const candidates = [];
  for (let i = 0; i < firstPassword; i++) {
    const f = fields[i];
    if (f.visible && TEXT_TYPES.has(f.type)) candidates.push(i);
  }
  const byAutocomplete = candidates.find((i) => {
    const t = tokens(fields[i]);
    return t.includes('username') || t.includes('email');
  });
  if (byAutocomplete !== undefined) return byAutocomplete;
  const byHint = candidates.filter((i) => USER_HINT.test(hintText(fields[i])) || fields[i].type === 'email');
  if (byHint.length) return byHint[byHint.length - 1];
  return candidates.length ? candidates[candidates.length - 1] : null;
}

function isNewPassword(fields, passwords, form) {
  const pw = passwords.map((i) => fields[i]);
  if (pw.some((f) => tokens(f).includes('new-password'))) return true;
  if (pw.some((f) => tokens(f).includes('current-password'))) return false;
  if (passwords.length >= 2) return true;
  if (pw.some((f) => NEW_HINT.test(hintText(f)))) return true;
  return NEW_HINT.test(`${form.id || ''} ${form.name || ''} ${form.action || ''}`);
}

globalThis.ArcanumForms = { classifyFields };
})();
