"""Offline contracts for the #6356 lifecycle catch-up and #6379 repairs."""
from pathlib import Path
import re
import unittest

from scripts.check_production_verification_sidecars import migrations
from scripts.production_catalog_verification import load_behavior_sidecars


REPO = Path(__file__).resolve().parents[1]
VERSION = '20261115163555'
MIGRATION = REPO / 'supabase/migrations' / f'{VERSION}_sandbox_catchup_lifecycle_tables.sql'
SQL = MIGRATION.read_text(encoding='utf-8')
DDL = SQL.split('CREATE OR REPLACE FUNCTION', 1)[0]


class LifecycleCatchupTests(unittest.TestCase):
    def test_lifecycle_access_matches_production(self):
        for provider in ('nbcu', 'peanuts', 'wildbrain'):
            for suffix in ('entity_lifecycle', 'lifecycle_publication'):
                table = f'plm.{provider}_{suffix}'
                with self.subTest(table=table):
                    revoke = f'revoke all on table {table} from public, anon, authenticated, service_role;'
                    grant = f'grant select on table {table} to authenticated, service_role;'
                    self.assertIn(revoke, DDL)
                    self.assertIn(grant, DDL)
                    self.assertLess(DDL.index(revoke), DDL.index(grant))
                    self.assertEqual(re.findall(rf'^grant (.*) on table {table} to (.*);$', DDL, re.M),
                                     [('select', 'authenticated, service_role')])

    def test_option_loader_permissions_match_their_sources(self):
        for provider in ('peanuts', 'wildbrain'):
            table = f'plm.{provider}_submission_property_option'
            self.assertIn(f'revoke all on table {table} from public, anon, authenticated, service_role;', DDL)
            self.assertIn(f'grant select, insert on table {table} to service_role;', DDL)
            self.assertIn(f'grant select on table {table} to authenticated;', DDL)
        self.assertIn('revoke all on table plm.sesame_submission_property_option from public, anon, authenticated;', DDL)
        self.assertIn('grant select, insert, update on table plm.sesame_submission_property_option to service_role;', DDL)

    def test_constraints_are_created_only_with_new_tables(self):
        tables = re.findall(r'create table if not exists (plm\.\w+) \(\n(.*?)\n\);', DDL, re.S)
        self.assertEqual(len(tables), 9)
        self.assertNotRegex(DDL.lower(), r'alter table .* add constraint')
        self.assertEqual(sum(len(re.findall(r'^  constraint ', body, re.M)) for _, body in tables), 73)
        positions = {name: i for i, (name, _) in enumerate(tables)}
        for name, body in tables:
            self.assertRegex(body, r'constraint "\w+_pkey" PRIMARY KEY')
            for target in re.findall(r'REFERENCES (plm\.\w+)\(', body):
                if target in positions:
                    self.assertLessEqual(positions[target], positions[name], f'{name} references {target} before creation')

    def test_policies_can_be_replaced_on_existing_tables(self):
        policies = re.findall(r'^create policy "([^"]+)" on (plm\.\w+)', DDL, re.M)
        self.assertEqual(len(policies), 10)
        for policy, table in policies:
            self.assertIn(f'drop policy if exists "{policy}" on {table};\ncreate policy "{policy}" on {table}', DDL)

    def test_option_data_is_explicitly_outside_this_shape_port(self):
        self.assertIn('option-table seed rows are deliberately not copied', DDL)
        self.assertIn('owning application loads authorized source data (#6356)', DDL)
        self.assertNotRegex(DDL.lower(), r'\binsert\s+into\b')
        self.assertIn('peanuts_submission_property_option_owner_scope_chk', DDL)
        self.assertIn('wildbrain_submission_property_option_owner_scope_chk', DDL)

    def test_sidecar_still_binds_to_migration_and_covers_markers(self):
        # The loader checks the hash and every relocated dynamic-execution marker.
        self.assertEqual(load_behavior_sidecars(REPO, migrations(REPO), [VERSION]), [])


if __name__ == '__main__':
    unittest.main()
