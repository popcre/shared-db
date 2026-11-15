"""Offline regression checks for the batch-7 relationship migration (#6383)."""
from pathlib import Path
import re
import unittest

from scripts.production_catalog_verification import load_behavior_sidecars


ROOT = Path(__file__).resolve().parents[1]
VERSION = "20261115172649"
MIGRATION = ROOT / "supabase/migrations/20261115172649_sandbox_catchup_core_relationships.sql"


class CoreRelationshipCatchupTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")

    def test_constraint_triggers_use_create_trigger_syntax(self):
        self.assertNotRegex(
            self.sql,
            r'(?im)^alter table\s+\S+\s+add constraint\s+"[^"]+"\s+TRIGGER\b',
        )
        triggers = re.findall(
            r"(?im)^CREATE CONSTRAINT TRIGGER assert_canonical_edge_still_supported\b[^;]+;",
            self.sql,
        )
        self.assertEqual(len(triggers), 4)
        for trigger in triggers:
            self.assertIn("DEFERRABLE INITIALLY DEFERRED FOR EACH ROW", trigger)
            self.assertIn("EXECUTE FUNCTION core.assert_canonical_edge_still_supported(", trigger)

    def test_support_function_is_complete_before_first_constraint_trigger(self):
        definition = "CREATE OR REPLACE FUNCTION core.assert_canonical_edge_still_supported()"
        self.assertEqual(self.sql.count(definition), 1)
        start = self.sql.index(definition)
        end = self.sql.index("$function$\n;", start)
        self.assertLess(end, self.sql.index("CREATE CONSTRAINT TRIGGER"))
        revoke = "revoke all on function core.assert_canonical_edge_still_supported() from public, anon, authenticated;"
        self.assertLess(self.sql.index(revoke), self.sql.index("CREATE CONSTRAINT TRIGGER"))

    def test_current_views_have_single_statement_terminators(self):
        self.assertEqual(len(re.findall(r"(?m)^  WHERE is_current;$", self.sql)), 4)
        self.assertNotIn(";;", self.sql)

    def test_verification_sidecar_matches_migration(self):
        sidecar = ROOT / "scripts/production-verification-sidecars" / f"{VERSION}.json"
        self.assertTrue(sidecar.is_file())
        load_behavior_sidecars(ROOT, {VERSION: MIGRATION}, [VERSION])


if __name__ == "__main__":
    unittest.main()
