-- Regression coverage for 20261225131100 and the DesignFlow backend upload.
begin;

do $contract$
declare
  grants_role constant text := 'designflow_prod_backend_grants';
  fixture_factory_id uuid;
  fixture_profile_id uuid;
  plm_notice uuid;
  other_notice uuid;
  actual text[];
begin
  select array_agg(format('%s.%s:%s', n.nspname, c.relname, acl.privilege_type)
                   order by n.nspname, c.relname, acl.privilege_type)
    into actual
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    cross join lateral aclexplode(c.relacl) acl
   where c.oid in ('core.factory_approval'::regclass, 'core.factory_approval_form'::regclass,
                   'app.notification'::regclass)
     and acl.grantee = grants_role::regrole;
  if actual is distinct from array['app.notification:SELECT', 'core.factory_approval:INSERT',
                                   'core.factory_approval:SELECT', 'core.factory_approval:UPDATE',
                                   'core.factory_approval_form:SELECT'] then
    raise exception 'Unexpected approval table grants: %', actual;
  end if;

  select array_agg(format('%s.%s.%s:%s', n.nspname, c.relname, a.attname, acl.privilege_type)
                   order by n.nspname, c.relname, a.attname, acl.privilege_type)
    into actual
    from pg_attribute a
    join pg_class c on c.oid = a.attrelid
    join pg_namespace n on n.oid = c.relnamespace
    cross join lateral aclexplode(a.attacl) acl
   where c.oid in ('core.factory_approval'::regclass, 'core.factory_approval_form'::regclass,
                   'app.notification'::regclass)
     and acl.grantee = grants_role::regrole;
  if actual is distinct from array[
      'app.notification.read_at:UPDATE', 'core.factory_approval_form.factory_id:INSERT',
      'core.factory_approval_form.file_name:INSERT', 'core.factory_approval_form.program:INSERT',
      'core.factory_approval_form.storage_path:INSERT', 'core.factory_approval_form.uploaded_by:INSERT'] then
    raise exception 'Unexpected approval column grants: %', actual;
  end if;

  select array_agg(format('%s.%s:%s', schemaname, tablename, cmd)
                   order by schemaname, tablename, cmd)
    into actual
    from pg_policies
   where grants_role::name = any(roles)
     and (schemaname, tablename) in (('core', 'factory_approval'), ('core', 'factory_approval_form'),
                                     ('app', 'notification'));
  if actual is distinct from array['app.notification:SELECT', 'app.notification:UPDATE',
                                   'core.factory_approval:INSERT', 'core.factory_approval:SELECT',
                                   'core.factory_approval:UPDATE', 'core.factory_approval_form:INSERT',
                                   'core.factory_approval_form:SELECT'] then
    raise exception 'Unexpected approval policies: %', actual;
  end if;

  if not exists (
    select 1 from pg_policies
     where schemaname = 'core' and tablename = 'factory_approval_form'
       and grants_role::name = any(roles) and cmd = 'INSERT'
       and with_check = '((storage_bucket = ''factory-approval-forms''::text) AND (ocr_status = ''pending''::text))'
  ) then
    raise exception 'Backend upload policy must require the forms bucket and pending OCR';
  end if;

  insert into core.factory (name, code) values ('Approval grant contract', gen_random_uuid()::text)
    returning id into fixture_factory_id;
  insert into app.profile (display_name) values ('Approval grant contract') returning id into fixture_profile_id;
  insert into app.notification (profile_id, app, title)
    values (fixture_profile_id, 'plm', 'Approval grant contract') returning id into plm_notice;
  insert into app.notification (profile_id, app, title)
    values (fixture_profile_id, 'crm', 'Approval grant contract') returning id into other_notice;

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '{}', true);
  set local role designflow_prod_backend_runtime;

  insert into core.factory_approval (factory_id, program, is_approved)
    values (fixture_factory_id, 'walmart', true)
    on conflict (factory_id, program) do update set is_approved = excluded.is_approved;
  if not found then
    raise exception 'Backend cannot save an existing approval';
  end if;

  insert into core.factory_approval_form (factory_id, program, storage_path, file_name, uploaded_by)
    values (fixture_factory_id, 'disney', fixture_factory_id || '/linked.pdf', 'linked.pdf', fixture_profile_id),
           (fixture_factory_id, 'disney', fixture_factory_id || '/unlinked.pdf', 'unlinked.pdf', null);
  insert into core.factory_approval_form (factory_id, program, storage_path, file_name)
    values (fixture_factory_id, 'disney', fixture_factory_id || '/default.pdf', 'default.pdf');

  begin
    update core.factory_approval_form set file_name = 'changed.pdf'
      where storage_path = fixture_factory_id || '/linked.pdf';
    raise exception 'Backend can update upload history';
  exception when insufficient_privilege then null;
  end;

  update app.notification set read_at = now() where id = plm_notice returning id into plm_notice;
  if not found then
    raise exception 'Backend cannot mark a PLM notification as read';
  end if;

  update app.notification set read_at = now() where id = other_notice;
  if found then
    raise exception 'Backend can mark a non-PLM notification as read';
  end if;

  begin
    update app.notification set body = 'changed' where id = plm_notice;
    raise exception 'Backend can change notification body';
  exception when insufficient_privilege then null;
  end;
  reset role;
end
$contract$;

rollback;
