# Disney DCP Vault withdrawal: answer routing across chats

This note is a durable intake instruction, not an answer or a vendor ruling.
Albert may obtain an answer himself from Laura or Ilona and relay it in any
future shared-db chat. No agent is authorized to contact Disney, Laura, Ilona,
or anyone else to obtain it.

## Recognize the answer

The business question is:

> When artwork disappears from DCP Vault, what notice or status do you use to confirm that Disney withdrew it?

Treat a relayed explanation about Disney/DCP Vault missing artwork, withdrawal
notices, removal status, Laura, or Ilona as potentially answering this question.
Read the actual answer before deciding its meaning. A name alone does not prove
authority, and an ambiguous answer remains unresolved rather than a new rule.

## Capture and act in the receiving chat

1. Read [issue #3347](https://github.com/popcre/shared-db/issues/3347)
   (orchestrator work: DCP capture qualification), including current comments
   and state. This is the durable answer anchor, a bounded successor to
   [issue #1275](https://github.com/popcre/shared-db/issues/1275)
   (orchestrator work). Do not send the answer to a remembered chat identifier.
2. Record a sanitized comment on #3347 with the date received, the reported
   speaker, the person relaying it, the answer's exact business meaning, and
   whether it is a direct statement, quotation, paraphrase, or interpretation.
   For example, an answer Albert relays must say "Albert reports that Laura
   said...", never claim the agent spoke to Laura. Preserve uncertainty and any
   limits on the answer's scope. Sign the GitHub comment under repository rules.
3. Keep private messages, licensed artwork, screenshots, identifiers and examples
   in the approved private `u2giants/licensor-source-data` repository. Public
   comments and rules contain only the sanitized decision and provenance; never
   copy private examples into this public repository. If exact wording itself is
   private, retain it privately and publish a faithful sanitized meaning.
4. Once authoritative and unambiguous, update the relevant topic in
   [the companywide business rules](business-rules/licensing-master-data.md)
   through the normal reviewed branch-and-PR process, with provenance and the
   issue reference. Do not create a competing business rule in this note.
   If authority or meaning is unresolved, record precisely what is unresolved
   and retain the existing rule until clarified.
5. Classify each concrete follow-up from its own actual work. A database SHAPE
   change must resolve the CURRENT orchestrator using
   `node scripts/check-orchestrator-marker.mjs --resolve` and follow that live
   route. Never reuse a stale chat UUID, marker, or predecessor's object claims.
   Ordinary source capture, producer qualification and loader changes belong
   to the private `u2giants/licensor-source-data` session; repository notes and
   business-rule documentation stay with a non-orchestrator repository session.
   Record the owning issue/repository and the specific next action at #3347.
6. If #3347 is already closed, still record the answer there as the historical
   anchor, then open or link a fresh scoped follow-up only where actual work is
   needed. Do not reopen completed work automatically or inherit its route,
   objects, approvals, or completion claim. A no-change answer is recorded as
   such with its reason; recording an answer alone is not implementation proof.

## Boundaries that remain in force

Disappearance from a portal is not by itself verified Disney withdrawal, nor
proof of legal entitlement, termination or lack of rights. Keep observed source
absence, confirmed vendor withdrawal and legal rights as separate facts.

A vendor attestation requirement was an agent proposal, not an owner decision.
Do not make one a prerequisite for technical capture qualification. The existing
engineering contract requires authenticated, exhaustive coverage of the configured
scope, immutable retained provenance, zero failed fetches and rejection of
incomparable captures. Confirm the current #3347 contract before implementation;
this note neither weakens it nor authorizes database or production writes.

The independent technical producer repair and capture qualification can proceed
without this human answer under their own approvals. Do not block all Disney work
on the question, and do not present the question as already answered. Apply any
later authoritative answer only to the behavior it actually settles.
