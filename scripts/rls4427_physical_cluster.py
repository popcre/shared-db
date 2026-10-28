#!/usr/bin/env python3
"""Issue4890 only: physical copy of synthetic native cluster, never a shared target.
Import is offline. Resource execution requires a separate exact action approval.
"""
import datetime
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time

DATA='/var/lib/postgresql/data'
CONFIG_ROOTS=('etc/postgresql','etc/postgresql-custom')
TMPFS={DATA:'rw,nosuid,nodev,uid=100,gid=101,mode=0700,size=4294967296',
       '/etc/postgresql':'rw,nosuid,nodev,uid=100,gid=101,mode=0700,size=33554432',
       '/etc/postgresql-custom':'rw,nosuid,nodev,uid=100,gid=101,mode=0700,size=33554432',
       '/var/run/postgresql':'rw,nosuid,nodev,uid=100,gid=101,mode=0700,size=16777216',
       '/var/log/postgresql':'rw,nosuid,nodev,uid=100,gid=101,mode=0700,size=33554432',
       '/tmp':'rw,nosuid,nodev,uid=100,gid=101,mode=0700,size=134217728'}
OWNER='01a1834a-813e-7b12-b17a-3e8c3aaedfb8'
IMMUTABLE_CONFIG_SHA='e1939b94b1fd12b8a446404ff49455d7cf2a6a275a77f010abb56a247bfd5377'
CRON_BINARY_SHA='55a7bdcf1b966d51d83d248797507348de19d16f1c968948c1854bc799751108'
BACKUP_ARGS=['pg_basebackup','-h','/var/run/postgresql','-p','5432','-U','supabase_admin','-D','-','-Ft','-X','fetch','-c','fast','--manifest-checksums=SHA256','--no-password']
CONFIG_ARGS=['tar','--numeric-owner','-C','/','-cf','-','etc/postgresql','etc/postgresql-custom']
BINARY_ARGS=['sha256sum','/nix/store/qpz7hxz26yk04v1f0cxfhgicy360zf9n-pg_cron-1.6.4/lib/pg_cron-1.6.4.so']
HBA_PATH='/etc/postgresql/pg_hba.conf'
HBA_READ_ARGS=['cat',HBA_PATH]
HBA_STAT_ARGS=['stat','-c','%F:%u:%g:%a:%h',HBA_PATH]
HBA_APPEND_ARGS=['sh','-c','cat >> /etc/postgresql/pg_hba.conf']
HBA_RESTORE_ARGS=['sh','-c','cat > /etc/postgresql/pg_hba.conf']
HBA_LINE=b'\nlocal replication supabase_admin trust\n'
REPL_PROBE_ARGS=['psql','-XqAtw','host=/var/run/postgresql port=5432 user=supabase_admin dbname=replication replication=true','-c','IDENTIFY_SYSTEM;']
RELOAD_ARGS=['psql','-XqAtw','-h','/var/run/postgresql','-p','5432','-U','supabase_admin','-d','postgres','-v','ON_ERROR_STOP=1','-c','select pg_reload_conf();']
SOURCE_HEALTH_SQL="""select json_build_object('recovery',pg_is_in_recovery(),'superuser',(select rolsuper from pg_roles where rolname=current_user),
'roles',(select md5(string_agg(row_to_json(r)::text,E'\n' order by rolname)) from pg_roles r),
'members',(select md5(coalesce(string_agg(row_to_json(m)::text,E'\n' order by roleid,member,grantor),'')) from pg_auth_members m),
'policies',(select md5(coalesce(string_agg(row_to_json(p)::text,E'\n' order by schemaname,tablename,policyname),'')) from pg_policies p),
'objects',(select md5(string_agg(concat_ws(':',c.oid,c.relowner,c.relacl::text,c.relrowsecurity,c.relforcerowsecurity),E'\n' order by c.oid)) from pg_class c),
'functions',(select md5(string_agg(concat_ws(':',p.oid,p.proowner,p.proacl::text,p.prosecdef,p.provolatile,p.proconfig::text,p.prosrc,p.probin),E'\n' order by p.oid)) from pg_proc p),
'slots',(select count(*) from pg_replication_slots),'walsenders',(select count(*) from pg_stat_replication))::text;"""


UNIX_HEALTH_ARGS=['psql','-XqAtw','-h','/var/run/postgresql','-p','5432','-U','supabase_admin','-d','postgres','-v','ON_ERROR_STOP=1','-c',SOURCE_HEALTH_SQL]


def process_input(stream):
    """BytesIO has no OS descriptor; archives keep their real streaming descriptor."""
    if stream is None:return {'stdin':subprocess.DEVNULL}
    if isinstance(stream,io.BytesIO):return {'input':stream.read()}
    try:descriptor=stream.fileno()
    except (AttributeError,io.UnsupportedOperation,OSError,ValueError):
        raise RuntimeError('4427 unsupported subprocess input stream') from None
    if not isinstance(descriptor,int) or descriptor<0:raise RuntimeError('4427 invalid subprocess input descriptor')
    return {'stdin':stream}


