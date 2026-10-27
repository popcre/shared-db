#!/usr/bin/env python3
"""4427-only actual-table qualification inside the existing ephemeral DB CI.

No connection options, Docker, downloaded code or live data. Each timed statement
gets a new physical TEMPLATE clone; rollback is never treated as heap restoration.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import sys
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / 'supabase/tests/rls_public_admin_initplan_contracts.sql'
SOURCE_SQL_SHA256 = '166a1d7cae922b27c229c31162b612ccb1957a27440806681a15677151354667'
END = '-- Invoker-only probing, with each write reverted by a private subtransaction.'
ADMIN = '00000000-7541-4000-8000-000000000001'
MEMBER = '00000000-7541-4000-8000-000000000002'
CASES = [('assets', 'INSERT'), ('assets', 'UPDATE'),
         ('style_groups', 'INSERT'), ('style_groups', 'UPDATE'), ('style_groups', 'DELETE')]
SIZES = (1, 100, 10000)
POLICIES = [('assets', 'Admins can insert assets', 'WITH CHECK'),
            ('assets', 'Admins can update assets', 'USING'),
            ('style_groups', 'Admins can manage style_groups', 'USING')]


def assert_ci(env):
    required = {'GITHUB_ACTIONS': 'true', 'CI': 'true', 'GITHUB_REPOSITORY': 'popcre/shared-db', 'GITHUB_WORKFLOW': 'Database Contract Tests',
                'PGHOST': '127.0.0.1', 'PGPORT': '54322', 'PGUSER': 'postgres', 'PGDATABASE': 'postgres'}
    if any(env.get(k) != v for k, v in required.items()):
        raise RuntimeError('4427 refuses mismatched declared native CI context; parent must independently prove resource custody')
    if not re.fullmatch('[a-f0-9]{40}', env.get('GITHUB_SHA', '')):
        raise RuntimeError('4427 requires the exact native CI source SHA')
    if any(env.get(k) for k in ('SUPABASE_ACCESS_TOKEN', 'SUPABASE_DB_PASSWORD_PRODUCTION',
                               'SUPABASE_DB_PASSWORD_PREVIEW', 'DATABASE_URL')):
        raise RuntimeError('4427 refuses live credentials or database URL')


def fixture_sql(source):
    if hashlib.sha256(source.encode()).hexdigest() != SOURCE_SQL_SHA256:
        raise RuntimeError('4427 retained exact fixture source hash changed')
    if source.count(END) != 1:
        raise RuntimeError('4427 fixture boundary changed')
    fragment = source[source.index('begin;'):source.index(END)]
    if not fragment.lstrip().startswith('begin;') or 'create temp table rls4427_manifest' not in fragment:
        raise RuntimeError('4427 actual source fixture/preconditions missing')
    return fragment + "\ncommit;\n"


def jobs():
    result = []
    for table, command in CASES:
        for size in SIZES:
            for sample in range(11):
                variants = ('original', 'candidate') if sample % 2 == 0 else ('candidate', 'original')
                result += [(table, command, size, sample, v) for v in variants]
    for table in ('assets', 'style_groups'):
        for sample in range(11):
            variants = ('original', 'candidate') if sample % 2 == 0 else ('candidate', 'original')
            result += [(table, 'SELECT', 1000, sample, v) for v in variants]
    return result


def seed_sql():
    return """
insert into public.assets(id,filename,relative_path,file_type,quick_hash,modified_at)
select md5('4427-actual-asset-'||i)::uuid,'zz-4427-actual-'||i||'.ai',
 'zz-4427-actual/'||i||'.ai','ai','zz-4427-actual-'||i,'2000-01-01'::timestamptz
from generate_series(1,10000) i;
insert into public.style_groups(id,sku,folder_path)
select md5('4427-actual-style-'||i)::uuid,'zz-4427-actual-'||i,'zz-4427-actual/'||i
from generate_series(1,10000) i;
"""


def statement(table, command, n):
    if table not in ('assets', 'style_groups') or command not in ('SELECT', 'INSERT', 'UPDATE', 'DELETE'):
        raise ValueError('4427 unknown workload')
    if command == 'SELECT':
        return f'SELECT count(*) FROM (SELECT id FROM public.{table} LIMIT 1000) bounded'
    identity = "'4427-actual-asset-'" if table == 'assets' else "'4427-actual-style-'"
    where = f"id IN (SELECT md5({identity}||i)::uuid FROM generate_series(1,{n}) i)"
    if command == 'UPDATE':
        change = "workflow_status='other'" if table == 'assets' else "program='changed-synthetic'"
        return f'UPDATE public.{table} SET {change} WHERE {where} RETURNING id'
    if command == 'DELETE' and table == 'style_groups':
        return f'DELETE FROM public.style_groups WHERE {where} RETURNING id'
    if command == 'INSERT' and table == 'assets':
        return f"""INSERT INTO public.assets(id,filename,relative_path,file_type,quick_hash,modified_at)
