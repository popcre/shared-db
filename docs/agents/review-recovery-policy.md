# Review service recovery policy

Owner-authorized implementation tracked on [#4297](https://github.com/popcre/shared-db/issues/4297). This tooling policy preserves the mandatory independent exact-head approval count and guarded merge.

## Two distinct allowances

For a proven unchanged-content group of one PR and review slot, two conservative review rounds are permitted. A paid start consumes a round unless immutable terminal evidence binds the exact issue, PR, head, sequence, reviewer and recorded slot, proves no verdict or artifact, and records a supported reviewer-side service failure. Unknown, running and unrecorded starts remain counted. Negative verdicts never receive a failure refund. Source-history verification remains mandatory; empty commits, evidence-only commits, upstream refreshes and net reverts and changing the linked work issue do not reset capacity.

Supported service failures are wrapper_terminal_failure, provider_unavailable, insufficient_quota and turn_limit_cancelled. Every proven such failure is tracked separately from review rounds. After two failures by the same reviewer for this unchanged-content group and slot, new draws exclude that reviewer while healthy independent reviewers remain eligible. This bounds starts by two review rounds plus two service failures per registered reviewer; task allowlists and the live eligible roster can make the actual bound smaller. Historical failure records remain immutable.

This change does not introduce a budget reset or make an exhausted reviewer eligible merely because time elapsed or a doctor reported PASS. If all eligible reviewers are exhausted, repair/recovery needs a separately supported evidence path; the tool refuses with the actual service exhaustion, without requiring unrelated source edits. Unknown historical failures need their original verifiable evidence; no session may invent it to unstick a review.

## Independent assignments

Either required slot can be assigned first. Every other live peer is checked before and under the assignment mutex to prevent duplicate reviewers. The earliest assigned peer provides initial task policy; each slot's existing immutable policy governs its retries and replacements. Requested policies that conflict with those durable records refuse. Provider eligibility, author-engine exclusion, immutable assignment records, compare-and-swap lease transitions and final exact-head approval count remain binding. Existing explicitly scoped merged-PR reviewer reuse remains unchanged.

## Automatic failure evidence

The governed runner records a paid-start marker before invoking a reviewer. When an existing recognized terminal service failure produces no verdict-like line in either output stream, it calls the existing guarded failure-release operation using the exact sequence and slot in that marker and the held reviewer lease. Release rechecks live issue/head, no existing verdict/artifact, and ownership under the mutex. A failed release preserves the original diagnostics and reports the recovery refusal. Unknown failures, pre-start refusals and output containing any verdict-like line do not automatically claim verdict-less service failure.

Release does not launch another paid reviewer. The next supported assignment or replacement chooses an eligible independent reviewer within both allowances. A direct inline replacement that has not first recorded its failure remains conservatively subject to existing capacity checks; automatic guarded release closes this path for recognized runner failures.

## Verification and delivery

Circuit-breaker, assignment-order, candidate-exhaustion and runner-release adversarial tests must pass. The independent review remains pinned to the final code head. Merged-source runtime verification is distinct from source tests and does not authorize a database write, production action or a retry of historical spent work. PR4206 and its licensing claims remain owned by their existing session.
