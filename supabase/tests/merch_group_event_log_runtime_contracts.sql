-- #6173: rollback-only runtime/RLS regression; no silent missing-role skip.
begin;
do $test$
declare v_id uuid; v_count integer; v_column text;
begin
  if not exists (select 1 from pg_class where oid='coldlion.merch_group_event_log'::regclass
                 and relrowsecurity) then
    raise exception '#6173: event journal must enforce RLS';
  end if;
  if exists (select 1 from pg_class c cross join lateral aclexplode(c.relacl) a
             where c.oid='coldlion.merch_group_event_log'::regclass
               and a.grantee='designflow_prod_backend_runtime'::regrole)
     or exists (select 1 from pg_attribute c cross join lateral aclexplode(c.attacl) a
                where c.attrelid='coldlion.merch_group_event_log'::regclass
                  and a.grantee='designflow_prod_backend_runtime'::regrole) then
    raise exception '#6173: runtime must not have direct ACLs';
  end if;
  -- SET ROLE failure is a test failure, never an unexercised success.
  set local role designflow_prod_backend_runtime;
  if not row_security_active('coldlion.merch_group_event_log') then
    raise exception '#6173: runtime bypasses RLS';
  end if;
  insert into coldlion.merch_group_event_log
    (event_id, action, company, division, mg_type_code, mg_code, payload, status)
  values ('contract-6173-' || gen_random_uuid(), 'updated', 'test', 'test', 'MG05', 'test', '{}', 'received')
  returning id into v_id;
  select count(*) into v_count from coldlion.merch_group_event_log where id=v_id;
  if v_count<>1 then raise exception '#6173: runtime cannot read inserted event'; end if;
  update coldlion.merch_group_event_log
    set status='applied', reason='contract', rows_touched='[]', processed_at=now()
    where id=v_id;
  get diagnostics v_count = row_count;
  if v_count<>1 then raise exception '#6173: runtime cannot update processing outcome'; end if;
  -- Every evidence column must reject UPDATE, even when assigning its own value.
  foreach v_column in array array['id','event_id','received_at','occurred_at','action',
      'company','division','mg_type_code','mg_code','mg_category','previous_key','payload'] loop
    begin
      execute format('update coldlion.merch_group_event_log set %I=%I where id=$1', v_column, v_column) using v_id;
      raise exception '#6173: runtime rewrote evidence column %', v_column;
    exception when insufficient_privilege then null;
    end;
  end loop;
  if has_table_privilege(current_user, 'coldlion.merch_group_event_log', 'DELETE') then
    raise exception '#6173: runtime has DELETE';
  end if;
  begin
    delete from coldlion.merch_group_event_log where id=v_id;
    raise exception '#6173: runtime DELETE was accepted';
  exception when insufficient_privilege then null;
  end;
  reset role;
end
$test$;
rollback;
