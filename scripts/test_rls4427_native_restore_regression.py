"""Offline-only local physical source/one-pair controls; never creates a resource."""
import copy
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tarfile
import contextlib
import tempfile
import os
import stat
import types
import unittest
from unittest.mock import patch

P=Path(__file__).with_name('rls4427_native_restore_regression.py')
spec=importlib.util.spec_from_file_location('local_reg4427',P)
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)


def fixture_helper():
    h=types.SimpleNamespace(OWNER='parent-helper-owner',BACKUP_ARGS=['pg_basebackup','fixed'],CONFIG_ARGS=['tar','fixed'],BINARY_ARGS=['sha256sum','fixed'])
    def kind(args):
        if args in (h.BACKUP_ARGS,h.CONFIG_ARGS):return 'archive'
        if args==['read']:return 'read'
        if args==['write']:return 'hba-write'
        if args==['metadata']:return 'hba-metadata'
        return None
    h.source_command_kind=kind
    h.validated_payloads=[]
    h.validate_hba_payload=lambda source,args,stream:h.validated_payloads.append(list(args))
    h.capture_external=lambda stderr,tool,code,phase:dict(tool=tool,exit_code=code,phase=phase,private_stderr_path='/private/test-receipt',private_stderr_sha256=hashlib.sha256(stderr).hexdigest())
    h.failure_receipt=lambda error,phase,events:dict(qualification_passed=False,phase=phase,error_type=type(error).__name__,invariant=str(error)if str(error).startswith('4427 ')else'4427 external failure',events=list(events))
    return h


def source_row(source):
    return dict(Id=source.container_id,Image=m.IMAGE,Name='/'+m.NAME,Config=dict(Labels=dict(m.LABELS),User='100:101',Entrypoint=['/bin/sleep'],Cmd=['infinity']),State=dict(Running=True),
                HostConfig=dict(Privileged=False,ReadonlyRootfs=True,Memory=2147483648,NanoCpus=1000000000,PidsLimit=256,NetworkMode='none',Tmpfs=dict(m.TMPFS)),
                NetworkSettings=dict(Networks={'none':{}},Ports={'5432/tcp':None}),Mounts=[])


def explain(init=False,rows=2,loops=1):
    return [{'Plan':{'Node Type':'ModifyTable','Operation':'Update','Actual Rows':rows,'Actual Loops':1,'Plans':([{'Parent Relationship':'InitPlan','Node Type':'Result','Actual Loops':loops}]if init else [])},'Execution Time':.2}]


