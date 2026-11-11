// The WebExtension API object: `browser` on Safari, `chrome` elsewhere.
export const ext = globalThis.browser ?? globalThis.chrome;

/** chrome.storage area as the async {get,set,remove} used by the client. */
export function storageArea(area) {
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

export function browserName(ua = globalThis.navigator?.userAgent ?? '') {
  if (/OPR\/|Opera/.test(ua)) return 'Opera';
  if (/Edg\//.test(ua)) return 'Edge';
  if (/Chrome\//.test(ua)) return 'Chrome';
  if (/Safari\//.test(ua)) return 'Safari';
  return 'Browser';
}
