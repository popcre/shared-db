-- #4634: shape and runtime behavior, isolated in a rolled-back transaction.
begin;
do $test$
declare v_id bigint;
begin
  if (select count(*) from information_schema.columns where table_schema='dflow_prod'
      and table_name='vendor_wechat_identity') <> 12 then
    raise exception 'expected twelve sandbox-compatible columns';
  end if;
  if not has_table_privilege('designflow_prod_backend_runtime',
      'dflow_prod.vendor_wechat_identity','SELECT')
     or not has_table_privilege('designflow_prod_backend_runtime',
      'dflow_prod.vendor_wechat_identity','INSERT')
     or not has_table_privilege('designflow_prod_backend_runtime',
      'dflow_prod.vendor_wechat_identity','UPDATE') then
    raise exception 'backend runtime permissions missing';
  end if;
end $test$;
set local role designflow_prod_backend_runtime;
do $test$
declare v_id bigint;
begin
  insert into dflow_prod.vendor_wechat_identity(wechat_key,openid)
    values ('openid:contract-4634','contract-4634') returning id into v_id;
  if not exists(select 1 from dflow_prod.vendor_wechat_identity where id=v_id and status='pending') then
    raise exception 'backend SELECT/defaults failed';
  end if;
  update dflow_prod.vendor_wechat_identity set status='approved',vendor_id=4634 where id=v_id;
  begin
    insert into dflow_prod.vendor_wechat_identity(wechat_key,openid)
      values ('openid:contract-4634','contract-4634');
    raise exception 'duplicate wechat_key accepted';
  exception when unique_violation then null; end;
  begin
    insert into dflow_prod.vendor_wechat_identity(wechat_key,openid,status)
      values ('openid:contract-4634-invalid','contract-4634-invalid','invalid');
    raise exception 'invalid status accepted';
  exception when check_violation then null; end;
  begin
    insert into dflow_prod.vendor_wechat_identity(wechat_key,openid,status)
      values ('openid:contract-4634-unlinked','contract-4634-unlinked','approved');
    raise exception 'unlinked approved identity accepted';
  exception when check_violation then null; end;
  begin
    insert into dflow_prod.vendor_wechat_identity(wechat_key,openid)
      values ('wrong-key','contract-4634-key');
    raise exception 'mismatched wechat_key accepted';
  exception when check_violation then null; end;
  insert into dflow_prod.vendor_wechat_identity(wechat_key,unionid,openid)
    values ('union-contract-4634','union-contract-4634','contract-4634-union');
end $test$;
rollback;
