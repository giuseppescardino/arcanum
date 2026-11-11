// Service worker: the only part of the extension that talks to the app.
import { ext, storageArea, browserName } from './lib/browser.js';
import { BridgeClient } from './lib/client.js';
import { createRouter } from './lib/router.js';

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
