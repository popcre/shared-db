#!/usr/bin/env python3
"""4427-specific REAL PG17 regression. Import is offline. Execution needs separate review/gates.

No connection/image/command options. One fixed owned cached-image container, no network,
ports, host binds, pulls or external rows. This is NOT the production qualification driver.
"""
import hashlib
import importlib.util
import json
import os
import re
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('actual4427', ROOT/'scripts/qualify_rls4427_actual_tables.py')
CORE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CORE)
IMAGE = 'sha256:2d2b8998d31037bf721cfdf764d76ba74171b4fab3431b7f72c27c56ddbdf9e3'
NAME = 'rls4427-restore-regression-01a1834a'
OWNER = '01a1834a-813e-7b12-b17a-3e8c3aaedfb8'
LABELS = {'shared-db.regression':'4427-fresh-restore','shared-db.owner':OWNER}
DATABASES = ('rls4427_source','rls4427_clean_negative','rls4427_restore','rls4427_nonempty','rls4427_truncated','rls4427_permission_negative')
# All OID-independent fixture object metadata, including owners, ACLs and defaults.
METADATA = """select json_build_object(
'schemas',(select json_agg(json_build_array(nspname,pg_get_userbyid(nspowner),nspacl::text) order by nspname) from pg_namespace where nspname in ('public','storage','auth')),
'relations',(select json_agg(json_build_array(n.nspname,c.relname,c.relkind,pg_get_userbyid(c.relowner),c.relacl::text,c.relrowsecurity,c.relforcerowsecurity) order by n.nspname,c.relname) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','storage','auth')),
'columns',(select json_agg(json_build_array(n.nspname,c.relname,a.attname,format_type(a.atttypid,a.atttypmod),a.attnotnull,a.attidentity,a.attgenerated,a.attacl::text,pg_get_expr(d.adbin,d.adrelid)) order by n.nspname,c.relname,a.attnum) from pg_attribute a join pg_class c on c.oid=a.attrelid join pg_namespace n on n.oid=c.relnamespace left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum where n.nspname in ('public','storage','auth') and a.attnum>0 and not a.attisdropped),
'policies',(select json_agg(json_build_array(schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check) order by schemaname,tablename,policyname) from pg_policies where schemaname in ('public','storage','auth')),
'defaults',(select json_agg(json_build_array(pg_get_userbyid(a.defaclrole),n.nspname,a.defaclobjtype,a.defaclacl::text) order by n.nspname,a.defaclobjtype) from pg_default_acl a join pg_namespace n on n.oid=a.defaclnamespace),
'constraints',(select json_agg(json_build_array(n.nspname,c.relname,k.conname,pg_get_constraintdef(k.oid)) order by n.nspname,c.relname,k.conname) from pg_constraint k join pg_class c on c.oid=k.conrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','storage','auth')),
'indexes',(select json_agg(json_build_array(schemaname,indexname,indexdef) order by schemaname,indexname) from pg_indexes where schemaname in ('public','storage','auth')),
'functions',(select json_agg(json_build_array(n.nspname,p.proname,pg_get_userbyid(p.proowner),p.proacl::text,pg_get_functiondef(p.oid)) order by n.nspname,p.proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','storage','auth')),
'triggers',(select json_agg(pg_get_triggerdef(t.oid) order by t.tgname) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','storage','auth') and not t.tgisinternal),
'sequences',(select json_agg(json_build_array(s.schemaname,s.sequencename,s.sequenceowner,s.data_type,s.start_value,s.min_value,s.max_value,s.increment_by,s.cycle,s.cache_size,s.last_value) order by s.schemaname,s.sequencename) from pg_sequences s where s.schemaname in ('public','storage','auth')),
'sequence_ownership',(select json_agg(json_build_array(n.nspname,q.relname,t.relname,a.attname,d.deptype) order by n.nspname,q.relname) from pg_class q join pg_namespace n on n.oid=q.relnamespace join pg_depend d on d.classid='pg_class'::regclass and d.objid=q.oid and d.refclassid='pg_class'::regclass and d.deptype in ('a','i') join pg_class t on t.oid=d.refobjid join pg_attribute a on a.attrelid=t.oid and a.attnum=d.refobjsubid where q.relkind='S' and n.nspname in ('public','storage','auth')),
'sequence_state',(select json_build_array(last_value,is_called) from public.restore_fixture_id_seq),
'rows',(select json_agg(o order by id) from storage.objects o),
'public_rows',(select json_agg(o order by id) from public.restore_fixture o),
'auth_rows',(select json_agg(o order by id) from auth.restore_authority_fixture o))::text;"""


