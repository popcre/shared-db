begin;

-- shared-db#4168: get/set_sg_nas_password are service_role-only and round-trip
-- through Vault. Rolled back.
do $$
begin
  if has_function_privilege('authenticated', 'public.get_sg_nas_password()', 'execute')
     or has_function_privilege('anon', 'public.get_sg_nas_password()', 'execute')
     or has_function_privilege('authenticated', 'public.set_sg_nas_password(text)', 'execute')
     or has_function_privilege('anon', 'public.set_sg_nas_password(text)', 'execute') then
    raise exception 'sg nas password functions must not be executable by anon/authenticated';
  end if;
  if not has_function_privilege('service_role', 'public.get_sg_nas_password()', 'execute')
     or not has_function_privilege('service_role', 'public.set_sg_nas_password(text)', 'execute') then
    raise exception 'service_role must execute the sg nas password functions';
  end if;

  perform public.set_sg_nas_password('zz-test-4168-a');
  if public.get_sg_nas_password() <> 'zz-test-4168-a' then
    raise exception 'set then get did not round-trip';
  end if;
  perform public.set_sg_nas_password('zz-test-4168-b');
  if public.get_sg_nas_password() <> 'zz-test-4168-b' then
    raise exception 'replace did not round-trip';
  end if;
  if (select count(*) from vault.secrets where name = 'popdam_sg_nas_password') <> 1 then
    raise exception 'replace must keep exactly one vault secret';
  end if;
  perform public.set_sg_nas_password(null);
  if public.get_sg_nas_password() <> '' then
    raise exception 'clear must yield empty string';
  end if;
end;
$$;

rollback;
