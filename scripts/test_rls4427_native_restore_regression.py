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
            self.assertEqual(m.restore_args(db),['pg_restore','-U','postgres','-d',db,'--exit-on-error'])
        for db in ('postgres','foreign',m.DATABASES[0]):
            with self.assertRaises(RuntimeError):m.restore_args(db)
        self.assertNotIn('--no-owner',P.read_text());self.assertNotIn('--no-acl',P.read_text())

    def test_nonempty_target_qualifier_refuses_before_restore(self):
        c=m.Regression();db=m.DATABASES[3];c.owned=[db]
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