def capture_external(stderr,tool,code,phase):
    """Raw external diagnostics stay0600 outside cleanup's config/PGDATA trees."""
    raw=stderr if isinstance(stderr,bytes) else (stderr or '').encode(errors='replace')
    fd,path=tempfile.mkstemp(prefix='rls4427-private-external-',suffix='.stderr')
    with os.fdopen(fd,'wb') as out:out.write(raw)
    found=re.search(rb'(?:ERROR|FATAL):\s+([A-Z0-9]{5})(?::|\s|$)',raw)
    return dict(phase=phase,tool=tool,exit_code=code,sqlstate=found[1].decode() if found else None,
                private_stderr_path=path,private_stderr_sha256=hashlib.sha256(raw).hexdigest())


def failure_receipt(error,phase,events):
    reason=str(error) if isinstance(error,RuntimeError) and str(error).startswith('4427 ') else '4427 external or unclassified failure'
    result=dict(qualification_passed=False,error_type=type(error).__name__,phase=phase,invariant=reason,events=list(events))
    if isinstance(error,subprocess.CalledProcessError):
        tool=Path(error.cmd[0]).name if isinstance(error.cmd,list) and error.cmd else 'external'
        result['external']=capture_external(error.stderr,tool,error.returncode,phase)
    return result


def emit(events,value):
    events.append(value);print(json.dumps(value,sort_keys=True),file=sys.stderr)


def source_command_kind(args):
    if args in (BACKUP_ARGS,CONFIG_ARGS):return 'archive'
    if args in (HBA_APPEND_ARGS,HBA_RESTORE_ARGS):return 'hba-write'
    if (len(args)==3 and args[0]=='chown' and args[1] in ('0:0','100:101') and args[2]==HBA_PATH) or (len(args)==3 and args[0]=='chmod' and args[1] in ('600','640','644','755') and args[2]==HBA_PATH):return 'hba-metadata'
    if args in (BINARY_ARGS,HBA_READ_ARGS,HBA_STAT_ARGS,REPL_PROBE_ARGS,RELOAD_ARGS,UNIX_HEALTH_ARGS):return 'read'
    if args in ([tool,'--version'] for tool in ('pg_basebackup','pg_verifybackup')):return 'read'
    fixed=['psql','-XqAtw','-h','127.0.0.1','-p','5432','-U','supabase_admin','-d','postgres','-v','ON_ERROR_STOP=1','-c']
    if args[:-1]==fixed and args[-1] in (SOURCE_FACTS_SQL,CRON_SQL,SOURCE_HEALTH_SQL):return 'read'
    return None


def validate_hba_payload(source,args,stream):
    if args in (HBA_APPEND_ARGS,HBA_RESTORE_ARGS):
        expected=HBA_LINE if args==HBA_APPEND_ARGS else getattr(source,'hba_original_bytes',None)
        if expected is None or stream is None or not stream.seekable():raise RuntimeError('4427 exact HBA payload identity absent')
        position=stream.tell();actual=stream.read();stream.seek(position)
        if actual!=expected:raise RuntimeError('4427 exact HBA payload differs')
    elif args and args[0] in ('chmod','chown'):
        expected=getattr(source,'hba_saved_mode' if args[0]=='chmod' else 'hba_saved_owner',None)
        if args[1]!=expected:raise RuntimeError('4427 exact original HBA metadata differs')


def validate_missing_unix_hba(raw):
    import shlex
    trusted=False
    for line in raw.decode('utf-8').splitlines():
        fields=shlex.split(line,comments=True,posix=False)
        if not fields:continue
        if any(any(char in token for char in (chr(34),chr(39),chr(92))) for token in fields):raise RuntimeError('4427 unsupported quoted or escaped HBA token')
        if fields[0] not in ('local','host','hostssl','hostnossl') or len(fields)<(4 if fields[0]=='local' else 5):
            raise RuntimeError('4427 unsupported source HBA syntax; no permission override')
        if any('@' in f or f.startswith('+') or f.startswith('/') for f in fields[1:3]):
            raise RuntimeError('4427 unsupported source HBA indirection')
        if fields[0]!='local':continue
        databases=fields[1].split(',');users=fields[2].split(',')
        applicable=bool({'all','supabase_admin'}&set(users))
        if 'replication' in databases and applicable:
            raise RuntimeError('4427 existing Unix replication rule/deny must not be overridden')
        if applicable and bool({'all','postgres'}&set(databases)) and not trusted:
            if fields[3]!='trust':raise RuntimeError('4427 existing admin SQL route is not already trusted')
            trusted=True
    if not trusted:raise RuntimeError('4427 trusted existing local admin SQL route missing')


