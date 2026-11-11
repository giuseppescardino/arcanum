// The WebExtension API object: `browser` on Safari, `chrome` elsewhere.
// Classic script (no import/export) so it loads in every browser's
// background (importScripts), popup and tests; sets globalThis.Arcanum.

(() => {
globalThis.Arcanum ??= {};
const ext = globalThis.browser ?? globalThis.chrome;

/** chrome.storage area as the async {get,set,remove} used by the client. */
function storageArea(area) {
  if (!area) {
    const mem = new Map();
    return {
      get: async (k) => mem.get(k),
      set: async (k, v) => void mem.set(k, v),
      remove: async (k) => void mem.delete(k),
      keys: async () => [...mem.keys()],
    };
  }
  return {
    get: async (k) => (await area.get(k))[k],
    set: (k, v) => area.set({ [k]: v }),
    remove: (k) => area.remove(k),
    keys: async () => Object.keys(await area.get(null)),
  };
}

/**
 * {get,set,remove} over IndexedDB in the extension's own origin. Values are
 * structured-cloned, so a non-extractable CryptoKey stays non-extractable;
 * content scripts run in the page's origin and cannot open this database.
 */
function idbStore(name = 'arcanum') {
  const db = new Promise((resolve, reject) => {
    const req = indexedDB.open(name, 1);
    req.onupgradeneeded = () => req.result.createObjectStore('kv');
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
  const run = async (mode, fn) => {
    const tx = (await db).transaction('kv', mode);
    const req = fn(tx.objectStore('kv'));
    return new Promise((resolve, reject) => {
      tx.oncomplete = () => resolve(req.result);
      tx.onerror = () => reject(tx.error);
    });
  };
  return {
    get: (k) => run('readonly', (s) => s.get(k)),
    set: (k, v) => run('readwrite', (s) => s.put(v, k)).then(() => undefined),
    remove: (k) => run('readwrite', (s) => s.delete(k)).then(() => undefined),
  };
}

function browserName(ua = globalThis.navigator?.userAgent ?? '') {
  if (/OPR\/|Opera/.test(ua)) return 'Opera';
  if (/Edg\//.test(ua)) return 'Edge';
  if (/Chrome\//.test(ua)) return 'Chrome';
  if (/Safari\//.test(ua)) return 'Safari';
  return 'Browser';
}

Object.assign(globalThis.Arcanum, { ext, storageArea, idbStore, browserName });
})();
