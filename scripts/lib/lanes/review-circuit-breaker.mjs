// Owner: reviewer assignment lane. Immutable start records bound paid rounds.
import { LaneError } from './claims.mjs'
import { REVIEW_STARTED_REF_PREFIX } from './constants.mjs'
import { parseTerminalFailureEvidence } from './review-replacement.mjs'

export function paidStart(row, commit) {
  const tuple = /^refs\/db-review-started\/(\d+)-(\d+)-([0-9a-f]{40})-slot(\d+)-seq(\d+)$/.exec(row.ref)
  if (!tuple || !/^[0-9a-f]{40}$/.test(row.sha)) throw new LaneError('review circuit breaker: malformed immutable start ref')
  const [, issue, pr, headSha, slot, sequence] = tuple
  const message = String(commit?.message ?? commit?.commit?.message ?? '')
  const start = /^db-coordination review-started issue=(\d+) pr=(\d+) head=([0-9a-f]{40}) slot=(\d+) sequence=(\d+) reviewer=([a-z0-9.-]+) at=(\S+)(?: session=([A-Za-z0-9._-]+) receipt-path=sha256:[0-9a-f]{64} source=sha256:[0-9a-f]{64})?$/.exec(message)
  if (start) {
    if (start.slice(1,6).join(':') !== tuple.slice(1).join(':') || !Number.isFinite(Date.parse(start[7]))) throw new LaneError('review circuit breaker: start record binding mismatch')
    return {issue:Number(issue),pr:Number(pr),headSha,slot:Number(slot),sequence:Number(sequence),reviewer:start[6]}
  }
  // Only the established atomic unstarted reclaim / independence conflict can
  // occupy a start marker without spending a provider attempt.
  const silence = /^db-coordination reviewer-silence-release reviewer=([a-z0-9.-]+) issue=(\d+) pr=(\d+) head=([0-9a-f]{40}) sequence=(\d+) code=silent_worker_observed probe=([0-9a-f]{40}) observed-at=(\S+) confirmed-at=(\S+) verdict=none artifact=none replacement=none$/.exec(message)
  if (silence && [silence[2],silence[3],silence[4],silence[5]].join(':') === [issue,pr,headSha,sequence].join(':') && Number.isFinite(Date.parse(silence[7])) && Number.isFinite(Date.parse(silence[8]))) return null
  const conflict=/^db-coordination reviewer-failure-replacement sequence=(\d+) reviewer=([a-z0-9.-]+) issue=(\d+) pr=(\d+) head=([0-9a-f]{40}) slot=(\d+)(?: allowlist=[a-z0-9.,-]+)? failed-sequence=(\d+) prior-sequence=(\d+) failure-ref=self failed-reviewer=([a-z0-9.-]+) code=slot_independence_conflict(?: failing-check=[a-z0-9_.-]+)? verdict=none artifact=none$/.exec(message)
  if(conflict && [conflict[3],conflict[4],conflict[5],conflict[6],conflict[7]].join(':') === tuple.slice(1).join(':')) return null
  throw new LaneError('review circuit breaker: unrecognized or unreadable start evidence')
}

export function assertPaidReviewCapacity(request, io) {
  const prefix=`${REVIEW_STARTED_REF_PREFIX}/`
  const rows = typeof io.readPaidReviewStarts === 'function' ? io.readPaidReviewStarts(prefix,request.pr) : io.listRefs(prefix)
  if (!Array.isArray(rows)) throw new LaneError('review circuit breaker: immutable start listing unreadable')
  const starts = rows.map(row=>paidStart(row,row.commit ?? io.getCommit(row.sha))).filter(row=>row && row.pr === request.pr && row.slot === request.slot)
  let count=0
  for (const start of starts) {
    let same=start.headSha === request.headSha
    if (!same) {
      if (typeof io.reviewContentComparison !== 'function') throw new LaneError('review circuit breaker: substantive content comparison unavailable')
      const comparison=io.reviewContentComparison(start.headSha,request.headSha,request.pr)
      if (!comparison || !/^[0-9a-f]{64}$/.test(comparison.before) || !/^[0-9a-f]{64}$/.test(comparison.after)) throw new LaneError('review circuit breaker: substantive content proof unreadable')
      same=comparison.before === comparison.after
    }
    if(same) count++
  }
  if(count>=2) throw new LaneError(`review circuit breaker: two paid attempts already started for unchanged reviewed content in slot ${request.slot}; third draw refused pending substantive repair or supported cause-bound reinstatement proof`)
  return {paidAttempts:count,remaining:2-count}
}

// Provider outage/quota evidence differs from a local preparation failure.
export function pauseActualReviewFailure(record,io) {
  if(!['insufficient_quota','provider_unavailable'].includes(record.failureCode))return {paused:false,reason:'not a verified provider failure class'}
  if(typeof io.readPaidReviewStarts!=='function'||typeof io.pauseReviewerFailure!=='function')throw new LaneError('verified provider failure requires the supported monotonic pause bridge')
  const rows=io.readPaidReviewStarts(`${REVIEW_STARTED_REF_PREFIX}/`,record.pr)
  if(!Array.isArray(rows))throw new LaneError('provider failure paid-start lineage unreadable')
  const start=rows.map(row=>paidStart(row,row.commit??io.getCommit(row.sha))).find(row=>row&&row.issue===record.issue&&row.pr===record.pr&&row.headSha===record.headSha&&row.slot===record.slot&&row.sequence===record.failedSequence&&(!record.reviewer||row.reviewer===record.reviewer))
  if(!start)return {paused:false,reason:'no immutable paid-start evidence'}
  const boundRecord={...record,reviewer:start.reviewer}
  const failure=parseTerminalFailureEvidence(typeof io.readReviewFailureCommit==='function'?io.readReviewFailureCommit(record.failureSha):io.getCommit(record.failureSha))
  if(!failure || ['issue','pr','headSha','failedSequence','reviewer','failureCode'].some(key=>failure[key]!==boundRecord[key]))throw new LaneError('provider pause immutable terminal failure binding mismatch')
  io.pauseReviewerFailure(boundRecord)
  return {paused:true}
}