class TemporaryUnixHba:
    """Exact permission window on the qualified synthetic source, restored before target."""
    def __init__(self,source,private_root):self.source=source;self.root=private_root;self.events=[];self.changed=False

    def call(self,args,input_bytes=None,allowed_failure=False):
        import io
        return self.source.source_checked(args,input_file=io.BytesIO(input_bytes) if input_bytes is not None else None,allowed_failure=allowed_failure)

    def probe(self):
        result=self.call(REPL_PROBE_ARGS,allowed_failure=True)
        if result.returncode==0:
            if re.fullmatch(rb'[0-9]+\|[0-9]+\|[0-9A-F]+/[0-9A-F]+\|\s*',result.stdout) is None:
                raise RuntimeError('4427 physical IDENTIFY_SYSTEM response invalid')
            expected=getattr(self.source,'restore_authority',{}).get('system_identifier')
            if result.stdout.split(b'|')[0].decode()!=expected:raise RuntimeError('4427 physical replication identity differs')
            state='ALLOWED'
        elif result.returncode==2 and all(x in result.stderr for x in (b'no pg_hba.conf entry for replication connection',b'[local]',b'supabase_admin')):state='HBA_ABSENT'
        else:
            self.source.last_external_failure=capture_external(result.stderr,'psql',result.returncode,'source-physical-identify')
            raise RuntimeError('4427 physical replication probe refused outside HBA absence')
        emit(self.events,{'physical_identify_state':state,'exit_code':result.returncode})
        return state

    def loaded(self,expected):
        deadline=time.monotonic()+3
        while True:
            state=self.probe()
            if state==expected:return
            if time.monotonic()>=deadline:raise RuntimeError('4427 loaded Unix HBA state did not converge within three seconds')
            time.sleep(.2)

    def health(self):
        facts=json.loads(self.call(UNIX_HEALTH_ARGS).stdout)
        if facts.get('recovery') is not False or facts.get('superuser') is not True or facts.get('slots')!=0 or facts.get('walsenders')!=0:raise RuntimeError('4427 source normal SQL/capability health refused')
        return facts

    def __enter__(self):
        self.original=self.call(HBA_READ_ARGS).stdout
        validate_missing_unix_hba(self.original)
        self.metadata=self.call(HBA_STAT_ARGS).stdout.decode().strip().split(':')
        if len(self.metadata)!=5 or self.metadata[0]!='regular file' or ':'.join(self.metadata[1:3]) not in ('0:0','100:101') or self.metadata[3] not in ('600','640','644','755') or self.metadata[4]!='1':
            raise RuntimeError('4427 original HBA owner/mode/type unsupported')
        with os.fdopen(os.open(self.root/'source-original-hba',os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600),'wb') as out:out.write(self.original)
        with tarfile.open(self.root/'source-config.tar','r:') as archive:
            if archive.extractfile('etc/postgresql/pg_hba.conf').read()!=self.original:raise RuntimeError('4427 original config/HBA capture raced')
        self.before_health=self.health()
        if self.probe()!='HBA_ABSENT':raise RuntimeError('4427 source permission window requires actual missing route')
        if not hasattr(self.source,'source_backup_window'):raise RuntimeError('4427 source backup minute admission absent')
        minute_guard(*self.source.source_backup_window,time.time(),time.monotonic())
        self.source.hba_original_bytes=self.original
        self.source.hba_saved_owner=':'.join(self.metadata[1:3]);self.source.hba_saved_mode=self.metadata[3]
        self.source.hba_window_active=True;self.changed=True
        try:
            self.call(HBA_APPEND_ARGS,HBA_LINE)
            if self.call(HBA_READ_ARGS).stdout!=self.original+HBA_LINE:raise RuntimeError('4427 source HBA append differs')
            if self.call(RELOAD_ARGS).stdout.strip()!=b't':raise RuntimeError('4427 source HBA reload signal refused')
            self.loaded('ALLOWED');self.source.hba_temporary_verified=True
            return self
        except Exception:
            self.restore();raise

    def restore(self):
        if not self.changed:return
        try:
            self.call(HBA_RESTORE_ARGS,self.original)
            self.call(['chown',':'.join(self.metadata[1:3]),HBA_PATH]);self.call(['chmod',self.metadata[3],HBA_PATH])
            if self.call(HBA_READ_ARGS).stdout!=self.original or self.call(HBA_STAT_ARGS).stdout.decode().strip().split(':')!=self.metadata:
                raise RuntimeError('4427 exact original source HBA bytes/metadata restoration failed')
            if self.call(RELOAD_ARGS).stdout.strip()!=b't':raise RuntimeError('4427 restored source HBA reload signal refused')
            self.loaded('HBA_ABSENT')
            if self.health()!=self.before_health:raise RuntimeError('4427 source capability/catalog changed during backup')
            emit(self.events,{'original_hba_restored':True,'bytes_owner_mode_equal':True,'fresh_physical_denied':True})
            self.changed=False
        except Exception:
            self.source.hba_restore_failed=True
            raise
        finally:self.source.hba_window_active=False;self.source.hba_temporary_verified=False

    def __exit__(self,*unused):self.restore()