SELECT md5('4427-actual-insert-asset-'||i)::uuid,'zz-4427-new-'||i||'.ai',
 'zz-4427-new/'||i||'.ai','ai','zz-4427-new-'||i,'2000-01-01'::timestamptz
FROM generate_series(1,{n}) i RETURNING id"""
    if command == 'INSERT' and table == 'style_groups':
        return f"""INSERT INTO public.style_groups(id,sku,folder_path)
SELECT md5('4427-actual-insert-style-'||i)::uuid,'zz-4427-new-'||i,'zz-4427-new/'||i
FROM generate_series(1,{n}) i RETURNING id"""
    raise ValueError('4427 unsupported table command')


def role_sql(subject):
    return f"""set local role authenticated;
select set_config('request.jwt.claim.sub','',true);
select set_config('request.jwt.claim','',true);
select set_config('request.jwt.claims','{{"role":"authenticated","sub":"{subject}"}}',true);
do $guard$ begin
 if current_user<>'authenticated' or exists(select 1 from pg_roles
 where rolname=current_user and(rolsuper or rolbypassrls)) then
 raise exception '4427 role bypass'; end if;
end $guard$;
"""


def snapshot_sql(table):
    # Actual relation bytes, rowset, indexes and visible union, not row-count-only pairing.
    return f"""select jsonb_build_object(
'heap_md5',md5(pg_read_binary_file(pg_relation_filepath('public.{table}'::regclass))),
'visibility_md5',case when (pg_stat_file(pg_relation_filepath('public.{table}'::regclass)||'_vm',true)).size is not null
 then md5(pg_read_binary_file(pg_relation_filepath('public.{table}'::regclass)||'_vm')) else null end,
'indexes_md5',(select jsonb_agg(jsonb_build_array(indexrelid,
 md5(pg_read_binary_file(pg_relation_filepath(indexrelid)))) order by indexrelid)
 from pg_index where indrelid='public.{table}'::regclass),
'heap_bytes',pg_relation_size('public.{table}'),'index_bytes',pg_indexes_size('public.{table}'),
'rows_md5',(select md5(string_agg(row_to_json(t)::text,E'\\n' order by id)) from public.{table} t),
'policies',(select jsonb_agg(jsonb_build_object('table',polrelid::regclass::text,
 'name',polname,'command',polcmd,'permissive',polpermissive,'roles',polroles,
 'qual',pg_get_expr(polqual,polrelid),'check',pg_get_expr(polwithcheck,polrelid))
 order by polrelid,polname) from pg_policy),
'capability',(select jsonb_agg(jsonb_build_array(c.oid,c.relowner,c.relacl::text,
 c.relrowsecurity,c.relforcerowsecurity) order by c.oid) from pg_class c
 join pg_namespace n on n.oid=c.relnamespace where n.nspname in('public','archive','plm')),
'helpers',(select jsonb_agg(jsonb_build_array(oid,proowner,proacl::text,provolatile,
 prosecdef,proconfig,pg_get_functiondef(oid)) order by oid) from pg_proc where oid in
 ('auth.uid()'::regprocedure,'public.has_role(uuid,public.app_role)'::regprocedure)),
'settings',jsonb_build_object('server_version',current_setting('server_version'),
 'block_size',current_setting('block_size'),'work_mem',current_setting('work_mem'),
 'plan_cache_mode',current_setting('plan_cache_mode')));"""


def compact_snapshot(snapshot):
    return {**{k: snapshot[k] for k in ('heap_md5', 'visibility_md5', 'indexes_md5', 'heap_bytes', 'index_bytes', 'rows_md5', 'settings')},
            'capability_sha256': hashlib.sha256(json.dumps({k:snapshot[k] for k in
                ('policies','capability','helpers')}, sort_keys=True).encode()).hexdigest()}


def summarize(samples):
    out = []
    for table, command, size, _, _ in jobs()[::22]:
        rows = [r for r in samples if (r['table'], r['command'], r['size']) == (table, command, size)
                and not r['warmup']]
        original = [r['plan'][0]['Execution Time'] for r in rows if r['variant'] == 'original']
        candidate = [r['plan'][0]['Execution Time'] for r in rows if r['variant'] == 'candidate']
        a, b = statistics.median(original), statistics.median(candidate)
        out.append(dict(table=table, command=command, size=size, original_median_ms=a,
                        candidate_median_ms=b, delta_percent=100*(b/a-1),
                        median_regression_over_10_percent=b > a*1.1,
                        original_p95_ms=sorted(original)[-1], candidate_p95_ms=sorted(candidate)[-1]))
    return out


def validate_policy_delta(before, after, variant):
    if before['capability'] != after['capability'] or before['helpers'] != after['helpers']:
        raise RuntimeError('4427 capabilities or helper definitions changed')
    left, right = before['policies'], after['policies']
    if len(left) != len(right):
        raise RuntimeError('4427 full policy union cardinality changed')
    changed = set()
    for a, b in zip(left, right):
        if a == b:
            continue
        expected = {(t, n): 'check' if clause == 'WITH CHECK' else 'qual' for t, n, clause in POLICIES}
        key = (a['table'].removeprefix('public.'), a['name'])
        if variant != 'original' or key not in expected:
            raise RuntimeError('4427 unrelated policy changed')
        field = expected[key]
        if {k:v for k,v in a.items() if k != field} != {k:v for k,v in b.items() if k != field}:
            raise RuntimeError('4427 policy roles/command/implicit check changed')
        if re.sub(r'\s+', ' ', b[field]).strip() != "has_role(auth.uid(), 'admin'::app_role)":
            raise RuntimeError('4427 original expression not exact')
        changed.add(key)
    if variant == 'original' and changed != {(t,n) for t,n,_ in POLICIES}:
        raise RuntimeError('4427 intended original policy delta incomplete')


class NativeCI:
    def __init__(self):
        assert_ci(os.environ)
        self.env = {'PATH': '/usr/bin:/bin', 'LANG': 'C.UTF-8'}
        self.env['PGPASSWORD'] = 'postgres'  # public, invented native CI password only
        self.prefix = 'rls4427_' + uuid.uuid4().hex[:12]
        self.owned = []
        self.started = time.monotonic()

    def command(self, tool, db, *args, input_text=None, binary=False):
        cmd = [tool, '-h', '127.0.0.1', '-p', '54322', '-U', 'postgres', '-d', db, *args]
        return subprocess.run(cmd, input=input_text, capture_output=True, text=not binary,
                              env=self.env, timeout=120, check=True).stdout

    def sql(self, db, query):
        return self.command('psql', db, '-XqAt', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=sqlstate', input_text=query)

    def create(self, db, template):
        if not re.fullmatch(self.prefix + r'_[a-z0-9_]+', db):
            raise RuntimeError('4427 refuses unowned database name')
        self.sql('postgres', f'CREATE DATABASE {db} TEMPLATE {template} STRATEGY FILE_COPY;')
        self.owned.append(db)

    def drop(self, db):
        if db not in self.owned:
            raise RuntimeError('4427 refuses dropping unowned database')
        # Never terminate connections or FORCE another process out; unexpected custody fails closed.
        self.sql('postgres', f'DROP DATABASE {db};')
        self.owned.remove(db)

    def run(self):
        # Source/context guards supplement independently reviewed native workflow custody.
        # Environment values alone cannot cryptographically prove an actual GitHub runner.
        checkout = subprocess.run(['/usr/bin/git', 'rev-parse', 'HEAD'], cwd=ROOT,
            env={'PATH':'/usr/bin:/bin','LANG':'C.UTF-8'}, capture_output=True, text=True,
            timeout=10, check=True).stdout.strip()
        if checkout != os.environ['GITHUB_SHA']:
            raise RuntimeError('4427 native CI SHA does not match actual checked-out source')
        source_hashes = {}
        for relative in ('scripts/qualify_rls4427_actual_tables.py',
                         'supabase/tests/rls_public_admin_actual_table_performance.sql',
                         'supabase/tests/rls_public_admin_initplan_contracts.sql'):
            committed = subprocess.run(['/usr/bin/git', 'show', 'HEAD:' + relative], cwd=ROOT,
                env={'PATH':'/usr/bin:/bin','LANG':'C.UTF-8'}, capture_output=True,
                timeout=10, check=True).stdout
            actual = (ROOT / relative).read_bytes()
            if actual != committed:
                raise RuntimeError('4427 executed source differs from exact checked-out Git source')
            source_hashes[relative] = hashlib.sha256(actual).hexdigest()
        samples = []
        template = self.prefix + '_seed'
        try:
            # Prove the exact psql shell-failure/SQL-error signal before any DB creation.
            try:
                self.sql('postgres', "\\! false\n\\if :SHELL_ERROR\nselect 1/0;\n\\endif\n")
            except subprocess.CalledProcessError as error:
                if error.returncode != 3 or not re.search(r'\b22012\b', error.stderr or ''):
                    raise RuntimeError('4427 native psql failure signal was not exact') from error
            else:
                raise RuntimeError('4427 native psql shell failure did not fail closed')
            # Source is the standard runner's credential-free, synthetic CI database.
            # Host client/server incompatibility must fail closed, never silently change executor.
            tool_versions = {}
            for tool in ('psql','pg_dump','pg_restore'):
                tool_versions[tool] = subprocess.run(['/usr/bin/' + tool, '--version'],
                    env=self.env, capture_output=True, text=True, timeout=10, check=True).stdout.strip()
            self.sql('postgres', """do $g$ begin
