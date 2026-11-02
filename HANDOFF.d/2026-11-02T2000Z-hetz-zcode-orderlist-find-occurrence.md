---
issue: 5467
status: OPEN
owner: zcode sess_8ac8b36e-1dd7-4c33-939a-98e95b34aad2 (branch orderlist-find-occurrence-5467, merged & deleted)
---

# OrderList Find occurrence navigation — production promotion + live assertion outstanding

## 0. ⚠️ BUSINESS DECISIONS ONLY THE OWNER CAN MAKE

**None — nothing in this workstream needs the owner.** Technical approvals,
promotion, and verification are AI-handled; the only human touch is Albert's team
*trying* the finished feature in the app (an acceptance, not a decision — tracked
on u2giants/popdam3#658, not an ask).

Already settled — do NOT re-ask:
- Google-Sheets-style Find UX (counter + arrows + Enter/Shift+Enter wrap + Esc)
  was requested by Albert 2026-11-02 and is delivered; no further sign-off pending
  on the design.

## 1. What this application is

`popcre/shared-db` is the canonical repo for the shared Supabase Postgres backend
(production project `qsllyeztdwjgirsysgai`) used by POP's apps, including PopDAM
(u2giants/popdam3), the internal digital-asset manager. PopDAM's OrderList page
has a Google-Sheets-style Find box that jumps to database-wide search matches via
the RPC `public.find_dam_order_list_row`.

## 2. What we set out to do this session, and why

Albert asked (2026-11-02) that Master Data and OrderList search "work more like
Google Sheets": see the total number of results and jump directly to each one
with arrows, instead of only the most recent match. The DB half of that: extend
`find_dam_order_list_row` to return any requested 1-based occurrence plus the
total match count.

## 3. Current state — what is true right now

All checked 2026-11-02 ~20:00Z (3:00 PM EST):

- Work issue #5467 (claim-first) CLOSED by the merge; exact-object claim #5468 released/closed (release attempt returned "not open"); `ai-shared-db-closeout-check` = `{"ok":true,...}` (receipt in private session evidence).
- PR #5469 MERGED to main (merge commit https://github.com/popcre/shared-db/pull/5469; branch deleted). Migration `20261102180759_orderlist_find_occurrence.sql` on main: https://github.com/popcre/shared-db/blob/main/supabase/migrations/20261102180759_orderlist_find_occurrence.sql — replaces the 3-arg function with 4-arg (`p_occurrence integer default 1`) returning `(order_line_id, row_index, match_count)`; 3-arg callers keep resolving via the defaulted argument.
- Behavioral test updated: https://github.com/popcre/shared-db/blob/main/scripts/test_order_list_find_position.py (9 new occurrence/match_count cases; run green on disposable loopback PG 17). Contract tests updated to the 4-arg signature: `supabase/tests/dam_order_list_find_position.sql`, `supabase/tests/dam_order_list_sales_order_date_sort.sql`. Sidecar + registry entry for the dynamic-SQL marker line 125 committed in the same PR.
- **Applied to PREVIEW: yes** (run 41506994852, `preview` job success, dispatched by me 2026-11-02T19:09Z).
- **Applied to PRODUCTION: NO.** It is queued in the automatic promotion lane, which promotes strictly in version order. Older migrations ahead of it keep failing promotion (PR #5417 / 20261102012258 and PR #5452 / 20261102181554 — hts_rag ruling-search family; see open PR #5476 "Skip the faulty ruling-search migration in the promotion line (#5444)" where another session is repairing exactly that). Latest observed: "DB preview apply … PR5452 20261102181554" failed 2026-11-02T19:53Z.
- Review finding #5473 (stale — reviewed the pre-sidecar head) closed with evidence: https://github.com/popcre/shared-db/issues/5473
- PopDAM side is DONE and LIVE (frontend PR u2giants/popdam3#659 merged; verified in the deployed bundle). The app works fully today via its deployment-skew fallback (it counts matches itself); it switches to the fast RPC path automatically once this migration reaches production — no deploy needed.
- No sub-agents were dispatched this session.

## 4. Everything we tried that did NOT work

- **First preview-apply dispatch refused**: dispatched with `commit_sha` = a main tip that was already behind (`REFUSED: origin/main … has moved past the dispatched commit`). Fix: re-dispatch at the current tip. Lesson: fetch immediately before dispatching.
- **`--prepare-preview-dispatch` refused** ("0 recoverable closed claims") — that flag is for historical recovery, not the normal post-merge rehearsal. The normal path is dispatching `shared-supabase-migrations.yml` directly with `target=preview mode=apply merged_preview_source_pr=<pr> commit_sha=<tip> preview_allowlist=<version>`.
- **First CI run failed**: `check_production_verification_sidecars.py` — dynamic-execution marker (line 125, `return query execute format`) requires a hash-bound sidecar + registry entry. Fixed in the PR; remember for ANY migration with `execute format`.
- **Dynamic SQL cannot see plpgsql variables**: `where m.match_ordinal = p_occurrence` inside `execute format` failed (`column "p_occurrence" does not exist`). Must pass as `using` parameter (`$2`).
- **`jsonb_typeof(spec->>'ascending')`** (text) does not exist — must be `spec->'ascending'` (jsonb). I transcribed this wrong once from a compressed read of the old migration.
- **Production dispatch HELD** by review-finding #5473 even though the finding described the pre-sidecar head. Resolution: verify the fix is on merged main, close the finding with evidence, re-run `automatic-production-trigger.yml`.
- **Promotion lane blocked ahead of us** (not mine to fix): PR #5417/#5452 migrations fail automatic qualification with "unclassifiable data effect: do $$ $$" evidence errors. Do not try to promote out of order — `automatic_promotion_candidates.py` enforces strict version order.

## 5. Root causes and key findings

- The production gate holds promotion on ANY open review-finding issue that references the source PR — even a stale one; closing it with evidence unblocks the hourly trigger.
- Production promotion is strictly version-ordered; a failing older migration blocks all newer ones until repaired (PR #5476 is that repair effort, owned by another session).
- `ai-shared-db-closeout-check` normalizes session ids; a `sess_…`-prefixed id in `CLAUDE_CODE_SESSION_ID` fails its format check — pass the bare UUID.
- Behavioral SQL tests need the `authenticated`/`anon`/`service_role` roles pre-created in the disposable loopback Postgres container.

## 6. Exact next steps

1. Watch PR #5476 / the promotion lane. You'll know it moved when a "DB production apply" run for version `20261102180759` appears (workflow "Shared Supabase Migrations" run list) — or when `supabase` migrations history on production shows it applied.
2. After production apply succeeds, verify the live assertion from issue #5467: as an authenticated PopDAM user (or via the app's own request), `find_dam_order_list_row('<term>','[]','[]',2)` returns the SECOND match with correct zero-based `row_index` and the total `match_count`. Gate: two rows returned for a two-match term, `match_count=2`, second row's id differs from the first.
3. Confirm the PopDAM app silently switched off the fallback (browser console no longer logs "OrderList Find RPC is unavailable during deployment"). Gate: typing in OrderList Find shows "1 of N" and the network tab shows one `find_dam_order_list_row` RPC with `p_occurrence` per jump.
4. Record the proof as a comment on u2giants/popdam3#658 and tick its live-proof checkbox; delete this handoff file in that same change (successor rule) — the file's issue #5467 is closed, so this file is a SUCCESSOR REVIEW candidate once step 2 passes.

## 7. Constraints and gotchas in force

- Never promote out of order or hand-apply migrations to production; only the automatic lane applies (owner rulings 2026-10-02/2026-10-14).
- Any future edit to this function needs a NEW timestamped migration + claim-first issue; never edit `20261102180759*` (applied to preview).
- Reviews are advisory and never block merges (owner ruling 2026-10-29), but an OPEN review-finding ISSUE does hold production dispatch.
- Shared-db work happens in own worktrees; canonical checkout is read/land only.

## 8. Access and environment

- Everything needed is GitHub-native (gh CLI authenticated as u2giants). No database credentials were used this session (all DB applies ran through GitHub workflows; the loopback test container was local/disposable and removed).
- No secrets appeared; secrets sweep: swept, nothing new.
- Docs pass: nothing outside this handoff is stale (contract tests + function comment updated in the merged PR; AGENTS.md unaffected).

## 9. Open questions and risks

- When `20261102180759` reaches production depends entirely on the ruling-search repair (PR #5476, another session). No user-facing impact while waiting — the live app uses its fallback.
- Risk (low): another replacement of `find_dam_order_list_row` merging before promotion would invalidate the preview rehearsal of this one; re-dispatch the preview apply at the new tip if that happens.
- Facts that may be stale: main tip `aff099353` and "PR #5476 open" were true at 2026-11-02T20:00Z; re-derive before acting.
