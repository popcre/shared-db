"""Fixed successor target binding; no credentials or live database calls."""
import copy
import hashlib
import io
from contextlib import redirect_stderr
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import atomic_migration_apply as atomic

RAW = (atomic.ROOT / 'supabase/migrations/20261105182200_target_bound_publisher_character_curation.sql').read_text()


class TargetBinding(unittest.TestCase):
    def connection(self, target):
        ref = atomic.CURATED_TARGET_PROJECTS[target]
        url = f'postgres://postgres.{ref}@pooler.example.invalid:6543/postgres'
        env = {'PGUSER': f'postgres.{ref}', 'PGHOST': 'pooler.example.invalid', 'PGPORT': '6543',
               'PGDATABASE': 'postgres', 'PGSSLMODE': 'require', 'EXPECTED_PROJECT_REF': ref}
        return ref, url, env

    def test_both_fixed_targets_bind_actual_linked_fields(self):
        for target in atomic.CURATED_TARGET_PROJECTS:
            with self.subTest(target=target):
                ref, url, env = self.connection(target)
                context = atomic.verified_curated_target(target, ref, url, env)
                wrapper = atomic.build_wrapper(atomic.CURATED_TARGET_VERSION, 'fixed', RAW, [RAW],
                    admission_lock_contract=atomic.CURATED_TARGET_CONTRACT, curated_target=context)
                self.assertLess(wrapper.index(atomic.CURATED_CHARACTER_LOCK_SQL), wrapper.index('do $curation$'))
                self.assertLess(wrapper.index("SET LOCAL app.curated_character_project = '" + ref), wrapper.index('do $curation$'))
                self.assertIn("transaction_timeout='3s'", wrapper)

    def test_wrong_project_target_and_actual_route_refuse(self):
        for target in atomic.CURATED_TARGET_PROJECTS:
            ref, url, env = self.connection(target)
            other = 'production' if target == 'preview' else 'preview'
            cases = [(other, ref, url, env), (target, atomic.CURATED_TARGET_PROJECTS[other], url, env)]
            for key, value in [('PGUSER', 'postgres.' + atomic.CURATED_TARGET_PROJECTS[other]),
                               ('PGHOST', 'different.invalid'), ('PGPORT', '5432'),
                               ('PGDATABASE', 'different'), ('PGSSLMODE', 'disable'),
                               ('EXPECTED_PROJECT_REF', atomic.CURATED_TARGET_PROJECTS[other])]:
                cases.append((target, ref, url, {**env, key: value}))
            for args in cases:
                with self.subTest(target=target, mismatch=args[0:2]), self.assertRaises(atomic.Refusal):
                    atomic.verified_curated_target(*args)

    def test_wrapper_and_policy_reject_every_unbound_variant(self):
        entry = {'sha256': atomic.CURATED_TARGET_SHA256, 'targets': ['preview', 'production'],
                 'admission_lock_contract': atomic.CURATED_TARGET_CONTRACT}
        for version, changed in [
            ('29990101000000', entry),
            (atomic.CURATED_TARGET_VERSION, {**entry, 'sha256': '0' * 64}),
            (atomic.CURATED_TARGET_VERSION, {**entry, 'admission_lock_contract': 'arbitrary'}),
            (atomic.CURATED_TARGET_VERSION, {**entry, 'tables': ['public.assets']}),
            (atomic.CURATED_TARGET_VERSION, {**entry, 'mode': 'ACCESS EXCLUSIVE'}),
            (atomic.CURATED_TARGET_VERSION, {k:v for k,v in entry.items() if k != 'admission_lock_contract'}),
        ]:
            with tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / 'policy.json'
                path.write_text(json.dumps({'schema_version': 1, 'migrations': {version: changed}}))
                with patch.object(atomic, 'POLICY', path), self.assertRaises(atomic.Refusal):
                    atomic.read_policy()
        for version, raw, contract, context in [
            (atomic.CURATED_TARGET_VERSION, RAW, None, None),
            (atomic.CURATED_TARGET_VERSION, RAW, atomic.CURATED_TARGET_CONTRACT, None),
            (atomic.CURATED_TARGET_VERSION, RAW + ' ', atomic.CURATED_TARGET_CONTRACT, ('preview', atomic.CURATED_TARGET_PROJECTS['preview'])),
            (atomic.CURATED_TARGET_VERSION, RAW, atomic.CURATED_TARGET_CONTRACT, ('preview', atomic.CURATED_TARGET_PROJECTS['production'])),
            ('29990101000000', RAW, atomic.CURATED_TARGET_CONTRACT, ('preview', atomic.CURATED_TARGET_PROJECTS['preview'])),
        ]:
            with self.subTest(version=version, contract=contract, context=context), self.assertRaises(atomic.Refusal):
                atomic.build_wrapper(version, 'fixed', raw, [raw], admission_lock_contract=contract, curated_target=context)

    def test_real_linked_connection_route_refuses_cross_target_before_any_database_call(self):
        for target in atomic.CURATED_TARGET_PROJECTS:
            other = 'production' if target == 'preview' else 'preview'
            ref, url, _ = self.connection(other)
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / 'supabase/.temp').mkdir(parents=True)
                (root / 'supabase/.temp/pooler-url').write_text(url)
                argv = ['atomic_migration_apply.py', '--migrations-dir', str(atomic.ROOT / 'supabase/migrations'), '--linked-dir', str(root),
                    '--version', atomic.CURATED_TARGET_VERSION, '--target', target,
                    '--expected-project-ref', ref, '--mode', 'apply']
                output = io.StringIO()
                with patch.object(sys, 'argv', argv), patch.dict(atomic.os.environ,
                        {'EXPECTED_PROJECT_REF': ref, 'SUPABASE_DB_PASSWORD': 'synthetic-local-test-only'}), \
                        patch.object(atomic, 'validate_remote') as remote, \
                        patch.object(atomic, 'psql') as psql, redirect_stderr(output):
                    self.assertEqual(atomic.main(), 2)
                self.assertIn('contradict the fixed target binding', output.getvalue())
                remote.assert_not_called(); psql.assert_not_called()

    def test_exact_source_and_four_check_sidecar(self):
        self.assertEqual(hashlib.sha256(RAW.encode()).hexdigest(), atomic.CURATED_TARGET_SHA256)
        sidecar = json.loads((atomic.ROOT / 'scripts/production-verification-sidecars/20261105182200.json').read_text())
        self.assertEqual(sidecar['migration_sha256'], atomic.CURATED_TARGET_SHA256)
        self.assertEqual(len(sidecar['checks']), 4)
        predecessor = json.loads((atomic.ROOT / 'scripts/production-verification-sidecars/20261105142616.json').read_text())
        self.assertTrue({row['id'] for row in sidecar['checks']}.isdisjoint(row['id'] for row in predecessor['checks']))


if __name__ == '__main__':
    unittest.main()
