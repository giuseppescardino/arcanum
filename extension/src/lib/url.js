/** Host of an http(s) page URL, lowercase, without `www.` and port; null otherwise. */
// Classic script (no import/export) so it loads in every browser's
// background (importScripts), popup and tests; sets globalThis.Arcanum.

(() => {
globalThis.Arcanum ??= {};
function httpHost(url) {
  let u;
  try {
    u = new URL(url);
  } catch {
    return null;
  }
  if (u.protocol !== 'http:' && u.protocol !== 'https:') return null;
  const host = u.hostname.toLowerCase();
  if (!host) return null;
  return host.startsWith('www.') ? host.slice(4) : host;
}

Object.assign(globalThis.Arcanum, { httpHost });
})();
