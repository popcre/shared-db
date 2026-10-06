// Rotation plan v10 helper: sanitize a provider API response for the record.
// WHITELIST extraction — it cannot print what it does not extract: reads the
// raw response file (0600 path given as argv[2]), prints ONLY "<status> <message?>"
// where message is capped at 300 printable-ASCII chars and any run of 20+
// non-space characters collapses to [redacted] (credential-shaped tokens).
// argv: node sanitize.mjs <status> <response-file>
import { readFileSync } from 'node:fs';

const status = process.argv[2];
const file = process.argv[3];
if (!/^\d{3}$/.test(String(status ?? '')) || !file) {
  console.error('usage: node sanitize.mjs <http-status> <response-file>');
  process.exit(2);
}
let message = '(none)';
try {
  const body = JSON.parse(readFileSync(file, 'utf8'));
  if (typeof body?.message === 'string' && body.message.length > 0) message = body.message;
} catch { /* unreadable/non-JSON body: the fallback stands */ }
// REDACT BEFORE TRUNCATING: truncating first would leak the prefix of a
// credential that crosses the 300-char boundary (round-26 Critical).
const redacted = message.replace(/[^\x20-\x7e]/g, '?').replace(/\S{20,}/g, '[redacted]');
const truncated = redacted.slice(0, 300);
console.log(`${status} ${truncated}`);
