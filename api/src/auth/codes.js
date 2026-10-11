// One-time codes for signing in and resetting passwords. Owned by AppWand.
// They live in this process's memory: a restart forgets them (people ask for
// a new one), and a code is only good for the process that issued it.
import crypto from 'node:crypto';

const LIFETIME_MS = 10 * 60_000;
const RESEND_MS = 60_000;
const MAX_TRIES = 5;
const codes = new Map();

const digest = (code) => crypto.createHash('sha256').update(String(code)).digest();

function sweep(now) {
  for (const [key, entry] of codes) if (now > entry.expires) codes.delete(key);
}

/** A new 6-digit code for [key], replacing the last; null when one was issued under a minute ago. */
export function issueCode(key) {
  const now = Date.now();
  sweep(now);
  const last = codes.get(key);
  if (last && now - last.issued < RESEND_MS) return null;
  const code = String(crypto.randomInt(0, 1_000_000)).padStart(6, '0');
  codes.set(key, { digest: digest(code), issued: now, expires: now + LIFETIME_MS, tries: 0 });
  return code;
}

/** Whether [code] is [key]'s current code. A right code is used up; five wrong ones void it. */
export function checkCode(key, code) {
  const entry = codes.get(key);
  if (!entry) return false;
  if (Date.now() > entry.expires) {
    codes.delete(key);
    return false;
  }
  if (crypto.timingSafeEqual(digest(String(code ?? '').replace(/\s/g, '')), entry.digest)) {
    codes.delete(key);
    return true;
  }
  entry.tries += 1;
  if (entry.tries >= MAX_TRIES) codes.delete(key);
  return false;
}
