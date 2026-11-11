// Content script (classic, after lib/forms.js): inline icon and menu in
// login fields, and the "save password" banner.
// Everything renders in a closed shadow root so the page can neither style
// nor read it. Page URLs are never sent: the background reads the tab URL.

(() => {
const { classifyFields } = globalThis.ArcanumForms;
const ext = globalThis.browser ?? globalThis.chrome;

// icons/icon-32.png, inlined so no extension file has to be web-accessible.
const ICON = 'data:image/png;base64,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';

const SKIP_TYPES = new Set(['hidden', 'submit', 'button', 'checkbox', 'radio', 'image', 'reset', 'file', 'range', 'color']);

const CSS = `
:host { all: initial; }
* { box-sizing: border-box; font: 13px/1.35 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
.icon { position: fixed; width: 22px; height: 22px; padding: 2px; border: 0; border-radius: 6px;
  background: transparent; cursor: pointer; z-index: 2147483647; }
.icon:hover { background: rgba(0,0,0,.08); }
.icon img { width: 18px; height: 18px; display: block; border-radius: 4px; }
.menu, .banner { position: fixed; z-index: 2147483647; background: #fff; color: #1b1b1f;
  border: 1px solid rgba(0,0,0,.12); border-radius: 10px; box-shadow: 0 8px 28px rgba(0,0,0,.18); }
.menu { min-width: 240px; max-width: 360px; padding: 4px; }
.item { display: block; width: 100%; text-align: left; border: 0; background: none; padding: 8px 10px;
  border-radius: 7px; cursor: pointer; color: inherit; }
.item:hover, .item:focus { background: #eef0f6; outline: none; }
.item small { display: block; color: #5d5f6a; }
.note { padding: 8px 10px; color: #5d5f6a; }
.banner { top: 16px; right: 16px; width: 320px; padding: 14px; }
.banner p { margin: 0 0 12px; }
.actions { display: flex; gap: 8px; justify-content: flex-end; }
.btn { border: 0; border-radius: 8px; padding: 7px 12px; cursor: pointer; background: #e7e8f0; color: #1b1b1f; }
.btn.primary { background: #3d4fb8; color: #fff; }
@media (prefers-color-scheme: dark) {
  .menu, .banner { background: #23242a; color: #e6e6ec; border-color: rgba(255,255,255,.12); }
  .item:hover, .item:focus { background: #33353f; }
  .item small, .note { color: #a6a8b4; }
  .btn { background: #383a46; color: #e6e6ec; }
  .icon:hover { background: rgba(255,255,255,.12); }
}`;

const STATE_TEXT = {
  not_running: "Avvia l'app Arcanum per usare le password.",
  not_paired: 'Collega questo browser: apri Arcanum dal pulsante nella barra degli strumenti.',
  error: 'Arcanum non risponde.',
};

function isVisible(el) {
  const r = el.getBoundingClientRect();
  if (r.width === 0 || r.height === 0) return false;
  const s = getComputedStyle(el);
  return s.visibility !== 'hidden' && s.display !== 'none' && s.opacity !== '0';
}

/** The form, or the nearest container holding a password field. */
function scopeOf(el) {
  if (el.form) return el.form;
  for (let n = el.parentElement; n && n !== document.body; n = n.parentElement) {
    if (n.querySelector('input[type=password]')) return n;
  }
  return document.body;
}

function analyze(scope) {
  const inputs = [...scope.querySelectorAll('input')].filter((i) => !SKIP_TYPES.has(i.type));
  const fields = inputs.map((i) => ({
    type: i.type,
    name: i.name,
    id: i.id,
    autocomplete: i.getAttribute('autocomplete') ?? '',
    placeholder: i.placeholder ?? '',
    visible: isVisible(i),
  }));
  const form =
    scope.tagName === 'FORM'
      ? { id: scope.id, name: scope.getAttribute('name') ?? '', action: scope.getAttribute('action') ?? '' }
      : {};
  const c = classifyFields(fields, form);
  return {
    username: c.username === null ? null : inputs[c.username],
    passwords: c.passwords.map((i) => inputs[i]),
    newPassword: c.newPassword,
  };
}

/** Sets a value the way typing would, so frameworks notice. */
function setValue(el, value) {
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
  el.focus();
  setter.call(el, value);
  el.dispatchEvent(new Event('input', { bubbles: true }));
  el.dispatchEvent(new Event('change', { bubbles: true }));
}

function el(tag, attrs = {}, ...children) {
  const n = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === 'onclick') n.addEventListener('click', v);
    else if (k === 'class') n.className = v;
    else n.setAttribute(k, v);
  }
  for (const c of children) n.append(c);
  return n;
}

