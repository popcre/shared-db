"""Immutable failed rehearsal retirement; no database or credentials."""
from pathlib import Path
import hashlib
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from post_batch_app_verification import resolve_batch
from production_migration_guard import classify_pending_version, RETIRED_VERSION_REASONS

VERSION = "20261105142616"


class FailedCurationRetirement(unittest.TestCase):
    def test_immutable_failed_source_is_preserved(self):
        path = ROOT / "supabase/migrations/20261105142616_publisher_character_curation.sql"
        self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(),
                         "faa341b2e472907f1e31275068b4c258272f6e0df782401cfaaec000faeb9059")

    def test_native_classifier_never_replays_failed_version_on_either_target(self):
        for target in ("preview", "production"):
            with self.subTest(target=target):
                self.assertEqual(classify_pending_version(VERSION, set(), ROOT, target=target)["kind"], "retired")
        self.assertTrue(any("RETIRED MIGRATION" in p for p in resolve_batch(None, VERSION).problems))
        self.assertIn("42060060160", RETIRED_VERSION_REASONS[VERSION])


if __name__ == "__main__":
    unittest.main()
