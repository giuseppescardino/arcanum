/** Host of an http(s) page URL, lowercase, without `www.` and port; null otherwise. */
export function httpHost(url) {
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
