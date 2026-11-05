"""Opt-in real Supabase17 proof; synthetic disposable fixtures only."""
import os
import unittest
from pathlib import Path
import test_hts_evaluation_access_postgres as fixturemod
import atomic_migration_apply as atomic

@unittest.skipUnless(os.environ.get('HTS_EVALUATION_TEST_PORT'),'disposable port not supplied')
class ProjectionPostgresTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        fixturemod.EvaluationPostgresTests.setUpClass()
        cls.sql=Path(os.environ.get('HTS_PREPACK_PROJECTION_MIGRATION_FILE','supabase/migrations/20261105143221_hts_private_prepack_qualification.sql')).read_text()
    def setUp(self):
        self.fixture=fixturemod.EvaluationPostgresTests()
        self.fixture.setUp()
        self.fixture.apply()
        with self.fixture.admin() as c:
            self.created_api=c.execute("SELECT to_regnamespace('api') IS NULL").fetchone()[0]
            c.execute("CREATE SCHEMA IF NOT EXISTS api; CREATE FUNCTION api.hts_projection_probe() RETURNS text LANGUAGE sql AS $$ SELECT 'synthetic-probe'::text $$;")
            c.execute('''CREATE TABLE plm.item(item_number text,raw jsonb,source_system text,private_price numeric);
              ALTER TABLE plm.item ENABLE ROW LEVEL SECURITY;
              CREATE TABLE coldlion.sync_run(id uuid PRIMARY KEY,endpoint text,company_code text,division_code text,request_params jsonb,status text,started_at timestamptz,finished_at timestamptz,requested_by text);
              ALTER TABLE coldlion.sync_run ENABLE ROW LEVEL SECURITY;
              CREATE TABLE coldlion.prepack_detail(company_code text,division_code text,pre_pack_code text,item_no text);
              INSERT INTO coldlion.prepack_detail VALUES ('C','D','PARENT','COMPONENT');
              ALTER TABLE coldlion.item_detail ADD run_id uuid, ADD fetched_at timestamptz, ADD last_seen_at timestamptz, ADD item_pkey text NOT NULL DEFAULT 'one';
              UPDATE coldlion.item_detail SET company_code='SYN',division_code='SYN';
              ALTER TABLE coldlion.item_detail ALTER company_code SET NOT NULL, ALTER division_code SET NOT NULL, ALTER item_no SET NOT NULL, ADD PRIMARY KEY(company_code,division_code,item_no,item_pkey);
              CREATE INDEX projection_style_fixture_idx ON plm.item((upper(btrim(item_number))));
              CREATE INDEX projection_detail_fixture_idx ON coldlion.item_detail(company_code,division_code,item_no);
              CREATE POLICY synthetic_public_broad ON plm.item FOR SELECT TO PUBLIC USING(true);
              INSERT INTO plm.item(item_number,raw,source_system) VALUES
              ('PARENT','{"companyCode":"C","divisionCode":"D"}','coldlion'),
              ('COMPONENT','{"companyCode":"C","divisionCode":"D"}','coldlion'),
              ('MISSING','{"companyCode":"C","divisionCode":"D"}','coldlion'),
              ('MULTI','{"companyCode":"C","divisionCode":"D"}','coldlion'),
              ('MULTIBLANK','{"companyCode":"C","divisionCode":"D"}','coldlion'),
              ('CONTEXT','{"companyCode":"C","divisionCode":"D"}','coldlion'),
              ('CONTEXT','{"companyCode":"C","divisionCode":"E"}','coldlion'),
              ('NOCTX','{}','coldlion'),('OTHER','{"companyCode":"C","divisionCode":"D"}','foreign');
              INSERT INTO coldlion.item_detail(item_no,company_code,division_code,pre_pack_code,item_pkey) VALUES
              ('PARENT','C','D','synthetic-parent-marker','one'),('COMPONENT','C','D','','one'),
              ('MULTI','C','D','','one'),('MULTI','C','D','parent','two'),
              ('MULTIBLANK','C','D','','one'),('MULTIBLANK','C','D','  ','two'),
              ('CONTEXT','C','D','','one'),('CONTEXT','C','E','parent','one');
              INSERT INTO coldlion.sync_run VALUES ('11111111-1111-4111-8111-111111111111','/itemDetails','C',NULL,
                '{"companyCode":"C","fullSnapshot":true,"requests":[{"companyCode":"C"},{"companyCode":"C","divisionCode":"D"},{"companyCode":"C","divisionCode":"E"}]}',
                'succeeded','2026-01-01T00:00:00Z','2026-01-01T00:01:00Z','coldlion-landing sync-masters');
              UPDATE coldlion.item_detail SET run_id='11111111-1111-4111-8111-111111111111',fetched_at='2026-01-01T00:01:00Z',last_seen_at='2026-01-01T00:01:00Z';''')
    def tearDown(self):
        self.fixture.clean_fixture()
        env={**self.fixture.env,'PGUSER':os.environ.get('HTS_EVALUATION_TEST_CLEANUP_USER','postgres')}
        with atomic.credential_connection(env) as c:
            c.execute('DROP ROLE IF EXISTS designflow_hts_prepack_projection_owner; DROP FUNCTION IF EXISTS api.hts_projection_probe();')
            if self.created_api:c.execute('DROP SCHEMA api')
    def apply(self,fail=False):
        with self.fixture.admin() as c:
            c.execute(self.sql)
            if fail:c.execute("DO $$ BEGIN RAISE EXCEPTION 'synthetic transaction failure'; END $$")
            c.execute("INSERT INTO supabase_migrations.schema_migrations(version) VALUES('20261105143221')")
    def reader(self):
        return atomic.credential_connection(self.fixture.env,reader=True)
    def test_typed_exact_context_membership_and_least_privilege(self):
        self.apply()
        with self.reader() as c:
            c.execute('SET ROLE designflow_hts_evaluation_read')
            rows=c.execute('SELECT style_number,state,detail_matched_count,source_complete FROM plm.hts_evaluation_prepack_membership ORDER BY style_number,state').fetchall()
            self.assertIn(('PARENT','prepack',1,True),rows)
            self.assertIn(('COMPONENT','non_prepack',1,True),rows)
            self.assertIn(('MISSING','unknown',0,False),rows)
            self.assertIn(('MULTI','prepack',2,True),rows)
            self.assertIn(('MULTIBLANK','non_prepack',2,True),rows)
            # Old completeness remains as-of evidence, never a hidden currency assertion.
            self.assertEqual(c.execute("SELECT extract(year FROM source_as_of)::int FROM plm.hts_evaluation_prepack_membership WHERE style_number='COMPONENT'").fetchone()[0],2026)
            self.assertIn(('NOCTX','unknown',0,False),rows)
            self.assertEqual(sum(r[0]=='CONTEXT' for r in rows),2)
            self.assertFalse(any(r[0]=='OTHER' for r in rows))
            self.assertFalse(c.execute("SELECT pg_has_role(current_user,'designflow_hts_prepack_projection_owner','SET')").fetchone()[0])
        for sql in ['SELECT raw FROM plm.item','SELECT private_price FROM plm.item','SELECT request_params FROM coldlion.sync_run',
                    'SELECT pre_pack_code FROM plm.hts_evaluation_prepack_membership',
                    'UPDATE plm.item SET raw=NULL','SELECT api.hts_projection_probe()','SET ROLE designflow_hts_prepack_projection_owner']:
            with self.subTest(sql=sql),self.reader() as c:
                c.execute('SET ROLE designflow_hts_evaluation_read')
                with self.assertRaises(self.fixture.pg.Error):c.execute(sql)
                c.rollback()
        with self.fixture.admin() as c:
            self.assertFalse(c.execute("SELECT has_table_privilege('designflow_hts_prepack_projection_owner','coldlion.prepack_detail','SELECT')").fetchone()[0])
            self.assertFalse(c.execute("SELECT has_schema_privilege('designflow_hts_prepack_projection_owner','plm','CREATE')").fetchone()[0])
            for role in ['anon','authenticated']:
                self.assertFalse(c.execute("SELECT has_table_privilege(%s,'plm.hts_evaluation_prepack_membership','SELECT')",(role,)).fetchone()[0])
            self.assertEqual(c.execute("SELECT admin_option,inherit_option,set_option FROM pg_auth_members WHERE roleid='designflow_hts_prepack_projection_owner'::regrole AND member=current_user::regrole").fetchall(),[(True,False,False)])
    def test_failed_transaction_restores_every_object_and_retry(self):
        with self.assertRaises(self.fixture.pg.Error):self.apply(fail=True)
        env={**self.fixture.env,'PGUSER':os.environ.get('HTS_EVALUATION_TEST_CLEANUP_USER','postgres')}
        with atomic.credential_connection(env) as c:
            c.execute('SET ROLE hts_evaluation_unauthorized')
            with self.assertRaisesRegex(self.fixture.pg.Error,'must use exact native postgres actor'):c.execute(self.sql)
            c.rollback()
        with self.fixture.admin() as c:
            self.assertIsNone(c.execute("SELECT to_regclass('plm.hts_evaluation_prepack_membership')").fetchone()[0])
            self.assertEqual(c.execute("SELECT count(*) FROM pg_roles WHERE rolname='designflow_hts_prepack_projection_owner'").fetchone()[0],0)
            self.assertEqual(c.execute("SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20261105143221'").fetchone()[0],0)
            self.assertEqual(c.execute("SELECT count(*) FROM pg_policies WHERE policyname LIKE 'hts_prepack_projection_owner%'").fetchone()[0],0)
        self.apply()
    def test_incomplete_filtered_mismatched_and_latest_failed_are_unknown(self):
        self.apply()
        mutations=[
            ("UPDATE coldlion.item_detail SET run_id=NULL WHERE item_no='MULTI' AND pre_pack_code=''",'prepack'),
            ("UPDATE coldlion.item_detail SET run_id=NULL WHERE item_no='MULTI' AND pre_pack_code='parent'",'unknown'),
            "UPDATE coldlion.sync_run SET requested_by='different-producer'",
            "UPDATE coldlion.sync_run SET request_params=request_params || '{\"itemNo\":\"COMPONENT\"}'::jsonb",
            "UPDATE coldlion.sync_run SET request_params=jsonb_set(request_params,'{requests}','[]'::jsonb)",
            "INSERT INTO coldlion.sync_run SELECT '22222222-2222-4222-8222-222222222222',endpoint,company_code,division_code,request_params,'failed',finished_at+interval '1 second',finished_at+interval '2 seconds',requested_by FROM coldlion.sync_run"
        ]
        for mutation in mutations:
            sql,expected=mutation if isinstance(mutation,tuple) else (mutation,'unknown')
            with self.subTest(mutation=sql),self.fixture.admin() as admin:
                admin.execute(sql)
                # Read as the real login in a separate transaction after committing fixture mutation.
            with self.reader() as c:
                c.execute('SET ROLE designflow_hts_evaluation_read')
                rows=c.execute("SELECT state,source_complete FROM plm.hts_evaluation_prepack_membership WHERE style_number='MULTI'").fetchall()
                self.assertEqual(rows,[(expected,False)])
            with self.fixture.admin() as admin:
                admin.execute("DELETE FROM coldlion.sync_run WHERE id<>'11111111-1111-4111-8111-111111111111'; UPDATE coldlion.sync_run SET requested_by='coldlion-landing sync-masters',request_params='{\"companyCode\":\"C\",\"fullSnapshot\":true,\"requests\":[{\"companyCode\":\"C\"},{\"companyCode\":\"C\",\"divisionCode\":\"D\"},{\"companyCode\":\"C\",\"divisionCode\":\"E\"}]}'::jsonb; UPDATE coldlion.item_detail SET run_id='11111111-1111-4111-8111-111111111111'")

    def test_filtered_plan_pushes_requested_style_before_lateral(self):
        self.apply()
        with self.reader() as c:
            c.execute('SET ROLE designflow_hts_evaluation_read')
            plan=c.execute("EXPLAIN (FORMAT JSON,COSTS OFF) SELECT style_number,state FROM plm.hts_evaluation_prepack_membership WHERE style_number=ANY(%s)",(['PARENT'],)).fetchone()[0]
            import json
            text=json.dumps(plan)
            self.assertIn('PARENT',text)
            # Predicate must reach the source scan, not remain above all contexts.
            def scans(node):
                if node.get('Relation Name')=='item':yield node
                for child in node.get('Plans',[]):yield from scans(child)
            source=list(scans(plan[0]['Plan']))
            self.assertEqual(len(source),1)
            self.assertIn('PARENT',json.dumps(source[0]))

    def test_existing_closed_contracts_accept_only_the_exact_private_pair(self):
        self.apply()
        def section(path,heading):
            text=Path(path).read_text();start=text.index('do $$',text.index(heading))
            return text[start:text.index('$$;',start)+3]
        spine=section('supabase/tests/coldlion_raw_landing_spine_contracts.sql','-- C. RLS')
        application=section('supabase/tests/dam_order_list_item_columns_contract.sql','-- A. THE POLICY ITSELF')
        with self.fixture.admin() as c:
            c.execute('''CREATE TABLE coldlion.window_ledger(id int); CREATE TABLE coldlion.change_log(id int);
              ALTER TABLE coldlion.window_ledger ENABLE ROW LEVEL SECURITY;
              ALTER TABLE coldlion.change_log ENABLE ROW LEVEL SECURITY;
              GRANT ALL ON coldlion.sync_run,coldlion.window_ledger,coldlion.change_log TO service_role;
              DROP POLICY synthetic_public_broad ON plm.item;
              CREATE POLICY item_popdam_read ON plm.item FOR SELECT TO authenticated USING(true);
              CREATE POLICY plm_read ON plm.item FOR SELECT TO authenticated USING(false);
              CREATE POLICY plm_admin_write ON plm.item FOR ALL TO authenticated USING(false) WITH CHECK(false);
              GRANT SELECT ON plm.item TO authenticated;''')
            c.execute(spine);c.execute(application)
            for mutate,contract in [
                ('CREATE POLICY unexpected_application_read ON plm.item FOR SELECT TO authenticated USING(true)',application),
                ('ALTER POLICY hts_prepack_projection_owner_select ON coldlion.sync_run TO authenticated',spine),
                ('ALTER POLICY hts_prepack_projection_owner_select ON coldlion.sync_run USING(true)',spine),
                ('CREATE POLICY unexpected_spine_read ON coldlion.window_ledger FOR SELECT TO PUBLIC USING(true)',spine),
            ]:
                with self.subTest(mutation=mutate),self.assertRaises(self.fixture.pg.Error),c.transaction():
                    c.execute(mutate);c.execute(contract)

if __name__=='__main__':unittest.main()