class LocalPhysicalControls(unittest.TestCase):
    def test_import_constructor_do_not_touch_resources(self):
        with patch.object(m.subprocess,'run')as run,patch.object(m.subprocess,'Popen')as popen:
            r=m.Regression();s=m.LocalSource(fixture_helper());self.assertIsNone(r.source);self.assertIsNone(s.container_id);run.assert_not_called();popen.assert_not_called()

    def test_committed_source_binding_precedes_resource(self):
        def git(argv,**kw):return subprocess.CompletedProcess(argv,0,stdout='a'*40 if argv[1]=='rev-parse'else b'wrong')
        with patch.object(m.subprocess,'run',side_effect=git)as run,self.assertRaisesRegex(RuntimeError,'committed bytes'):m.source_identity()
        self.assertTrue(all(c.args[0][0]=='/usr/bin/git'for c in run.call_args_list))

    def test_exact_native_versions_not_host_pg1711(self):
        versions=[x+' (PostgreSQL) 17.6'for x in ('psql','pg_basebackup','pg_ctl')]
        self.assertEqual(m.validate_versions(versions,170006)['server_version_num'],170006)
        for tools,server in [(versions,170011),(versions[:2],170006),([x.replace('17.6','17.11')for x in versions],170006),(versions[::-1],170006)]:
            with self.assertRaisesRegex(RuntimeError,'exact native PG17.6'):m.validate_versions(tools,server)

    def test_qualified_closed_source_transport_and_input_channel(self):
        h=fixture_helper();s=m.LocalSource(h)
        with patch.object(s,'execute',return_value=types.SimpleNamespace(stdout=b'good'))as execute:
            for args in [['foreign'],h.BACKUP_ARGS,['write'],['metadata']]:
                with self.assertRaises(RuntimeError):s.source_checked(args)
            s.restore_authority_qualified=True
            with self.assertRaisesRegex(RuntimeError,'positively loaded'):s.source_checked(h.BACKUP_ARGS,output_file=io.BytesIO())
            s.hba_temporary_verified=True;s.source_checked(h.BACKUP_ARGS,output_file=io.BytesIO())
            for arg in [dict(input_file=io.BytesIO()),dict(output_file=io.BytesIO())]:
                with self.assertRaises(RuntimeError):s.source_checked(['read'],**arg)
            s.hba_window_active=True;s.source_checked(['write'],input_file=io.BytesIO(b'only fixed helper input'))
            s.source_checked(['metadata']);self.assertEqual(s.container_exec(['read']),b'good')
            with self.assertRaises(RuntimeError):s.source_checked(['write'])
            self.assertEqual(execute.call_args.args[0],['read'])
            self.assertEqual(h.validated_payloads,[['write'],['metadata']])

    def test_expected_probe_denial_retains_process_exit_stderr(self):
        s=m.LocalSource(fixture_helper());failure=subprocess.CompletedProcess([],2,stdout=b'',stderr=b'expected fixture denial')
        with patch.object(s,'execute',return_value=failure)as execute:
            self.assertIs(s.source_checked(['read'],allowed_failure=True),failure)
            self.assertTrue(execute.call_args.kwargs['allowed_failure'])

    def test_custody_rejects_replacement_network_mount_memory_privilege(self):
        s=m.LocalSource(fixture_helper());s.container_id='a'*64;s.image_id=m.IMAGE;s.expected_labels=dict(m.LABELS);row=source_row(s)
        def result(value):return types.SimpleNamespace(stdout=json.dumps([value]).encode())
        with patch.object(s,'docker',return_value=result(row)):self.assertEqual(s.custody()[0],s.container_id)
        for section,key,value in [(None,'Id','b'*64),('Config','User','root'),('Config','Entrypoint',['postgres']),('State','Running',False),('HostConfig','Memory',1073741824),('HostConfig','PidsLimit',128),('HostConfig','Privileged',True),('HostConfig','Binds',['/host:/data']),('HostConfig','ReadonlyRootfs',False),('HostConfig','Tmpfs',{**m.TMPFS,m.DATA:'rw,size=1'}),('NetworkSettings','Networks',{'bridge':{}}),('NetworkSettings','Ports',{'5432/tcp':[{'HostPort':'5432'}]})]:
            bad=copy.deepcopy(row);(bad[section]if section else bad)[key]=value
            with self.subTest(key=key),patch.object(s,'docker',return_value=result(bad)),self.assertRaises(RuntimeError):s.custody()

    def test_source_same_instance_existing_native_admin_not_invented(self):
        s=m.LocalSource(fixture_helper());s.immutable_config_sha=m.IMAGE_CONFIG.removeprefix('sha256:')
        context=dict(system_identifier='123',server_version_num=170006,postmaster_start='fixed',database='postgres')
        authority=dict(**context,current_user='supabase_admin',session_user='supabase_admin',rolsuper=True,rolcanlogin=True,is_superuser='on')
        with patch.object(s,'custody'),patch.object(s,'sql',side_effect=[json.dumps(context),json.dumps(authority)]):
            s.qualify_physical_source();self.assertEqual(s.restore_authority,authority);self.assertTrue(s.restore_authority_qualified)
        for key,value in [('current_user','postgres'),('system_identifier','456'),('rolsuper',False),('is_superuser','off')]:
            bad={**authority,key:value}
            with self.subTest(key=key),patch.object(s,'custody'),patch.object(s,'sql',side_effect=[json.dumps(context),json.dumps(bad)]),self.assertRaises(RuntimeError):s.qualify_physical_source()

    def test_pair_plan_requires_two_rows_and_real_candidate_initplan_once(self):
        self.assertEqual(m.validate_pair_sample('original',explain())['affected_rows'],2)
        self.assertEqual(m.validate_pair_sample('candidate',explain(True))['initplan_loops'],[1])
        for raw in [explain(False),explain(True,1),explain(True,2,2),{},[],[{'Plan':{}}]]:
            with self.assertRaises(RuntimeError):m.validate_pair_sample('candidate',raw)

    def test_role_operations_preserve_denials_and_do_not_print_errors(self):
        def execute(query):
            if "set local role rls4427_reader;update"in query or "set local role rls4427_reader;select nextval"in query:
                raise subprocess.CalledProcessError(3,['psql'],stderr='ERROR: 42501 synthetic denial')
            if 'count(*) from rls4427_fixture.objects' in query:return '2\n'
            if 'returning label' in query:return 'allowed\n'
            if 'returning id' in query:return ''
            if 'last_value' in query:return '1\n'
            return '0\n'
        rows=m.permission_outcomes(execute);self.assertEqual(len(rows),7);self.assertEqual(sum(r.get('allowed')is False for r in rows),2)
        with self.assertRaisesRegex(RuntimeError,'SQLSTATE'):m.permission_outcomes(lambda q:(_ for _ in()).throw(subprocess.CalledProcessError(3,['psql'],stderr='ERROR: XX000 unrelated')))
        with self.assertRaisesRegex(RuntimeError,'outcome differs'):m.permission_outcomes(lambda q:'wrong')

    def test_fixture_preserves_native_schemas_and_authority_and_uses_real_role_rls(self):
        fixture=(m.ROOT/'supabase/tests/fixtures/rls4427_native_restore_fixture.sql').read_text()
        for forbidden in ['create role supabase_admin','alter schema public','create schema auth','create schema storage','cron.schedule','launch_active_jobs','shared_preload_libraries']:
            self.assertNotIn(forbidden,fixture.lower())
        for required in ['current_user <> \'supabase_admin\'','CREATE SCHEMA rls4427_fixture','ALTER DEFAULT PRIVILEGES','ENABLE ROW LEVEL SECURITY','CREATE TRIGGER','request_allowed()','GRANT UPDATE(label)']:
            self.assertIn(required,fixture)
        for key in ['schemas','columns','policies','defaults','constraints','indexes','functions','triggers','sequences','sequence_ownership','sequence_state','rows','public_rows','authority_rows']:
            self.assertIn("'"+key+"'",m.METADATA)
        self.assertIn('native374_acceptance=\'NOT_EVALUATED\'',P.read_text());self.assertIn('PRESERVED_NOT_RECLASSIFIED',P.read_text())

    def test_source_bootstrap_once_and_no_target_init_rekey_or_guard_waiver(self):
        text=P.read_text();self.assertEqual(text.count('self.execute(BOOTSTRAP_START,detach=True)'),1)
        self.assertIn("self.execute(['test','!','-e',DATA+'/PG_VERSION'])",text)
        self.assertIn("self.execute(['test','!','-e','/etc/postgresql-custom/pgsodium_root.key'])",text)
        self.assertNotIn("['initdb'",text);self.assertNotIn('pg_terminate_backend',text);self.assertNotIn('cron.launch_active_jobs = off',text)
        self.assertIn('source_command_kind(args)',text);self.assertIn('600-(time.monotonic()-started)',text)



