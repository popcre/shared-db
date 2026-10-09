"""Isolated PG16 regression; never connects to production or reads credentials."""
import os
from pathlib import Path
import subprocess
import time
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / 'supabase/migrations/20261009040550_dflow_users_email_ci_unique_forward.sql'
CONTRACT = ROOT / 'supabase/tests/dflow_users_email_ci_unique_contracts.sql'


@unittest.skipUnless(os.environ.get('RUN_4060_PG16') == '1', 'explicit isolated PG16 execution required')
class ForwardMigrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.container = 'codex-4060-pg16-' + uuid.uuid4().hex[:12]
        subprocess.run(['docker', 'run', '--detach', '--network', 'none', '--name', cls.container,
                        '-e', 'POSTGRES_HOST_AUTH_METHOD=trust', 'postgres:16'], check=True, capture_output=True)
        cls.addClassCleanup(lambda: subprocess.run(['docker', 'rm', '-f', cls.container], check=True, capture_output=True))
        for _ in range(60):
            ready = subprocess.run(['docker', 'exec', cls.container, 'pg_isready', '-U', 'postgres'], capture_output=True)
            if ready.returncode == 0:
                return
            time.sleep(.25)
        raise RuntimeError('isolated PostgreSQL did not become ready')

    def sql(self, text, database=None):
        return subprocess.run(['docker', 'exec', '-i', self.container, 'psql', '-X', '-v', 'ON_ERROR_STOP=1',
                               '-U', 'postgres', '-d', database or self.database, '-At'],
                              input=text, text=True, capture_output=True)

    def setUp(self):
        self.database = 'test_' + uuid.uuid4().hex
        self.assertEqual(self.sql('CREATE DATABASE ' + self.database, 'postgres').returncode, 0)
        self.assertEqual(self.sql('CREATE SCHEMA dflow; CREATE TABLE dflow.users(id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,name text,email text); INSERT INTO dflow.users(name,email) VALUES (\'existing\',\'existing@example.test\');').returncode, 0)

    def assert_success(self, result):
        self.assertEqual(result.returncode, 0, result.stderr)

    def assert_preserved(self):
        self.assertEqual(self.sql('SELECT count(*) FROM ONLY dflow.users').stdout.strip(), '1')
        self.assertEqual(self.sql("SELECT name || ':' || email FROM ONLY dflow.users").stdout.strip(), 'existing:existing@example.test')

    def test_correct_source_and_behavior_rollback_preserve_users(self):
        self.assert_success(self.sql(MIGRATION.read_text()))
        sequence_before = self.sql('SELECT last_value,is_called FROM dflow.users_id_seq').stdout
        self.assert_success(self.sql(CONTRACT.read_text()))
        self.assertEqual(self.sql('SELECT last_value,is_called FROM dflow.users_id_seq').stdout, sequence_before)
        self.assert_preserved()
        self.assert_success(self.sql("INSERT INTO dflow.users(name,email) VALUES ('normal','normal@example.test')"))
        rejected = self.sql("INSERT INTO dflow.users(name,email) VALUES ('duplicate',' EXISTING@EXAMPLE.TEST ')")
        self.assertNotEqual(rejected.returncode, 0)
        self.assertIn('users_email_lower_uidx', rejected.stderr)
        self.assertEqual(self.sql('SELECT count(*) FROM ONLY dflow.users').stdout.strip(), '2')

    def test_historical_preview_then_forward_preserves_exact_index_and_users(self):
        old = ROOT / 'supabase/migrations/20261007232712_dflow_users_email_ci_unique.sql'
        self.assert_success(self.sql(old.read_text()))
        fingerprint = "SELECT i.indexrelid, pg_get_indexdef(i.indexrelid),obj_description(i.indexrelid,'pg_class') FROM pg_index i WHERE i.indexrelid='dflow.users_email_lower_uidx'::regclass"
        before = self.sql(fingerprint).stdout
        sequence_before = self.sql('SELECT last_value,is_called FROM dflow.users_id_seq').stdout
        self.assert_success(self.sql(MIGRATION.read_text()))
        self.assertEqual(self.sql(fingerprint).stdout, before)
        self.assertEqual(self.sql('SELECT last_value,is_called FROM dflow.users_id_seq').stdout, sequence_before)
        self.assert_preserved()
        self.assert_success(self.sql(CONTRACT.read_text()))
        self.assert_preserved()

    def test_varchar_historical_preview_then_forward_preserves_index(self):
        self.assert_success(self.sql('ALTER TABLE dflow.users ALTER COLUMN email TYPE varchar(255)'))
        old = ROOT / 'supabase/migrations/20261007232712_dflow_users_email_ci_unique.sql'
        self.assert_success(self.sql(old.read_text()))
        fingerprint = "SELECT i.indexrelid, pg_get_indexdef(i.indexrelid),obj_description(i.indexrelid,'pg_class') FROM pg_index i WHERE i.indexrelid='dflow.users_email_lower_uidx'::regclass"
        before = self.sql(fingerprint).stdout
        self.assert_success(self.sql(MIGRATION.read_text()))
        self.assertEqual(self.sql(fingerprint).stdout, before)
        self.assert_success(self.sql(CONTRACT.read_text()))
        self.assert_preserved()

    def test_varchar_wrong_normalization_refuses(self):
        self.assert_success(self.sql('ALTER TABLE dflow.users ALTER COLUMN email TYPE varchar(255)'))
        for expression in ['lower(email)', 'btrim(email)']:
            with self.subTest(expression=expression):
                self.assert_success(self.sql("CREATE UNIQUE INDEX users_email_lower_uidx ON dflow.users(" + expression + ") WHERE nullif(btrim(email),'') IS NOT NULL"))
                result = self.sql(MIGRATION.read_text())
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('exact contract refused', result.stderr)
                self.assertNotEqual(self.sql(CONTRACT.read_text()).returncode, 0)
                self.assert_preserved()
                self.assert_success(self.sql('DROP INDEX dflow.users_email_lower_uidx'))

    def test_nonbuiltin_text_domain_refuses_before_rows(self):
        self.assert_success(self.sql('CREATE DOMAIN dflow.custom_email AS text; ALTER TABLE dflow.users ALTER COLUMN email TYPE dflow.custom_email'))
        for existing in [False, True]:
            with self.subTest(existing_index=existing):
                if existing:
                    self.assert_success(self.sql("CREATE UNIQUE INDEX users_email_lower_uidx ON dflow.users(lower(btrim(email))) WHERE nullif(btrim(email),'') IS NOT NULL"))
                result = self.sql(MIGRATION.read_text())
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('email must be builtin text or varchar', result.stderr)
                self.assert_preserved()

    def test_exact_existing_forward_replay_is_noop(self):
        self.assert_success(self.sql(MIGRATION.read_text()))
        before = self.sql("SELECT 'dflow.users_email_lower_uidx'::regclass::oid,pg_get_indexdef('dflow.users_email_lower_uidx'::regclass)").stdout
        self.assert_success(self.sql(MIGRATION.read_text()))
        self.assertEqual(self.sql("SELECT 'dflow.users_email_lower_uidx'::regclass::oid,pg_get_indexdef('dflow.users_email_lower_uidx'::regclass)").stdout, before)
        self.assert_preserved()

    def test_mismatched_existing_index_refuses(self):
        indexes = [
            'CREATE INDEX users_email_lower_uidx ON dflow.users(email)',
            'CREATE UNIQUE INDEX users_email_lower_uidx ON dflow.users(lower(email))',
        ]
        for definition in indexes:
            with self.subTest(definition=definition):
                self.assert_success(self.sql(definition))
                before = self.sql("SELECT pg_get_indexdef('dflow.users_email_lower_uidx'::regclass)").stdout
                result = self.sql(MIGRATION.read_text())
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('existing dflow.users_email_lower_uidx exact contract refused', result.stderr)
                self.assertEqual(self.sql("SELECT pg_get_indexdef('dflow.users_email_lower_uidx'::regclass)").stdout, before)
                self.assert_preserved()
                self.assert_success(self.sql('DROP INDEX dflow.users_email_lower_uidx'))

    def test_wrong_index_contract_refuses_before_insert(self):
        definitions = [
            'CREATE UNIQUE INDEX users_email_lower_uidx ON dflow.users(lower(email))',
            'CREATE UNIQUE INDEX users_email_lower_uidx ON dflow.users(lower(btrim(email)))',
            'CREATE INDEX users_email_lower_uidx ON dflow.users(lower(btrim(email))) WHERE nullif(btrim(email),\'\') IS NOT NULL',
            'CREATE UNIQUE INDEX users_email_lower_uidx ON dflow.users(lower(btrim(email)) text_pattern_ops) WHERE nullif(btrim(email),\'\') IS NOT NULL',
            'CREATE UNIQUE INDEX users_email_lower_uidx ON dflow.users(lower(btrim(email)) COLLATE "C") WHERE nullif(btrim(email),\'\') IS NOT NULL',
            'CREATE UNIQUE INDEX users_email_lower_uidx ON dflow.users(lower(btrim(email))) WITH (fillfactor=80) WHERE nullif(btrim(email),\'\') IS NOT NULL',
            'CREATE UNIQUE INDEX users_email_lower_uidx ON dflow.users(lower(btrim(email)) DESC) WHERE nullif(btrim(email),\'\') IS NOT NULL',
            'CREATE UNIQUE INDEX users_email_lower_uidx ON dflow.users(lower(btrim(email))) INCLUDE(name) WHERE nullif(btrim(email),\'\') IS NOT NULL',
        ]
        for definition in definitions:
            with self.subTest(definition=definition):
                self.assert_success(self.sql(definition))
                definition_before = self.sql("SELECT pg_get_indexdef('dflow.users_email_lower_uidx'::regclass)").stdout
                migration_result = self.sql(MIGRATION.read_text())
                self.assertNotEqual(migration_result.returncode, 0)
                self.assertIn('existing dflow.users_email_lower_uidx exact contract refused', migration_result.stderr)
                self.assertEqual(self.sql("SELECT pg_get_indexdef('dflow.users_email_lower_uidx'::regclass)").stdout, definition_before)
                result = self.sql(CONTRACT.read_text())
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('exact normalized nonblank index contract refused', result.stderr)
                self.assert_preserved()
                self.assert_success(self.sql('DROP INDEX dflow.users_email_lower_uidx'))

    def test_duplicate_groups_refuse_without_index_or_row_rewrite(self):
        self.assert_success(self.sql("INSERT INTO dflow.users(name,email) VALUES ('duplicate',' EXISTING@EXAMPLE.TEST ');"))
        result = self.sql(MIGRATION.read_text())
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('case-insensitive duplicate email group', result.stderr)
        self.assertEqual(self.sql("SELECT to_regclass('dflow.users_email_lower_uidx') IS NULL").stdout.strip(), 't')
        self.assertEqual(self.sql('SELECT count(*) FROM ONLY dflow.users').stdout.strip(), '2')

    def test_inheritance_refuses_before_rows_or_index(self):
        self.assert_success(self.sql('CREATE TABLE dflow.child() INHERITS(dflow.users)'))
        result = self.sql(MIGRATION.read_text())
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('inheritance is unsupported', result.stderr)
        self.assertEqual(self.sql("SELECT to_regclass('dflow.users_email_lower_uidx') IS NULL").stdout.strip(), 't')
        self.assert_preserved()
