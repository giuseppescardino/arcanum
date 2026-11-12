// Helpers for the content script that need no DOM, so they can be tested.
// Classic script (no import/export); sets globalThis.Arcanum.

(() => {
globalThis.Arcanum ??= {};

const SEND_TIMEOUT_MS = 15_000;

/**
 * Sends a message to the background and always settles: with the reply,
 * or { error: 'error' } if there is none, the send fails, or no reply
 * comes within `timeoutMs`. Promise form only: Safari's sendMessage takes
 * no callback, and passing one leaves the promise pending forever.
 */
function sendToBackground(ext, msg, timeoutMs = SEND_TIMEOUT_MS) {
  return new Promise((resolve) => {
    const fail = () => resolve({ error: 'error' });
    const timer = setTimeout(fail, timeoutMs);
    const done = (r) => {
      clearTimeout(timer);
      resolve(r ?? { error: 'error' });
    };
    try {
      Promise.resolve(ext.runtime.sendMessage(msg)).then(done, () => done(null));
    } catch {
      done(null);
    }
  });
}

/**
 * Distance of the inline icon's left edge from the field's right edge.
 * Safari draws its own AutoFill button at the right end of login fields,
 * so there the icon goes to its left.
 */
function iconInset(ua = globalThis.navigator?.userAgent ?? '') {
  const safari = /Safari\//.test(ua) && !/Chrome\/|Chromium\/|Edg\/|OPR\//.test(ua);
  return safari ? 56 : 28;
}

Object.assign(globalThis.Arcanum, { sendToBackground, iconInset });
})();
