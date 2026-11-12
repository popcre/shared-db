---
issue: 6150
status: OPEN
owner: claude/edge-dev3 MG06 coordinator (designflow-coordinator-c77315)
---

# Close-nested handoff — MG06 licensor-submission groundwork (2026-11-12, 4:00 PM EST)

Owner: Albert (business owner, not a programmer — plain-English replies, standing rules in
`~/.claude/CLAUDE.md`). Coordinator authority: Albert's original request to run the MG06
coordinator prompt (`HANDOFF.d/20261111T2216Z-edge-dev3-claude-mg06-coordinator-prompt.md`)
and "/close-nested" at 3:54 PM EST.

## Owner rulings made today (binding)
- "there's no Mickey Mouse Family vs. MICKEY MOUSE. one lives under the other." — Mickey Mouse
  Family (MMF) is the parent; MICKEY MOUSE, Minnie Mouse, etc. are under it.
- "if it's mickey + anyone else (minnie, pluto, goofy) it submitted as 'Standard Characters',
  not under any sub-property under 'Mickey Mouse Family'." Final: 208 styles move
  Standard Characters → MMF (207 Mickey Mouse, 1 Minnie Mouse); 9 stay on Standard Characters.
- "leave rugrats inactive. old styles can still be associated with an inactive property, you
  just can't make new ones."
- Minnie-only design → OPA "Minnie" > "Minnie & Me" (unanimous submission history).
- After Albert asked "what are you using the contract for?", contract-based studio placement of
  OPA properties is PAUSED; 493 site-only properties stay "potential".

## Tree closed
| Session | Final state | Branch |
|---|---|---|
| Coordinator (this) | closed | `claude/mg06-note-mickey-session` → PR 6149 |
| MG06 site-path store (local_899a1434) | closed | merged; handoff PR 6197 queued |
| └ Property nickname (local_6df652b9) | closed | `db/mg06-property-nickname` → PR 6181 queued |
| MG06 sheet vs handoff (local_5c82011c) | closed, nothing unfinished | merged |
| Ilona email + OPA properties (local_58ebe867) | closed | handoffs PR 6195 queued |
| Disney OPA auto-fill gaps (local_2528e7f1) | closed, all merged | merged |

## Landed (verified merged)
- popcre/shared-db#6091 plan; #6153 `core.property_site_path` + `api.mg06_site_path` + tests
  (merged 3:10 PM EST; NOT yet on preview at 3:52 PM EST).
- #6154 515 Disney OPA properties canonical in production (verified live); #6165 check file.
- #6151, #6161, #6169 sheet-vs-handoff write-up and rulings.
- #6158, #6170, #6182 Ilona email draft `docs/mg06-ilona-confirmation-email-draft-2026-11-12.md` (unsent).
- #6163, #6168 OPA product lines, Minnie choice, Style Guide rule, group-shot rule in plan.
- Files (Albert's Dropbox, unsent): `ai/ColdLion changes for Jamielynn - 2026-11-12.xlsx`
  (293 values, 584 style moves, 5 spelling fixes); older drafts in `ai/superseded-jamielynn-drafts/`.

## Open tasks (dependency order)

### 1. Prove site-path store on preview and production
State: merged, preview queue had not applied migration 20261112194140 at 3:52 PM EST.
Next: after the automatic preview run, read preview (table, RLS, grants, function); after
automatic promotion, read production; post proof on #6150. Done when both verified.
Issue: https://github.com/popcre/shared-db/issues/6150 · resume: main · claim #6150 kept open on purpose.
Child handoff: https://github.com/popcre/shared-db/blob/main/HANDOFF.d/20261112T2100Z-edge-dev3-claude-mg06-site-path-step6.md (PR 6197).

### 2. Plan step 6 — populate site paths (after: 1)
Map the 128 Keep/Reactivate values in the Dropbox Jamielynn sheet to `core.property` ids and
scraped OPA names via a new claimed data migration. Group shots → Standard Characters; MICKEY
MOUSE → Mickey Mouse Family > Mickey Mouse; Minnie → Minnie > Minnie & Me. Leave Standard
Characters out until task 5 creates it. Done when every active MG06 has ≥1 current row and a
count query proves it on production. Issue: #6150 · resume: fresh from main.

### 3. Land property nickname field
PR https://github.com/popcre/shared-db/pull/6181 requeued 3:53 PM EST after a "backdated" ejection.
Next: watch with `ai-pr-wait 6181`, fix ejections, verify column on preview + production.
Issue: https://github.com/popcre/shared-db/issues/6178 (claim held) · branch `db/mg06-property-nickname`.

### 4. Set Standard Characters nickname "Mickey Group" (after: 3, 5)
Issue #6178. Done when production shows the nickname.

### 5. OPA properties placement — BLOCKED on Albert
Ask Albert §0 of https://github.com/popcre/shared-db/blob/main/HANDOFF.d/2026-11-12T2052Z-edge-dev3-claude-opa-submission-properties.md
(contract use; 917 unplaced). Done when Standard Characters exists as a Disney `core.property`
in production. Issue: https://github.com/popcre/shared-db/issues/2541 (PR 6195 holds the handoff).

### 6. ColdLion → core.property feed + stale merchGroup copies — BLOCKED on Albert + Uma
Handoff: https://github.com/popcre/shared-db/blob/main/HANDOFF.d/2026-11-12T2052Z-edge-dev3-claude-coldlion-property-feed-and-stale-tables.md
Needs Albert's yes to fill `core.property` from live ColdLion, and Uma's reply to the email in
Albert's Dropbox `ai/email-to-uma-merchgroup-functions-2026-11-12.md` (Albert sends it).
Issue: https://github.com/popcre/shared-db/issues/6194.

### 7. Jamielynn sheet delivery — waits on Albert
Albert confirms whether his own 11:12 AM sheet already reached Jamielynn, then sends the one
consolidated sheet. Also 112 "needs a call" styles from Anyela's review need Albert/Licensing
decisions. No PR; nothing for AI until he answers.

### 8. Land handoff PRs
#6149 (this file + Mickey note), #6195, #6197 — merge queue; done when merged.

## Child handoffs
- https://github.com/popcre/shared-db/blob/main/HANDOFF.d/20261112T2100Z-edge-dev3-claude-mg06-site-path-step6.md
- https://github.com/popcre/shared-db/blob/main/HANDOFF.d/2026-11-12T2052Z-edge-dev3-claude-opa-submission-properties.md
- https://github.com/popcre/shared-db/blob/main/HANDOFF.d/2026-11-12T2052Z-edge-dev3-claude-coldlion-property-feed-and-stale-tables.md
- https://github.com/popcre/shared-db/blob/main/HANDOFF.d/20261112T1730Z-mg06-note-for-mickey-minnie-properties-session.md

## Self-audit
Fresh coordinator can act without chat context: yes — rulings quoted, every task has next
action, done-when, issue. Unverified: preview/prod state of #6153 after 3:52 PM EST; merge of
6149/6181/6195/6197. No secrets; no claims held by the coordinator.