def native_layer(entries):
    output=io.BytesIO()
    with tarfile.open(fileobj=output,mode='w:gz')as archive:
        for name,data,kind,uid in entries:
            member=tarfile.TarInfo(name);member.uid=uid;member.gid=101;member.mode=0o755 if kind=='dir'else 0o644
            if kind=='dir':member.type=tarfile.DIRTYPE
            elif kind=='symlink':member.type=tarfile.SYMTYPE;member.linkname='/outside'
            else:member.size=len(data)
            archive.addfile(member,io.BytesIO(data)if kind=='file'else None)
    return output.getvalue()


def cached_export(layers,reverse=True,config_mutation=None):
    config=json.dumps({'rootfs':{'diff_ids':['sha256:'+str(i)*64 for i in range(1,len(layers)+1)]}}).encode()
    config_id=hashlib.sha256(config).hexdigest()
    members=[('blobs/sha256/'+hashlib.sha256(layer).hexdigest(),layer)for layer in layers]
    manifest=json.dumps({'schemaVersion':2,'config':{'digest':'sha256:'+config_id},'layers':[{'digest':'sha256:'+name.rsplit('/',1)[-1]}for name,data in members]}).encode()
    members+=[('blobs/sha256/'+config_id,config),('blobs/sha256/'+hashlib.sha256(manifest).hexdigest(),manifest)]
    if reverse:members.reverse()
    output=io.BytesIO()
    with tarfile.open(fileobj=output,mode='w:')as archive:
        for name,data in members:
            member=tarfile.TarInfo(name);member.size=len(data);archive.addfile(member,io.BytesIO(data))
    output.seek(0);return output,'sha256:'+config_id


