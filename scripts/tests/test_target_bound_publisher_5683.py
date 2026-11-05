"""Disposable PG17 proof. Optional protected packets are never copied to source.

T2_TARGET_PACKET_DIRECTORY may name a private directory containing the existing
preview/production-witness-diagnosis.json captures. Without it, public synthetic
fixtures exercise the same contracts; only fixture witness hashes are substituted
AFTER the real wrapper source/hash validation.
"""
import copy
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import atomic_migration_apply as atomic

URL = os.environ.get('T2_TARGET_TEST_DATABASE_URL', '')
if not re.fullmatch(r'postgres(?:ql)?://postgres@127\.0\.0\.1:\d+/t2_curated_target', URL):
    raise RuntimeError('Dedicated localhost t2_curated_target database required')
RAW = (atomic.ROOT / 'supabase/migrations/20261105182200_target_bound_publisher_character_curation.sql').read_text()
PARENTS = ['a03fff4b-65f4-4fd6-98ad-c9db3216b140', 'b96edc00-9261-46ec-af93-9de0f5b88d48']
PARENT_HASHES = ['c60b4b8c468491a776eeaa2055107d1f', '90251184f71c72503ec125057f347349']
WITNESS_HASHES = {'preview': ['39c07e12bf848133109e25c159b1dc77', 'ac4126d56fdae4ae0548e350d7fbeb48'],
                  'production': ['3f657490a39eb75d2a557f03c2addbc2', '1cd7d09dc8a047f8226b3681eff67efb']}
DIRECTORY = os.environ.get('T2_TARGET_PACKET_DIRECTORY')


def query(sql, ok=True):
    result = subprocess.run(['psql', URL, '-X', '-qAt', '-v', 'ON_ERROR_STOP=1'],
        input="set time zone 'UTC';\n" + sql, text=True, capture_output=True)
    if ok and result.returncode:
        raise AssertionError(result.stderr)
    return result


def packets(target):
    if DIRECTORY:
        data = json.loads((Path(DIRECTORY) / (target + '-witness-diagnosis.json')).read_text())
        if isinstance(data, dict):
            if data['projectRef'] != atomic.CURATED_TARGET_PROJECTS[target]:
                raise AssertionError('Protected packet target does not match fixed native target')
            data = data['body']
        return next(row['data'] for row in data if row['kind'] == 'parents')
    result = []
    for n, parent in enumerate(PARENTS):
        refs = []
        for index in range(2):
            refs.append({'id': f'00000000-0000-4000-8000-{(n*2+index+1)+(100 if target=="preview" else 200):012d}',
                'entity_schema': 'core', 'entity_table': 'licensor', 'entity_id': parent,
                'source_system': 'coldlion', 'source_table': 'fixture', 'source_id': f'fixture-{n}-{index}',
                'source_name': 'Synthetic authority', 'source_code': f'S{n}', 'confidence': 'verified',
                'source_licensor_id': parent, 'raw': {'nested': ['keep', n, index]},
                'created_at': ('2020' if target=='preview' else '2021') + '-01-01T00:00:00+00:00',
                'first_seen_at': '2022-01-01T00:00:00+00:00', 'last_seen_at': '2023-01-01T00:00:00+00:00',
                'missing_since': None})
        result.append({'licensor': {'id': parent, 'name': f'Synthetic parent {n}', 'code': f'S{n}',
            'status': 'active', 'metadata': {}, 'created_at': '2020-01-01T00:00:00+00:00',
            'updated_at': '2020-01-01T00:00:00+00:00'}, 'source_refs': refs})
    return result


