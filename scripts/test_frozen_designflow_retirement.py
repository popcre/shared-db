"""Synthetic PostgreSQL regression only; never connects to Supabase.

Creates its own loopback-only cluster and empty synthetic databases. No backup,
credential or production row is loaded. Files remain available for inspection.
"""
import json
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / 'supabase/migrations/20260920203316_retire_frozen_designflow_schema.sql'
PROOF = ROOT / '.github/live-proofs/2110.sql'


def postgres_tools():
    """Find one installed PostgreSQL bin directory, including server tools.

    Linux packages often put only psql on PATH and keep initdb/pg_ctl under
    /usr/lib/postgresql/<version>/bin. pg_config identifies the matching bin.
    """
    candidates = []
    pg_config = shutil.which('pg_config')
    if pg_config:
        result = subprocess.run([pg_config, '--bindir'], capture_output=True, text=True)
        if result.returncode == 0:
            candidates.append(Path(result.stdout.strip()))
    candidates.extend(sorted(Path('/usr/lib/postgresql').glob('*/bin'), reverse=True))
    psql = shutil.which('psql')
    if psql:
        candidates.append(Path(psql).resolve().parent)
    for directory in candidates:
        tools = tuple(directory / name for name in ('psql', 'pg_ctl', 'initdb'))
        if all(tool.is_file() for tool in tools):
            return tuple(str(tool) for tool in tools)
        windows_tools = tuple(directory / f'{name}.exe' for name in ('psql', 'pg_ctl', 'initdb'))
        if all(tool.is_file() for tool in windows_tools):
            return tuple(str(tool) for tool in windows_tools)
    raise RuntimeError('Installed PostgreSQL psql, pg_ctl and initdb binaries required')

FIXTURE = '''
CREATE SCHEMA app; CREATE SCHEMA plm; CREATE SCHEMA dflow;
CREATE SCHEMA designflow_frozen_20260710;
CREATE TABLE designflow_frozen_20260710."Roles"("Id" integer PRIMARY KEY, "Name" text);
INSERT INTO designflow_frozen_20260710."Roles" SELECT n,'role-'||n FROM generate_series(1,5) n;
CREATE TABLE dflow."Roles" (LIKE designflow_frozen_20260710."Roles" INCLUDING ALL);
ALTER TABLE dflow."Roles" ADD COLUMN app_role_id uuid;
INSERT INTO dflow."Roles" SELECT *,NULL FROM designflow_frozen_20260710."Roles";
CREATE TABLE designflow_frozen_20260710.art_piece(id integer PRIMARY KEY, art_description text, art_number text, created_at timestamp, art_source_id integer, updated_at timestamp, updated_by integer);
INSERT INTO designflow_frozen_20260710.art_piece SELECT n,'synthetic-'||n,'art-'||n,'2026-07-10',1,'2026-07-10',1 FROM generate_series(1,1114) n;
CREATE TABLE dflow.art_piece (LIKE designflow_frozen_20260710.art_piece INCLUDING ALL);
INSERT INTO dflow.art_piece SELECT * FROM designflow_frozen_20260710.art_piece;
UPDATE dflow.art_piece SET art_source_id=2,updated_at='2026-09-20',updated_by=2;
CREATE TABLE app."RolePermissions"(id integer PRIMARY KEY,"RoleId" integer NOT NULL,CONSTRAINT "RolePermissions_RoleId_fkey" FOREIGN KEY("RoleId") REFERENCES designflow_frozen_20260710."Roles"("Id"));
INSERT INTO app."RolePermissions" SELECT n,1+n%2 FROM generate_series(1,4) n;
CREATE TABLE plm.art_piece_attachment(id integer PRIMARY KEY,art_piece_id integer NOT NULL,CONSTRAINT art_piece_attachment_art_piece_id_fkey FOREIGN KEY(art_piece_id) REFERENCES designflow_frozen_20260710.art_piece(id));
INSERT INTO plm.art_piece_attachment SELECT n,1+n%1114 FROM generate_series(1,2276) n;
'''
for table, count in [('Factory',175),('artists',14),('comments',13),('customers',57),('product_category',7)]:
    FIXTURE += f'CREATE TABLE designflow_frozen_20260710."{table}"(id integer PRIMARY KEY); INSERT INTO designflow_frozen_20260710."{table}" SELECT generate_series(1,{count});\n'
for seq in ['Factory_id_seq','Roles_Id_seq','StandardizedVersionDetail_id_seq','StandardizedVersion_id_seq','art_piece_id_seq','artists_id_seq','comments_id_seq','customers_customers_id_seq','product_category_id_seq']:
    FIXTURE += f'CREATE SEQUENCE designflow_frozen_20260710."{seq}";\n'
# Include both owned and unowned sequences and an internal foreign key.
FIXTURE += '''ALTER SEQUENCE designflow_frozen_20260710.art_piece_id_seq OWNED BY designflow_frozen_20260710.art_piece.id;
ALTER TABLE designflow_frozen_20260710.comments ADD CONSTRAINT internal_art FOREIGN KEY(id) REFERENCES designflow_frozen_20260710.art_piece(id);
'''


class RetirementTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = Path(tempfile.mkdtemp(prefix='2110-synthetic-postgres-'))
        with socket.socket() as s:
            s.bind(('127.0.0.1', 0))
            cls.port = s.getsockname()[1]
        cls.psql, cls.pgctl, cls.initdb = postgres_tools()
        cls.counter = 0
        subprocess.run([cls.initdb,'-D',str(cls.directory / 'data'),'-U','postgres','-A','trust','--no-locale'],check=True,capture_output=True)
        # Windows postgres inherits pg_ctl handles: use a file, never a pipe
        # whose EOF would wait for the database server to exit.
        with (cls.directory / 'start.log').open('wb') as output:
            subprocess.run([cls.pgctl,'-D',str(cls.directory / 'data'),'-l',str(cls.directory / 'server.log'),'-o',f'-h 127.0.0.1 -p {cls.port}','-w','start'],check=True,stdout=output,stderr=output,timeout=60)

    @classmethod
    def tearDownClass(cls):
        subprocess.run([cls.pgctl,'-D',str(cls.directory / 'data'),'-m','fast','-w','stop'],check=True,capture_output=True)
        print(json.dumps({'synthetic_cluster_stopped': True, 'retained_for_inspection': str(cls.directory)}))

    def sql(self, text, database=None):
        return subprocess.run([self.psql,'-X','-h','127.0.0.1','-p',str(self.port),'-U','postgres','-d',database or self.database,'-At','-v','ON_ERROR_STOP=1'],input=text,text=True,capture_output=True)

    def setUp(self):
        type(self).counter += 1
        self.database = f'synthetic_{self.counter}'
        self.assertEqual(self.sql(f'CREATE DATABASE {self.database};','postgres').returncode,0)
        result = self.sql(FIXTURE)
        self.assertEqual(result.returncode,0,result.stderr)

    def assert_abort(self, modification, cause):
        result = self.sql(modification)
        self.assertEqual(result.returncode,0,result.stderr)
        result = self.sql(MIGRATION.read_text())
        self.assertNotEqual(result.returncode,0)
        self.assertIn(cause,result.stderr)
        unchanged = self.sql('''SELECT to_regnamespace('designflow_frozen_20260710') IS NOT NULL,
          (SELECT count(*) FROM plm.art_piece_attachment)=2276,
          (SELECT count(*) FROM app."RolePermissions")=4,
          (SELECT count(*) FROM pg_constraint WHERE conname IN ('RolePermissions_RoleId_fkey','art_piece_attachment_art_piece_id_fkey') AND confrelid IN ('designflow_frozen_20260710."Roles"'::regclass,'designflow_frozen_20260710.art_piece'::regclass))=2;''')
        self.assertEqual(unchanged.stdout.strip(),'t|t|t|t',unchanged.stderr)

    def test_success_and_preserved_children(self):
        result = self.sql(MIGRATION.read_text())
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(self.sql(PROOF.read_text()).stdout.strip(),'t')
        self.assertEqual(self.sql('SELECT (SELECT count(*) FROM plm.art_piece_attachment),(SELECT count(*) FROM app."RolePermissions"),(SELECT count(*) FROM dflow.art_piece WHERE art_source_id=2);').stdout.strip(),'2276|4|1114')

    def test_unknown_table_aborts(self):
        self.assert_abort('CREATE TABLE designflow_frozen_20260710.unexpected(id int);','relation inventory changed')

    def test_unknown_sequence_aborts(self):
        self.assert_abort('CREATE SEQUENCE designflow_frozen_20260710.unexpected;','sequence inventory changed')

    def test_external_view_aborts(self):
        self.assert_abort('CREATE VIEW public.unexpected AS SELECT id FROM designflow_frozen_20260710.art_piece;','unknown external dependency')

    def test_external_routine_text_aborts(self):
        self.assert_abort("CREATE FUNCTION public.unexpected() RETURNS integer LANGUAGE plpgsql AS $$BEGIN RETURN (SELECT count(*)::integer FROM designflow_frozen_20260710.art_piece); END$$;",'routine text references frozen schema')

    def test_changed_identity_aborts(self):
        self.assert_abort("UPDATE dflow.art_piece SET art_description='changed' WHERE id=1;",'art parent identity changed')

    def test_missing_live_parent_aborts(self):
        self.assert_abort('DELETE FROM dflow.art_piece WHERE id=1;','art parent identity changed')

    def test_changed_fk_actions_abort(self):
        self.assert_abort('ALTER TABLE app."RolePermissions" DROP CONSTRAINT "RolePermissions_RoleId_fkey"; ALTER TABLE app."RolePermissions" ADD CONSTRAINT "RolePermissions_RoleId_fkey" FOREIGN KEY("RoleId") REFERENCES designflow_frozen_20260710."Roles"("Id") ON DELETE CASCADE;','original foreign key contract changed')

    def test_unexpected_type_rolls_back_completed_ddl(self):
        self.assert_abort("CREATE TYPE designflow_frozen_20260710.unexpected AS ENUM ('synthetic');",'other objects depend on it')

    def test_row_inventory_change_aborts(self):
        self.assert_abort('INSERT INTO designflow_frozen_20260710."Factory" VALUES (999);','row inventory no longer matches')


if __name__ == '__main__':
    unittest.main()
