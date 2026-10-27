"""No resources: source-specific admission, matrix, failure and pairing checks."""
import copy
import importlib.util
import os
from pathlib import Path
import unittest
from unittest.mock import patch

P = Path(__file__).with_name('qualify_rls4427_actual_tables.py')
spec = importlib.util.spec_from_file_location('actual4427', P)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class Actual4427StaticTests(unittest.TestCase):
    def valid_env(self):
        return dict(GITHUB_ACTIONS='true', CI='true', GITHUB_REPOSITORY='popcre/shared-db',
                    GITHUB_WORKFLOW='Database Contract Tests', GITHUB_SHA='a'*40,
                    PGHOST='127.0.0.1', PGPORT='54322', PGUSER='postgres', PGDATABASE='postgres')

    def test_fails_closed_before_any_command_outside_exact_ci_or_with_live_credentials(self):
        m.assert_ci(self.valid_env())
        for k, v in [('PGHOST','qsllyeztdwjgirsysgai.supabase.co'), ('PGPORT','5432'),
                     ('GITHUB_ACTIONS','false'), ('GITHUB_SHA','bad'), ('PGUSER','service_role'),
                     ('DATABASE_URL','postgres://not-allowed'), ('SUPABASE_ACCESS_TOKEN','not-a-real-secret')]:
            with self.subTest(k=k), patch.dict(os.environ, {**self.valid_env(), k:v}, clear=True), \
                 patch.object(m.subprocess, 'run') as run:
                with self.assertRaises(RuntimeError):
                    m.NativeCI()
                run.assert_not_called()

    def test_complete_330_dml_44_select_matrix_and_balanced_order(self):
        jobs = m.jobs()
        self.assertEqual(len(jobs), 374)
        self.assertEqual(sum(cmd != 'SELECT' for _,cmd,_,_,_ in jobs), 330)
        for i in range(0, len(jobs), 2):
            a,b = jobs[i:i+2]
            self.assertEqual(a[:4], b[:4])
            self.assertEqual({a[4],b[4]}, {'original','candidate'})
            self.assertEqual(a[4], 'original' if a[3] % 2 == 0 else 'candidate')

    def test_reuses_actual_full_fixture_and_preserves_198_plan_matrix(self):
        source=m.FIXTURE.read_text()
        pre=m.fixture_sql(source)
        self.assertIn("from pg_policy",pre)
        self.assertIn('count(*) from rls4427_candidate_policies)<>72',pre)
        self.assertIn('create temp table rls4427_manifest',pre)
        self.assertIn('insert into public.assets',pre)
        self.assertIn('INSERT INTO public.style_groups',pre)
        self.assertIn('commit;',pre)
        for damaged in [source.replace(m.END,''),source+m.BEGIN,source.replace('begin;','select 1;',1)]:
            with self.assertRaises(RuntimeError):m.fixture_sql(damaged)
        self.assertIn('count(*) from rls4427_performance)<>198',source)
        self.assertEqual(source.count('select pg_temp.rls4427_measure_batch('),9)

    def test_actual_commands_not_expression_surrogates_and_read_union_retained(self):
        for table,cmd in m.CASES:
            query=m.statement(table,cmd,100)
            self.assertIn(f'public.{table}',query)
            self.assertTrue(query.startswith(cmd))
            self.assertIn('RETURNING id',query)
            self.assertNotIn('has_role',query)
        self.assertIn('LIMIT 1000',m.statement('style_groups','SELECT',1000))
        with self.assertRaises(ValueError):m.statement('assets','DELETE',1)
        with self.assertRaises(ValueError):m.statement('other','INSERT',1)

    def test_policy_delta_guard_preserves_metadata_helpers_and_full_union(self):
        rows=[]
        for table,name,clause in m.POLICIES:
            rows.append(dict(table=table,name=name,qual='SELECT wrapped' if clause=='USING' else None,
                             check='SELECT wrapped' if clause=='WITH CHECK' else None,
                             command='ALL',roles=[0],permissive=True))
        before=dict(capability=['original'],helpers=['original'],policies=rows)
        m.validate_policy_delta(before,copy.deepcopy(before),'candidate')
        after=copy.deepcopy(before)
        for p,(_,_,clause) in zip(after['policies'],m.POLICIES):
            p['qual' if clause=='USING' else 'check']="has_role(auth.uid(), 'admin'::app_role)"
        m.validate_policy_delta(before,after,'original')
        for key,value in [('helpers',[]),('capability',[]),('policies',[])]:
            damaged=copy.deepcopy(after);damaged[key]=value
            with self.assertRaises(RuntimeError):m.validate_policy_delta(before,damaged,'original')
        damaged=copy.deepcopy(after);damaged['policies'][0]['roles']=[42]
        with self.assertRaises(RuntimeError):m.validate_policy_delta(before,damaged,'original')
        damaged=copy.deepcopy(after);damaged['policies'][1]['check']='true'
        with self.assertRaises(RuntimeError):m.validate_policy_delta(before,damaged,'original')
        with self.assertRaises(RuntimeError):m.validate_policy_delta(before,after,'candidate')

    def test_unowned_drop_and_create_refuse_without_subprocess(self):
        with patch.dict(os.environ,self.valid_env(),clear=True):c=m.NativeCI()
        with patch.object(c,'sql') as run:
            with self.assertRaises(RuntimeError):c.drop('postgres')
            with self.assertRaises(RuntimeError):c.create('postgres','template0')
            run.assert_not_called()


if __name__ == '__main__':unittest.main()
