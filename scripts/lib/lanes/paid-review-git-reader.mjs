import { execFileSync } from 'node:child_process'

// Owner: exact paid-review provenance. Complete source blobs can exceed the
// Node default1MiB. This process bound does not change semantic evidence limits.
export const PAID_REVIEW_GIT_MAX_BYTES = 4 * 1024 * 1024
export function paidReviewGitReader(args) {
  return execFileSync('git', args, {encoding:'utf8', stdio:['ignore','pipe','pipe'], maxBuffer:PAID_REVIEW_GIT_MAX_BYTES})
}
