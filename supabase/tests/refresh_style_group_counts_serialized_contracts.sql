begin;

-- shared-db#4174: public.refresh_style_group_counts_serialized is service_role-only,
-- uses a bounded lock_timeout, returns 0 for empty/null input, and delegates to
-- refresh_style_group_counts_batch. Rolled back.
do $$
declare
  v_cfg text[];
begin
  if has_function_privilege('authenticated', 'public.refresh_style_group_counts_serialized(uuid[])', 'execute')
     or has_function_privilege('anon', 'public.refresh_style_group_counts_serialized(uuid[])', 'execute') then
    raise exception 'refresh_style_group_counts_serialized must not be executable by anon/authenticated';
  end if;
  if not has_function_privilege('service_role', 'public.refresh_style_group_counts_serialized(uuid[])', 'execute') then
    raise exception 'service_role must execute refresh_style_group_counts_serialized';
  end if;
  select proconfig into v_cfg from pg_proc
   where oid = 'public.refresh_style_group_counts_serialized(uuid[])'::regprocedure;
  if not ('lock_timeout=5s' = any(v_cfg)) then
    raise exception 'lock_timeout must be 5s, got %', v_cfg;
  end if;
  if public.refresh_style_group_counts_serialized('{}'::uuid[]) <> 0
     or public.refresh_style_group_counts_serialized(array[null]::uuid[]) <> 0
     or public.refresh_style_group_counts_serialized(null) <> 0 then
    raise exception 'empty input must return 0';
  end if;
  -- An id with no style group updates nothing.
  if public.refresh_style_group_counts_serialized(array[gen_random_uuid(), gen_random_uuid()]) <> 0 then
    raise exception 'unknown ids must update nothing';
  end if;
end;
$$;

rollback;
