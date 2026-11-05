"""Owner5622 opt-in actual PG17 proof in one newly owned localhost fixture DB.

Uses the existing atomic runner's exact policy/hash check and SQL/ledger wrapper.
No hosted target, new role, privilege grant, forced cleanup or shared asset is used.
"""
import hashlib
import os
from pathlib import Path
import sys
import unittest
import uuid
sys.path.insert(0,str(Path(__file__).resolve().parent))
import atomic_migration_apply as atomic

VERSION='20261105160321'
OLD='20261105073920'

@unittest.skipUnless(os.environ.get('HEALTH_RPC_TEST_PORT'),'Explicit disposable localhost PG17 port required')
class HealthRpcPostgresTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import psycopg
        from psycopg import sql
        cls.pg=psycopg;cls.sql=sql
        port=int(os.environ['HEALTH_RPC_TEST_PORT'])
        if not 1024<=port<=65535:raise RuntimeError('Explicit localhost test port refused')
        cls.kwargs=dict(host='127.0.0.1',port=port,user='postgres',password=os.environ.get('HEALTH_RPC_TEST_PASSWORD',''),dbname='postgres',autocommit=True,connect_timeout=10)
        cls.admin=psycopg.connect(**cls.kwargs)
        if not 170000<=cls.admin.execute("select current_setting('server_version_num')::int").fetchone()[0]<180000:raise RuntimeError('Actual PG17 required')
        if cls.admin.execute("select count(*) from pg_roles where rolname in('anon','authenticated','service_role')").fetchone()[0]!=3:raise RuntimeError('Existing disposable Supabase roles required; no new roles allowed')
        cls.name='health_rpc_5622_'+uuid.uuid4().hex
        cls.admin.execute(sql.SQL('create database {} owner postgres').format(sql.Identifier(cls.name)))
        cls.c=psycopg.connect(**{**cls.kwargs,'dbname':cls.name})
        cls.env={**os.environ,'PGHOST':'127.0.0.1','PGPORT':str(port),'PGUSER':'postgres','PGPASSWORD':cls.kwargs['password'],'PGDATABASE':cls.name,'PGSSLMODE':'disable'}
        cls.url=f'postgresql://postgres@127.0.0.1:{port}/{cls.name}'
        cls.path=Path(os.environ.get('HEALTH_RPC_MIGRATION_FILE',f'supabase/migrations/{VERSION}_search_embedding_health_rpc_successor.sql')).resolve()
        cls.old_path=cls.path.parent/(OLD+'_search_embedding_health_and_bounded_reset.sql')
        cls.c.execute("""create schema extensions;create extension pgcrypto with schema extensions;
          create schema auth; create function auth.uid() returns uuid language sql stable as $$select null::uuid$$;
          create function public.has_role(uuid,text) returns boolean language sql stable as $$select false$$;
          create schema supabase_migrations;create table supabase_migrations.schema_migrations(version text primary key,statements text[],name text);
          create table public.dam_search_documents(document_type text,entity_id uuid,embedding text,embedding_attempts int default0,embedding_max_attempts int default5,
            embedding_error_category text,embedding_error text,embedding_updated_at timestamptz,indexed_at timestamptz default now(),metadata jsonb default '{}',
            embedding_next_retry_at timestamptz,embedding_lease_token uuid,embedding_lease_owner text,embedding_lease_expires_at timestamptz,primary key(document_type,entity_id));
          create table public.style_guide_files(id uuid primary key,thumbnail_url text);
          create table public.style_guide_search_documents(style_guide_file_id uuid primary key,is_active boolean,content_sha256 text,embedding text,
            embedding_attempts int default0,embedding_max_attempts int default5,embedding_error_category text,embedding_error text,embedding_updated_at timestamptz,document_updated_at timestamptz default now());
          create function public.reset_dam_search_embedding_errors(text,uuid[]) returns integer language sql security definer set search_path=public as $$select7$$;
        """.replace('default0','default 0').replace('default5','default 5').replace('select7','select 7'))
        cls.legacy=cls.c.execute("select prosrc,proacl::text,prosecdef,proconfig from pg_proc where oid='public.reset_dam_search_embedding_errors(text,uuid[])'::regprocedure").fetchone()
    @classmethod
    def tearDownClass(cls):
        cls.c.close()
        cls.admin.execute(cls.sql.SQL('drop database {}').format(cls.sql.Identifier(cls.name)))
        cls.admin.close()
    def setUp(self):
        self.c.execute("drop function if exists public.get_search_embedding_health();drop function if exists public.reset_dam_search_embedding_errors(text,integer);drop function if exists public.reset_dam_search_embedding_errors(text,integer,text);")
        self.c.execute("drop index if exists public.dam_search_health_errored_idx;drop index if exists public.dam_search_health_last_write_idx;drop index if exists public.sg_search_health_last_write_idx;")
        self.c.execute("truncate public.dam_search_documents,public.style_guide_search_documents,public.style_guide_files,supabase_migrations.schema_migrations;")
        self.c.execute("create index dam_search_health_errored_idx on public.dam_search_documents using btree(entity_id) where(embedding_error is not null);")
        self.c.execute("create index dam_search_health_last_write_idx on public.dam_search_documents using btree(embedding_updated_at desc) where(embedding_updated_at is not null);")
        self.c.execute("create index sg_search_health_last_write_idx on public.style_guide_search_documents using btree(embedding_updated_at desc) where(is_active and(embedding_updated_at is not null));")
        self.c.execute("select set_config('request.jwt.claim.role','service_role',false),set_config('request.jwt.claims','{\"role\":\"service_role\"}',false)")
    def apply(self,old=False):
        version=OLD if old else VERSION
        path=self.old_path if old else self.path
        _,name,raw,statements=atomic.load_candidate(path.parent,version,'preview')
        atomic.psql(self.url,self.env,atomic.build_wrapper(version,name,raw,statements))
    def ledger(self):return self.c.execute('select version from supabase_migrations.schema_migrations order by version').fetchall()
    def snapshot(self):
        return self.c.execute("select oid::regprocedure::text,prosrc,proacl::text,prosecdef,proconfig from pg_proc where pronamespace='public'::regnamespace and proname in('get_search_embedding_health','reset_dam_search_embedding_errors') order by1".replace('order by1','order by 1')).fetchall()
    def assert_legacy(self):
        self.assertEqual(self.c.execute("select prosrc,proacl::text,prosecdef,proconfig from pg_proc where oid='public.reset_dam_search_embedding_errors(text,uuid[])'::regprocedure").fetchone(),self.legacy)
    def test_absent_production_functions_install_atomically_with_ledger_and_legacy_preserved(self):
        self.apply();self.assertEqual(self.ledger(),[(VERSION,)])
        self.assertEqual(len(self.snapshot()),4);self.assert_legacy()
    def test_exact_historical_preview_functions_replaced_without_changing_bodies_or_acl(self):
        self.apply(old=True);before=self.snapshot();self.apply()
        self.assertEqual(self.snapshot(),before);self.assertEqual(self.ledger(),[(OLD,),(VERSION,)]);self.assert_legacy()
    def test_each_missing_index_refuses_without_functions_or_ledger(self):
        for name in ['dam_search_health_errored_idx','dam_search_health_last_write_idx','sg_search_health_last_write_idx']:
            with self.subTest(name=name):
                self.setUp();self.c.execute(self.sql.SQL('drop index public.{}').format(self.sql.Identifier(name)))
                before=self.snapshot()
                with self.assertRaises(atomic.Refusal):self.apply()
                self.assertEqual(self.snapshot(),before);self.assertEqual(self.ledger(),[]);self.assert_legacy()
    def test_wrong_exact_name_definition_refuses_and_preserves_preimage(self):
        self.c.execute('drop index public.dam_search_health_errored_idx;create index dam_search_health_errored_idx on public.dam_search_documents(entity_id desc) where embedding_error is not null;')
        before=self.c.execute("select oid,pg_get_indexdef(oid) from pg_class where oid='public.dam_search_health_errored_idx'::regclass").fetchone()
        with self.assertRaises(atomic.Refusal):self.apply()
        self.assertEqual(self.c.execute("select oid,pg_get_indexdef(oid) from pg_class where oid='public.dam_search_health_errored_idx'::regclass").fetchone(),before);self.assertEqual(self.ledger(),[])
    def test_mixed_prestate_refuses_without_modifying_existing_functions(self):
        self.apply(old=True);self.c.execute('drop function public.reset_dam_search_embedding_errors(text,integer)');before=self.snapshot()
        with self.assertRaises(atomic.Refusal):self.apply()
        self.assertEqual(self.snapshot(),before);self.assertEqual(self.ledger(),[(OLD,)])
    def test_divergent_body_acl_or_definer_refuses_without_mutating_preimage(self):
        mutations=["create or replace function public.reset_dam_search_embedding_errors(p_category text,p_limit integer) returns integer language sql security invoker set search_path=public as $$select 99$$",
          "grant execute on function public.reset_dam_search_embedding_errors(text,integer,text) to authenticated",
          "alter function public.get_search_embedding_health() security invoker"]
        for change in mutations:
            with self.subTest(change=change):
                self.setUp();self.apply(old=True);self.c.execute(change);before=self.snapshot()
                with self.assertRaises(atomic.Refusal):self.apply()
                self.assertEqual(self.snapshot(),before);self.assertEqual(self.ledger(),[(OLD,)]);self.assert_legacy()
    def test_real_counts_bounded_reset_acl_and_active_lease_exclusion(self):
        self.apply();ids=[uuid.uuid4() for _ in range(6)]
        self.c.execute("insert into public.dam_search_documents(document_type,entity_id,metadata,embedding_error,embedding_error_category,embedding_attempts,embedding_lease_token,embedding_lease_expires_at,embedding,embedding_updated_at) values('asset',%s,'{\"thumbnail_url\":\"https://example.invalid/a\"}',null,null,0,null,null,null,null),('asset',%s,'{\"thumbnail_url\":\"https://example.invalid/b\"}','failed','transient',5,null,null,null,null),('asset',%s,'{}','failed','transient',5,null,null,null,null),('asset',%s,'{\"thumbnail_url\":\"https://example.invalid/d\"}','failed','transient',5,gen_random_uuid(),now()+interval '1hour',null,null),('asset',%s,'{\"thumbnail_url\":\"https://example.invalid/e\"}',null,null,0,null,null,'canonical-vector',now())",ids[:5])
        self.c.execute("insert into public.style_guide_files values(%s,'https://example.invalid/sg')",[ids[5]])
        self.c.execute("insert into public.style_guide_search_documents(style_guide_file_id,is_active,content_sha256) values(%s,true,'fixture')",[ids[5]])
        counts={r[0]:(r[1],r[2]) for r in self.c.execute('select * from public.get_search_embedding_health()').fetchall()}
        self.assertEqual(counts,{'dam':(1,3),'popsg':(1,0)})
        before=self.c.execute('select embedding_lease_token,embedding_lease_expires_at from public.dam_search_documents where entity_id=%s',[ids[3]]).fetchone()
        self.assertEqual(self.c.execute("select public.reset_dam_search_embedding_errors('transient',1)").fetchone()[0],1)
        self.assertEqual(self.c.execute('select embedding_lease_token,embedding_lease_expires_at from public.dam_search_documents where entity_id=%s',[ids[3]]).fetchone(),before)
        self.assertEqual(self.c.execute('select embedding_error from public.dam_search_documents where entity_id=%s',[ids[2]]).fetchone()[0],'failed')
        for signature in ['public.get_search_embedding_health()','public.reset_dam_search_embedding_errors(text,integer)','public.reset_dam_search_embedding_errors(text,integer,text)']:
            self.assertFalse(self.c.execute('select has_function_privilege(%s,%s,%s)',['anon',signature,'EXECUTE']).fetchone()[0])
            self.assertTrue(self.c.execute('select has_function_privilege(%s,%s,%s)',['service_role',signature,'EXECUTE']).fetchone()[0])
            self.assertEqual(self.c.execute('select has_function_privilege(%s,%s,%s)',['authenticated',signature,'EXECUTE']).fetchone()[0],signature.endswith('health()'))
        with self.assertRaises(self.pg.Error):self.c.execute('select public.reset_dam_search_embedding_errors(null::text,0)')
        self.c.execute("select set_config('request.jwt.claim.role','authenticated',false),set_config('request.jwt.claims','{\"role\":\"authenticated\"}',false)")
        with self.assertRaises(self.pg.Error):self.c.execute('select * from public.get_search_embedding_health()')
        self.assert_legacy()

if __name__=='__main__':unittest.main()
