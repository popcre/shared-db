begin;

-- u2giants/popdam3#185: a new @popcre.com sign-in gets app_access 'dam'; an outside
-- email gets only 'crm'. Runs the real trigger on auth.users, rolled back.
do $$
declare
  v_emp uuid := gen_random_uuid();
  v_out uuid := gen_random_uuid();
begin
  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data)
  values (v_emp, 'zz-signup-test-' || v_emp || '@popcre.com', '{}', '{}'),
         (v_out, 'zz-signup-test-' || v_out || '@example.com', '{}', '{}');

  if not exists (select 1 from app.app_access a join app.profile p on p.id = a.profile_id
                 where p.auth_user_id = v_emp and a.app = 'dam') then
    raise exception 'new @popcre.com user did not get dam access';
  end if;
  if exists (select 1 from app.app_access a join app.profile p on p.id = a.profile_id
             where p.auth_user_id = v_out and a.app = 'dam') then
    raise exception 'non-employee user was granted dam access';
  end if;
  if not exists (select 1 from app.app_access a join app.profile p on p.id = a.profile_id
                 where p.auth_user_id = v_out and a.app = 'crm') then
    raise exception 'crm grant regressed';
  end if;
end $$;

rollback;