CRON_SQL="""select json_build_object(
'jobs',(select count(*) from cron.job),
'job_hash',(select md5(coalesce(string_agg(row_to_json(j)::text,E'\n' order by jobid),'')) from cron.job j),
'schedules',(select coalesce(json_agg(schedule order by jobid),'[]') from cron.job where active),
'runs',(select count(*) from cron.job_run_details),
'run_hash',(select md5(coalesce(string_agg(row_to_json(r)::text,E'\n' order by runid),'')) from cron.job_run_details r),
'pending',(select count(*) from cron.job_run_details where status in ('starting','running')),
'workers',(select count(*) from pg_stat_activity where backend_type='pg_cron worker' or application_name='pg_cron'),
'schedulers',(select coalesce(json_agg(json_build_array(pid,backend_start::text) order by pid),'[]') from pg_stat_activity where application_name='pg_cron scheduler'))::text;"""
SOURCE_FACTS_SQL="""begin read only;
do $g$ declare r record; present boolean; begin
for r in select n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relpersistence='u' and c.relkind in ('r','m') loop
 execute format('select exists(select 1 from %I.%I limit 1)',r.nspname,r.relname) into present;
 if present then raise exception '4427 physical backup refuses nonempty unlogged relation'; end if;
end loop; end $g$;
select json_build_object('database',current_database(),'current_user',current_user,'session_user',session_user,
'superuser',(select rolsuper from pg_roles where rolname=current_user),'replication',(select rolreplication from pg_roles where rolname=current_user),
'recovery',pg_is_in_recovery(),'wal_level',current_setting('wal_level'),'max_wal_senders',current_setting('max_wal_senders')::int,
'external_tablespaces',(select count(*) from pg_tablespace where spcname not in ('pg_default','pg_global')),
'subscriptions',(select count(*) from pg_subscription),'slots',(select count(*) from pg_replication_slots),'prepared_transactions',(select count(*) from pg_prepared_xacts),
'cron_version',(select extversion from pg_extension where extname='pg_cron'),
'sodium_version',(select extversion from pg_extension where extname='pgsodium'),
'sodium_nonce_api',to_regprocedure('pgsodium.crypto_secretbox_noncegen()') is not null,
'sodium_keyid_api',to_regprocedure('pgsodium.crypto_secretbox(bytea,bytea,bigint,bytea)') is not null,
'sodium_open_keyid_api',to_regprocedure('pgsodium.crypto_secretbox_open(bytea,bytea,bigint,bytea)') is not null,
'config_file',current_setting('config_file'),'hba_file',current_setting('hba_file'),'ident_file',current_setting('ident_file'),
'data_directory',current_setting('data_directory'),'archive_mode',current_setting('archive_mode'),'archive_command',current_setting('archive_command'),
'restore_command',current_setting('restore_command'),'primary_conninfo',current_setting('primary_conninfo'),
'ssl',current_setting('ssl'),'log_directory',current_setting('log_directory'),'socket',current_setting('unix_socket_directories'),
'cron_database',current_setting('cron.database_name'),'preload',current_setting('shared_preload_libraries'),
'hba_errors',(select count(*) from pg_hba_file_rules where error is not null),
'replication_hba',(select count(*) from pg_hba_file_rules where type='host' and 'replication'=any(database) and ('all'=any(user_name) or 'supabase_admin'=any(user_name)) and address in ('127.0.0.1','127.0.0.1/32') and auth_method in ('trust','scram-sha-256','md5')),
'other_backends',(select count(*) from pg_stat_activity where backend_type='client backend' and pid<>pg_backend_pid() and state='active'))::text;
rollback;"""
CANARY_CREATE_SQL="""create schema if not exists rls4427_physical;
create table rls4427_physical.canary as with n as (select pgsodium.crypto_secretbox_noncegen() nonce)
select nonce,pgsodium.crypto_secretbox(convert_to('4427-physical-root-canary','UTF8'),nonce,4427::bigint,convert_to('4427snap','UTF8')) cipher from n;"""
CANARY_CHECK_SQL="select count(*)=1 and bool_and(pgsodium.crypto_secretbox_open(cipher,nonce,4427::bigint,convert_to('4427snap','UTF8'))=convert_to('4427-physical-root-canary','UTF8')) from rls4427_physical.canary;"


def validate_source_facts(f):
    if (f.get('database')!='postgres' or f.get('current_user')!='supabase_admin' or f.get('session_user')!='supabase_admin' or f.get('superuser') is not True
        or f.get('recovery') is not False or f.get('wal_level') not in ('replica','logical') or f.get('max_wal_senders',0)<1
        or any(f.get(k)!=0 for k in ('external_tablespaces','subscriptions','slots','prepared_transactions','hba_errors','other_backends'))
        or not isinstance(f.get('replication_hba'),int) or f.get('cron_version') not in ('1.6','1.6.4') or f.get('cron_database')!='postgres'
        or f.get('sodium_version')!='3.1.8' or any(f.get(k) is not True for k in ('sodium_nonce_api','sodium_keyid_api','sodium_open_keyid_api'))
        or f.get('config_file')!='/etc/postgresql/postgresql.conf' or f.get('hba_file')!='/etc/postgresql/pg_hba.conf'
        or f.get('ident_file')!='/etc/postgresql/pg_ident.conf' or f.get('data_directory')!=DATA
        or f.get('archive_mode')!='off' or f.get('archive_command') not in ('','(disabled)') or any(f.get(k) for k in ('restore_command','primary_conninfo'))
        or f.get('ssl')!='off' or f.get('log_directory') not in ('log','/var/log/postgresql') or f.get('socket')!='/var/run/postgresql'
        or any(x not in [item.strip() for item in f.get('preload','').split(',')] for x in ('pg_cron','pgsodium'))):
        raise RuntimeError('4427 physical source startup/replication/dependency facts refused')
    return f


def validate_cron(f, require_scheduler=True):
    if f.get('pending')!=0 or f.get('workers')!=0 or not isinstance(f.get('schedules'),list):
        raise RuntimeError('4427 physical cron activity or schedule facts refused')
    for schedule in f['schedules']:
        fields=schedule.split() if isinstance(schedule,str) else []
        if len(fields)!=5 or any(re.fullmatch(r'[0-9*/,-]+',x) is None for x in fields):
            raise RuntimeError('4427 physical requires ordinary five-field cron schedules')
    if require_scheduler and len(f.get('schedulers',[]))!=1:
        raise RuntimeError('4427 physical scheduler identity missing or ambiguous')
    return f