class ImageArchiveControls(unittest.TestCase):
    def base(self):
        return [('etc/postgresql',b'','dir',100),('etc/postgresql-custom',b'','dir',100),
                ('etc/postgresql/postgresql.conf',b'original','file',100),('etc/postgresql/pg_hba.conf',b'local all supabase_admin trust','file',100),
                ('etc/postgresql/pg_ident.conf',b'fixed','file',100),('etc/postgresql/logging.conf',b'old','file',100)]

    def test_actual_tar_layer_order_and_whiteouts_not_archive_occurrence(self):
        export,config=cached_export([native_layer(self.base()),native_layer([('etc/postgresql/.wh.logging.conf',b'','file',100),('etc/postgresql/postgresql.conf',b'final','file',100)])])
        with patch.object(m,'IMAGE_CONFIG',config):tree,raw,manifest=m.image_config_records(export)
        self.assertEqual(tree['etc/postgresql/postgresql.conf'][-1],b'final');self.assertNotIn('etc/postgresql/logging.conf',tree)
        archive=io.BytesIO();m.write_config_tar(tree,archive);archive.seek(0)
        with tarfile.open(fileobj=archive,mode='r:')as contents:
            self.assertEqual(contents.extractfile('etc/postgresql/postgresql.conf').read(),b'final')
            self.assertTrue(all(x.uid==100 and x.gid==101 for x in contents))
        self.assertEqual('sha256:'+hashlib.sha256(raw).hexdigest(),config)

    def test_opaque_whiteout_removes_children_in_prior_layer(self):
        records=self.base()+[('etc/postgresql-custom/conf.d',b'','dir',100),('etc/postgresql-custom/conf.d/old.conf',b'old','file',100)]
        export,config=cached_export([native_layer(records),native_layer([('etc/postgresql-custom/conf.d/.wh..wh..opq',b'','file',100),('etc/postgresql-custom/conf.d/new.conf',b'new','file',100)])])
        with patch.object(m,'IMAGE_CONFIG',config):tree,_,_=m.image_config_records(export)
        self.assertNotIn('etc/postgresql-custom/conf.d/old.conf',tree);self.assertIn('etc/postgresql-custom/conf.d/new.conf',tree)

    def test_escaping_links_foreign_owners_and_baked_root_key_fail_closed(self):
        for extra in [('etc/postgresql/../../escape',b'bad','file',100),('etc/postgresql/link',b'','symlink',100),
                      ('etc/postgresql/foreign.conf',b'bad','file',0),('etc/postgresql-custom/pgsodium_root.key',b'x'*64,'file',100)]:
            export,config=cached_export([native_layer(self.base()+[extra])])
            with self.subTest(extra=extra[0]),patch.object(m,'IMAGE_CONFIG',config),self.assertRaises(RuntimeError):m.image_config_records(export)

    def test_missing_config_identity_or_required_file_refuses(self):
        export,config=cached_export([native_layer(self.base())])
        with patch.object(m,'IMAGE_CONFIG','sha256:'+'f'*64),self.assertRaisesRegex(RuntimeError,'binding missing'):m.image_config_records(export)
        export,config=cached_export([native_layer(self.base()[:-3])])
        with patch.object(m,'IMAGE_CONFIG',config),self.assertRaisesRegex(RuntimeError,'closure missing'):m.image_config_records(export)