if (select count(*) from auth.users where email in
('zz-fixture-user-1@fixture.invalid','zz-fixture-user-2@fixture.invalid',
 'zz-fixture-user-3@fixture.invalid','zz-fixture-user-4@fixture.invalid'))<>4
then raise exception '4427 native synthetic users missing'; end if;
end $g$;""")
            self.create(template, 'template0')
            with tempfile.TemporaryDirectory(prefix='rls4427-dump-') as temp:
                dump = Path(temp) / 'fixture.dump'
                dump.write_bytes(self.command('pg_dump', 'postgres', '-Fc', binary=True))
                dump.chmod(0o600)
                self.command('pg_restore', template, '--clean', '--if-exists', '--exit-on-error', str(dump))
            # Preserve and execute the existing 2124-equivalence/198-plan capability as-is.
            original = FIXTURE.read_text()
            original_result = self.sql(template, original)
            self.sql(template, fixture_sql(original) + seed_sql())
            # Prime hint bits before sealing; never assume a rollback repaired physical pages.
            for table in ('assets', 'style_groups'):
                self.sql(template, snapshot_sql(table))
            base_metadata = {t: json.loads(self.sql(template, snapshot_sql(t))) for t in ('assets', 'style_groups')}
            self.sql('postgres', f'ALTER DATABASE {template} ALLOW_CONNECTIONS false;')
            if self.sql('postgres', f"select count(*) from pg_stat_activity where datname='{template}';").strip() != '0':
                raise RuntimeError('4427 template still has a session; no forced termination allowed')
            pair_fingerprints = {}
            negative_pairs = {}
            for index, (table, cmd, size, sample, variant) in enumerate(jobs()):
                if time.monotonic() - self.started > 900:
                    raise RuntimeError('4427 fifteen-minute qualification budget exhausted')
                db = self.prefix + '_trial_' + str(index)
                self.create(db, template)
                try:
                    before = json.loads(self.sql(db, snapshot_sql(table)))
                    if before['heap_bytes'] >= 1073741824 or before['index_bytes'] >= 1073741824:
                        raise RuntimeError('4427 relation too large for bounded first-segment fingerprint')
                    if before != base_metadata[table]:
                        raise RuntimeError('4427 clone physical/rowset/index/policy/settings drift')
                    if variant == 'original':
                        self.sql(db, '\n'.join(f'ALTER POLICY "{name}" ON public.{t} {clause} '
                            "(public.has_role(auth.uid(), 'admin'::public.app_role));"
                            for t, name, clause in POLICIES))
                    variant_metadata = json.loads(self.sql(db, snapshot_sql(table)))
                    validate_policy_delta(before, variant_metadata, variant)
                    # Identical read-only warmup; no aborted DML changes the starting heap.
                    query = statement(table, cmd, size)
                    selected = None
                    if cmd == 'SELECT':
                        control = f"SELECT jsonb_build_object('count',count(*),'rowset_md5',md5(string_agg(id::text,',' order by id))) FROM (SELECT id FROM public.{table} LIMIT 1000) bounded;"
                        out = self.sql(db, 'begin;\n' + role_sql(ADMIN) + control + '\nrollback;')
                        selected = json.loads(out.splitlines()[-1])
                        if selected['count'] != 1000:
                            raise RuntimeError('4427 actual SELECT count changed')
                    trial = "begin; set local statement_timeout='30s'; set local lock_timeout='3s';\n"
                    trial += role_sql(ADMIN)
                    trial += "do $g$ begin if not public.has_role(auth.uid(),'admin'::public.app_role) then raise exception '4427 missing admin'; end if; end $g$;\n"
                    trial += f'SELECT count(*) FROM public.{table};\n'
                    trial += 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' + query + ';\nrollback;'
                    output = self.sql(db, trial)
                    # psql also prints set_config/warmup values; JSON plan is final array.
                    start = output.index('[\n')
                    plan = json.loads(output[start:])
                    rows = plan[0]['Plan']['Actual Rows']
                    if cmd != 'SELECT' and rows != size:
                        raise RuntimeError('4427 actual command did not affect the expected synthetic rows')
                    if cmd == 'SELECT' and rows != 1:
                        raise RuntimeError('4427 SELECT aggregate row missing')
                    # Nonadmin actual-command control after timing, in its own rollback.
                    negative_sql = "begin; set local statement_timeout='30s';\n" + role_sql(MEMBER)
                    negative_sql += "do $g$ begin if public.has_role(auth.uid(),'admin'::public.app_role) then raise exception '4427 nonadmin identity is admin'; end if; end $g$;\n"
                    negative_sql += 'EXPLAIN (ANALYZE, FORMAT JSON) ' + query + ';\nrollback;'
                    try:
                        negative_out = self.sql(db, negative_sql)
                        negative_plan = json.loads(negative_out[negative_out.index('[\n'):])
                        negative = dict(sqlstate='00000', rows=negative_plan[0]['Plan']['Actual Rows'])
                    except subprocess.CalledProcessError as error:
                        found = re.search(r'(?:ERROR|FATAL):\s+([A-Z0-9]{5})(?::|\s|$)', error.stderr or '')
                        if not found:
                            raise RuntimeError('4427 negative control lacked exact SQLSTATE') from error
                        if found.group(1) != '42501':
                            raise RuntimeError('4427 nonadmin control failed outside permission denial') from error
                        negative = dict(sqlstate=found.group(1))
                    after = json.loads(self.sql(db, snapshot_sql(table)))
                    # Rollback logical restoration is checked, but physical after-bytes are NOT called restored.
                    validate_policy_delta(variant_metadata, after, 'candidate')
                    if before['rows_md5'] != after['rows_md5']:
                        raise RuntimeError('4427 actual fixture rollback failed')
                    key = (table, cmd, size, sample)
                    logical = {k: before[k] for k in ('heap_md5', 'visibility_md5', 'indexes_md5', 'rows_md5', 'heap_bytes', 'index_bytes', 'settings')}
                    if selected is not None:
                        logical['selected'] = selected
                    if key in pair_fingerprints and pair_fingerprints[key] != logical:
                        raise RuntimeError('4427 pair did not start with the same physical fixture')
                    pair_fingerprints[key] = logical
                    if key in negative_pairs and negative_pairs[key] != negative:
                        raise RuntimeError('4427 original/candidate nonadmin command outcome differs')
                    negative_pairs[key] = negative
                    samples.append(dict(table=table, command=cmd, size=size, sample=sample,
                        warmup=sample == 0, variant=variant, before=compact_snapshot(before), after=compact_snapshot(after), selected=selected, negative=negative, plan=plan))
                finally:
                    self.drop(db)
            if len(samples) != 374:
                raise RuntimeError('4427 incomplete 330-DML/44-SELECT matrix')
            summary = summarize(samples)
            return dict(schema_version=1, source_sha=os.environ['GITHUB_SHA'],
                executed_source_sha256=source_hashes, tool_versions=tool_versions, psql_shell_failure_signal_proven=True, qualification='ISOLATED_ACTUAL_TABLES_ONLY', production_acceptance='NOT_EVALUATED',
                historical_flags='PRESERVED_UNATTRIBUTED', source_sql_sha256=hashlib.sha256(original.encode()).hexdigest(),
                original_contract_output_sha256=hashlib.sha256(original_result.encode()).hexdigest(),
                template_snapshots=base_metadata, samples=samples, summary=summary,
                synthetic_performance_disposition='FLAGGED' if any(r['median_regression_over_10_percent'] for r in summary) else 'NO_FLAG_IN_THIS_SYNTHETIC_BATCH')
        finally:
            for db in list(reversed(self.owned)):
                self.drop(db)


def main():
    try:
        report = NativeCI().run()
        print(json.dumps(report, sort_keys=True))
        return 0
    except Exception as exc:
        print('4427 qualification refused: ' + str(exc), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