def cron_fingerprint(f):
    return {k:f[k] for k in ('jobs','job_hash','schedules','runs','run_hash','pending','workers')}


def validate_tar(path, kind):
    """Validate archive names/types/size before any extraction, never extract on host."""
    names=set();total=0;members={}
    with tarfile.open(path,'r:') as archive:
        for member in archive:
            raw=member.name.removeprefix('./').rstrip('/')
            pure=PurePosixPath(raw)
            if raw in ('','.') and member.isdir():continue
            if not raw or pure.is_absolute() or '..' in pure.parts or raw in names or not (member.isfile() or member.isdir()) or member.size<0:
                raise RuntimeError('4427 physical archive path/type/cardinality refused')
            if kind=='config' and not any(raw==root or raw.startswith(root+'/') for root in CONFIG_ROOTS):
                raise RuntimeError('4427 physical config archive escaped exact roots')
            if kind!='config' and (raw in ('standby.signal','recovery.signal','postmaster.pid') or raw.startswith('pg_tblspc/')):
                raise RuntimeError('4427 physical archive has external/recovery dependency')
            names.add(raw);total+=member.size
            if len(names)>100000 or total>1073741824:
                raise RuntimeError('4427 physical archive exceeds one-GiB bounded snapshot')
            if kind=='config' and member.isfile():
                if member.size>1048576:raise RuntimeError('4427 physical configuration file too large')
                members[raw]=archive.extractfile(member).read()
    if kind=='config':
        key='etc/postgresql-custom/pgsodium_root.key'
        if key not in members or re.fullmatch(rb'[0-9a-fA-F]{64}\n?',members[key]) is None:
            raise RuntimeError('4427 physical actual root-key file missing or invalid')
        for required in ('etc/postgresql/postgresql.conf','etc/postgresql/pg_hba.conf','etc/postgresql/pg_ident.conf'):
            if required not in members:raise RuntimeError('4427 physical active configuration closure missing')
        for name,raw in members.items():
            if not name.endswith('.conf'):continue
            for line in raw.decode('utf-8').splitlines():
                line=line.strip()
                if not line or line.startswith('#'):continue
                include=re.fullmatch(r"(include|include_if_exists|include_dir)\s*(?:=\s*)?'([^']+)'\s*(?:#.*)?",line)
                if not include:
                    if re.match(r'include(?:_if_exists|_dir)?\b',line):raise RuntimeError('4427 physical include syntax unsupported')
                    continue
                target=PurePosixPath(include[2])
                target=(PurePosixPath(name).parent/target) if not target.is_absolute() else PurePosixPath(str(target).lstrip('/'))
                value=str(target)
                if '..' in target.parts or not any(value==r or value.startswith(r+'/') for r in CONFIG_ROOTS):
                    raise RuntimeError('4427 physical config include escaped exact closure')
                if include[1]=='include' and value not in members:
                    raise RuntimeError('4427 physical required config include missing')
                if include[1]=='include_dir' and value not in names:
                    raise RuntimeError('4427 physical config include directory missing')
    else:
        if not {'PG_VERSION','global/pg_control'}.issubset(names):raise RuntimeError('4427 physical full cluster archive incomplete')
        if kind=='backup' and not {'backup_label','backup_manifest'}.issubset(names):raise RuntimeError('4427 physical backup manifest missing')
    with Path(path).open('rb') as stream:digest=hashlib.file_digest(stream,'sha256').hexdigest()
    return dict(files=len(names),bytes=total,sha256=digest)


