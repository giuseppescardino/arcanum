// Service worker: the only part of the extension that talks to the app.
// A classic worker (Safari does not run module service workers).
importScripts('lib/url.js', 'lib/crypto.js', 'lib/client.js', 'lib/router.js', 'lib/browser.js');

const { ext, storageArea, idbStore, browserName, BridgeClient, createRouter } = globalThis.Arcanum;

// The port is not secret; the pairing key lives in IndexedDB, out of reach
// of content scripts (which can read storage.local).
const client = new BridgeClient({ storage: storageArea(ext.storage.local), keyStore: idbStore() });
const session = storageArea(ext.storage.session);

const route = createRouter({
  client,
  // Pending logins hold a password: memory only, never written to disk.
  session,
  resolveTab: (tabId) => ext.tabs.get(tabId),
  // Top frame only; the content script re-checks its own host.
  deliverFill: async (tabId, payload) => {
    try {
      const r = await ext.tabs.sendMessage(tabId, { kind: 'applyFill', ...payload }, { frameId: 0 });
      return r?.filled === true;
    } catch {
      return false;
    }
  },
  browserName: browserName(),
});

ext.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  // Only this extension's own pages and content scripts.
  if (sender.id !== ext.runtime.id) return false;
  route(msg, sender).then(sendResponse);
  return true;
});

// A closed tab's pending login (with its password) is dropped at once.
ext.tabs.onRemoved.addListener((tabId) => session.remove(`pending:${tabId}`));