def validate_exact_versions(versions, server_version):
    tools = ('psql','pg_dump','pg_restore')
    if server_version != 170011 or len(versions) != len(tools) or any(
        re.fullmatch(re.escape(tool)+r' \(PostgreSQL\) 17\.11(?: \([^\r\n]+\))?', version) is None
        for tool,version in zip(tools,versions)):
        raise RuntimeError('4427 local regression requires exact server170011 and matching PG17.11 tools')
    return dict(server_version_num=server_version,versions=dict(zip(tools,versions)))


def source_identity():
    env={'PATH':'/usr/bin:/bin','LANG':'C.UTF-8'}
    head=subprocess.run(['/usr/bin/git','rev-parse','HEAD'],cwd=ROOT,env=env,check=True,capture_output=True,text=True,timeout=10).stdout.strip()
    if not re.fullmatch(r'[0-9a-f]{40}',head):raise RuntimeError('4427 regression source commit invalid')
    hashes={}
    for relative in ('scripts/rls4427_native_restore_regression.py','scripts/qualify_rls4427_actual_tables.py','supabase/tests/fixtures/rls4427_native_restore_fixture.sql'):
        committed=subprocess.run(['/usr/bin/git','show','HEAD:'+relative],cwd=ROOT,env=env,check=True,capture_output=True,timeout=10).stdout
        actual=(ROOT/relative).read_bytes()
        if actual!=committed:raise RuntimeError('4427 regression executed source differs from committed bytes')
        hashes[relative]=hashlib.sha256(actual).hexdigest()
    return dict(source_sha=head,executed_source_sha256=hashes)


def restore_args(database, role='supabase_admin'):
    if database not in DATABASES[1:] or role not in ('supabase_admin','rls4427_restore_operator') or (role=='rls4427_restore_operator' and database!=DATABASES[5]):
        raise RuntimeError('4427 regression refuses foreign restore database')
    return ['pg_restore','-U',role,'-d',database,'--exit-on-error']


