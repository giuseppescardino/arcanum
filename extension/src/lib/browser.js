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
    };
  }
  return {
    get: async (k) => (await area.get(k))[k],
    set: (k, v) => area.set({ [k]: v }),
    remove: (k) => area.remove(k),
  };
}

function browserName(ua = globalThis.navigator?.userAgent ?? '') {
  if (/OPR\/|Opera/.test(ua)) return 'Opera';
  if (/Edg\//.test(ua)) return 'Edge';
  if (/Chrome\//.test(ua)) return 'Chrome';
  if (/Safari\//.test(ua)) return 'Safari';
  return 'Browser';
}

Object.assign(globalThis.Arcanum, { ext, storageArea, browserName });
})();