function start() {
  const send = (msg) =>
    new Promise((resolve) => {
      try {
        const p = ext.runtime.sendMessage(msg, (r) => resolve(r ?? { error: 'error' }));
        if (p?.then) p.then((r) => resolve(r ?? { error: 'error' }), () => resolve({ error: 'error' }));
      } catch {
        resolve({ error: 'error' });
      }
    });

  const host = document.createElement('arcanum-ui');
  const root = host.attachShadow({ mode: 'closed' });
  root.append(el('style', {}, CSS));
  document.documentElement.append(host);

  let field = null; // input the icon is attached to
  let icon = null;
  let menu = null;
  let banner = null;

  // ---- Inline icon and menu ----

  function closeMenu() {
    menu?.remove();
    menu = null;
  }

  function hideIcon() {
    icon?.remove();
    icon = null;
    field = null;
  }

  function place() {
    if (!field || !field.isConnected) return hideIcon();
    const r = field.getBoundingClientRect();
    if (icon) {
      icon.style.left = `${r.right - 28}px`;
      icon.style.top = `${r.top + (r.height - 22) / 2}px`;
    }
    if (menu) {
      menu.style.left = `${Math.max(8, r.right - 280)}px`;
      menu.style.top = `${r.bottom + 4}px`;
    }
  }

  function showIcon(input) {
    if (field === input) return;
    closeMenu();
    hideIcon();
    field = input;
    icon = el('button', { class: 'icon', type: 'button', title: 'Arcanum' }, el('img', { src: ICON, alt: '' }));
    // Keep focus in the field while clicking the icon.
    icon.addEventListener('mousedown', (e) => e.preventDefault());
    icon.addEventListener('click', () => (menu ? closeMenu() : openMenu()));
    root.append(icon);
    place();
  }

  function menuNote(text) {
    menu.append(el('div', { class: 'note' }, text));
  }

  function menuItem(title, subtitle, onclick) {
    const b = el('button', { class: 'item', type: 'button', onclick }, title);
    if (subtitle) b.append(el('small', {}, subtitle));
    b.addEventListener('mousedown', (e) => e.preventDefault());
    menu.append(b);
  }

  function showError(error) {
    if (error === 'locked') {
      menuItem('Sblocca Arcanum', "L'app è bloccata", async () => {
        closeMenu();
        await send({ kind: 'openApp' });
      });
    } else {
      menuNote(STATE_TEXT[error] ?? STATE_TEXT.error);
    }
  }

  async function openMenu() {
    if (!field) return;
    const target = field;
    const form = analyze(scopeOf(target));
    menu = el('div', { class: 'menu', role: 'menu' });
    root.append(menu);
    place();

    if (form.newPassword) {
      const r = await send({ kind: 'generate' });
      if (menu === null || field !== target) return;
      if (r.error) return showError(r.error);
      menuItem('Usa password sicura', `${'•'.repeat(12)} (${r.password.length} caratteri)`, () => {
        for (const p of form.passwords) {
          // Fill new and confirmation fields, never a "current password".
          if ((p.getAttribute('autocomplete') ?? '').includes('current-password')) continue;
          setValue(p, r.password);
        }
        closeMenu();
      });
      return;
    }

    const r = await send({ kind: 'list' });
    if (menu === null || field !== target) return;
    if (r.error) return showError(r.error);
    if (!r.logins.length) return menuNote('Nessuna credenziale per questo sito');
    for (const login of r.logins) {
      menuItem(login.title, login.username, async () => {
        closeMenu();
        const c = await send({ kind: 'fill', id: login.id });
        if (c.error) return;
        fillForm(target, c.username, c.password);
      });
    }
  }

  function fillForm(anchor, username, password) {
    const form = analyze(scopeOf(anchor));
    if (form.username && username) setValue(form.username, username);
    const pw = form.passwords[0];
    if (pw) setValue(pw, password);
  }

  document.addEventListener(
    'focusin',
    (e) => {
      const t = e.target;
      if (!(t instanceof HTMLInputElement) || SKIP_TYPES.has(t.type)) return;
      const form = analyze(scopeOf(t));
      if (t === form.username || form.passwords.includes(t)) showIcon(t);
      else {
        closeMenu();
        hideIcon();
      }
    },
    true,
  );
  document.addEventListener('focusout', () => {
    // Let a click on the menu land first.
    setTimeout(() => {
      if (!menu && field && document.activeElement !== field) hideIcon();
    }, 150);
  });
  document.addEventListener('keydown', (e) => e.key === 'Escape' && closeMenu(), true);
  document.addEventListener(
    'mousedown',
    (e) => {
      if (menu && !e.composedPath().includes(host)) closeMenu();
    },
    true,
  );
  addEventListener('scroll', place, true);
  addEventListener('resize', place);

  // ---- Capture on submit ----

  let lastCapture = '';

  async function capture(scope) {
    const form = analyze(scope);
    if (!form.passwords.length) return;
    const values = form.passwords.map((p) => p.value);
    // change-password forms: current, new, confirmation → the new one.
    const password = values.length >= 3 ? values[1] : values[values.length - 1];
    if (!password) return;
    const username = form.username?.value ?? '';
    const key = `${username}\u0000${password}`;
    if (key === lastCapture) return;
    lastCapture = key;
    const r = await send({ kind: 'submitted', username, password });
    // Single-page apps don't navigate: offer to save here.
    if (r.pending) setTimeout(checkPending, 1200);
  }

  document.addEventListener('submit', (e) => capture(e.target), true);
  document.addEventListener(
    'click',
    (e) => {
      const b = e.target instanceof Element ? e.target.closest('button, input[type=submit]') : null;
      if (b && (b.type === 'submit' || b.form)) capture(b.form ?? scopeOf(b));
    },
    true,
  );
  document.addEventListener(
    'keydown',
    (e) => {
      if (e.key === 'Enter' && e.target instanceof HTMLInputElement && e.target.type === 'password') {
        capture(scopeOf(e.target));
      }
    },
    true,
  );

  // ---- Save banner ----

  function closeBanner() {
    banner?.remove();
    banner = null;
  }

  async function checkPending() {
    const r = await send({ kind: 'pending' });
    if (r.pending) showBanner(r.pending);
  }

  function showBanner(p) {
    closeBanner();
    const update = p.state === 'update';
    const text = update
      ? `Aggiornare in Arcanum la password di ${p.username || p.host}?`
      : `Salvare in Arcanum la password per ${p.host}?`;
    const message = el('p', {}, text);
    const primary = el('button', { class: 'btn primary', type: 'button' }, update ? 'Aggiorna' : 'Salva');
    const later = el('button', { class: 'btn', type: 'button' }, 'Non ora');
    const actions = el('div', { class: 'actions' }, later, primary);
    banner = el('div', { class: 'banner', role: 'dialog' }, message, actions);
    root.append(banner);

    later.addEventListener('click', async () => {
      closeBanner();
      await send({ kind: 'dismiss' });
    });
    primary.addEventListener('click', async () => {
      primary.disabled = true;
      const r = await send({ kind: 'save' });
      primary.disabled = false;
      if (r.saved) {
        message.textContent = update ? 'Password aggiornata.' : 'Password salvata.';
        actions.remove();
        setTimeout(closeBanner, 2000);
      } else if (r.error === 'locked') {
        message.textContent = "Arcanum è bloccato: sbloccalo, poi premi di nuovo " + (update ? 'Aggiorna.' : 'Salva.');
        if (!actions.querySelector('.unlock')) {
          const unlock = el('button', { class: 'btn unlock', type: 'button' }, 'Sblocca');
          unlock.addEventListener('click', () => send({ kind: 'openApp' }));
          actions.insertBefore(unlock, primary);
        }
      } else if (r.error) {
        message.textContent = STATE_TEXT[r.error] ?? 'Impossibile salvare la password.';
      } else {
        closeBanner();
      }
    });
  }

  // ---- Fill requested from the popup ----

  ext.runtime.onMessage.addListener((msg, sender, sendResponse) => {
    if (sender.id !== ext.runtime.id || msg?.kind !== 'applyFill') return false;
    const active = document.activeElement;
    const anchor =
      active instanceof HTMLInputElement && !SKIP_TYPES.has(active.type)
        ? active
        : [...document.querySelectorAll('input[type=password]')].find(isVisible);
    if (anchor) fillForm(anchor, msg.username, msg.password);
    sendResponse({ filled: Boolean(anchor) });
    return false;
  });

  checkPending();
}

start();
})();
