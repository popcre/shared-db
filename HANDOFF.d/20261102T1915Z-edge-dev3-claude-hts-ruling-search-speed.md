---
issue: 5483
status: OPEN
owner: unowned — next session claims
---

# HTS ruling search speed — not started

Owns only the HTS ruling search follow-up on popcre/shared-db#5483.

Albert (2026-11-02) asked to investigate database load. Connections were 37/90 and apps already pooled through Supavisor. HTS ruling search averaged ~24 s/call; its root cause is not yet identified and #5283 may already have fixed it. No database change was made.

Correction to the chat summary: the "vector step reads a 103k-row table" observation came from a synthetic query; the function skips that step without an embedding. Treat it as unproven.

Continue with [plan_hts-ruling-search-speed.md](../plan_hts-ruling-search-speed.md), starting at step 0 in its STATUS table. Re-measure after #5283 before making changes; preserve ranked results and record production live proof on #5483.
