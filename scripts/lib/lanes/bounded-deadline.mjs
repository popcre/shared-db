// Bounded remaining-deadline I/O for reviewer-assignment holds (issue #4414 step 4).
// Monotonic deadline caps for gh and git children under ownership. Never widens
// request ceilings (25 / 15) and never adds a mutex.

/**
 * Milliseconds still available before `deadlineAtMs`.
 * Invalid / missing deadline is treated as unbounded (null).
 * A past or zero deadline is 0 — callers must refuse before launching.
 */
export function remainingDeadlineMs(deadlineAtMs, nowMs = Date.now()) {
  if (deadlineAtMs == null) return null
  const at = Number(deadlineAtMs)
  if (!Number.isFinite(at)) return null
  return Math.max(0, at - Number(nowMs))
}

/**
 * Refuse before launching a call when the remaining budget cannot cover
 * `minMs` (default 1). Throws a named Error so callers keep their own types.
 */
export function assertDeadlineBudget(deadlineAtMs, minMs = 1, nowMs = Date.now(), wrapError = null) {
  const remaining = remainingDeadlineMs(deadlineAtMs, nowMs)
  if (remaining === null) return null
  const need = Math.max(1, Number(minMs) || 1)
  if (remaining < need) {
    const detail = `remaining deadline ${Math.round(remaining)}ms cannot fit the required ${need}ms; refusing before launching the call`
    if (typeof wrapError === 'function') throw wrapError(detail, null)
    const error = new Error(detail)
    error.code = 'DEADLINE_EXHAUSTED'
    throw error
  }
  return remaining
}

/**
 * Clamp a child timeout to the remaining deadline.
 * Returns null when the deadline is unbounded.
 * Returns 0 when nothing remains — the caller must not launch.
 */
export function clampTimeoutToDeadline(timeoutMs, deadlineAtMs, nowMs = Date.now()) {
  const remaining = remainingDeadlineMs(deadlineAtMs, nowMs)
  if (remaining === null) return timeoutMs
  return Math.min(Math.max(0, timeoutMs), remaining)
}

/**
 * Cleanup allowance reserved before a commit so release can still run after a
 * near-deadline write. Derived from the existing 3-request release ladder
 * (owner-qualified delete + readback + one git fallback). Not a new ceiling.
 */
export const CLEANUP_RESERVE_MS = 15_000

/**
 * Reserve the cleanup allowance before starting a commit under a deadline.
 * Throws when remaining time minus the reserve cannot cover `commitMs`.
 */
export function assertCleanupReserve(
  deadlineAtMs,
  commitMs = 1,
  reserveMs = CLEANUP_RESERVE_MS,
  nowMs = Date.now(),
  wrapError = null,
) {
  const remaining = remainingDeadlineMs(deadlineAtMs, nowMs)
  if (remaining === null) return { remaining: null, reserveMs, commitMs }
  const need = Math.max(1, Number(commitMs) || 1) + Math.max(0, Number(reserveMs) || 0)
  if (remaining < need) {
    const detail = `remaining deadline ${Math.round(remaining)}ms cannot fit commit ${Math.round(need - reserveMs)}ms + cleanup reserve ${reserveMs}ms; refusing before commit`
    if (typeof wrapError === 'function') throw wrapError(detail, null)
    const error = new Error(detail)
    error.code = 'DEADLINE_CLEANUP_RESERVE'
    throw error
  }
  return { remaining, reserveMs, commitMs }
}

/**
 * Classify an atomic multi-ref write whose response was lost or timed out.
 *
 * readObserved: (ref) => string|null — exact current SHA of each intended ref.
 * desired: [{ref, sha}] — what the transaction should have written.
 * prior:  [{ref, sha|null}] — known state before the transaction.
 *
 * Returns:
 *   {kind:'committed'}   every desired ref reads as its desired SHA
 *   {kind:'uncommitted'} every desired ref reads as its prior SHA (or null)
 *   {kind:'partial'}     some committed, some not
 *   {kind:'unknown'}     a read failed or results are inconsistent
 *
 * Never redraws. Never deletes. Never treats a successor owner as ours.
 */
export function reconcileAmbiguousWrite({ desired, prior, readObserved }) {
  if (!Array.isArray(desired) || desired.length === 0) {
    return { kind: 'unknown', reason: 'desired ref set is empty or malformed' }
  }
  if (typeof readObserved !== 'function') {
    return { kind: 'unknown', reason: 'readObserved is not a function' }
  }
  const priorByRef = new Map()
  for (const row of Array.isArray(prior) ? prior : []) {
    if (row && typeof row.ref === 'string') priorByRef.set(row.ref, row.sha ?? null)
  }
  let committed = 0
  let uncommitted = 0
  let unknown = 0
  const rows = []
  for (const want of desired) {
    if (!want || typeof want.ref !== 'string' || typeof want.sha !== 'string') {
      unknown += 1
      rows.push({ ref: want?.ref ?? null, state: 'unknown', reason: 'malformed desired row' })
      continue
    }
    let observed
    try {
      observed = readObserved(want.ref)
    } catch {
      unknown += 1
      rows.push({ ref: want.ref, state: 'unknown', reason: 'read failed' })
      continue
    }
    if (observed === want.sha) {
      committed += 1
      rows.push({ ref: want.ref, state: 'committed', observed })
      continue
    }
    const before = priorByRef.has(want.ref) ? priorByRef.get(want.ref) : null
    if (observed === before || (observed === null && before === null)) {
      uncommitted += 1
      rows.push({ ref: want.ref, state: 'uncommitted', observed, prior: before })
      continue
    }
    // Observed something else entirely — a successor or a foreign write.
    unknown += 1
    rows.push({ ref: want.ref, state: 'unknown', observed, prior: before, reason: 'observed SHA is neither desired nor prior' })
  }
  if (unknown > 0) return { kind: 'unknown', rows, committed, uncommitted, unknown }
  if (committed === desired.length) return { kind: 'committed', rows, committed, uncommitted, unknown }
  if (uncommitted === desired.length) return { kind: 'uncommitted', rows, committed, uncommitted, unknown }
  return { kind: 'partial', rows, committed, uncommitted, unknown }
}

/**
 * Map a reconciliation result to the recovery the plan requires.
 * - committed     → keep the assignment; never redraw
 * - uncommitted   → retryable no-write refusal
 * - partial/unknown → recovery-required
 */
export function recoveryForReconcile(result) {
  const kind = result?.kind ?? 'unknown'
  if (kind === 'committed') return 'keep_assignment_no_redraw'
  if (kind === 'uncommitted') return 'retryable_no_write'
  return 'recovery_required'
}

/**
 * Cleanup must never delete a successor owner's mutex.
 * currentOwner is the SHA now on the mutex ref (or null if absent).
 * ourOwner is the SHA we believe we used.
 */
export function cleanupMayDeleteMutex(currentOwner, ourOwner) {
  if (!ourOwner || typeof ourOwner !== 'string') return false
  if (!/^[0-9a-f]{40}$/.test(ourOwner)) return false
  if (currentOwner == null) return false
  return currentOwner === ourOwner
}
