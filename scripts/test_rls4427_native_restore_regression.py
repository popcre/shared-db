"""Offline controls only. Real PG17 resource must be reviewed/gated separately."""
import importlib.util
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

P=Path(__file__).with_name('rls4427_native_restore_regression.py')
spec=importlib.util.spec_from_file_location('reg4427',P)
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)


class NativeRestoreControls(unittest.TestCase):
    def test_import_and_construction_do_not_execute_resources(self):
        with patch.object(m.subprocess,'run') as run:
            c=m.Regression();self.assertIsNone(c.cid);run.assert_not_called()

    def test_modified_source_refuses_before_any_docker_resource(self):
        def git(argv,**kw):
            return subprocess.CompletedProcess(argv,0,stdout='a'*40 if argv[1]=='rev-parse' else b'wrong committed bytes')
        with patch.object(m.subprocess,'run',side_effect=git) as run:
            with self.assertRaisesRegex(RuntimeError,'source differs'):m.source_identity()
            self.assertTrue(all(call.args[0][0]=='/usr/bin/git' for call in run.call_args_list))

    def test_exact_full_fresh_restore_args_keep_fatal_errors_and_no_exclusions(self):
        for db in m.DATABASES[1:]:
            self.assertEqual(m.restore_args(db),['pg_restore','-U','supabase_admin','-d',db,'--exit-on-error'])
        for db in ('postgres','foreign',m.DATABASES[0]):
            with self.assertRaises(RuntimeError):m.restore_args(db)
        self.assertNotIn('--no-owner',P.read_text());self.assertNotIn('--no-acl',P.read_text())

    def test_nonempty_target_qualifier_refuses_before_restore(self):
        c=m.Regression();db=m.DATABASES[3];c.owned=[db];c.admin_qualified=True
        facts=dict(database=db,owner='postgres',extra_schemas=0,relations=1,routines=0,types=0,policies=0,default_acls=0,
            extensions=['plpgsql'],public_owner='pg_database_owner',public_acl=['PUBLIC:USAGE:false','pg_database_owner:CREATE:false','pg_database_owner:USAGE:false'])
        result=subprocess.CompletedProcess([],0,stdout=json.dumps(facts).encode())
        with patch.object(c,'sql',return_value=result),patch.object(c,'execute') as execute:
            with self.assertRaisesRegex(RuntimeError,'fresh template0 target catalog differs'):c.restore(db,b'archive')
            execute.assert_not_called()

    def test_foreign_or_excess_owned_database_actions_refuse_before_resource(self):
        c=m.Regression()
        with patch.object(c,'sql') as sql:
            with self.assertRaises(RuntimeError):c.create('foreign')
            with self.assertRaises(RuntimeError):c.drop('postgres')
            c.owned=list(m.DATABASES[:2])
            with self.assertRaises(RuntimeError):c.create(m.DATABASES[2])
            sql.assert_not_called()

    def test_local_resource_custody_refuses_replacement_and_any_expanded_authority(self):
        import copy
        c=m.Regression();c.cid='a'*64;c.expected_labels=dict(m.LABELS)
        row=dict(Id=c.cid,Image=m.IMAGE,Name='/'+m.NAME,Config=dict(Labels=dict(m.LABELS)),State=dict(Running=True),
            HostConfig=dict(Privileged=False,NetworkMode='none',ReadonlyRootfs=True,Memory=536870912,NanoCpus=1000000000,PidsLimit=128,Tmpfs={x:'fixed' for x in ['/var/lib/postgresql/data','/var/run/postgresql','/tmp']}),
            NetworkSettings=dict(Ports={'5432/tcp':None},Networks={'none':{}}),Mounts=[])
        def result(value):return subprocess.CompletedProcess([],0,stdout=json.dumps([value]).encode())
        with patch.object(c,'docker',return_value=result(row)):c.custody()
        for section,key,value in [(None,'Id','b'*64),('Config','Labels',{}),('State','Running',False),('HostConfig','Privileged',True),('HostConfig','Memory',1073741824),('HostConfig','NanoCpus',2000000000),('HostConfig','PidsLimit',256),('HostConfig','Binds',['/host:/data']),('HostConfig','ReadonlyRootfs',False),('NetworkSettings','Networks',{'bridge':{}}),('NetworkSettings','Ports',{'5432/tcp':[{'HostPort':'5432'}]})]:
            wrong=copy.deepcopy(row)
            (wrong[section] if section else wrong)[key]=value
            with self.subTest(key=key),patch.object(c,'docker',return_value=result(wrong)),self.assertRaises(RuntimeError):c.custody()

    def test_readonly_exec_is_noninteractive_and_restore_input_is_explicit(self):
        c=m.Regression();c.cid='a'*64
        with patch.object(c,'custody'),patch.object(c,'docker') as docker:
            c.execute(['pg_restore','--version'])
            self.assertNotIn('-i',docker.call_args.args)
            c.execute(m.restore_args(m.DATABASES[2]),input_data=b'archive')
            self.assertIn('-i',docker.call_args.args)
            self.assertEqual(docker.call_args.kwargs['input_data'],b'archive')

    def test_clean_negative_mismatch_preserves_real_diagnostic_before_refusal(self):
        import io
        c=m.Regression();db=m.DATABASES[1];c.owned=[db];c.version_bound=True
        for code,stderr in [(1,b''),(0,b'unexpected warning'),(1,b'different restore failure'),(3,b'x'*5000)]:
            result=subprocess.CompletedProcess([],code,stdout=b'',stderr=stderr)
            capture=io.StringIO()
            with self.subTest(code=code),patch.object(c,'execute',return_value=result) as execute,patch.object(m.sys,'stderr',capture):
                with self.assertRaisesRegex(RuntimeError,'unexpected status or stderr'):
                    c.clean_negative(db,b'archive')
                execute.assert_called_once_with(['pg_restore','-U','postgres','-d',db,'--clean','--if-exists','--exit-on-error'],input_data=b'archive',allowed_failure=True)
                receipt=json.loads(capture.getvalue())
                self.assertEqual(receipt,dict(phase='old-clean-negative',command=execute.call_args.args[0],exit_code=code,
                    stderr=stderr[:4096].decode(),stderr_truncated=len(stderr)>4096))
                self.assertEqual(c.events[-1],receipt)
        with patch.object(c,'execute') as execute:
            with self.assertRaisesRegex(RuntimeError,'exact owned target'):c.clean_negative('foreign',b'archive')
            execute.assert_not_called()

    def test_exact_pg1711_binding_and_old_control_success_are_narrow(self):
        versions=[tool+' (PostgreSQL) 17.11 (Debian 17.11-1.pgdg13+2)' for tool in ('psql','pg_dump','pg_restore')]
        self.assertEqual(m.validate_exact_versions(versions,170011)['server_version_num'],170011)
        for server,tools in [(170006,versions),(170012,versions),(170011,[v.replace('17.11','17.6') for v in versions]),
                             (170011,versions[:2]),(170011,[versions[1],versions[0],versions[2]]),(170011,[v+'\nunexpected' for v in versions])]:
            with self.subTest(server=server,tools=tools),self.assertRaisesRegex(RuntimeError,'exact server170011'):
                m.validate_exact_versions(tools,server)
        c=m.Regression();db=m.DATABASES[1];c.owned=[db]
        with patch.object(c,'execute') as execute:
            with self.assertRaisesRegex(RuntimeError,'exact owned target'):c.clean_negative(db,b'archive')
            execute.assert_not_called()
        c.version_bound=True
        result=subprocess.CompletedProcess([],0,stdout=b'',stderr=b'')
        with patch.object(c,'execute',return_value=result),patch.object(m.sys,'stderr'):
            self.assertIs(c.clean_negative(db,b'archive'),result)
        self.assertIn("if source!=old_restored:raise RuntimeError",P.read_text())
        self.assertIn("NOT_REPRODUCED_PG17_11",P.read_text())
        self.assertIn("historical_native_17_6_failure='PRESERVED_NOT_REPRODUCED'",P.read_text())

    def test_local_restore_roles_are_closed_and_admin_requires_qualification(self):
        for role,db in [('postgres',m.DATABASES[2]),('foreign',m.DATABASES[2]),('rls4427_restore_operator',m.DATABASES[2])]:
            with self.subTest(role=role),self.assertRaises(RuntimeError):m.restore_args(db,role)
        self.assertEqual(m.restore_args(m.DATABASES[5],'rls4427_restore_operator')[2],'rls4427_restore_operator')
        c=m.Regression()
        with patch.object(c,'qualify') as qualify,patch.object(c,'execute') as execute:
            with self.assertRaisesRegex(RuntimeError,'admin restore is not qualified'):c.restore(m.DATABASES[2],b'archive')
            qualify.assert_not_called();execute.assert_not_called()
            with self.assertRaisesRegex(RuntimeError,'admin restore is not qualified'):c.admin_restore(m.DATABASES[2],b'archive')
            execute.assert_not_called()
        fixture=(m.ROOT/'supabase/tests/fixtures/rls4427_native_restore_fixture.sql').read_text()
        self.assertIn('create role rls4427_restore_operator login nosuperuser nobypassrls createdb',fixture)
        self.assertIn('create role supabase_admin login superuser',fixture)
        self.assertIn('create schema auth authorization supabase_admin',fixture)
        self.assertIn("'auth_rows'",m.METADATA)

    def test_local_permission_negative_keeps_exact_failure_and_preconditions(self):
        import io
        c=m.Regression();db=m.DATABASES[5];c.owned=[db];c.version_bound=True;c.admin_qualified=True
        facts=dict(database=db,owner='rls4427_restore_operator',extra_schemas=0,relations=0,routines=0,types=0,policies=0,default_acls=0,
            extensions=['plpgsql'],public_owner='pg_database_owner',public_acl=['PUBLIC:USAGE:false','pg_database_owner:CREATE:false','pg_database_owner:USAGE:false'])
        operator=dict(rolsuper=False,rolcanlogin=True,rolbypassrls=False,rolcreatedb=True,admin_member=False)
        def sql(db,query):return subprocess.CompletedProcess([],0,stdout=json.dumps(facts if query==m.CORE.FRESH_SEED_QUERY else operator).encode())
        expected=b'ERROR: must be able to SET ROLE "supabase_admin"\nCommand was: ALTER SCHEMA auth OWNER TO supabase_admin;'
        for code,stderr,accepted in [(1,expected,True),(0,b'',False),(1,b'other failure',False),(1,expected.replace(b'auth',b'foreign'),False)]:
            result=subprocess.CompletedProcess([],code,stdout=b'',stderr=stderr);capture=io.StringIO()
            with self.subTest(code=code,stderr=stderr),patch.object(c,'sql',side_effect=sql),patch.object(c,'execute',return_value=result) as execute,patch.object(m.sys,'stderr',capture):
                if accepted:self.assertEqual(c.permission_negative(db,b'archive')['exit_code'],1)
                else:
                    with self.assertRaisesRegex(RuntimeError,'exact owner authorization failure'):c.permission_negative(db,b'archive')
                self.assertEqual(execute.call_args.args[0],m.restore_args(db,'rls4427_restore_operator'))
                self.assertEqual(json.loads(capture.getvalue())['stderr'],stderr.decode())
        operator['admin_member']=True
        with patch.object(c,'sql',side_effect=sql),patch.object(c,'execute') as execute:
            with self.assertRaisesRegex(RuntimeError,'operator capability'):c.permission_negative(db,b'archive')
            execute.assert_not_called()

    def test_real_external_failure_is_never_turned_into_success(self):
        c=m.Regression();c.config='/private'
        result=subprocess.CompletedProcess([],1,stdout=b'',stderr=b'real restore failure')
        with patch.object(m.subprocess,'run',return_value=result) as run:
            with self.assertRaisesRegex(RuntimeError,'real restore failure'):c.docker('exec','fixed')
            self.assertEqual(run.call_args.kwargs['stdin'],subprocess.DEVNULL)
            self.assertEqual(c.docker('exec','fixed',allowed_failure=True).returncode,1)
            self.assertEqual(run.call_args.args[0][:3],['/usr/bin/docker','--host','unix:///var/run/docker.sock'])

    def test_fixture_and_comparison_cover_full_metadata_not_counts_only(self):
        fixture=(m.ROOT/'supabase/tests/fixtures/rls4427_native_restore_fixture.sql').read_text()
        for text in ('create schema storage','create policy crm_customer_logos_update','alter default privileges','grant update(label)',
                     'alter schema public owner','create trigger','enable row level security'):
            self.assertIn(text,fixture)
        for text in ('public_owner','public_acl','default_acls','relations','routines','types','policies','extensions'):
            self.assertIn(text,m.CORE.FRESH_SEED_QUERY)
        for text in ('schemas','columns','policies','defaults','constraints','indexes','functions','triggers','sequences','sequence_ownership','sequence_state','rows','public_rows'):
            self.assertIn("'"+text+"'",m.METADATA)
        for flag in ('--network','--read-only','--pull=never','--tmpfs','--memory','--pids-limit'):
            self.assertIn(flag,P.read_text())
        self.assertIn("'none'",P.read_text());self.assertIn(m.IMAGE,P.read_text())


if __name__=='__main__':unittest.main()
