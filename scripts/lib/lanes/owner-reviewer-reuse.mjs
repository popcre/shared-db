// OWNER RULING, Albert Hazan in his chat 2026-10-14 (verbatim): "let Muse review
// twice but don't stop the other agent's approach". Extends the 2026-10-02 reuse
// ruling to the exact open pull requests and reviewer listed in
// config/owner-reviewer-reuse.json. Slot 1 is never affected; any malformed or
// unreadable list grants nothing.
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

const CONFIG = fileURLToPath(new URL('../../../config/owner-reviewer-reuse.json', import.meta.url))

export function ownerReuseEntries(read = () => readFileSync(CONFIG, 'utf8')) {
  try {
    const data = JSON.parse(read())
    if (data?.schema !== 'shared-db-owner-reviewer-reuse/v1' || !Array.isArray(data.entries)) return []
    return data.entries.filter((e) => Number.isInteger(e?.pr) && e.pr > 0 && typeof e?.reviewer === 'string' && e.reviewer && typeof e?.owner_quote === 'string' && e.owner_quote.trim())
  } catch { return [] }
}

export function ownerReviewerReuseAllowed({ pr, slot, reviewer }, read) {
  if (!(Number(slot) >= 2)) return false
  return ownerReuseEntries(read).some((e) => e.pr === Number(pr) && (reviewer === undefined || e.reviewer === reviewer))
}