class FakePhysical:
    def __init__(self,drift=False,canary_fail=False,permission_diff=False):
        self.running=True;self.starts=0;self.stops=0;self.variant='original';self.drift=drift;self.canary_fail=canary_fail;self.permission_diff=permission_diff
        self.metadata={key:[] for key in ['schemas','rows']};self.metadata['policies']=[['rls4427_fixture','objects','fixture_write','PERMISSIVE',['rls4427_writer'],'UPDATE','old','old'],['rls4427_fixture','objects','fixture_read','PERMISSIVE',['rls4427_reader'],'SELECT','fixed',None]]
        self.helper=types.SimpleNamespace(CANARY_CHECK_SQL='canary')
    def seal(self):self.running=False;return {'sha256':'a'*64}
    def begin_trial(self):self.running=True;self.starts+=1;self.variant='original';return {'baseline_sha256':'a'*64}
    def end_trial(self):self.running=False;self.stops+=1
    def sql(self,query,role):
        if query==m.METADATA:
            value=copy.deepcopy(self.metadata)
            if self.variant=='candidate':value['policies'][0][-2:]=['candidate','candidate']
            return json.dumps(value)
        if query==m.NATIVE_SQL:return json.dumps({'native':'unchanged'})
        if query=='canary':return 'f'if self.canary_fail and self.starts else't'
        if query==m.FINGERPRINT_SQL:return json.dumps({'heap':'b'if self.drift and self.starts==2 else'a'})
        if query.startswith('alter policy'):
            self.variant='candidate'if 'SELECT'in query else'original';return''
        if query==m.PAIR_SQL:return json.dumps(explain(self.variant=='candidate'))
        raise AssertionError(query)


class CalibrationOrchestrationControls(unittest.TestCase):
    def test_same_physical_baseline_canary_native_and_role_evidence_each_start(self):
        cluster=FakePhysical()
        with patch.object(m,'permission_outcomes',return_value=[{'fixed':'roles'}]):result=m.calibrate_pair(cluster,cluster.helper)
        self.assertEqual(cluster.starts,2);self.assertEqual(cluster.stops,2);self.assertFalse(cluster.running)
        self.assertTrue(result['root_key_decrypt_two_restarts']);self.assertTrue(result['physical_start_equal'])
        self.assertEqual([r['variant']for r in result['samples']],['original','candidate'])

    def test_starting_byte_drift_or_key_failure_cannot_pass_and_closes_trial(self):
        for cluster in [FakePhysical(drift=True),FakePhysical(canary_fail=True)]:
            with self.subTest(drift=cluster.drift),patch.object(m,'permission_outcomes',return_value=[]),self.assertRaises(RuntimeError):m.calibrate_pair(cluster,cluster.helper)
            self.assertFalse(cluster.running);self.assertEqual(cluster.stops,cluster.starts)

    def test_permission_mismatch_refuses_second_sample(self):
        cluster=FakePhysical()
        with patch.object(m,'permission_outcomes',side_effect=[[{'allowed':True}],[{'allowed':False}]]),self.assertRaisesRegex(RuntimeError,'role outcomes differ'):m.calibrate_pair(cluster,cluster.helper)
        self.assertEqual(cluster.stops,2);self.assertFalse(cluster.running)