class TargetCuration(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        assert 170000 <= int(query('show server_version_num').stdout.strip()) < 180000
        query('''drop schema if exists core cascade; drop schema if exists supabase_migrations cascade; create schema if not exists app; do $$begin create type app.entity_status as enum
        ('active','inactive','archived','deleted','potential'); exception when duplicate_object then null;end$$;
        create schema if not exists core; create schema if not exists supabase_migrations;
        create table core.licensor(id uuid primary key,name text,code text,status app.entity_status,metadata jsonb,created_at timestamptz,updated_at timestamptz);
        create table core.character(id uuid primary key default gen_random_uuid(),licensor_id uuid references core.licensor,name text,code text,status app.entity_status,metadata jsonb);
        create table core.character_alias(character_id uuid,licensor_id uuid,alias text,normalized_alias text);
        create table core.taxonomy_source_ref(id uuid primary key default gen_random_uuid(),entity_schema text,entity_table text,entity_id uuid,source_system text,source_table text,source_id text,source_name text,source_code text,confidence text,source_licensor_id uuid,raw jsonb,created_at timestamptz,first_seen_at timestamptz,last_seen_at timestamptz,missing_since timestamptz,unique(source_system,source_table,source_id));
        create table supabase_migrations.schema_migrations(version text primary key,statements text[],name text);''')

    def seed(self, target):
        query('truncate core.character_alias,core.character,core.taxonomy_source_ref,core.licensor,supabase_migrations.schema_migrations cascade;')
        for item in packets(target):
            for table, rows in [('licensor', [item['licensor']]), ('taxonomy_source_ref', item['source_refs'])]:
                for row in rows:
                    query(f'insert into core.{table} select * from jsonb_populate_record(null::core.{table},'
                        + atomic.dollar_quote(json.dumps(row), 'fixture') + '::jsonb);')
        self.replacements = {}
        for n, parent in enumerate(PARENTS):
            row = query(f"select md5(to_jsonb(l)::text) from core.licensor l where id='{parent}'").stdout.strip()
            refs = query(f"select md5(jsonb_agg(to_jsonb(r) order by id)::text) from core.taxonomy_source_ref r where entity_id='{parent}' and source_system='coldlion'").stdout.strip()
            if DIRECTORY:
                self.assertEqual(row, PARENT_HASHES[n])
                self.assertEqual(refs, WITNESS_HASHES[target][n])
            else:
                self.replacements[PARENT_HASHES[n]] = row
                for fixture_target, hashes in WITNESS_HASHES.items():
                    # Compute distinct target fixture hashes without flattening target selection.
                    other = next(p for p in packets(fixture_target) if p['licensor']['id'] == parent)
                    # PostgreSQL JSONB/timestamptz canonicalization comes from a typed scratch CTE.
                    literal = atomic.dollar_quote(json.dumps(other['source_refs']), 'refs')
                    canonical = query(f"select md5(jsonb_agg(to_jsonb(r) order by id)::text) from jsonb_populate_recordset(null::core.taxonomy_source_ref,{literal}::jsonb) r").stdout.strip()
                    self.replacements[hashes[n]] = canonical
        self.target = target

    def snapshot(self):
        return query("select jsonb_build_object('parents',(select jsonb_agg(to_jsonb(l) order by id) from core.licensor l),'refs',(select jsonb_agg(to_jsonb(r) order by id) from core.taxonomy_source_ref r),'chars',(select jsonb_agg(to_jsonb(c) order by id) from core.character c),'aliases',(select jsonb_agg(to_jsonb(a) order by alias) from core.character_alias a),'ledger',(select jsonb_agg(to_jsonb(m) order by version) from supabase_migrations.schema_migrations m))").stdout.strip()

    def wrapper(self, target=None, marker=True):
        target = target or self.target
        text = atomic.build_wrapper(atomic.CURATED_TARGET_VERSION, 'target_bound_publisher_character_curation', RAW,
            atomic.split_sql(RAW), admission_lock_contract=atomic.CURATED_TARGET_CONTRACT,
            curated_target=(target, atomic.CURATED_TARGET_PROJECTS[target]))
        for old, new in self.replacements.items():
            text = text.replace(old, new)
        if not marker:
            text = re.sub(r"SET LOCAL app\.curated_character_(?:target|project) = '[^']+';\n", '', text)
        return text

    def abstain(self, reason, text=None):
        before = self.snapshot()
        result = query('\\set VERBOSITY verbose\n' + (text or self.wrapper()), ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(reason, result.stderr)
        self.assertEqual(self.snapshot(), before, 'All current rows and ledger must survive refusal unchanged')

    def test_both_complete_target_packets_and_native_typed_catalog(self):
        import production_catalog_verification as native
        for target in atomic.CURATED_TARGET_PROJECTS:
            with self.subTest(target=target):
                self.seed(target); before = json.loads(self.snapshot())
                query(self.wrapper()); after = json.loads(self.snapshot())
                self.assertEqual(after['parents'], before['parents'])
                self.assertEqual([r for r in after['refs'] if r['entity_table']=='licensor'], before['refs'])
                self.assertEqual(len(after['chars']), 2); self.assertEqual(len(after['refs']), 6)
                self.assertIsNone(after['aliases']); self.assertEqual(len(after['ledger']), 1)
                for row in after['chars']:
                    parent = PARENTS.index(row['licensor_id'])
                    expected = WITNESS_HASHES[target][parent]
                    self.assertEqual(row['metadata']['coldlion_witness_md5'], self.replacements.get(expected, expected))
                path = atomic.ROOT / 'supabase/migrations/20261105182200_target_bound_publisher_character_curation.sql'
                checks = native.load_behavior_sidecars(atomic.ROOT, {atomic.CURATED_TARGET_VERSION:path}, [atomic.CURATED_TARGET_VERSION])
                rows = json.loads(query(native.build_behavior_sql(checks)).stdout)['behavior_checks']
                self.assertEqual(len(rows),4); self.assertTrue(all(r['actual_count']==r['expected_count']==1 for r in rows))

    def test_cross_target_missing_and_contradictory_marker_rollback(self):
        for target in atomic.CURATED_TARGET_PROJECTS:
            self.seed(target)
            other = 'production' if target=='preview' else 'preview'
            self.abstain('Unchanged approved parent/source witness unavailable', self.wrapper(other))
            self.abstain('Verified native target context unavailable', self.wrapper(marker=False))
            text = self.wrapper().replace("app.curated_character_target = '"+target, "app.curated_character_target = 'invalid")
            self.abstain('Verified native target context unavailable', text)
            text = self.wrapper().replace("app.curated_character_project = '"+atomic.CURATED_TARGET_PROJECTS[target], "app.curated_character_project = '"+atomic.CURATED_TARGET_PROJECTS[other])
            self.abstain('Verified native target context unavailable', text)

    def test_every_complete_witness_field_and_parent_state_is_guarded(self):
        mutations = [
            "update core.taxonomy_source_ref set id=gen_random_uuid() where entity_id='"+PARENTS[0]+"'",
            *[f"update core.taxonomy_source_ref set {column}={column}+interval '1 microsecond' where entity_id='{PARENTS[0]}'" for column in ('created_at','first_seen_at','last_seen_at')],
            "update core.taxonomy_source_ref set raw='{\"different\":true}' where entity_id='"+PARENTS[0]+"'",
            "do $$declare ids uuid[]; temp_id uuid:=gen_random_uuid(); begin select array_agg(id order by id) into ids from core.taxonomy_source_ref where entity_id='"+PARENTS[0]+"'; update core.taxonomy_source_ref set id=temp_id where id=ids[1]; update core.taxonomy_source_ref set id=ids[1] where id=ids[2]; update core.taxonomy_source_ref set id=ids[2] where id=temp_id; end$$",
            "update core.taxonomy_source_ref set source_system='foreign' where entity_id='"+PARENTS[0]+"'",
            "delete from core.taxonomy_source_ref where id=(select id from core.taxonomy_source_ref limit 1)",
            "update core.taxonomy_source_ref set source_licensor_id='"+PARENTS[1]+"' where entity_id='"+PARENTS[0]+"'",
            "update core.licensor set status='inactive' where id='"+PARENTS[0]+"'",
            "update core.licensor set updated_at=updated_at+interval '1 microsecond' where id='"+PARENTS[0]+"'",
        ]
        for target in atomic.CURATED_TARGET_PROJECTS:
            for mutation in mutations:
                with self.subTest(target=target, mutation=mutation.split(' set ')[-1].split(' where ')[0]):
                    self.seed(target); query(mutation)
                    self.abstain('Unchanged approved parent/source witness unavailable')

    def start_paused(self, text):
        boundary = '  end loop;\n  for candidate'
        self.assertGreaterEqual(text.count(boundary), 1)
        text = text.replace(boundary, "  end loop;\n  raise notice 'PREFLIGHT_FINISHED';\n  perform pg_sleep(0.8);\n  for candidate", 1)
        process = subprocess.Popen(['psql', URL, '-X', '-qAt', '-v', 'ON_ERROR_STOP=1'],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        def cleanup():
            if process.poll() is None:
                process.kill(); process.wait(timeout=5)
            for stream in (process.stdin, process.stdout, process.stderr):
                if stream and not stream.closed: stream.close()
        self.addCleanup(cleanup)
        process.stdin.write(text); process.stdin.close()
        self.assertIn('PREFLIGHT_FINISHED', process.stderr.readline())
        return process

    def finish_paused(self, process):
        process.stdout.read(); error = process.stderr.read(); process.wait(timeout=5)
        self.assertEqual(process.returncode, 0, error)
        self.assertEqual(query('select count(*) from supabase_migrations.schema_migrations').stdout.strip(), '1')

    def test_real_two_connection_barrier_and_mutant_for_both_targets(self):
        for target in atomic.CURATED_TARGET_PROJECTS:
            for mutation in [
                f"insert into core.character values(gen_random_uuid(),'{PARENTS[0]}','Chase',null,'active','{{}}')",
                f"insert into core.character_alias values(gen_random_uuid(),'{PARENTS[1]}','Cheer Bear','cheer bear')",
                f"update core.taxonomy_source_ref set raw='{{\"concurrent\":true}}' where entity_id='{PARENTS[0]}'",
            ]:
                with self.subTest(target=target, mutation=mutation.split()[0:3]):
                    self.seed(target); before=json.loads(self.snapshot()); process=self.start_paused(self.wrapper())
                    result=query("\\set VERBOSITY verbose\nbegin;set local lock_timeout='100ms';set local statement_timeout='2500ms';"+mutation+';commit;',ok=False)
                    self.assertNotEqual(result.returncode,0); self.assertIn('55P03',result.stderr)
                    query("begin;set local lock_timeout='100ms';select id from core.licensor for key share;rollback;")
                    self.finish_paused(process); after=json.loads(self.snapshot())
                    self.assertEqual(after['parents'],before['parents'])
                    self.assertEqual([r for r in after['refs'] if r['entity_table']=='licensor'],before['refs'])
                    self.assertIsNone(after['aliases']); self.assertEqual(len(after['chars']),2)
            # The actual source mutant must wrongly COMMIT, proving this is a race detector.
            self.seed(target)
            text=self.wrapper().replace('LOCK TABLE core.licensor, core.character, core.character_alias, core.taxonomy_source_ref IN SHARE ROW EXCLUSIVE MODE;\n','',1)
            process=self.start_paused(text)
            query(f"update core.taxonomy_source_ref set raw='{{\"concurrent\":true}}' where entity_id='{PARENTS[0]}'")
            competing=query(f"select jsonb_agg(to_jsonb(r) order by id) from core.taxonomy_source_ref r where entity_id='{PARENTS[0]}'").stdout
            self.finish_paused(process)
            self.assertEqual(query(f"select jsonb_agg(to_jsonb(r) order by id) from core.taxonomy_source_ref r where entity_id='{PARENTS[0]}'").stdout,competing)
            self.assertEqual(query('select count(*) from core.character').stdout.strip(),'2')

    def test_all_status_identity_conflicts_refuse_whole_packet(self):
        for target in atomic.CURATED_TARGET_PROJECTS:
            for status in ('active','inactive','archived','deleted','potential'):
                self.seed(target)
                query(f"insert into core.character values(gen_random_uuid(),'{PARENTS[0]}','Chase',null,'{status}','{{}}')")
                self.abstain('Existing or conflicting identity')
            for mutation in [
                f"insert into core.character_alias values(gen_random_uuid(),'{PARENTS[1]}','Cheer Bear','cheer bear')",
                f"insert into core.character values(gen_random_uuid(),'{PARENTS[0]}','Unrelated',null,'inactive','{{\"source_id\":\"https://www.carebears.com/#cheer-bear\"}}')",
                f"insert into core.taxonomy_source_ref(entity_schema,entity_table,entity_id,source_system,source_table,source_id,source_name,source_licensor_id) values('foreign','character',gen_random_uuid(),'foreign','other','unrelated','Cheer Bear','{PARENTS[1]}')",
                "insert into core.taxonomy_source_ref(entity_schema,entity_table,entity_id,source_system,source_table,source_id) values('foreign','other',gen_random_uuid(),'foreign','other','https://www.carebears.com/#cheer-bear')",
                f"insert into core.character values(gen_random_uuid(),'{PARENTS[1]}','Unrelated','CH-EER BEAR','inactive','{{}}')",
            ]:
                self.seed(target); query(mutation); self.abstain('Existing or conflicting identity')


if __name__ == '__main__':
    unittest.main()
