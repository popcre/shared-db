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

    def test_baseline_requires_file_copy_before_hashing_and_never_reopens_sealed_template(self):
        with patch.dict(os.environ,self.valid_env(),clear=True):c=m.NativeCI()
        events=[]
        def sql(db,query):
            events.append(('sql',db,query))
            if 'pg_stat_activity' in query:return '0'
            return '{"heap_md5":"post-flush"}'
        def create(db,template):events.append(('copy',db,template))
        def drop(db):events.append(('drop',db))
        with patch.object(c,'sql',side_effect=sql),patch.object(c,'create',side_effect=create),patch.object(c,'drop',side_effect=drop):
            base=c.prepare_baseline(c.prefix+'_seed')
        self.assertEqual(base['assets']['heap_md5'],'post-flush')
        copy_index=next(i for i,e in enumerate(events) if e[0]=='copy')
        seal_index=next(i for i,e in enumerate(events) if e[0]=='sql' and 'ALLOW_CONNECTIONS false' in e[2])
        self.assertLess(seal_index,copy_index)
        reads=[i for i,e in enumerate(events) if e[0]=='sql' and e[1].endswith('_baseline')]
        self.assertEqual(len(reads),2)
        self.assertTrue(all(i>copy_index for i in reads))
        self.assertFalse(any(e[0]=='sql' and e[1].endswith('_seed') for e in events[seal_index+1:]))
        self.assertEqual(events[-1][0],'drop')

    def test_baseline_session_or_snapshot_failure_refuses_and_cleans_owned_clone(self):
        with patch.dict(os.environ,self.valid_env(),clear=True):c=m.NativeCI()
        def live_session(db,query):return '1' if 'pg_stat_activity' in query else '{}'
        with patch.object(c,'sql',side_effect=live_session),patch.object(c,'create') as create:
            with self.assertRaisesRegex(RuntimeError,'still has a session'):c.prepare_baseline(c.prefix+'_seed')
            create.assert_not_called()
        def broken_snapshot(db,query):
            if db.endswith('_baseline'):raise RuntimeError('snapshot failed')
            return '0' if 'pg_stat_activity' in query else '{}'
        with patch.object(c,'sql',side_effect=broken_snapshot),patch.object(c,'create'),patch.object(c,'drop') as drop:
            with self.assertRaisesRegex(RuntimeError,'snapshot failed'):c.prepare_baseline(c.prefix+'_seed')
            drop.assert_called_once_with(c.prefix+'_baseline')

    def test_unowned_drop_and_create_refuse_without_subprocess(self):
        with patch.dict(os.environ,self.valid_env(),clear=True):c=m.NativeCI()
        with patch.object(c,'sql') as run:
            with self.assertRaises(RuntimeError):c.drop('postgres')
            with self.assertRaises(RuntimeError):c.create('postgres','template0')
            run.assert_not_called()

    def fresh_facts(self, database):
        return dict(database=database,owner='postgres',extra_schemas=0,relations=0,routines=0,types=0,policies=0,default_acls=0,
            extensions=['plpgsql'],public_owner='pg_database_owner',public_acl=['PUBLIC:USAGE:false','pg_database_owner:CREATE:false','pg_database_owner:USAGE:false'])

    def test_fresh_target_requires_owned_identity_and_every_catalog_boundary(self):
        with patch.dict(os.environ,self.valid_env(),clear=True):c=m.NativeCI()
        seed=c.prefix+'_seed';facts=self.fresh_facts(seed)
        self.assertEqual(m.validate_fresh_seed(facts,seed),facts)
        for key,value in [('database','postgres'),('owner','foreign'),('extra_schemas',1),('relations',1),('routines',1),('types',1),('policies',1),('default_acls',1),('extensions',['plpgsql','other']),('public_owner','foreign'),('public_acl',[])]:
            with self.subTest(key=key),self.assertRaises(RuntimeError):m.validate_fresh_seed({**facts,key:value},seed)
        with patch.object(c,'sql',return_value=m.json.dumps(facts)) as sql:
            with self.assertRaises(RuntimeError):c.qualify_fresh_seed(seed)
            sql.assert_not_called();c.owned.append(seed)
            c.qualify_fresh_seed(seed);self.assertEqual(c.fresh_restore_seed,seed)

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
        with patch.object(c,'docker_read',side_effect=inspect),patch.object(c,'checked') as run:
            c.container_exec(['pg_dump','--version'])
            argv=run.call_args.args[0]
            self.assertEqual(argv[:3],['/usr/bin/docker','--host','unix:///var/run/docker.sock'])
            self.assertIn('a'*64,argv)
            self.assertNotIn('-i',argv)
            self.assertEqual(run.call_args.kwargs['stdin'],m.subprocess.DEVNULL)
            row['Id']='c'*64
            with self.assertRaises(RuntimeError):c.container_exec(['pg_dump','--version'])
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

    def test_actual_wrapper_distinguishes_exact_restore_version_and_owned_data_restore(self):
        import io
        with patch.dict(os.environ,self.valid_env(),clear=True):c=m.NativeCI()
        c.docker_config='/private';c.container_id='a'*64
        connection=['-h','127.0.0.1','-p','5432','-U','postgres','-d']
        seed=c.prefix+'_seed';restore=['pg_restore',*connection,seed,'--exit-on-error']
        read_commands=[['pg_restore','--version'],['pg_dump','--version'],
            ['psql','-XqAtw',*connection,'postgres','-v','ON_ERROR_STOP=1','-c',m.POSTGRES_CONTEXT_QUERY]]
        completed=m.subprocess.CompletedProcess([],0,stdout=b'actual version probe result')
        with patch.object(c,'custody') as custody,patch.object(m.subprocess,'run',return_value=completed) as run:
            for command in read_commands:
                self.assertEqual(c.container_exec(command),b'actual version probe result')
                self.assertNotIn('-i',run.call_args.args[0]);self.assertEqual(run.call_args.kwargs['stdin'],m.subprocess.DEVNULL)
                with self.assertRaises(RuntimeError):c.container_exec(command,input_file=io.BytesIO(b'archive'))
            data=io.BytesIO(b'archive')
            with self.assertRaises(RuntimeError):c.container_exec(restore,input_file=data)
            c.owned.append(seed)
            with self.assertRaises(RuntimeError):c.container_exec(restore,input_file=data)
            c.fresh_restore_seed=seed
            with self.assertRaises(RuntimeError):c.container_exec(restore)
            c.container_exec(restore,input_file=data)
            self.assertIn('-i',run.call_args.args[0]);self.assertIs(run.call_args.kwargs['stdin'],data)
            bad=[['pg_restore'],['pg_restore','--version','--clean'],['pg_restore','--version','--exit-on-error'],
                 ['pg_restore',*connection,'postgres','--clean','--if-exists','--exit-on-error'],
                 ['pg_restore',*connection,seed,'--clean','--if-exists'],['psql','-c','select 1'],
                 ['pg_dump','--version','-Fc'],['pg_dump',*connection,'postgres','-Fc','--ignore-version']]
            count=run.call_count
            for command in bad:
                with self.subTest(command=command),self.assertRaises(RuntimeError):c.container_exec(command)
            self.assertEqual(run.call_count,count)
            self.assertEqual(custody.call_count,count)

    def test_restore_failure_run_finally_drops_owned_seed(self):
        with patch.dict(os.environ,self.valid_env(),clear=True):c=m.NativeCI()
        def git(argv,**kw):
            value=('a'*40) if argv[1]=='rev-parse' else (m.ROOT/argv[2].removeprefix('HEAD:')).read_bytes()
            return m.subprocess.CompletedProcess(argv,0,stdout=value)
        def sql(db,query):
            if '\\! false' in query:raise m.subprocess.CalledProcessError(3,[],stderr='22012')
            return ''
        def snapshot(seed):
            c.owned.append(seed)
            raise m.subprocess.CalledProcessError(1,['pg_restore'],stderr=b'actual restore failure')
        def drop(db):c.owned.remove(db);c.cleanup.append(db)
        with patch.dict(os.environ,self.valid_env(),clear=True),patch.object(m.subprocess,'run',side_effect=git),patch.object(c,'sql',side_effect=sql),patch.object(c,'snapshot',side_effect=snapshot),patch.object(c,'drop',side_effect=drop) as cleanup:
            with self.assertRaises(m.subprocess.CalledProcessError):c.run()
            cleanup.assert_called_once_with(c.prefix+'_seed');self.assertEqual(c.owned,[])
            # Report aliases this exact list and main serializes only after run/finally returns.
            report={'owned_drop_receipts':c.cleanup}
            self.assertIn(c.prefix+'_seed',m.json.loads(m.json.dumps(report))['owned_drop_receipts'])

    def test_snapshot_rejects_remote_environment_before_any_command(self):
        with patch.dict(os.environ,{**self.valid_env(),'DOCKER_HOST':'tcp://foreign:2375'},clear=True), patch.object(m.subprocess,'run') as run:
            c=m.NativeCI()
            with self.assertRaisesRegex(RuntimeError,'override refused'):c.snapshot(c.prefix+'_seed')
            run.assert_not_called()

    def test_untrusted_socket_refuses_before_docker_command(self):
        from types import SimpleNamespace
        for mode,uid in [(m.stat.S_IFREG|0o600,0),(m.stat.S_IFSOCK|0o666,0),(m.stat.S_IFSOCK|0o600,1000)]:
            with patch.dict(os.environ,self.valid_env(),clear=True),patch.object(m.Path,'stat',return_value=SimpleNamespace(st_mode=mode,st_uid=uid)),patch.object(m.Path,'resolve',return_value=m.Path('/run/docker.sock')),patch.object(m.subprocess,'run') as run:
                c=m.NativeCI()
                with self.assertRaisesRegex(RuntimeError,'Unix Docker endpoint refused'):c.snapshot(c.prefix+'_seed')
                run.assert_not_called()

    def snapshot_harness(self, major=17, dump_failure=False, restore_failure=False, wrong_instance=False, wrong_start=False):
        with patch.dict(os.environ,self.valid_env(),clear=True):c=m.NativeCI()
        events=[];identity=('a'*64,'sha256:'+'b'*64,'public.ecr.aws/supabase/postgres:17.6.1.063')
        context=dict(system_identifier='12345',server_version_num=170006,postmaster_start='2026-10-27 10:00:00+00',database='postgres')
        def sql(db,query):return m.json.dumps(self.fresh_facts(db) if query==m.FRESH_SEED_QUERY else context)
        def execute(args,input_file=None,output_file=None):
            events.append(args)
            if args[0]=='psql':return m.json.dumps({**context,'system_identifier':'999' if wrong_instance else '12345','postmaster_start':'different-postmaster' if wrong_start else context['postmaster_start']}).encode()
            if args[-1]=='--version':return f'{args[0]} (PostgreSQL) {major}.6\n'.encode()
            if args[0]=='pg_dump':
                if dump_failure:raise m.subprocess.CalledProcessError(1,args,stderr=b'actual dump failure')
                self.assertEqual(m.stat.S_IMODE(os.fstat(output_file.fileno()).st_mode),0o600)
                output_file.write(b'PGDMP synthetic archive');return None
            if args[0]=='pg_restore':
                self.assertEqual(input_file.read(),b'PGDMP synthetic archive')
                if restore_failure:raise m.subprocess.CalledProcessError(1,args,stderr=b'actual restore failure')
                return b''
            self.fail('unexpected fixed operation')
        socket=m.stat.S_IFSOCK|0o660
        fake=m.subprocess.CompletedProcess([],0,stdout='host (PostgreSQL) 16.15\n')
        return c,events,identity,sql,execute,socket,fake

    def exercise_snapshot(self, **options):
        c,events,identity,sql,execute,socket,fake=self.snapshot_harness(**options)
        from types import SimpleNamespace
        # Path.stat is mocked only for the fixed socket; temporary files retain real metadata.
        real_stat=m.Path.stat
        def create_owned(db,template):c.owned.append(db)
        def path_stat(path,*a,**kw):
            if str(path)=='/var/run/docker.sock':return SimpleNamespace(st_mode=socket,st_uid=0)
            return real_stat(path,*a,**kw)
        with patch.dict(os.environ,self.valid_env(),clear=True),patch.object(m.Path,'stat',path_stat), \
             patch.object(m.Path,'resolve',lambda p,*a,**kw:p),patch.object(c,'custody',return_value=identity), \
             patch.object(c,'sql',side_effect=sql),patch.object(c,'container_exec',side_effect=execute), \
             patch.object(c,'checked',return_value=fake),patch.object(c,'create',side_effect=create_owned) as create:
            try:result=c.snapshot(c.prefix+'_seed')
            except Exception as error:return c,events,create.call_count,error
            return c,events,create.call_count,result

    def test_matching_container_snapshot_preserves_full_archive_and_exact_two_operations(self):
        c,events,creates,result=self.exercise_snapshot()
        self.assertEqual(creates,1)
        self.assertIsInstance(result,dict)
        operations=[x for x in events if x[-1]!='--version' and x[0]!='psql']
        self.assertEqual(len(operations),2)
        self.assertEqual(operations[0],['pg_dump','-h','127.0.0.1','-p','5432','-U','postgres','-d','postgres','-Fc'])
        self.assertEqual(operations[1][-1:],['--exit-on-error']);self.assertNotIn('--clean',operations[1]);self.assertNotIn('--if-exists',operations[1])
        self.assertEqual(result['archive_sha256'],m.hashlib.sha256(b'PGDMP synthetic archive').hexdigest())

    def test_wrong_instance_versions_and_dump_fail_before_seed_creation_restore_fails_loudly(self):
        for options in [dict(major=16),dict(wrong_instance=True),dict(wrong_start=True),dict(dump_failure=True),dict(restore_failure=True)]:
            with self.subTest(options=options):
                c,events,creates,error=self.exercise_snapshot(**options)
                self.assertIsInstance(error,Exception)
                self.assertEqual(creates,1 if options.get('restore_failure') else 0)
                self.assertEqual(sum(x[0]=='pg_dump' and x[-1]!='--version' for x in events),
                                 1 if options.get('dump_failure') or options.get('restore_failure') else 0)

    def test_failure_preserves_exit_with_bounded_binary_stderr_and_no_archive_output(self):
        with patch.dict(os.environ,self.valid_env(),clear=True):c=m.NativeCI()
        failure=m.subprocess.CalledProcessError(7,['/usr/bin/docker'],output=b'not-for-logs',stderr=b'e'*5000)
        with patch.object(m.subprocess,'run',side_effect=failure),patch.object(c,'diagnostic') as diagnostic:
            with self.assertRaises(m.subprocess.CalledProcessError) as caught:c.checked(['/usr/bin/docker'])
            self.assertEqual(caught.exception.returncode,7)
            self.assertEqual(len(diagnostic.call_args.kwargs['stderr']),4096)
            self.assertTrue(diagnostic.call_args.kwargs['truncated'])
            self.assertNotIn('not-for-logs',str(diagnostic.call_args))

    def test_drop_receipt_requires_actual_absence(self):
        with patch.dict(os.environ,self.valid_env(),clear=True):c=m.NativeCI()
        db=c.prefix+'_seed';c.owned=[db]
        with patch.object(c,'sql',side_effect=['','0']),patch.object(c,'diagnostic') as record:
            c.drop(db);self.assertEqual(c.owned,[]);self.assertEqual(c.cleanup,[db]);record.assert_called_once()
        c.owned=[db]
        with patch.object(c,'sql',side_effect=['','1']):
            with self.assertRaises(RuntimeError):c.drop(db)
            self.assertEqual(c.owned,[db])


if __name__ == '__main__':unittest.main()