class DiagnosticReadinessControls(unittest.TestCase):
    def test_ready_requires_completed_init_marker_then_final_postmaster_and_sql(self):
        command=m.BOOTSTRAP_READY[2]
        marker='PostgreSQL init process complete; ready for start up.'
        self.assertIn(marker,command);self.assertIn('pg_ctl -D /etc/postgresql status',command)
        self.assertIn('pg_isready -h 127.0.0.1',command);self.assertIn("-c 'select 1;'",command)
        self.assertLess(command.index(marker),command.index('pg_isready'))
        self.assertEqual(m.BOOTSTRAP_START,['sh','-c','exec docker-entrypoint.sh postgres -D /etc/postgresql > /var/log/postgresql/4427-bootstrap.log 2>&1'])
        self.assertNotIn('initdb',m.BOOTSTRAP_START[2])

    def test_external_failure_receipt_keeps_tool_exit_private_hash_not_raw(self):
        helper=fixture_helper();source=m.LocalSource(helper);source.source_docker_config='/private';source.phase='source-bootstrap';source.container_id='a'*64
        raw=b'FATAL: XX000 UNIT_SECRET_CANARY'
        result=subprocess.CompletedProcess([],7,stdout=b'',stderr=raw)
        with patch.object(m.subprocess,'run',return_value=result),self.assertRaises(subprocess.CalledProcessError)as caught:
            source.docker('exec','--user','100:101',source.container_id,'sh','fixed')
        self.assertEqual(caught.exception.returncode,7);self.assertEqual(source.last_external_failure['tool'],'sh')
        self.assertEqual(source.last_external_failure['private_stderr_sha256'],hashlib.sha256(raw).hexdigest())
        self.assertNotIn('UNIT_SECRET_CANARY',json.dumps(source.events));self.assertNotIn('UNIT_SECRET_CANARY',json.dumps(source.last_external_failure))

    def test_primary_failure_survives_independent_cleanup_failure_and_cleanup_events(self):
        helper=fixture_helper()
        class Source:
            def __init__(self,h):self.events=[];self.phase='source-bootstrap';self.last_external_failure={'private_stderr_path':'/outside/private','private_stderr_sha256':'a'*64}
            def open(self):self.phase='source-bootstrap';raise RuntimeError('4427 original bootstrap invariant')
            def close(self):self.events.append({'cleanup_attempted':True});raise RuntimeError('4427 separate cleanup invariant')
        with patch.object(m,'load_helper',return_value=helper),patch.object(m,'source_identity',return_value={}),patch.object(m,'LocalSource',Source),self.assertRaises(m.LocalCalibrationFailure)as caught:
            m.Regression().run()
        report=caught.exception.receipt
        self.assertFalse(report['qualification_passed']);self.assertEqual(report['primary_failure']['phase'],'source-bootstrap')
        self.assertIn('original bootstrap',report['primary_failure']['invariant']);self.assertEqual(report['cleanup_failures'][0]['phase'],'cleanup-source')
        self.assertIn('separate cleanup',report['cleanup_failures'][0]['invariant']);self.assertEqual(report['events']['source'],[{'cleanup_attempted':True}])

    def test_own_absence_event_prints_even_when_prior_phase_failed(self):
        source=m.LocalSource(fixture_helper());source.container_id='a'*64;source.phase='cleanup-source'
        source.temporary=types.SimpleNamespace(cleanup=lambda:None)
        good=types.SimpleNamespace(returncode=0,stderr=b'',stdout=b'')
        capture=io.StringIO()
        with patch.object(source,'custody'),patch.object(source,'execute',return_value=good),patch.object(source,'docker',return_value=good),contextlib.redirect_stderr(capture):source.close()
        reports=[json.loads(line)for line in capture.getvalue().splitlines()]
        self.assertTrue(any(r.get('kind')=='owned-source-stopped'for r in reports))
        self.assertTrue(any(r.get('kind')=='owned-source-removed'and r.get('absent')is True for r in reports))

    def test_permissions_run_under_each_actual_variant_after_timed_update(self):
        cluster=FakePhysical();order=[];original=cluster.sql
        def sql(query,role):
            if query==m.FINGERPRINT_SQL:order.append(('before',cluster.starts))
            if query.startswith('alter policy'):order.append(('policy','candidate'if'SELECT'in query else'original'))
            if query==m.PAIR_SQL:order.append(('timed',cluster.variant))
            return original(query,role)
        cluster.sql=sql
        def permissions(execute):order.append(('permissions',cluster.variant));return[]
        with patch.object(m,'permission_outcomes',side_effect=permissions):m.calibrate_pair(cluster,cluster.helper)
        self.assertEqual(order,[('before',1),('policy','original'),('timed','original'),('permissions','original'),('before',2),('policy','candidate'),('timed','candidate'),('permissions','candidate')])



