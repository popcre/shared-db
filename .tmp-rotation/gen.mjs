// Rotation plan v10 helper: generate the new password value into a 0600-intent
// file under the user profile and print ONLY its sha256-16 fingerprint.
// Alphabet is URL-embeddable ([A-Za-z0-9._~-], RFC 3986 unreserved) so the
// pooler-URL form of the secret never needs percent-encoding.
import { randomInt } from 'node:crypto';
import { createHash } from 'node:crypto';
import { writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { existsSync } from 'node:fs';
import { homedir } from 'node:os';

const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._~-';
const LENGTH = 40;
// One file PER GENERATED VALUE, named by the caller's label: a fresh-value
// recovery writes value-<new-label>.txt and never overwrites the old value's
// file, because step 7 of the plan must be able to probe every superseded
// value dead before its file is deleted.
const label = process.argv[2];
if (!label || !/^[a-z0-9-]+$/.test(label)) {
  console.error('usage: node gen.mjs <label>   (label names the generation, e.g. b, c2)');
  process.exit(2);
}
const dir = join(homedir(), '.tmp-rotation');
mkdirSync(dir, { recursive: true });
let value = '';
for (let i = 0; i < LENGTH; i += 1) value += ALPHABET[randomInt(ALPHABET.length)];
const file = join(dir, `value-${label}.txt`);
if (existsSync(file)) {
  console.error(`refusing to overwrite an existing value file: ${file}`);
  process.exit(2);
}
writeFileSync(file, value, { mode: 0o600 }); // NO trailing newline: every consumer (provider PATCH body, vault template, GitHub secret) uses the file bytes verbatim, so the stored value is exactly the 40 characters
const fingerprint = createHash('sha256').update(value).digest('hex').slice(0, 16);
console.log(`wrote ${file}`);
console.log(`fingerprint ${fingerprint}`);
