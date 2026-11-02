---
issue: 5482
status: OPEN
owner: unowned — next session claims
---

# DAM embedding claim speed — not started

Owns only the DAM embedding claim follow-up on popcre/shared-db#5482.

Albert (2026-11-02) asked to investigate database load. Connections were 37/90 and apps already pooled through Supavisor. The DAM embedding claim averaged ~23 s/call; its sort key is missing from the index. No database change was made.

Continue with [plan_dam-embedding-claim-speed.md](../plan_dam-embedding-claim-speed.md), starting at step 0 in its STATUS table. Preserve claim ordering and eligibility, rehearse in preview, and record production live proof on #5482.
