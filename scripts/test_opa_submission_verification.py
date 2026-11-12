"""Offline checks for the OPA migration's behavioral verification binding."""
import unittest
from pathlib import Path

from production_catalog_verification import CATALOG_CONTRACTS, load_behavior_sidecars
from check_production_verification_sidecars import check_registry

ROOT = Path(__file__).resolve().parents[1]
VERSION = '20261112173641'


class OpaSubmissionVerificationTests(unittest.TestCase):
    def test_hash_bound_sidecar_loads_and_selects_opa_contract(self):
        migration = next((ROOT / 'supabase/migrations').glob(VERSION + '_*.sql'))
        checks = load_behavior_sidecars(ROOT, {VERSION: migration}, [VERSION])
        self.assertEqual(len(checks), 1)
        self.assertEqual(checks[0]['contract'], 'opa_submission_properties_current_v1')
        self.assertEqual(checks[0]['expected_count'], 1)
        self.assertIn(checks[0]['contract'], CATALOG_CONTRACTS)

    def test_registry_includes_all_sidecars(self):
        versions = [p.stem for p in (ROOT / 'scripts/production-verification-sidecars').glob('*.json')]
        check_registry(ROOT, versions)


if __name__ == '__main__':
    unittest.main()
