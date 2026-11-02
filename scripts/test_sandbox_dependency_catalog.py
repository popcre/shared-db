"""Regression coverage for pre-ledger sandbox dependencies (#4578)."""
import tempfile
import unittest
import sys
from pathlib import Path
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
from production_migration_guard import GuardError, preflight_batch, read_sandbox_dependencies


class SandboxDependencies(unittest.TestCase):
    def read(self, rows=None, ledger="sandbox", target="xupnyeifmpsacrqahwwm", returned=None):
        query = Mock(return_value=rows if rows is not None else [{"name": "dflow.sample"}])
        fetch = Mock(return_value={"id": returned or target})
        result = read_sandbox_dependencies(ledger, target, "test-token", query, fetch)
        query.assert_called_once()
        return result

    def test_catalog_proves_existing_relation(self):
        self.assertEqual(self.read(), frozenset({"dflow.sample"}))

    def test_other_targets_and_wrong_returned_identity_refuse(self):
        for args in ({"ledger": "production"}, {"ledger": "preview"},
                     {"target": "qsllyeztdwjgirsysgai"}, {"returned": "wrong-project"}):
            with self.subTest(args=args), self.assertRaises(GuardError):
                self.read(**args)

    def test_unreadable_or_malformed_catalog_refuses(self):
        for rows in ([], {}, [{"name": "public.sample"}], [{"name": "dflow.sample"}] * 2):
            with self.subTest(rows=rows), self.assertRaises(GuardError):
                self.read(rows=rows)

    def test_missing_dependency_still_refuses_and_live_proof_rescues_only_present_one(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            creator, change = root / "base.sql", root / "change.sql"
            creator.write_text("CREATE TABLE dflow.sample(id int);")
            change.write_text("ALTER TABLE dflow.sample ADD COLUMN quantity int;")
            migrations = {"20260101000000": creator, "20260102000000": change}
            with self.assertRaises(GuardError):
                preflight_batch(migrations, ["20260102000000"], set())
            preflight_batch(migrations, ["20260102000000"], set(), self.read())
            change.write_text("DROP TABLE dflow.sample; ALTER TABLE dflow.sample ADD COLUMN quantity int;")
            with self.assertRaises(GuardError):
                preflight_batch(migrations, ["20260102000000"], set(), self.read())


if __name__ == "__main__":
    unittest.main()
