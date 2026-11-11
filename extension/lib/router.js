// Background message routing, free of browser APIs so it can be tested.
// The page URL always comes from the browser (sender.tab or resolveTab),
// never from the message.

import { httpHost } from './url.js';

export const PENDING_TTL_MS = 120_000;

/**
 * client: BridgeClient; session: async {get,set,remove} (memory only);
 * resolveTab(tabId) -> {id, url} for messages from the popup.
 */
export function createRouter({ client, session, now = Date.now, resolveTab, browserName = 'Browser' }) {
  let pairing = null; // { code, status: 'waiting'|'done'|<error code> }

  const pendingKey = (tabId) => `pending:${tabId}`;

  async function tabOf(msg, sender) {
    if (sender?.tab) return sender.tab;
    if (msg.tabId !== undefined && resolveTab) return resolveTab(msg.tabId);
    return null;
  }

  async function getPending(tabId) {
    const p = await session.get(pendingKey(tabId));
    if (!p) return null;
    if (now() - p.at > PENDING_TTL_MS) {
      await session.remove(pendingKey(tabId));
      return null;
    }
    return p;
  }

  async function check(url, username, password) {
    try {
      return await client.request({ op: 'check', url, username, password });
    } catch (e) {
      if (e.code === 'locked') return { state: 'unknown' };
      throw e;
    }
  }

  async function state() {
    try {
      await client.hello();
    } catch {
      return { state: 'not_running' };
    }
    if (!(await client.isPaired())) return { state: 'not_paired', pairing };
    try {
      const r = await client.request({ op: 'status' });
      return { state: r.locked ? 'locked' : 'ready' };
    } catch (e) {
      return { state: e.code === 'not_paired' ? 'not_paired' : 'not_running', pairing };
    }
  }

  function startPairing() {
    return new Promise((resolve) => {
      pairing = { code: null, status: 'waiting' };
      client
        .pair(browserName, (code) => {
          pairing.code = code;
          resolve({ pairing });
        })
        .then(() => {
          pairing.status = 'done';
        })
        .catch((e) => {
          pairing.status = e.code ?? 'error';
          resolve({ pairing });
        });
    });
  }

  async function handle(msg, sender) {
    switch (msg.kind) {
      case 'state':
        return state();
      case 'pair':
        return startPairing();
      case 'pairing':
        return { pairing };
      case 'openApp':
        return client.request({ op: 'open_app' });
      case 'generate':
        return client.request({ op: 'generate' });
    }

    const tab = await tabOf(msg, sender);
    const url = tab?.url ?? '';
    const host = httpHost(url);

    switch (msg.kind) {
      case 'list':
        if (!host) return { logins: [] };
        return client.request({ op: 'list', url });
      case 'fill':
        if (!host) return { error: 'domain_mismatch' };
        return client.request({ op: 'fill', id: msg.id, url });
      case 'submitted': {
        if (!host || !msg.password) return { pending: false };
        const username = (msg.username ?? '').trim();
        const r = await check(url, username, msg.password);
        if (r.state === 'same') return { pending: false };
        await session.set(pendingKey(tab.id), {
          url,
          host,
          username,
          password: msg.password,
          state: r.state,
          id: r.id ?? null,
          at: now(),
        });
        return { pending: true };
      }
      case 'pending': {
        const p = tab ? await getPending(tab.id) : null;
        return { pending: p && { host: p.host, username: p.username, state: p.state } };
      }
      case 'dismiss':
        if (tab) await session.remove(pendingKey(tab.id));
        return {};
      case 'save': {
        const p = tab ? await getPending(tab.id) : null;
        if (!p) return { saved: false };
        let { state: st, id } = p;
        if (st === 'unknown') {
          const r = await client.request({ op: 'check', url: p.url, username: p.username, password: p.password });
          st = r.state;
          id = r.id ?? null;
        }
        if (st === 'update') {
          await client.request({ op: 'update', id, url: p.url, password: p.password });
        } else if (st === 'new') {
          await client.request({ op: 'save', url: p.url, username: p.username, password: p.password });
        }
        await session.remove(pendingKey(tab.id));
        return { saved: true };
      }
      default:
        return { error: 'bad_request' };
    }
  }

  return async function route(msg, sender) {
    try {
      return await handle(msg ?? {}, sender);
    } catch (e) {
      return { error: e?.code ?? 'error' };
    }
  };
}
