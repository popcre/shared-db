# shared-db#1941 — load Laura and Ilona's Creative-to-Submissions decisions

Owner request on shared-db#1941 (2026-10-08): do the linking from the returned answers.

- `run.js` + `q.sql`: read-only snapshot of the Scraped Properties inventory (same logic as api.db_data_admin_scraped_source_inventory, live body).
- `parse.js`: reads the returned spreadsheet; keeps only rows with exactly one clear answer and still unmapped live. rows marked "No matching Submissions property exists" stay open (not excluded). Data files are local only (.gitignore): licensed rows never enter this public repo.
- `load.js`: one transaction; target proof = server identity + exact ledger size from the dry run (EXPECT_BEFORE); workbook digest checked; appends one superseding approved version per identity (append-only; nothing updated or deleted); asserts EXPECT_DECISIONS and EXPECT_MEMBERS; dry-run unless COMMIT=1. Dry run on production 2026-10-08: ledger 1411, 495 decisions (188 mapped, 307 excluded), 339 members, rolled back.
