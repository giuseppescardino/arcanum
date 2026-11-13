(() => {
const { ext } = globalThis.Arcanum;

const main = document.getElementById('main');
const send = (msg) => ext.runtime.sendMessage(msg);

function h(tag, attrs = {}, ...children) {
  const n = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === 'onclick') n.addEventListener('click', v);
    else if (k === 'class') n.className = v;
    else n.setAttribute(k, v);
  }
  n.append(...children);
  return n;
}

const show = (...nodes) => main.replaceChildren(...nodes);

async function activeTab() {
  const [tab] = await ext.tabs.query({ active: true, currentWindow: true });
  return tab;
}

async function render() {
  const s = await send({ kind: 'state' });
  switch (s.state) {
    case 'not_running':
      return show(
        h('p', {}, "L'app Arcanum non è in esecuzione."),
        h('p', { class: 'muted' }, 'Avviala su questo computer: la compilazione funziona mentre il vault è sbloccato.'),
        h('button', { onclick: render }, 'Riprova'),
      );
    case 'not_paired':
      return renderPairing(s.pairing);
    case 'locked':
      return show(
        h('p', {}, 'Il vault è bloccato.'),
        h('button', { class: 'primary', onclick: async () => { await send({ kind: 'openApp' }); window.close(); } }, 'Sblocca Arcanum'),
      );
    case 'ready':
      return renderReady();
    default:
      return show(h('p', {}, 'Arcanum non risponde.'), h('button', { onclick: render }, 'Riprova'));
  }
}

function renderPairing(pairing) {
  if (pairing?.status === 'waiting' && pairing.code) return showCode(pairing.code);
  const start = h('button', { class: 'primary' }, 'Collega');
  const error = h('p', { class: 'muted' });
  start.addEventListener('click', async () => {
    start.disabled = true;
    const r = await send({ kind: 'pair' });
    const p = r.pairing;
    if (p?.code && p.status === 'waiting') return showCode(p.code);
    start.disabled = false;
    error.textContent =
      p?.status === 'pairing_closed'
        ? 'In Arcanum apri Impostazioni → Browser collegati → Collega browser, poi premi di nuovo Collega.'
        : p?.status === 'pairing_busy'
          ? "In Arcanum c'è già una richiesta di collegamento che non hai avviato tu? Premi Rifiuta nell'app, poi riprova."
          : 'Collegamento non riuscito.';
  });
  show(
    h('p', {}, 'Collega questo browser al vault.'),
    h('p', { class: 'muted' }, 'In Arcanum: menu → Browser collegati → Collega browser. Poi premi Collega qui.'),
    start,
    error,
  );
}

function showCode(code) {
  show(
    h('p', {}, 'Digita questo codice in Arcanum:'),
    h('div', { class: 'code' }, `${code.slice(0, 3)} ${code.slice(3)}`),
    h('p', { class: 'muted' }, 'Arcanum lo chiede per collegare questo browser. Non comunicarlo a nessuno.'),
  );
  const timer = setInterval(async () => {
    const { pairing } = await send({ kind: 'pairing' });
    if (pairing?.status === 'waiting') return;
    clearInterval(timer);
    if (pairing?.status === 'done') render();
    else show(h('p', {}, 'Collegamento rifiutato o scaduto.'), h('button', { onclick: render }, 'Riprova'));
  }, 1000);
}

async function renderReady() {
  const tab = await activeTab();
  const list = h('ul');
  const section = [h('h2', {}, 'Questo sito'), list];
  const r = tab ? await send({ kind: 'list', tabId: tab.id }) : { logins: [] };
  if (r.error) list.append(h('li', { class: 'muted' }, 'Impossibile leggere le credenziali.'));
  else if (!r.logins.length) list.append(h('li', { class: 'muted' }, 'Nessuna credenziale per questo sito.'));
  for (const login of r.logins ?? []) {
    list.append(
      h('li', {},
        h('div', { class: 'who' }, h('b', {}, login.title), h('small', {}, login.username || '—')),
        h('button', {
          onclick: async () => {
            const r = await send({ kind: 'fillTab', id: login.id, tabId: tab.id });
            if (r.filled) window.close();
          },
        }, 'Compila'),
      ),
    );
  }

  const out = h('code', {}, '');
  const copy = h('button', {}, 'Copia');
  const regen = h('button', {}, 'Genera');
  const generate = async () => {
    const g = await send({ kind: 'generate' });
    out.textContent = g.password ?? '';
    copy.textContent = 'Copia';
  };
  regen.addEventListener('click', generate);
  copy.addEventListener('click', async () => {
    await navigator.clipboard.writeText(out.textContent);
    copy.textContent = 'Copiata';
  });
  show(...section, h('h2', {}, 'Nuova password'), h('div', { class: 'gen' }, out, regen, copy));
  generate();
}

render();
})();