class Regression:
    def __init__(self):
        self.cid = None
        self.owned = []
        self.events = []
        self.started = time.monotonic()
        self.cleanup_mode = False
        self.version_bound = False
        self.admin_qualified = False
        self.env = {'PATH':'/usr/bin:/bin','LANG':'C.UTF-8'}

    def docker(self, *args, input_data=None, output=None, allowed_failure=False):
        if time.monotonic()-self.started > 600 and not self.cleanup_mode:
            raise RuntimeError('4427 regression ten-minute action budget exhausted')
        proc = subprocess.run(['/usr/bin/docker','--host','unix:///var/run/docker.sock','--config',self.config,*args],
            env=self.env,stdout=output or subprocess.PIPE,stderr=subprocess.PIPE,timeout=20 if self.cleanup_mode else 120,
            **({'input':input_data} if input_data is not None else {'stdin':subprocess.DEVNULL}))
        self.events.append(dict(operation=args[0],exit_code=proc.returncode))
        if proc.returncode and not allowed_failure:
            print(json.dumps(dict(native_restore_failure=args[0],exit_code=proc.returncode,stderr=proc.stderr[:4096].decode(errors='replace'))),file=sys.stderr)
            raise RuntimeError('4427 regression command failed: '+proc.stderr[:4096].decode(errors='replace'))
        return proc

    def custody(self):
        rows=json.loads(self.docker('inspect','--type','container',NAME).stdout)
        if len(rows)!=1:
            raise RuntimeError('4427 regression container cardinality differs')
        row=rows[0];host=row['HostConfig'];labels=row['Config'].get('Labels') or {}
        if (row['Id']!=self.cid or row['Image']!=IMAGE or row['Name']!='/'+NAME or
            labels!=self.expected_labels or row.get('State',{}).get('Running') is not True or host.get('Privileged') is not False or
            host.get('Memory')!=536870912 or host.get('NanoCpus')!=1000000000 or host.get('PidsLimit')!=128 or host.get('PidMode','') or
            host.get('NetworkMode')!='none' or host.get('Binds') or host.get('PortBindings') or
            any(row['NetworkSettings'].get('Ports',{}).values()) or set(row['NetworkSettings'].get('Networks',{}))!={'none'} or host.get('ReadonlyRootfs') is not True or host.get('Devices') or host.get('CapAdd') or set(host.get('Tmpfs',{}))!={'/var/lib/postgresql/data','/var/run/postgresql','/tmp'} or any(m.get('Type')!='tmpfs' or m.get('Destination') not in host['Tmpfs'] for m in row.get('Mounts',[]))):
            raise RuntimeError('4427 regression owned resource custody differs')

    def execute(self, args, **kw):
        self.custody()
        return self.docker('exec',*(['-i'] if kw.get('input_data') is not None else []),self.cid,*args,**kw)

    def sql(self, db, query, allowed_failure=False):
        if db not in ('postgres',*DATABASES):
            raise RuntimeError('4427 regression refuses foreign SQL database')
        return self.execute(['psql','-XqAt','-U','postgres','-d',db,'-v','ON_ERROR_STOP=1','-v','VERBOSITY=sqlstate'],
                            input_data=query.encode(),allowed_failure=allowed_failure)

    def create(self, db, owner='postgres'):
        if db not in DATABASES or db in self.owned or len(self.owned)>=2 or owner not in ('postgres','rls4427_restore_operator') or (owner=='rls4427_restore_operator' and db!=DATABASES[5]):
            raise RuntimeError('4427 regression refuses nonowned creation')
        self.sql('postgres',f'create database {db} template template0 owner {owner};')
        self.owned.append(db)

    def drop(self, db):
        if db not in self.owned:
            raise RuntimeError('4427 regression refuses nonowned drop')
        self.sql('postgres',f'drop database {db};')
        if self.sql('postgres',f"select count(*) from pg_database where datname='{db}';").stdout.strip()!=b'0':
            raise RuntimeError('4427 regression owned drop absence differs')
        self.owned.remove(db)
        receipt=dict(owned_drop=db,absent=True)
        self.events.append(receipt);print(json.dumps(receipt),file=sys.stderr)

    def qualify(self, db):
        if db not in self.owned:
            raise RuntimeError('4427 regression fresh qualification requires owned target')
        return CORE.validate_fresh_seed(json.loads(self.sql(db,CORE.FRESH_SEED_QUERY).stdout),db)

    def admin_restore(self, db, archive, allowed_failure=False):
        if not self.admin_qualified or db not in self.owned or db==DATABASES[5]:
            raise RuntimeError('4427 regression admin restore is not qualified')
        return self.execute(restore_args(db),input_data=archive,allowed_failure=allowed_failure)

    def restore(self, db, archive):
        if not self.admin_qualified:raise RuntimeError('4427 regression admin restore is not qualified')
        self.qualify(db)
        return self.admin_restore(db,archive)

    def qualify_admin(self):
        context=json.loads(self.sql('postgres',CORE.POSTGRES_CONTEXT_QUERY).stdout)
        command=['psql','-XqAtw','-U','supabase_admin','-d','postgres','-v','ON_ERROR_STOP=1','-c',CORE.RESTORE_AUTHORITY_QUERY]
        authority=CORE.validate_restore_authority(json.loads(self.execute(command).stdout),context)
        self.admin_qualified=True
        print(json.dumps(dict(phase='local-existing-fixture-admin-qualified',**authority),sort_keys=True),file=sys.stderr)
        return authority

    def permission_negative(self, db, archive):
        if db!=DATABASES[5] or db not in self.owned or not self.version_bound or not self.admin_qualified:
            raise RuntimeError('4427 permission negative requires exact owned qualified target')
        facts=json.loads(self.sql(db,CORE.FRESH_SEED_QUERY).stdout)
        expected=dict(database=db,owner='rls4427_restore_operator',extra_schemas=0,relations=0,routines=0,types=0,policies=0,default_acls=0,
            extensions=['plpgsql'],public_owner='pg_database_owner',public_acl=['PUBLIC:USAGE:false','pg_database_owner:CREATE:false','pg_database_owner:USAGE:false'])
        if facts!=expected:raise RuntimeError('4427 permission negative fresh limited-owned target differs')
        operator=json.loads(self.sql('postgres',"select json_build_object('rolsuper',rolsuper,'rolcanlogin',rolcanlogin,'rolbypassrls',rolbypassrls,'rolcreatedb',rolcreatedb,'admin_member',pg_has_role('rls4427_restore_operator','supabase_admin','MEMBER'))::text from pg_roles where rolname='rls4427_restore_operator';").stdout)
        if operator!=dict(rolsuper=False,rolcanlogin=True,rolbypassrls=False,rolcreatedb=True,admin_member=False):
            raise RuntimeError('4427 permission negative operator capability differs')
        command=restore_args(db,'rls4427_restore_operator')
        failure=self.execute(command,input_data=archive,allowed_failure=True)
        receipt=dict(phase='limited-owner-restore-negative',command=command,exit_code=failure.returncode,
            stderr=failure.stderr[:4096].decode(errors='replace'),stderr_truncated=len(failure.stderr)>4096)
        self.events.append(receipt);print(json.dumps(receipt,sort_keys=True),file=sys.stderr)
        if not failure.returncode or b'must be able to SET ROLE "supabase_admin"' not in failure.stderr or b'ALTER SCHEMA auth OWNER TO supabase_admin;' not in failure.stderr:
            raise RuntimeError('4427 permission negative did not reproduce exact owner authorization failure')
        return receipt

    def clean_negative(self, db, archive):
        if db != DATABASES[1] or db not in self.owned or not self.version_bound:
            raise RuntimeError('4427 regression clean negative requires exact owned target')
        command = ['pg_restore','-U','postgres','-d',db,'--clean','--if-exists','--exit-on-error']
        failure = self.execute(command,input_data=archive,allowed_failure=True)
        diagnostic = dict(phase='old-clean-negative',command=command,exit_code=failure.returncode,
                          stderr=failure.stderr[:4096].decode(errors='replace'),stderr_truncated=len(failure.stderr)>4096)
        self.events.append(diagnostic)
        print(json.dumps(diagnostic,sort_keys=True),file=sys.stderr)
        if failure.returncode != 0 or failure.stderr != b'':
            raise RuntimeError('4427 PG17.11 old-clean control returned unexpected status or stderr')
        return failure

    def permissions(self, db):
        outcomes=[]
        for role,sql,expected,value in [
            ('rls4427_reader','select count(*) from storage.objects;',0,b'2'),
            ('rls4427_reader',"update storage.objects set label='denied' where id=1;",3,None),
            ('rls4427_writer',"update storage.objects set label=' allowed ' where id=1 returning label;",0,b'allowed'),
            ('rls4427_reader',"select nextval('public.restore_fixture_id_seq');",3,None),
            ('rls4427_writer',"select nextval('public.restore_fixture_id_seq');",0,b'1')]:
            result=self.sql(db,f'begin;set local role {role};{sql}rollback;',allowed_failure=True)
            if result.returncode!=expected or (expected and b'42501' not in result.stderr):
                raise RuntimeError('4427 regression role permission differs')
            if value is not None and result.stdout.strip()!=value:
                raise RuntimeError('4427 regression affected row or sequence outcome differs')
            outcomes.append([role,result.returncode,result.stdout.decode().strip(),result.stderr.decode().strip()])
        self.sql(db,'set role rls4427_owner;create table public.default_acl_probe(id integer);reset role;')
        result=self.sql(db,'begin;set local role rls4427_reader;select count(*) from public.default_acl_probe;rollback;')
        if result.stdout.strip()!=b'0':raise RuntimeError('4427 regression default ACL readback differs')
        outcomes.append(['default_acl',result.returncode,result.stdout.decode().strip()])
        return outcomes

    def run(self):
        if any(k.startswith('DOCKER_') and v for k,v in os.environ.items()):
            raise RuntimeError('4427 regression Docker environment override refused')
        source_facts=source_identity()
        sock=Path('/var/run/docker.sock');info=sock.stat()
        if not stat.S_ISSOCK(info.st_mode) or info.st_uid!=0 or info.st_mode&0o007 or str(sock.resolve()) not in ('/run/docker.sock','/var/run/docker.sock'):
            raise RuntimeError('4427 regression local Docker endpoint refused')
        with tempfile.TemporaryDirectory(prefix='rls4427-native-restore-') as temp:
            os.chmod(temp,0o700);self.config=temp
            if json.loads(self.docker('ps','-aq','--filter','name=^/'+NAME+'$','--format','{{json .ID}}').stdout or b'null'):
                raise RuntimeError('4427 regression name already occupied; no takeover')
            image=json.loads(self.docker('image','inspect',IMAGE).stdout)
            if len(image)!=1 or image[0]['Id']!=IMAGE:
                raise RuntimeError('4427 regression cached immutable image differs')
            inherited=image[0].get('Config',{}).get('Labels') or {}
            if any(k in inherited and inherited[k]!=v for k,v in LABELS.items()):
                raise RuntimeError('4427 regression cached image ownership conflicts')
            self.expected_labels={**inherited,**LABELS}
            try:
                args=['run','--detach','--pull=never','--name',NAME,'--network','none','--read-only','--memory','512m','--cpus','1','--pids-limit','128',
                      '--tmpfs','/var/lib/postgresql/data:rw,nosuid,nodev,noexec,size=268435456','--tmpfs','/var/run/postgresql:rw,nosuid,nodev,size=16777216',
                      '--tmpfs','/tmp:rw,nosuid,nodev,noexec,size=16777216','--env','POSTGRES_HOST_AUTH_METHOD=trust']
                for k,v in LABELS.items():args+=['--label',k+'='+v]
                self.cid=self.docker(*args,IMAGE).stdout.decode().strip()
                if not re.fullmatch(r'[0-9a-f]{64}',self.cid):raise RuntimeError('4427 regression immutable container ID invalid')
                # A single bounded native readiness command, no service polling or external port.
                ready="for i in $(seq 1 30); do test \"$(cat /proc/1/comm)\" = postgres && pg_isready -U postgres >/dev/null 2>&1 && exit 0; sleep 1; done; exit 1"
                self.execute(['sh','-c',ready])
                versions=[self.execute([tool,'--version']).stdout.decode().strip() for tool in ('psql','pg_dump','pg_restore')]
                server_version=int(self.sql('postgres',"select current_setting('server_version_num');").stdout.strip())
                version_facts=validate_exact_versions(versions,server_version)
                self.version_bound=True
                print(json.dumps(dict(phase='exact-local-version',**version_facts),sort_keys=True),file=sys.stderr)
                self.create(DATABASES[0]);self.sql(DATABASES[0],(ROOT/'supabase/tests/fixtures/rls4427_native_restore_fixture.sql').read_text())
                archive_path=Path(temp)/'full.dump'
                with os.fdopen(os.open(archive_path,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600),'wb') as out:
                    self.execute(['pg_dump','-U','postgres','-d',DATABASES[0],'-Fc'],output=out)
                archive=archive_path.read_bytes();source=json.loads(self.sql(DATABASES[0],METADATA).stdout)
                admin_authority=self.qualify_admin()
                self.create(DATABASES[1])
                failure=self.clean_negative(DATABASES[1],archive)
                negative=failure.stderr.decode()
                old_restored=json.loads(self.sql(DATABASES[1],METADATA).stdout)
                if source!=old_restored:raise RuntimeError('4427 PG17.11 successful old-clean metadata differs')
                old_control=dict(disposition='NOT_REPRODUCED_PG17_11',metadata_equal=True,exit_code=failure.returncode,stderr=negative)
                print(json.dumps(dict(phase='old-clean-equivalence',**old_control),sort_keys=True),file=sys.stderr)
                self.drop(DATABASES[1])
                self.create(DATABASES[5],owner='rls4427_restore_operator')
                permission_negative=self.permission_negative(DATABASES[5],archive)
                self.drop(DATABASES[5])
                self.create(DATABASES[2]);self.restore(DATABASES[2],archive)
                restored=json.loads(self.sql(DATABASES[2],METADATA).stdout)
                if source!=restored:raise RuntimeError('4427 regression full metadata/data/owner/ACL/policy equivalence differs')
                expected=self.permissions(DATABASES[0]);actual=self.permissions(DATABASES[2])
                if expected!=actual or json.loads(self.sql(DATABASES[0],METADATA).stdout)!=json.loads(self.sql(DATABASES[2],METADATA).stdout):
                    raise RuntimeError('4427 regression effective permissions/default ACL or final metadata differs')
                self.drop(DATABASES[2])
                nonempty_refusals=[]
                for kind,mutation in [('public_object','create table public.unexpected(id integer);'),
                                      ('default_acl','alter default privileges grant select on tables to rls4427_reader;'),
                                      ('extension','create extension pg_trgm;')]:
                    self.create(DATABASES[3]);self.sql(DATABASES[3],mutation)
                    try:self.restore(DATABASES[3],archive)
                    except RuntimeError as error:
                        if 'fresh template0 target catalog differs' not in str(error):raise
                        nonempty_refusals.append(kind)
                    else:raise RuntimeError('4427 regression accepted nonempty target')
                    self.drop(DATABASES[3])
                self.create(DATABASES[4]);self.qualify(DATABASES[4])
                truncated=self.admin_restore(DATABASES[4],archive[:32],allowed_failure=True)
                if not truncated.returncode:raise RuntimeError('4427 regression accepted truncated archive')
                self.drop(DATABASES[4]);self.drop(DATABASES[0])
                return dict(**source_facts,qualification='REAL_PG17_11_FRESH_RESTORE_ONLY',production_acceptance='NOT_EVALUATED',historical_native_17_6_failure='PRESERVED_NOT_REPRODUCED',native374_acceptance='NOT_EVALUATED',old_clean_control=old_control,permission_negative=permission_negative,qualified_admin=admin_authority,version_facts=version_facts,versions=versions,
                    archive_sha256=hashlib.sha256(archive).hexdigest(),metadata_sha256=hashlib.sha256(json.dumps(source,sort_keys=True).encode()).hexdigest(),
                    clean_negative_exit=failure.returncode,clean_negative_stderr=negative,nonempty_refusals=nonempty_refusals,truncated_exit=truncated.returncode,permissions=actual,events=self.events,elapsed_seconds=time.monotonic()-self.started)
            finally:
                if self.cid:
                    self.cleanup_mode=True
                    try:
                        for db in list(reversed(self.owned)):self.drop(db)
                    finally:
                        self.custody();self.docker('stop','--time','10',self.cid);self.docker('rm',self.cid)
                        if self.docker('ps','-aq','--filter','name=^/'+NAME+'$').stdout.strip():
                            raise RuntimeError('4427 regression container removal absence differs')
                        receipt=dict(container_removed=self.cid,absent=True)
                        self.events.append(receipt);print(json.dumps(receipt),file=sys.stderr)


if __name__=='__main__':
    try:print(json.dumps(Regression().run(),sort_keys=True))
    except Exception as error:
        print('4427 native restore regression failed: '+str(error),file=sys.stderr);sys.exit(1)
