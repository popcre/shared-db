-- Issue #4430 packaging access InitPlan contracts.
-- LOCAL THROWAWAY DATABASE ONLY. Never execute against production.
do $rls4430_contracts$
declare
  v_bad int;
begin
  select count(*) into v_bad
  from pg_policies
  where schemaname = 'core' and tablename = 'packaging_type'
    and policyname in ('admin_or_packaging_manager_write','shared_read')
    and not (coalesce(qual, '') like '%( SELECT app.has_role(%');
  if v_bad <> 0 then
    raise exception 'rls4430: % packaging policies lack the wrapped has_role form', v_bad;
  end if;
end
$rls4430_contracts$;