def minute_guard(start_wall,start_mono,now_wall,now_mono):
    if (int(start_wall//60)!=int(now_wall//60) or now_wall%60>=50 or now_wall<start_wall
        or abs((now_wall-start_wall)-(now_mono-start_mono))>.25):
        raise RuntimeError('4427 physical minute/deadline/clock continuity violated')


class PhysicalCluster:
    def __init__(self, source, budget_seconds=2100):
        self.source=source;self.budget=min(budget_seconds,2100);self.started=time.monotonic();self.cid=None
        self.name=source.prefix+'-physical';self.labels={'shared-db.qualifier':'4427-physical','shared-db.owner':OWNER}
        self.running=False;self.sealed=False;self.events=[];self.env={'PATH':'/usr/bin:/bin','LANG':'C.UTF-8'}
        self.root=None;self.cleanup_mode=False;self.window_wait_seconds=0.0;self.phase='created';self.start_number=0;self.last_external_failure=None

    def __enter__(self):return self.open()
    def __exit__(self,*unused):self.close()

    def budget_check(self):
        if not self.cleanup_mode and time.monotonic()-self.started>self.budget:raise RuntimeError('4427 physical total budget exhausted')

    def docker(self,*args,input_file=None,output_file=None,allowed_failure=False):
        self.budget_check()
        r=subprocess.run(['/usr/bin/docker','--host','unix:///var/run/docker.sock','--config',str(self.root/'docker-config'),*args],
            env=self.env,**process_input(input_file),stdout=output_file or subprocess.PIPE,stderr=subprocess.PIPE,timeout=20 if self.cleanup_mode else 120)
        if r.returncode and not allowed_failure:
            self.last_external_failure=capture_external(r.stderr,args[0],r.returncode,self.phase)
            raise RuntimeError('4427 owned physical operation failed: '+args[0])
        return r

    def custody(self,allow_stopped=False):
        rows=json.loads(self.docker('inspect','--type','container',self.name).stdout)
        if len(rows)!=1:raise RuntimeError('4427 physical target cardinality differs')
        row=rows[0];h=row['HostConfig'];n=row['NetworkSettings'];state=row['State']
        running=state.get('Running') is True
        stopped=allow_stopped and self.cleanup_mode and state.get('Running') is False and state.get('Status') in ('created','exited','dead')
        expected_tmpfs={DATA,'/etc/postgresql','/etc/postgresql-custom','/var/run/postgresql','/var/log/postgresql','/tmp'}
        if (row['Id']!=self.cid or row['Name']!='/'+self.name or row['Image']!=self.image_id or row['Config'].get('Labels')!=self.target_labels
            or row['Config'].get('User')!='100:101' or row['Config'].get('Entrypoint')!=['/bin/sleep'] or row['Config'].get('Cmd')!=['infinity']
            or h.get('NetworkMode')!='none' or h.get('Privileged') is not False or h.get('ReadonlyRootfs') is not True or h.get('Binds')
            or h.get('Memory')!=2147483648 or h.get('NanoCpus')!=1000000000 or h.get('PidsLimit')!=256
            or h.get('Devices') or h.get('CapAdd') or h.get('PidMode','') or h.get('PortBindings')
            or h.get('Tmpfs',{})!=TMPFS or any(m.get('Type')!='tmpfs' or m.get('Destination') not in expected_tmpfs for m in row.get('Mounts',[]))
            or set(n.get('Networks',{}))!={'none'} or any(n.get('Ports',{}).values()) or not (running or stopped)):
            raise RuntimeError('4427 physical target custody/resource bounds differ')
        return {'running':running,'status':state.get('Status','running' if running else 'unknown'),'oom_killed':state.get('OOMKilled',False)}

    def target(self,args,input_file=None,output_file=None,allowed_failure=False):
        self.custody()
        return self.docker('exec',*(['-i'] if input_file else []),'--user','100:101',self.cid,*args,input_file=input_file,output_file=output_file,allowed_failure=allowed_failure)

    def sql(self,query,role='postgres'):
        if role not in ('postgres','supabase_admin'):raise RuntimeError('4427 physical SQL role refused')
        self.guard()
        import io
        r=self.target(['psql','-XqAtw','-h','127.0.0.1','-p','5432','-U',role,'-d','postgres','-v','ON_ERROR_STOP=1','-v','VERBOSITY=sqlstate'],input_file=io.BytesIO(query.encode()),allowed_failure=True)
        if r.returncode:
            self.last_external_failure=capture_external(r.stderr,'psql',r.returncode,self.phase)
            raise subprocess.CalledProcessError(r.returncode,['psql'],output=r.stdout.decode(),stderr=r.stderr.decode())
        return r.stdout.decode()

    def guard(self):
        self.budget_check()
        if self.running:minute_guard(self.start_wall,self.start_mono,time.time(),time.monotonic())

    def _admin_source(self,query):
        args=['psql','-XqAtw','-h','127.0.0.1','-p','5432','-U','supabase_admin','-d','postgres','-v','ON_ERROR_STOP=1','-c',query]
        return self.source.container_exec(args).decode()

    def open(self):
        self.root=Path(tempfile.mkdtemp(prefix='rls4427-private-physical-'));os.chmod(self.root,0o700)
        (self.root/'docker-config').mkdir(mode=0o700)
        try:
            self.phase='source-qualification'
            self.source.docker_config=str(self.root/'docker-config')
            self.source.qualify_physical_source()
            if getattr(self.source,'immutable_config_sha',None)!=IMMUTABLE_CONFIG_SHA:raise RuntimeError('4427 physical source immutable config digest differs')
            identity=self.source.custody();self.source.container_id=identity[0];self.image_id=identity[1]
            facts=validate_source_facts(json.loads(self._admin_source(SOURCE_FACTS_SQL).splitlines()[-1]))
            self.source.source_backup_window=self.admit_window()
            source_cron=validate_cron(json.loads(self._admin_source(CRON_SQL)))
            binary=self.source.container_exec(BINARY_ARGS).decode().split()[0]
            if binary!=CRON_BINARY_SHA:raise RuntimeError('4427 physical actual pg_cron binary not audited version1.6.4')
            # Capture ORIGINAL configuration before granting the temporary route.
            with os.fdopen(os.open(self.root/'source-config.tar',os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600),'wb') as out:
                self.source.container_exec(CONFIG_ARGS,output_file=out)
            self.original_config_receipt=validate_tar(self.root/'source-config.tar','config')
            self.phase='source-temporary-unix-backup-window'
            permission=TemporaryUnixHba(self.source,self.root)
            try:
                with permission:
                    with os.fdopen(os.open(self.root/'source-basebackup.tar',os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600),'wb') as out:
                        self.source.container_exec(BACKUP_ARGS,output_file=out)
                    self.original_backup_receipt=validate_tar(self.root/'source-basebackup.tar','backup')
            finally:self.events.extend(permission.events)
            minute_guard(*self.source.source_backup_window,time.time(),time.monotonic())
            after=validate_cron(json.loads(self._admin_source(CRON_SQL)))
            if cron_fingerprint(source_cron)!=cron_fingerprint(after):raise RuntimeError('4427 physical source changed during backup')
            if self.docker('ps','-aq','--filter','name=^/'+self.name+'$').stdout.strip():raise RuntimeError('4427 physical target name occupied')
            image=json.loads(self.docker('image','inspect',self.image_id).stdout)
            if len(image)!=1 or image[0]['Id']!=self.image_id:raise RuntimeError('4427 physical cached source image differs')
            self.target_labels={**(image[0].get('Config',{}).get('Labels') or {}),**self.labels}
            args=['run','--detach','--pull=never','--name',self.name,'--network','none','--read-only','--user','100:101','--memory','2g','--cpus','1','--pids-limit','256','--entrypoint','/bin/sleep']
            for path,options in TMPFS.items():args+=['--tmpfs',path+':'+options]
            for k,v in self.labels.items():args+=['--label',k+'='+v]
            self.phase='target-create'
            self.cid=self.docker(*args,self.image_id,'infinity').stdout.decode().strip()
            if not re.fullmatch('[a-f0-9]{64}',self.cid):raise RuntimeError('4427 physical target ID invalid')
            with (self.root/'source-config.tar').open('rb') as data:self.target(['tar','-C','/','-xf','-','--no-same-owner'],input_file=data)
            with (self.root/'source-basebackup.tar').open('rb') as data:self.target(['tar','-C',DATA,'-xf','-','--no-same-owner'],input_file=data)
            self.target(['test','-s','/etc/postgresql-custom/pgsodium_root.key'])
            with tarfile.open(self.root/'source-config.tar','r:') as archive:
                original_key=archive.extractfile('etc/postgresql-custom/pgsodium_root.key').read()
            if self.target(['sha256sum','/etc/postgresql-custom/pgsodium_root.key']).stdout.decode().split()[0]!=hashlib.sha256(original_key).hexdigest():raise RuntimeError('4427 physical original root-key copy differs')
            del original_key
            self.target(['pg_verifybackup','--exit-on-error',DATA])
            self.original_backup_verified=True
            self.start(preparation=True)
            self.source_facts=facts;self.source_cron=cron_fingerprint(source_cron)
            target_health=json.loads(self.sql(SOURCE_HEALTH_SQL,'supabase_admin'))
            if target_health!=permission.before_health:raise RuntimeError('4427 physical complete roles/grants/policies/functions/owners differ after recovery')
            self.full_capability_fingerprint=target_health
            if cron_fingerprint(validate_cron(json.loads(self.sql(CRON_SQL,'supabase_admin'))))!=self.source_cron:
                raise RuntimeError('4427 physical restored cron capability/data differs')
            self.sql(CANARY_CREATE_SQL,'supabase_admin')
            if self.sql(CANARY_CHECK_SQL,'supabase_admin').strip()!='t':raise RuntimeError('4427 physical key-derived canary failed')
            return self
        except Exception as original:
            try:self.close()
            except Exception as cleanup:
                print(json.dumps(failure_receipt(cleanup,'physical-open-cleanup',self.events),sort_keys=True),file=sys.stderr)
            raise original

    def admit_window(self,preparation=False):
        self.budget_check()
        second=time.time()%60
        earliest,latest=(5,8) if preparation else (5,40)
        if not earliest<=second<=latest:
            wait=(65-second) if second>latest else (5-second)
            if wait>60 or time.monotonic()-self.started+wait>self.budget:raise RuntimeError('4427 physical safe startup window unavailable')
            before=time.monotonic();time.sleep(wait);self.window_wait_seconds+=time.monotonic()-before
        if not earliest<=time.time()%60<=latest:raise RuntimeError('4427 physical safe startup admission missed')
        return time.time(),time.monotonic()

    def start(self,preparation=False):
        self.start_wall,self.start_mono=self.admit_window(preparation)
        self.running=True;self.start_number+=1
        self.phase='target-preparation' if preparation else 'target-trial'
        self.start_kind='preparation' if preparation else 'baseline-trial'
        self.target(['pg_ctl','-D','/etc/postgresql','-l','/var/log/postgresql/4427.log','-w','-t','10','start'])
        self.guard()
        if self.sql('select pg_is_in_recovery();','supabase_admin').strip()!='f':raise RuntimeError('4427 physical target not normal primary')
        self.cron_at_start=validate_cron(json.loads(self.sql(CRON_SQL,'supabase_admin')))
        scheduler_start=datetime.datetime.fromisoformat(self.cron_at_start['schedulers'][0][1]).timestamp()
        if scheduler_start<self.start_wall-.25 or scheduler_start>time.time():raise RuntimeError('4427 physical scheduler startup identity/time differs')
        server_now=float(self.sql('select extract(epoch from clock_timestamp());','supabase_admin'))
        if abs(time.time()-server_now)>.25:raise RuntimeError('4427 physical target wall clock differs')
        emit(self.events,{'owned_server_started':True,'restart':self.start_number,'kind':self.start_kind,'wall_start':self.start_wall,'monotonic_start':self.start_mono,'scheduler_identity':self.cron_at_start['schedulers'][0],'cron_fingerprint_sha256':hashlib.sha256(json.dumps(cron_fingerprint(self.cron_at_start),sort_keys=True).encode()).hexdigest(),'canonical_sha256':self.baseline['sha256'] if self.sealed else None})

    def stop(self,check=True):
        if not self.running:return
        error=None
        try:
            if check:
                self.guard();after=validate_cron(json.loads(self.sql(CRON_SQL,'supabase_admin')))
                if after!=self.cron_at_start:raise RuntimeError('4427 physical scheduler identity/activity/job data changed')
        except Exception as caught:error=caught
        result=self.target(['pg_ctl','-D','/etc/postgresql','-w','-t','10','-m','smart','stop'],allowed_failure=True)
        self.running=False
        if check:
            try:minute_guard(self.start_wall,self.start_mono,time.time(),time.monotonic())
            except Exception as caught:error=error or caught
        if result.returncode or self.target(['test','!','-e',DATA+'/postmaster.pid'],allowed_failure=True).returncode:
            raise RuntimeError('4427 physical owned graceful-stop/absence failed')
        if self.target(['pg_ctl','-D','/etc/postgresql','status'],allowed_failure=True).returncode!=3:
            raise RuntimeError('4427 physical stopped server status not proven')
        control=self.target(['pg_controldata',DATA]).stdout.decode()
        if re.search(r'^Database cluster state:\s+shut down$',control,re.M) is None:
            raise RuntimeError('4427 physical canonical cluster not cleanly shut down')
        if check:
            try:minute_guard(self.start_wall,self.start_mono,time.time(),time.monotonic())
            except Exception as caught:error=error or caught
        emit(self.events,{'owned_server_stopped':True,'restart':self.start_number,'kind':self.start_kind,'pid_absent':True,'clean_shutdown':True,'minute_window_qualified':check and error is None,'wall_start':self.start_wall,'wall_end':time.time(),'elapsed_active':time.monotonic()-self.start_mono,'scheduler_identity':getattr(self,'cron_at_start',{}).get('schedulers',[]),'canonical_sha256':self.baseline['sha256'] if self.sealed else None})
        if error:raise error

    def seal(self):
        if self.sql(CANARY_CHECK_SQL,'supabase_admin').strip()!='t':raise RuntimeError('4427 physical canary failed before seal')
        self.stop()
        archive=self.root/'sealed-canonical.tar'
        with os.fdopen(os.open(archive,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600),'wb') as out:self.target(['tar','--numeric-owner','-C',DATA,'-cf','-','.'],output_file=out)
        self.baseline=validate_tar(archive,'sealed');self.sealed=True
        # Original basebackup manifest was checked before recovery. It is NOT a
        # verification claim for this changed, cleanly shut down canonical image.
        return self.baseline

    def begin_trial(self):
        if not self.sealed or self.running:raise RuntimeError('4427 physical reset requires stopped sealed owned target')
        self.target(['test','!','-e',DATA+'/postmaster.pid'])
        self.target(['find',DATA,'-mindepth','1','-delete'])
        archive=self.root/'sealed-canonical.tar'
        with archive.open('rb') as stream:digest=hashlib.file_digest(stream,'sha256').hexdigest()
        if digest!=self.baseline['sha256']:raise RuntimeError('4427 physical immutable baseline drift')
        with archive.open('rb') as data:self.target(['tar','-C',DATA,'-xf','-','--no-same-owner'],input_file=data)
        self.start()
        if self.sql(CANARY_CHECK_SQL,'supabase_admin').strip()!='t':raise RuntimeError('4427 physical copied root-key decrypt failed after reset')
        return {'baseline_sha256':self.baseline['sha256'],'start_wall':self.start_wall}

    def end_trial(self):self.stop()

    def projected_matrix_check(self,active_seconds):
        # Exclude ONLY observed explicit admission waits from measured per-restart
        # active cost. All actual wait remains consumed in the35-minute budget.
        import math
        if not isinstance(active_seconds,list) or len(active_seconds)!=2 or any(isinstance(v,bool) or not isinstance(v,(float,int)) or not math.isfinite(v) or v<=0 for v in active_seconds):
            raise RuntimeError('4427 physical measured active calibration cost invalid')
        projected=374*max(active_seconds)*(60/35)+60
        if projected>self.budget-(time.monotonic()-self.started):raise RuntimeError('4427 physical calibrated374-run cost exceeds remaining bound')
        return projected

    def close(self):
        self.cleanup_mode=True
        if self.cid:
            state=self.custody(allow_stopped=True)
            try:
                if state['running']:
                    if self.running:self.stop(check=False)
                else:
                    self.running=False
                    emit(self.events,{'owned_keeper_not_running':True,'status':state['status'],'oom_killed':state['oom_killed'],'graceful_pg_stop':False})
            finally:
                state=self.custody(allow_stopped=True)
                if state['running']:self.docker('stop','--time','10',self.cid)
                self.custody(allow_stopped=True)
                self.docker('rm',self.cid)
                if self.docker('ps','-aq','--filter','name=^/'+self.name+'$').stdout.strip():raise RuntimeError('4427 physical owned target removal absence failed')
                emit(self.events,{'owned_container_removed':self.cid,'absent':True});self.cid=None;self.running=False
        if self.root is not None:
            if getattr(self.source,'hba_restore_failed',False):
                self.source.diagnostic('source-hba-restoration-failed',private_recovery_path=str(self.root))
            else:
                shutil.rmtree(self.root);self.root=None
