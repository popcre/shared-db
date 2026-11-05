-- #5696: installed structure/ACL/input contracts. No catalog data is changed.
begin;
do $test$
declare
  f pg_proc;
  item text;
begin
  select * into strict f from pg_proc
  where oid='public.dam_catalog_code_format_exists(text)'::regprocedure;
  if f.prosecdef or f.provolatile <> 's' then
    raise exception 'format reader must remain stable/security-invoker';
  end if;
  if has_function_privilege('anon',f.oid,'EXECUTE')
     or has_function_privilege('authenticated',f.oid,'EXECUTE')
     or not has_function_privilege('service_role',f.oid,'EXECUTE')
     or exists (select 1 from aclexplode(coalesce(f.proacl,acldefault('f',f.proowner)))
                where grantee=0 and privilege_type='EXECUTE') then
    raise exception 'format reader is restricted to the existing service-role contract';
  end if;
  if not exists (select 1 from pg_index where indexrelid='public.idx_style_groups_code_format'::regclass and indisvalid) then
    raise exception 'complete-format equality index is absent/invalid';
  end if;
  if not ('statement_timeout=1000ms'=any(f.proconfig)) then
    raise exception 'function timeout hint changed; outer deadline proof remains separately required';
  end if;
  foreach item in array array[null::text,'','AAAAAAA','9999999','AAA99','A9.*AAAA','A9AAAAĀ',repeat('A',64)||'9'] loop
    begin
      perform public.dam_catalog_code_format_exists(item);
      raise exception 'invalid format did not raise22023';
    exception when invalid_parameter_value then null;
    end;
  end loop;
end;
$test$;
rollback;
