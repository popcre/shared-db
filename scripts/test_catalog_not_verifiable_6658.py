"""Post-apply verification distinguishes delivery from catalog evidence.

No database. Derivation, reporting, and enforcement on temporary files.
"""
from __future__ import annotations

import contextlib
import io
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))

from production_catalog_verification import (  # noqa: E402
    derive_targets,
    render_report,
    verify,
)

VERSION = "20261204000300"


def write_migration(root: Path, sql: str) -> Path:
    migrations = root / "supabase" / "migrations"
    migrations.mkdir(parents=True)
    path = migrations / f"{VERSION}_t.sql"
    path.write_text(sql, encoding="utf-8")
    return path


def render(sql: str, catalog=None):
    with tempfile.TemporaryDirectory() as tmp:
        path = write_migration(Path(tmp), sql)
        targets = derive_targets({VERSION: path}, [VERSION])
        return targets, render_report([VERSION], targets, catalog, None, [], True)


class NotVerifiableFailsEnforcement(unittest.TestCase):
    def test_opaque_batch_fails_enforcement_without_catalog_evidence(self):
        sql = "do $$ begin execute 'create table public.opaque (id int)'; end $$;\n"
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_migration(root, sql)
            out = root / "out"
            with (
                mock.patch("production_catalog_verification.run_query") as query,
                contextlib.redirect_stdout(io.StringIO()),
                contextlib.redirect_stderr(io.StringIO()) as stderr,
            ):
                status = verify(root, VERSION, out, "synthetic", "synthetic", enforcing=True)
            query.assert_not_called()
            markdown = (out / "production-catalog-verification.md").read_text(encoding="utf-8")
        self.assertEqual(status, 1)
        self.assertIn("proved nothing", stderr.getvalue())
        self.assertIn("Not verifiable by catalog", markdown)
        self.assertIn("No catalog evidence was produced", markdown)
        self.assertIn("ledger", markdown.lower())

    def test_rejected_noop_claim_still_fails(self):
        sql = "-- catalog-verification: no-op meh\nupdate plm.widget set a = 1;\n"
        targets, (_, failures) = render(sql)
        self.assertTrue(failures)
        self.assertIn("REJECTED", failures[0])

    def test_readable_mismatch_still_fails(self):
        sql = "create table public.no_such_expected (id int);\n"
        targets, (_, failures) = render(
            sql, catalog={"relations": [{"name": "public.no_such_expected", "to_regclass": None}]}
        )
        self.assertFalse(targets.is_empty())
        self.assertTrue(failures)

    def test_absent_catalog_with_real_targets_still_fails(self):
        sql = "create table public.real_target (id int);\n"
        targets, (_, failures) = render(sql, catalog=None)
        self.assertFalse(targets.is_empty())
        self.assertTrue(failures)
        self.assertIn("NO evidence", failures[0])


if __name__ == "__main__":
    unittest.main()
