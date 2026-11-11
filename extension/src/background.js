// Service worker: the only part of the extension that talks to the app.
// A classic worker (Safari does not run module service workers).
importScripts('lib/url.js', 'lib/crypto.js', 'lib/client.js', 'lib/router.js', 'lib/browser.js');

const { ext, storageArea, browserName, BridgeClient, createRouter } = globalThis.Arcanum;

const client = new BridgeClient({ storage: storageArea(ext.storage.local) });

const route = createRouter({
  client,
  // Pending logins hold a password: memory only, never written to disk.
  session: storageArea(ext.storage.session),
  resolveTab: (tabId) => ext.tabs.get(tabId),
  browserName: browserName(),
});

ext.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  // Only this extension's own pages and content scripts.
  if (sender.id !== ext.runtime.id) return false;
  route(msg, sender).then(sendResponse);
  return true;
});
