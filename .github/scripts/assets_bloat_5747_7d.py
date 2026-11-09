"""One-shot 7-day reading for popcre/shared-db#5747 Step 7 (read-only).

Same measures as docs/verification/assets-bloat-5747/after.md: public.assets
heap / index / TOAST / total bytes, live row bytes (sum(pg_column_size)),
row count, dead tuples, heap-vs-live ratio (pass <= 2.0). Writes the
after-7d.md body and the issue-comment body (which adds provenance and the
paired search-test-set pointer). Never writes the database.
"""

from __future__ import annotations

import json
import os
import sys
import urllib.request
from datetime import datetime, timezone

PROJECT_REF = os.environ.get("PROJECT_REF", "qsllyeztdwjgirsysgai")
TOKEN = os.environ["SUPABASE_ACCESS_TOKEN"]
PASS_HEAP_LIVE_RATIO = 2.0
QUERY = """
select
  pg_relation_size('public.assets')::bigint as heap_bytes,
  pg_indexes_size('public.assets')::bigint as index_bytes,
  (pg_table_size('public.assets') - pg_relation_size('public.assets'))::bigint as toast_bytes,
  (select n_dead_tup from pg_stat_user_tables where relid = 'public.assets'::regclass)::bigint as dead_tuples,
  now() as read_at
"""


def query(sql: str) -> list[dict]:
    body = json.dumps({"query": sql}).encode()
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{PROJECT_REF}/database/query",
        data=body,
        headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=120) as res:
        return json.load(res)


def mb(n: float) -> str:
    return f"{n / 1048576:,.0f} MB"


def main() -> int:
    sizes = query(QUERY)[0]
    live = query(
        "select sum(pg_column_size(t))::bigint as live_bytes, count(*)::bigint as rows from public.assets t"
    )[0]
    heap = int(sizes["heap_bytes"])
    index = int(sizes["index_bytes"])
    toast = int(sizes["toast_bytes"])
    live_bytes = int(live["live_bytes"])
    rows = int(live["rows"])
    dead = int(sizes["dead_tuples"])
    ratio = heap / live_bytes if live_bytes else float("inf")
    passed = ratio <= PASS_HEAP_LIVE_RATIO
    read_at = str(sizes["read_at"])

    md = f"""# public.assets 7-day reading (popcre/shared-db#5747 Step 7)

Captured read-only on production `{PROJECT_REF}` by scheduled workflow (one-shot,
2026-11-12 9:47 PM EST slot), same measures as `after.md` / `after-24h.md`.

| Measure | After repack (Nov 5) | 24 h (Nov 8) | 7-day (this reading) |
|---|---|---|---|
| Heap | 196 MB | 279 MB | {mb(heap)} |
| Indexes | 335 MB | 658 MB | {mb(index)} |
| TOAST | 1 MB | 1 MB | {mb(toast)} |
| Total | 532 MB | 938 MB | {mb(heap + index + toast)} |
| Live row bytes | 193,038,136 B | 217,709,208 B | {live_bytes:,} B |
| Rows (`count(*)`) | 152,234 | 184,383 | {rows:,} |
| Dead tuples | 1,317 | 1,196 | {dead:,} |
| Heap / live bytes | 1.07 | 1.34 | **{ratio:.2f}** (limit {PASS_HEAP_LIVE_RATIO}) |

Heap criterion: {'MET' if passed else 'NOT MET'} (heap ≤ 2× live bytes).
Database read at `{read_at}` (UTC, server clock).

Paired search test set: scheduled the same minute on u2giants/popdam3
["Search test set"](https://github.com/u2giants/popdam3/actions/workflows/search-eval.yml?query=event%3Aschedule)
(label `issue-5747-after-7d`); pass counts are expected to hold vs the 24 h reading
(PopDAM 118/119, PopSG 48/65 + 54/65).

---
*Posted by automation created by ZCode chat sess_8b70908a-3792-40c9-b76c-5b177235da50
on hetz, per Albert's chat instruction "set up automations for these" (Nov 9, 2026).
Read-only SELECTs only. This workflow is one-shot and retires with its PR.*
"""
    with open("/tmp/after-7d.md", "w") as fh:
        fh.write(md)
    with open("/tmp/after-7d-comment.md", "w") as fh:
        fh.write(md)
        fh.write(
            "\n(A full after-7d.md copy is attached to the workflow run artifact; "
            "a session may commit it under docs/verification/assets-bloat-5747/ at will.)\n"
        )
    print(md)
    return 0


if __name__ == "__main__":
    sys.exit(main())
