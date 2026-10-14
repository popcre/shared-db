// OWNER RULING, Albert Hazan in his chat 2026-10-14 (verbatim): "let Muse review
// twice but don't stop the other agent's approach". Extends the 2026-10-02 reuse
// ruling to the exact open pull requests and reviewer listed in
// OWNER_REVIEWER_REUSE below. Slot 1 is never affected; a malformed list grants
// nothing. Remove an entry once its pull request merges.
export const OWNER_REVIEWER_REUSE = Object.freeze({
  schema: 'shared-db-owner-reviewer-reuse/v1',
  entries: Object.freeze([
    Object.freeze({ pr: 4206, issue: 2336, reviewer: 'muse-spark-1.3-contributor', owner_quote: "let Muse review twice but don't stop the other agent's approach", ruled_at: '2026-10-14' }),
  ]),
})

export function ownerReuseEntries(read = () => JSON.stringify(OWNER_REVIEWER_REUSE)) {
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