class ActualReadyShellControls(unittest.TestCase):
    def test_transient_ready_without_completion_marker_cannot_satisfy_final_gate(self):
        with tempfile.TemporaryDirectory(prefix='4427-ready-unit-')as temp:
            root=Path(temp);log=root/'bootstrap.log';bindir=root/'bin';bindir.mkdir()
            for tool,body in {'pg_ctl':'exit 0','pg_isready':'exit 0','psql':'echo 1','sleep':'exit 0'}.items():
                p=bindir/tool;p.write_text('#!/bin/sh\n'+body+'\n');p.chmod(0o700)
            command=m.BOOTSTRAP_READY[2].replace(m.BOOTSTRAP_LOG,str(log))
            env={'PATH':str(bindir)+':/usr/bin:/bin'}
            log.write_text('temporary init server accepting connections\n')
            transient=subprocess.run(['sh','-c',command],env=env,capture_output=True,timeout=5)
            self.assertEqual(transient.returncode,1)
            log.write_text('PostgreSQL init process complete; ready for start up.\n')
            ready=subprocess.run(['sh','-c',command],env=env,capture_output=True,timeout=5)
            self.assertEqual(ready.returncode,0)
            (bindir/'psql').write_text('#!/bin/sh\nexit 1\n');(bindir/'psql').chmod(0o700)
            sql_not_ready=subprocess.run(['sh','-c',command],env=env,capture_output=True,timeout=5)
            self.assertEqual(sql_not_ready.returncode,1)

    def test_private_external_capture_outlives_local_temporary_cleanup(self):
        helper=fixture_helper()
        with tempfile.TemporaryDirectory(prefix='4427-private-evidence-unit-')as evidence:
            paths=[]
            def capture(raw,tool,code,phase):
                fd,path=tempfile.mkstemp(dir=evidence);os.write(fd,raw);os.close(fd);paths.append(path)
                return dict(tool=tool,exit_code=code,phase=phase,private_stderr_path=path,private_stderr_sha256=hashlib.sha256(raw).hexdigest())
            helper.capture_external=capture;source=m.LocalSource(helper);source.source_docker_config='/private';source.phase='source-bootstrap'
            raw=b'UNIT_PRIVATE_STDERR_CANARY'
            with tempfile.TemporaryDirectory(prefix='4427-owned-temp-unit-')as temporary:
                source.temporary=types.SimpleNamespace(cleanup=lambda:None)
                with patch.object(m.subprocess,'run',return_value=subprocess.CompletedProcess([],9,stderr=raw,stdout=b'')),self.assertRaises(subprocess.CalledProcessError):source.docker('fixed')
            path=Path(paths[0]);self.assertTrue(path.exists());self.assertEqual(path.read_bytes(),raw)
            self.assertEqual(stat.S_IMODE(path.stat().st_mode),0o600)
            self.assertNotIn('UNIT_PRIVATE_STDERR_CANARY',json.dumps(source.last_external_failure))


if __name__=='__main__':unittest.main()
