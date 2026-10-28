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
                        GITHUB_EVENT_NAME='workflow_dispatch',RLS4427_QUALIFICATION='1',
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

    def test_only_exact_manual_optin_can_reach_any_subprocess(self):
            for event in ('pull_request','merge_group','push','workflow_dispatch'):
                for flag in (None,'','0','true','yes','2','1'):
                    env=self.valid_env();env['GITHUB_EVENT_NAME']=event
                    if flag is None:env.pop('RLS4427_QUALIFICATION',None)
                    else:env['RLS4427_QUALIFICATION']=flag
                    with self.subTest(event=event,flag=flag),patch.dict(os.environ,env,clear=True),patch.object(m.subprocess,'run') as run:
                        if event=='workflow_dispatch' and flag=='1':
                            self.assertIsInstance(m.NativeCI(),m.NativeCI)
                        else:
                            with self.assertRaises(RuntimeError):m.NativeCI()
                        run.assert_not_called()

    def test_existing_workflow_and_sql_keep_fixed_default_off_boundary(self):
            workflow=(m.ROOT/'.github/workflows/database-contract-tests.yml').read_text()
            self.assertIn("qualify_rls4427:\n        description: 'Run the fixed #4427 synthetic actual-table qualification once'\n        type: boolean\n        required: false\n        default: false",workflow)
            flag="RLS4427_QUALIFICATION: ${{ github.event_name == 'workflow_dispatch' && inputs.qualify_rls4427 == true && '1' || '0' }}"
            self.assertEqual(workflow.count(flag),1)
            self.assertGreater(workflow.index(flag),workflow.index('      - name: Run every supabase/tests/*.sql'))
            entry=(m.ROOT/'supabase/tests/rls_public_admin_actual_table_performance.sql').read_text()
            self.assertIn("\\set rls4427_qualification 0",entry)
            self.assertIn("\\getenv rls4427_qualification RLS4427_QUALIFICATION",entry)
            self.assertIn("in ('0','1')",entry)
            self.assertIn("flag must be exactly 0 or 1",entry)
            gate=entry.index('\\if :rls4427_run');execute=entry.index('\\! python3')
            self.assertLess(entry.index('\\if :rls4427_flag_valid'),gate);self.assertLess(gate,execute)
            self.assertIn('SKIPPED: no explicit manual opt-in; not evaluated',entry)

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
            self.assertEqual(m.hashlib.sha256(source.encode()).hexdigest(),m.SOURCE_SQL_SHA256)
            for damaged in [source.replace(m.END,''),source+'-- drift',source.replace('begin;','select 1;',1)]:
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

    def test_measured_select_is_byte_exact_accepted_historical_read_workload(self):
        # Import the actual old pure workload builder; do not duplicate its SQL.
        code="import {workloadSQL} from './scripts/qualify-authenticated-rls-read.mjs';process.stdout.write(JSON.stringify(['assets','style_groups'].map(t=>[t,workloadSQL(t,1000)])));"
        result=m.subprocess.run(['node','--input-type=module','-e',code],cwd=m.ROOT,capture_output=True,text=True,check=True,timeout=10)
        for table,query in m.json.loads(result.stdout):
            self.assertEqual(m.statement(table,'SELECT',1000).encode(),query.encode())
        jobs=m.jobs()
        self.assertEqual(sum(command=='SELECT'for _,command,_,_,_ in jobs),44)
        self.assertEqual(sum(command!='SELECT'for _,command,_,_,_ in jobs),330)

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

    def test_entrypoint_uses_sql_error_not_unsupported_quit_status(self):
            entry=(m.ROOT/'supabase/tests/rls_public_admin_actual_table_performance.sql').read_text()
            self.assertIn('\\if :SHELL_ERROR',entry)
            self.assertIn("raise exception '4427 driver failure'",entry)
            self.assertNotIn('\\quit',entry)
            source=P.read_text()
            self.assertIn('error.returncode != 3',source)
            self.assertIn('psql_shell_failure_signal_proven=True',source)
            self.assertIn("checkout != os.environ['GITHUB_SHA']",source)
            self.assertIn("'HEAD:' + relative",source)
            self.assertIn('actual != committed',source)

    def container_row(self):
            return dict(Id='a'*64, Name='/supabase_db_shared-db', Image='sha256:'+'b'*64,
                Config=dict(Image='public.ecr.aws/supabase/postgres:17.6.1.063', Labels={
                    'com.supabase.cli.project':'shared-db','com.docker.compose.project':'shared-db'}),
                State=dict(Running=True,Status='running',Health=dict(Status='healthy')),
                HostConfig=dict(Privileged=False,NetworkMode='supabase_network_shared-db',
                    Binds=['supabase_db_shared-db:/var/lib/postgresql/data'],
                    PortBindings={'5432/tcp':[dict(HostPort='54322',HostIp='0.0.0.0')]}),
                Mounts=[dict(Type='volume',Name='supabase_db_shared-db',Destination='/var/lib/postgresql/data',RW=True)],
                NetworkSettings=dict(Networks={'supabase_network_shared-db':{}},
                    Ports={'5432/tcp':[dict(HostPort='54322',HostIp='0.0.0.0')]}))

    def test_container_custody_rejects_each_foreign_resource_dimension(self):
            original=self.container_row()
            self.assertEqual(m.NativeCI.validate_container(original)[0],'a'*64)
            mutations=[('Name','/foreign'),('Id','c'*64),('Image','mutable'),
                ('Config.Labels.com.supabase.cli.project','foreign'),('State.Health.Status','unhealthy'),
                ('HostConfig.Privileged',True),('HostConfig.Binds',['/tmp:/var/lib/postgresql/data']),
                ('HostConfig.NetworkMode','host'),('Mounts',[]),('NetworkSettings.Networks',{'foreign':{}}),
                ('NetworkSettings.Ports',{'5432/tcp':[dict(HostPort='5432')]}),
                ('Config.Image','example.invalid/postgres:17')]
            for field,value in mutations:
                row=copy.deepcopy(original)
                if field=='Config.Labels.com.supabase.cli.project':row['Config']['Labels']['com.supabase.cli.project']=value
                else:
                    parent=row
                    parts=field.split('.')
                    for k in parts[:-1]:parent=parent[k]
                    parent[parts[-1]]=value
                with self.subTest(field=field),self.assertRaises(RuntimeError):
                    m.NativeCI.validate_container(row,expected_id='a'*64)

    def test_every_container_exec_revalidates_identity_and_uses_fixed_local_endpoint(self):
            with patch.dict(os.environ,self.valid_env(),clear=True):c=m.NativeCI()
            c.docker_config='/private/config';c.container_id='a'*64;c.container_image=('sha256:'+'b'*64,'public.ecr.aws/supabase/postgres:17.6.1.063')
            row=self.container_row()
            def inspect(*args):
                if args[0]=='image':return m.json.dumps([dict(Id=c.container_image[0],RepoTags=[c.container_image[1]])])
                return m.json.dumps([row])
            with patch.object(c,'docker_read',side_effect=inspect),patch.object(m.subprocess,'run',return_value=m.subprocess.CompletedProcess([],0,stdout=b'version',stderr=b'')) as run:
                c.container_exec(['pg_basebackup','--version'])
                argv=run.call_args.args[0]
                self.assertEqual(argv[:3],['/usr/bin/docker','--host','unix:///var/run/docker.sock'])
                self.assertIn('a'*64,argv)
                self.assertNotIn('-i',argv)
                self.assertEqual(run.call_args.kwargs['stdin'],m.subprocess.DEVNULL)
                row['Id']='c'*64
                with self.assertRaises(RuntimeError):c.container_exec(['pg_basebackup','--version'])
                self.assertEqual(run.call_count,1)
            with patch.object(c,'docker_read',side_effect=inspect):
                row['Id']='a'*64
                c.container_image=('sha256:'+'d'*64,c.container_image[1])
                with self.assertRaises(RuntimeError):c.custody()

    def test_image_inherited_metadata_is_exact_and_ownership_may_not_conflict(self):
            with patch.dict(os.environ,self.valid_env(),clear=True):c=m.NativeCI()
            row=self.container_row(); image=dict(Id=row['Image'],RepoTags=[row['Config']['Image']],Config=dict(Labels={'org.opencontainers.image.version':'17.6'}))
            def inspect(*args):return m.json.dumps([image if args[0]=='image' else row])
            row['Config']['Labels']['org.opencontainers.image.version']='17.6'
            with patch.object(c,'docker_read',side_effect=inspect):
                c.custody()
                row['Config']['Labels']['unexpected']='foreign'
                with self.assertRaises(RuntimeError):c.custody()
                del row['Config']['Labels']['unexpected']
                image['Config']['Labels']['com.supabase.cli.project']='foreign'
                with self.assertRaises(RuntimeError):c.custody()

    def test_failure_preserves_exit_with_bounded_binary_stderr_and_no_archive_output(self):
            with patch.dict(os.environ,self.valid_env(),clear=True):c=m.NativeCI()
            failure=m.subprocess.CalledProcessError(7,['/usr/bin/docker'],output=b'not-for-logs',stderr=b'e'*5000)
            with patch.object(m.subprocess,'run',side_effect=failure),patch.object(c,'diagnostic') as diagnostic:
                with self.assertRaises(m.subprocess.CalledProcessError) as caught:c.checked(['/usr/bin/docker'])
                self.assertEqual(caught.exception.returncode,7)
                self.assertEqual(len(diagnostic.call_args.kwargs['stderr']),4096)
                self.assertTrue(diagnostic.call_args.kwargs['truncated'])
                self.assertNotIn('not-for-logs',str(diagnostic.call_args))

    def test_only_current_physical_source_commands_are_admitted(self):
        import io
        with patch.dict(os.environ,self.valid_env(),clear=True):c=m.NativeCI()
        c.docker_config='/private';c.container_id='a'*64;c.restore_authority_qualified=True
        completed=m.subprocess.CompletedProcess([],0,stdout=b'fixed result',stderr=b'')
        with patch.object(c,'custody'),patch.object(m.subprocess,'run',return_value=completed) as run:
            c.source_checked(m.physical4427.REPL_PROBE_ARGS,allowed_failure=True)
            self.assertEqual(run.call_args.kwargs['stdin'],m.subprocess.DEVNULL)
            for args in [['pg_dump','--version'],['pg_restore','--version'],['psql','-c','select 1'],
                         m.physical4427.REPL_PROBE_ARGS+['--extra']]:
                with self.assertRaises(RuntimeError):c.source_checked(args)
            with self.assertRaises(RuntimeError):c.source_checked(m.physical4427.HBA_APPEND_ARGS,input_file=io.BytesIO(m.physical4427.HBA_LINE))
            c.hba_window_active=True
            with self.assertRaises(RuntimeError):c.source_checked(m.physical4427.HBA_APPEND_ARGS,input_file=io.BytesIO(b'host all all all trust'))
            c.source_checked(m.physical4427.HBA_APPEND_ARGS,input_file=io.BytesIO(m.physical4427.HBA_LINE))
            self.assertIn('-i',run.call_args.args[0])
            with self.assertRaises(RuntimeError):c.source_checked(m.physical4427.BACKUP_ARGS,output_file=io.BytesIO())
            c.hba_temporary_verified=True
            c.source_checked(m.physical4427.BACKUP_ARGS,output_file=io.BytesIO())
            self.assertNotIn('-i',run.call_args.args[0])

    def test_real_child_native_hba_bytes_and_file_backed_restore_channels(self):
        import io
        import tempfile
        real_run=m.subprocess.run;seen=[]
        reader=['/usr/bin/python3','-c','import sys;sys.stdout.buffer.write(sys.stdin.buffer.read())']
        def child(argv,**kwargs):
            self.assertEqual(argv[0],'/usr/bin/docker');seen.append(dict(kwargs))
            return real_run(reader,**kwargs)
        with patch.dict(os.environ,self.valid_env(),clear=True):c=m.NativeCI()
        c.container_id='a'*64;c.docker_config='/private/offline-test-config';c.restore_authority_qualified=True;c.hba_window_active=True
        with patch.object(c,'custody'),patch.object(m.subprocess,'run',side_effect=child):
            payload=m.physical4427.HBA_LINE
            self.assertEqual(c.source_checked(m.physical4427.HBA_APPEND_ARGS,input_file=io.BytesIO(payload)).stdout,payload)
            self.assertEqual(seen[-1]['input'],payload);self.assertNotIn('stdin',seen[-1])
            c.hba_original_bytes=b'local all supabase_admin trust\n'
            with tempfile.TemporaryFile() as file:
                file.write(c.hba_original_bytes);file.seek(0)
                self.assertEqual(c.source_checked(m.physical4427.HBA_RESTORE_ARGS,input_file=file).stdout,c.hba_original_bytes)
                self.assertIs(seen[-1]['stdin'],file);self.assertNotIn('input',seen[-1])

    def test_existing_source_authority_remains_exact_same_instance(self):
        context=dict(system_identifier='12345',server_version_num=170006,postmaster_start='fixed',database='postgres')
        facts={**context,'current_user':'supabase_admin','session_user':'supabase_admin','rolsuper':True,'rolcanlogin':True,'is_superuser':'on'}
        self.assertEqual(m.validate_restore_authority(facts,context),facts)
        for key,value in [('current_user','postgres'),('session_user','postgres'),('rolsuper',False),('rolcanlogin',False),('is_superuser','off'),('system_identifier','foreign'),('postmaster_start','other'),('server_version_num',170011),('database','foreign')]:
            with self.subTest(key=key),self.assertRaises(RuntimeError):m.validate_restore_authority({**facts,key:value},context)

    def test_target_sql_cannot_be_redirected_to_another_database(self):
        with patch.dict(os.environ,self.valid_env(),clear=True):c=m.NativeCI()
        c.physical=unittest.mock.Mock()
        with self.assertRaises(RuntimeError):c.sql('foreign','select 1;')
        c.physical.sql.assert_not_called()
        c.sql('postgres','select 1;');c.physical.sql.assert_called_once_with('select 1;')


if __name__=='__main__':unittest.main()
