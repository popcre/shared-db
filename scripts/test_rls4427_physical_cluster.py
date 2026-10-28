"""Offline controls: no Docker/socket/SQL action is executed by these tests."""
import copy
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import time
import unittest
from unittest.mock import patch

P=Path(__file__).with_name('rls4427_physical_cluster.py')
spec=importlib.util.spec_from_file_location('physical4427',P)
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)


class PhysicalControls(unittest.TestCase):
    def source(self):
        class Source:
            prefix='rls4427_test'
        return Source()

    def facts(self):
        return dict(database='postgres',current_user='supabase_admin',session_user='supabase_admin',superuser=True,replication=True,
            recovery=False,wal_level='logical',max_wal_senders=10,external_tablespaces=0,subscriptions=0,slots=0,prepared_transactions=0,
            cron_version='1.6',sodium_version='3.1.8',sodium_nonce_api=True,sodium_keyid_api=True,sodium_open_keyid_api=True,config_file='/etc/postgresql/postgresql.conf',hba_file='/etc/postgresql/pg_hba.conf',
            ident_file='/etc/postgresql/pg_ident.conf',data_directory=m.DATA,archive_mode='off',archive_command='',restore_command='',
            primary_conninfo='',ssl='off',log_directory='/var/log/postgresql',socket='/var/run/postgresql',cron_database='postgres',
            preload='pg_stat_statements, pg_cron, pgsodium',hba_errors=0,replication_hba=1,other_backends=0)

    def test_import_and_construction_do_not_launch_resources(self):
        with patch.object(m.subprocess,'run') as run:
            p=m.PhysicalCluster(self.source());self.assertIsNone(p.cid);run.assert_not_called()

    def test_actual_source_startup_and_omission_facts_fail_closed(self):
        facts=self.facts();self.assertEqual(m.validate_source_facts(facts),facts)
        for k,v in [('current_user','postgres'),('superuser',False),('recovery',True),('wal_level','minimal'),('max_wal_senders',0),
                    ('external_tablespaces',1),('subscriptions',1),('slots',1),('prepared_transactions',1),('replication_hba','unknown'),
                    ('hba_errors',1),('other_backends',1),('cron_version','other'),('ssl','on'),('archive_mode','on'),
                    ('archive_command','external'),('primary_conninfo','external'),('restore_command','external'),
                    ('config_file','/foreign/config'),('preload','pg_cron')]:
            with self.subTest(key=k),self.assertRaisesRegex(RuntimeError,'facts refused'):m.validate_source_facts({**facts,k:v})
        self.assertIn("select exists(select 1",m.SOURCE_FACTS_SQL)
        self.assertIn("nonempty unlogged relation",m.SOURCE_FACTS_SQL)
        self.assertNotIn('reltuples',m.SOURCE_FACTS_SQL)

    def test_actual_cached_sodium_sql_api_is_required_before_any_backup(self):
        facts=self.facts();self.assertEqual(m.validate_source_facts(facts)['sodium_version'],'3.1.8')
        for key,value in [('sodium_version',None),('sodium_version','3.1.7'),('sodium_nonce_api',False),('sodium_keyid_api',False),('sodium_open_keyid_api',False)]:
            with self.subTest(key=key),self.assertRaises(RuntimeError):m.validate_source_facts({**facts,key:value})
        self.assertIn("to_regprocedure('pgsodium.crypto_secretbox(bytea,bytea,bigint,bytea)')",m.SOURCE_FACTS_SQL)
        self.assertIn("to_regprocedure('pgsodium.crypto_secretbox_open(bytea,bytea,bigint,bytea)')",m.SOURCE_FACTS_SQL)
        source=P.read_text()
        self.assertLess(source.index('facts=validate_source_facts'),source.index('with permission:'))

    def test_inactive_archive_display_is_qualified_without_configuration_change(self):
        facts=self.facts()
        self.assertEqual(m.validate_source_facts({**facts,'archive_command':'(disabled)'} )['archive_mode'],'off')
        for changes in [dict(archive_mode='on',archive_command='(disabled)'),dict(archive_mode='always',archive_command=''),dict(archive_command='external'),dict(restore_command='external'),dict(primary_conninfo='external')]:
            with self.subTest(changes=changes),self.assertRaises(RuntimeError):m.validate_source_facts({**facts,**changes})

    def test_real_child_physical_sql_hba_and_file_archive_channels(self):
        import subprocess
        real_run=subprocess.run;seen=[]
        reader=['/usr/bin/python3','-c','import sys;sys.stdout.buffer.write(sys.stdin.buffer.read())']
        def child(argv,**kwargs):
            self.assertEqual(argv[0],'/usr/bin/docker')
            seen.append(dict(kwargs))
            return real_run(reader,**kwargs)
        p=m.PhysicalCluster(self.source());p.root=Path('/private/offline-test-config');p.cid='a'*64
        with patch.object(p,'custody'),patch.object(m.subprocess,'run',side_effect=child):
            for payload in (b"select 'owned4427';\n",m.HBA_LINE):
                self.assertEqual(p.target(['fixed-test-stdin-reader'],input_file=io.BytesIO(payload)).stdout,payload)
                self.assertEqual(seen[-1]['input'],payload);self.assertNotIn('stdin',seen[-1])
            with tempfile.TemporaryFile() as archive:
                payload=b'PGDMP-invented-archive\x00'*4096;archive.write(payload);archive.seek(0)
                self.assertEqual(p.target(['fixed-test-archive-reader'],input_file=archive).stdout,payload)
                self.assertIs(seen[-1]['stdin'],archive);self.assertNotIn('input',seen[-1])
            query="select 'small fixed SQL';"
            self.assertEqual(p.sql(query),query)
            self.assertEqual(seen[-1]['input'],query.encode())
        with self.assertRaises(RuntimeError):m.process_input(io.StringIO('unsupported'))

    def test_existing_nix_cron_binary_is_closed_without_alias_or_hash_fallback(self):
        self.assertEqual(m.BINARY_ARGS,['sha256sum','/nix/store/qpz7hxz26yk04v1f0cxfhgicy360zf9n-pg_cron-1.6.4/lib/pg_cron-1.6.4.so'])
        self.assertEqual(m.CRON_BINARY_SHA,'55a7bdcf1b966d51d83d248797507348de19d16f1c968948c1854bc799751108')
        self.assertEqual(m.source_command_kind(m.BINARY_ARGS),'read')
        self.assertIsNone(m.source_command_kind(['sha256sum','/usr/lib/postgresql/lib/pg_cron.so']))
        self.assertIsNone(m.source_command_kind(m.BINARY_ARGS+['another-library']))

    def test_cron_preserves_normal_minute_jobs_but_no_startup_or_interval_jobs(self):
        facts=dict(jobs=2,job_hash='j',schedules=['* * * * *','0 1 * * 1-5'],runs=3,run_hash='r',pending=0,workers=0,schedulers=[[10,'fixed']])
        self.assertEqual(m.validate_cron(facts),facts)
        for schedules in [['@reboot'],['5 seconds'],['* * * * * *'],['bad * * * *']]:
            with self.assertRaises(RuntimeError):m.validate_cron({**facts,'schedules':schedules})
        for key,value in [('pending',1),('workers',1),('schedulers',[])]:
            with self.assertRaises(RuntimeError):m.validate_cron({**facts,key:value})
        changed=copy.deepcopy(facts);changed['schedulers']=[[11,'new']]
        self.assertEqual(m.cron_fingerprint(facts),m.cron_fingerprint(changed))
        # Per-running-instance check retains the full scheduler tuple separately.
        self.assertNotEqual(facts,changed)

    def archive(self,path,files,links=None):
        with tarfile.open(path,'w') as out:
            for name,value in files.items():
                entry=tarfile.TarInfo(name);entry.uid=100;entry.gid=101;entry.size=len(value);out.addfile(entry,io.BytesIO(value))
            for name,target in (links or {}).items():
                entry=tarfile.TarInfo(name);entry.type=tarfile.SYMTYPE;entry.linkname=target;out.addfile(entry)

    def config(self):
        return {'etc/postgresql/postgresql.conf':b"include='/etc/postgresql-custom/custom.conf'\n",
                'etc/postgresql/pg_hba.conf':b'local replication supabase_admin trust\n',
                'etc/postgresql/pg_ident.conf':b'', 'etc/postgresql-custom/custom.conf':b"shared_preload_libraries='pg_cron,pgsodium'\n",
                'etc/postgresql-custom/pgsodium_root.key':b'a'*64}

    def test_private_config_requires_real_key_and_exact_closed_include_graph(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'config.tar';self.archive(path,self.config());self.assertEqual(m.validate_tar(path,'config')['files'],5)
            for change in [dict(self.config(),**{'etc/postgresql-custom/pgsodium_root.key':b''}),
                           {k:v for k,v in self.config().items() if not k.endswith('root.key')},
                           dict(self.config(),**{'etc/postgresql/postgresql.conf':b"include='/outside/file'\n"}),
                           dict(self.config(),**{'etc/postgresql/postgresql.conf':b"include='/etc/postgresql-custom/missing.conf'\n"}),
                           dict(self.config(),**{'etc/postgresql/postgresql.conf':b'include /unsupported\n'})]:
                self.archive(path,change)
                with self.assertRaises(RuntimeError):m.validate_tar(path,'config')
            self.archive(path,self.config(),{'etc/postgresql-custom/alias':'/outside'})
            with self.assertRaises(RuntimeError):m.validate_tar(path,'config')

    def test_archive_escape_recovery_external_dependency_and_manifest_refuse(self):
        full={'PG_VERSION':b'17','global/pg_control':b'invented','backup_label':b'owned','backup_manifest':b'{}'}
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'cluster.tar';self.archive(path,full);m.validate_tar(path,'backup')
            for name in ('../escape','/absolute','standby.signal','recovery.signal','postmaster.pid','pg_tblspc/external'):
                self.archive(path,{**full,name:b'bad'})
                with self.assertRaises(RuntimeError):m.validate_tar(path,'backup')
            self.archive(path,{k:v for k,v in full.items() if k!='backup_manifest'})
            with self.assertRaises(RuntimeError):m.validate_tar(path,'backup')
            m.validate_tar(path,'sealed') # Explicitly different from original backup verification.

    def test_mixed_configuration_metadata_is_preserved_and_every_mutation_refuses(self):
        from types import SimpleNamespace
        def config_archive(path,change=None):
            with tarfile.open(path,'w') as out:
                for name,owner in [('etc/postgresql',(0,0)),('etc/postgresql-custom',(100,101))]:
                    e=tarfile.TarInfo(name);e.type=tarfile.DIRTYPE;e.uid,e.gid=owner;e.mode=0o755
                    if change:change(e)
                    out.addfile(e)
                for i,(name,value) in enumerate(self.config().items()):
                    e=tarfile.TarInfo(name);e.uid,e.gid=(0,0) if i%2 else (100,101);e.mode=0o600 if name.endswith('key') else 0o755;e.size=len(value)
                    if change:change(e)
                    out.addfile(e,io.BytesIO(value))
        with tempfile.TemporaryDirectory() as d:
            p=m.PhysicalCluster(self.source());p.root=Path(d);p.cid='a'*64
            original=p.root/'source-config.tar';config_archive(original)
            p.original_config_receipt=m.validate_tar(original,'config')
            calls=[]
            def docker(*args,**kw):
                calls.append(args)
                if kw.get('output_file'):
                    kw['output_file'].write(original.read_bytes())
                return SimpleNamespace(returncode=0,stdout=b'',stderr=b'')
            with patch.object(p,'custody') as custody,patch.object(p,'docker',side_effect=docker):
                p.restore_config();self.assertTrue(p.config_metadata_verified)
                self.assertEqual(calls[0],('exec','-i','--user','0:0',p.cid,*m.CONFIG_RESTORE_ARGS))
                self.assertEqual(calls[1],('exec','--user','0:0',p.cid,*m.CONFIG_ARGS));self.assertEqual(custody.call_count,2)
                for args in [m.CONFIG_RESTORE_ARGS+['foreign'],['sh','-c','anything'],['tar','-C','/','-xf','-']]:
                    with self.assertRaises(RuntimeError):p.config_target(args)
                foreign=p.root/'foreign.tar';foreign.write_bytes(original.read_bytes())
                with foreign.open('rb') as stream,self.assertRaises(RuntimeError):p.config_target(m.CONFIG_RESTORE_ARGS,input_file=stream)
            for changes in [dict(uid=100,gid=101),dict(mode=0o644)]:
                changed=p.root/'changed.tar';config_archive(changed,lambda e:[setattr(e,k,v) for k,v in changes.items()])
                self.assertNotEqual(m.validate_tar(changed,'config')['metadata_sha256'],p.original_config_receipt['metadata_sha256'])
                (p.root/'target-config.tar').unlink(missing_ok=True)
                def altered_docker(*args,**kw):
                    if kw.get('output_file'):kw['output_file'].write(changed.read_bytes())
                    return SimpleNamespace(returncode=0,stdout=b'',stderr=b'')
                with patch.object(p,'custody'),patch.object(p,'docker',side_effect=altered_docker),self.assertRaisesRegex(RuntimeError,'ownership/mode/content differs'):p.restore_config()
            for changes in [dict(uid=99),dict(mode=0o777),dict(mode=0o4755)]:
                changed=p.root/'bad.tar';config_archive(changed,lambda e:[setattr(e,k,v) for k,v in changes.items()])
                with self.assertRaises(RuntimeError):m.validate_tar(changed,'config')
            # A root-owned PGDATA entry must refuse before extraction, including archive root.
            for name in ['PG_VERSION','.']:
                with tarfile.open(p.root/'bad-pg.tar','w') as out:
                    e=tarfile.TarInfo(name);e.type=tarfile.DIRTYPE if name=='.' else tarfile.REGTYPE;out.addfile(e)
                with self.assertRaisesRegex(RuntimeError,'PGDATA ownership'):m.validate_tar(p.root/'bad-pg.tar','backup')

    def test_only_backup_tool_manifest_has_exact_generated_header_exception(self):
        full={'PG_VERSION':b'17','global/pg_control':b'invented','backup_label':b'owned','backup_manifest':b'{}'}
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'backup.tar'
            def archive(name='backup_manifest',uid=2048,gid=1024,mode=0o600,directory=False):
                with tarfile.open(p,'w') as out:
                    for n,data in full.items():
                        e=tarfile.TarInfo(n if n!='backup_manifest' else name);e.uid=100;e.gid=101;e.mode=0o600;e.size=len(data)
                        if n=='backup_manifest':
                            e.uid=uid;e.gid=gid;e.mode=mode
                            if directory:e.type=tarfile.DIRTYPE;e.size=0
                        out.addfile(e,io.BytesIO(data) if e.isfile() else None)
            archive();self.assertEqual(m.validate_tar(p,'backup')['files'],4)
            with self.assertRaisesRegex(RuntimeError,'ownership'):m.validate_tar(p,'sealed')
            for change in [dict(name='other'),dict(uid=2047),dict(gid=1025),dict(mode=0o644),dict(directory=True)]:
                archive(**change)
                with self.subTest(change=change),self.assertRaisesRegex(RuntimeError,'ownership'):m.validate_tar(p,'backup')

    def test_minute_deadline_and_wall_monotonic_continuity_are_real_guards(self):
        m.minute_guard(125,10,140,25)
        for endwall,endmono in [(170,55),(185,70),(124,9),(140,26)]:
            with self.subTest(endwall=endwall),self.assertRaises(RuntimeError):m.minute_guard(125,10,endwall,endmono)

    def test_exact_target_resource_custody_rejects_authority_expansion(self):
        import subprocess
        p=m.PhysicalCluster(self.source());p.cid='a'*64;p.image_id='sha256:'+'b'*64;p.target_labels=dict(p.labels)
        row=dict(Id=p.cid,Name='/'+p.name,Image=p.image_id,Config=dict(Labels=p.target_labels,User='100:101',Entrypoint=['/bin/sleep'],Cmd=['infinity']),
            State=dict(Running=True),HostConfig=dict(NetworkMode='none',Privileged=False,ReadonlyRootfs=True,Memory=2147483648,NanoCpus=1000000000,PidsLimit=256,Tmpfs=dict(m.TMPFS)),
            NetworkSettings=dict(Networks={'none':{}},Ports={}),Mounts=[])
        def result(value):return subprocess.CompletedProcess([],0,stdout=json.dumps([value]).encode(),stderr=b'')
        with patch.object(p,'docker',return_value=result(row)):p.custody()
        for section,key,value in [('Config','User','0'),('Config','Labels',{}),('HostConfig','Memory',4294967296),('HostConfig','PidsLimit',512),
            ('HostConfig','NetworkMode','bridge'),('HostConfig','Binds',['/host:/target']),('HostConfig','ReadonlyRootfs',False),
            ('HostConfig','Tmpfs',{**m.TMPFS,m.DATA:m.TMPFS[m.DATA].replace('4294967296','8589934592')}),
            ('NetworkSettings','Ports',{'5432/tcp':[{'HostPort':'5432'}]})]:
            wrong=copy.deepcopy(row);wrong[section][key]=value
            with self.subTest(key=key),patch.object(p,'docker',return_value=result(wrong)),self.assertRaises(RuntimeError):p.custody()

    def test_stopped_owned_keeper_cleanup_skips_exec_and_foreign_identity_refuses(self):
        import subprocess
        for foreign in (False,True):
            p=m.PhysicalCluster(self.source());p.cid='a'*64;p.running=True;p.image_id='sha256:'+'b'*64;p.target_labels=dict(p.labels)
            row=dict(Id='b'*64 if foreign else p.cid,Name='/'+p.name,Image=p.image_id,Config=dict(Labels=p.target_labels,User='100:101',Entrypoint=['/bin/sleep'],Cmd=['infinity']),
                State=dict(Running=False,Status='exited',OOMKilled=True),HostConfig=dict(NetworkMode='none',Privileged=False,ReadonlyRootfs=True,Memory=2147483648,NanoCpus=1000000000,PidsLimit=256,Tmpfs=dict(m.TMPFS)),
                NetworkSettings=dict(Networks={'none':{}},Ports={}),Mounts=[])
            operations=[]
            def docker(*args,**kwargs):
                operations.append(args)
                if args[0]=='inspect':return subprocess.CompletedProcess([],0,stdout=json.dumps([row]).encode(),stderr=b'')
                if args[0]in('rm','ps'):return subprocess.CompletedProcess([],0,stdout=b'',stderr=b'')
                self.fail('no stop or exec into dead owned keeper')
            with patch.object(p,'docker',side_effect=docker),patch.object(p,'stop') as stop:
                if foreign:
                    with self.assertRaises(RuntimeError):p.close()
                    self.assertFalse(any(x[0]=='rm' for x in operations))
                else:
                    with self.assertRaises(RuntimeError):p.target(['pg_ctl','status'])
                    p.close();self.assertIsNone(p.cid);self.assertFalse(p.running)
                    self.assertEqual(sum(x[0]=='rm'for x in operations),1)
                    self.assertTrue(p.events[-1]['absent']);self.assertFalse(p.events[0]['graceful_pg_stop'])
                stop.assert_not_called()

    def test_graceful_stop_failure_still_disposes_exact_owned_target_and_remains_failure(self):
        import subprocess
        p=m.PhysicalCluster(self.source());p.cid='a'*64;p.running=True
        states=[dict(running=True,status='running',oom_killed=False),dict(running=True,status='running',oom_killed=False),dict(running=False,status='exited',oom_killed=False)]
        result=subprocess.CompletedProcess([],0,stdout=b'',stderr=b'')
        with patch.object(p,'custody',side_effect=states),patch.object(p,'stop',side_effect=RuntimeError('4427 actual graceful failure')),patch.object(p,'docker',return_value=result) as docker:
            with self.assertRaisesRegex(RuntimeError,'actual graceful failure'):p.close()
            self.assertTrue(any(x.args[0]=='rm' for x in docker.call_args_list));self.assertIsNone(p.cid)
            self.assertTrue(p.events[-1]['absent'])

    def test_failure_diagnostics_are_private_and_never_inline_raw_stderr(self):
        import subprocess
        err=subprocess.CalledProcessError(3,['psql'],stderr='ERROR:  42501\nprivate external detail')
        receipt=m.failure_receipt(err,'fixture-stage',[{'absent':True}])
        self.assertFalse(receipt['qualification_passed']);self.assertEqual(receipt['external']['sqlstate'],'42501')
        path=Path(receipt['external']['private_stderr_path'])
        try:
            self.assertEqual(path.stat().st_mode&0o777,0o600)
            self.assertEqual(path.read_text(),err.stderr)
            self.assertNotIn('private external detail',json.dumps(receipt))
        finally:path.unlink()

    def test_reset_requires_stopped_sealed_owned_target_before_command(self):
        p=m.PhysicalCluster(self.source())
        with patch.object(p,'target') as target:
            with self.assertRaises(RuntimeError):p.begin_trial()
            p.sealed=True;p.running=True
            with self.assertRaises(RuntimeError):p.begin_trial()
            target.assert_not_called()

    def test_measured_cost_admission_refuses_unbounded_full_matrix(self):
        p=m.PhysicalCluster(self.source())
        self.assertGreater(p.projected_matrix_check([1]*34),340)
        with self.assertRaisesRegex(RuntimeError,'cost exceeds'):p.projected_matrix_check([10]*34)
        for invalid in ([1]*33,[1]*35,[1]*33+[0],[1]*33+[True],[1]*33+[float('nan')]):
            with self.assertRaisesRegex(RuntimeError,'cost invalid'):p.projected_matrix_check(invalid)
        p.started-=2050
        with self.assertRaisesRegex(RuntimeError,'remaining bound'):p.projected_matrix_check([1]*34)

    def test_cleanup_survives_action_budget_expiry(self):
        p=m.PhysicalCluster(self.source());p.started=time.monotonic()-2200
        with self.assertRaises(RuntimeError):p.budget_check()
        p.cleanup_mode=True;p.budget_check()

    def test_original_unix_hba_denial_allow_denial_and_metadata_are_proven(self):
        import subprocess
        original=b'local all supabase_admin trust\nlocal all all peer\nhost all all 127.0.0.1/32 trust\n'
        class Source:
            restore_authority={'system_identifier':'123'}
            hba_window_active=False;hba_temporary_verified=False
            data=original;loaded=False;mode='755';owner='100:101'
            def source_checked(self,args,input_file=None,allowed_failure=False):
                self.asserted=m.source_command_kind(args)
                if self.asserted is None:raise AssertionError('unlisted source command')
                result=b''
                if args==m.HBA_READ_ARGS:result=self.data
                elif args==m.HBA_STAT_ARGS:result=('regular file:'+self.owner+':'+self.mode+':1').encode()
                elif args==m.HBA_APPEND_ARGS:
                    assert self.hba_window_active;self.data+=input_file.read()
                elif args==m.HBA_RESTORE_ARGS:
                    assert self.hba_window_active;self.data=input_file.read()
                elif args[0]=='chown':self.owner=args[1]
                elif args[0]=='chmod':self.mode=args[1]
                elif args==m.RELOAD_ARGS:self.loaded=m.HBA_LINE in self.data;result=b't\n'
                elif args==m.REPL_PROBE_ARGS:
                    if self.loaded:return subprocess.CompletedProcess(args,0,stdout=b'123|1|0/A|\n',stderr=b'')
                    return subprocess.CompletedProcess(args,2,stdout=b'',stderr=b'FATAL: no pg_hba.conf entry for replication connection from host "[local]", user "supabase_admin"')
                else:result=json.dumps(dict(recovery=False,superuser=True,slots=0,walsenders=0,roles='same',members='same',policies='same',objects='same')).encode()
                return subprocess.CompletedProcess(args,0,stdout=result,stderr=b'')
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);self.archive(root/'source-config.tar',{'etc/postgresql/pg_hba.conf':original})
            source=Source();window=m.TemporaryUnixHba(source,root)
            source.source_backup_window=(125,10)
            with patch.object(m.time,'time',return_value=130),patch.object(m.time,'monotonic',return_value=15),self.assertRaisesRegex(RuntimeError,'synthetic backup failure'):
                with window:
                    self.assertTrue(source.hba_temporary_verified);self.assertEqual(source.data,original+m.HBA_LINE)
                    raise RuntimeError('synthetic backup failure')
            self.assertEqual(source.data,original);self.assertEqual(source.mode,'755');self.assertEqual(source.owner,'100:101')
            self.assertFalse(source.loaded);self.assertFalse(source.hba_window_active)
            self.assertEqual([r['physical_identify_state'] for r in window.events if 'physical_identify_state' in r],['HBA_ABSENT','ALLOWED','HBA_ABSENT'])
            self.assertTrue(window.events[-1]['original_hba_restored'])
            self.assertEqual((root/'source-original-hba').read_bytes(),original)

    def test_existing_replication_deny_and_hba_indirection_cannot_be_overridden(self):
        valid=b'local all supabase_admin trust\n'
        m.validate_missing_unix_hba(valid)
        for extra in (b'local replication supabase_admin reject\n',b'local replication all trust\n',b'include /external/file\n',b'local all @users trust\n',b'local "replication" supabase_admin trust\n',b'local all "all" trust\n'):
            with self.subTest(extra=extra),self.assertRaises(RuntimeError):m.validate_missing_unix_hba(valid+extra)
        self.assertIsNone(m.source_command_kind(['sh','-c','arbitrary']))
        self.assertIsNone(m.source_command_kind(['chmod','777',m.HBA_PATH]))
        self.assertEqual(m.source_command_kind(['chmod','755',m.HBA_PATH]),'hba-metadata')
        self.assertEqual(m.BACKUP_ARGS[m.BACKUP_ARGS.index('-h')+1],'/var/run/postgresql')

    def test_canary_uses_only_root_derived_bigint_api_and_never_outputs_root(self):
        self.assertIn('4427::bigint',m.CANARY_CREATE_SQL)
        self.assertIn('crypto_secretbox_open',m.CANARY_CHECK_SQL)
        self.assertNotIn('derive_key',m.CANARY_CREATE_SQL+m.CANARY_CHECK_SQL)
        self.assertNotIn('pgsodium_root.key',m.CANARY_CREATE_SQL+m.CANARY_CHECK_SQL)


if __name__=='__main__':unittest.main()
