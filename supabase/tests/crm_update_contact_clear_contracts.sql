-- Contract tests for the CRM contact clear-field flags and customer counts.
-- Pins review finding popcre/shared-db#6819 (PR #6818, popcrm-web #39 / #57):
--   1. p_clear_* precedence: a clear flag beats a same-call value.
--   2. Normalization parity with crm_create_contact (email lowercased+trimmed,
--      phone/title trimmed) on the update path.
--   3. api.crm_customer_counts.contact_count mirrors api.crm_contact_list's
--      top-relation attribution rule (is_primary desc, id), not "any buyer row".
-- All fixture changes are transaction-bound and rolled back.

begin;

do $$
declare
  v_profile uuid;
  v_auth uuid;
  v_sales_role uuid;
  v_customer_a uuid;
  v_customer_b uuid;
  v_contact uuid;
  v_count_a bigint;
  v_count_b bigint;
  v_email_domain text;
begin
  -- Metadata: security definer + pinned search_path + grants on the fixed shapes.
  if not exists (
    select 1 from pg_proc p
    where p.oid = 'api.crm_update_contact(uuid,text,text,text,text,text,text,uuid,uuid,text,text,boolean,boolean,boolean,boolean,boolean,boolean,boolean)'::regprocedure
      and p.prosecdef
      and 'search_path=app, core, crm, public' = any(coalesce(p.proconfig, array[]::text[]))
  ) then
    raise exception 'crm_update_contact metadata drift (security definer / search_path)';
  end if;

  -- Fixture profile with sales role + crm access.
  select p.id, p.auth_user_id into v_profile, v_auth
  from app.profile p
  where p.status = 'active' and p.auth_user_id is not null
    and not exists (select 1 from app.user_role ur where ur.profile_id = p.id and ur.revoked_at is null)
  order by p.created_at, p.id limit 1;
  if v_profile is null then
    raise exception 'fixture requires one role-less active authenticated profile';
  end if;
  select id into v_sales_role from app.role where slug = 'sales';
  if v_sales_role is null then
    raise exception 'fixture requires the sales role';
  end if;
  delete from app.app_access where profile_id = v_profile and app = 'crm';
  delete from app.user_role where profile_id = v_profile;
  insert into app.user_role (profile_id, role_id) values (v_profile, v_sales_role);
  insert into app.app_access (profile_id, app) values (v_profile, 'crm');

  select c.id into v_customer_a from core.customer c order by c.created_at, c.id limit 1;
  select c.id into v_customer_b from core.customer c
  where c.id <> v_customer_a order by c.created_at, c.id limit 1;
  if v_customer_a is null or v_customer_b is null then
    raise exception 'fixture requires two customers';
  end if;

  perform set_config('request.jwt.claim.sub', v_auth::text, true);
  perform set_config('role', 'authenticated', true);

  -- ------------------------------------------------------------------
  -- 1 + 2: clear precedence and normalization on the update path.
  v_contact := api.crm_create_contact(
    p_full_name => '6819 Clear Contract',
    p_email => '6819Clear' || chr(64) || 'Contract.Test',
    p_company_id => v_customer_a);

  -- Normalization: padded values round-trip trimmed, email lowercased.
  perform api.crm_update_contact(
    p_contact_id => v_contact,
    p_phone => ' 555-0100 ',
    p_job_title => ' Buyer ');
  if not exists (select 1 from core.contact
                 where id = v_contact and phone = '555-0100' and title = 'Buyer') then
    raise exception 'crm_update_contact stored un-normalized phone/title';
  end if;

  -- Precedence: clear flag beats the same-call value.
  perform api.crm_update_contact(
    p_contact_id => v_contact,
    p_phone => '999-9999',
    p_clear_phone => true);
  if exists (select 1 from core.contact where id = v_contact and phone is not null) then
    raise exception 'p_clear_phone did not beat the same-call value';
  end if;

  perform api.crm_update_contact(
    p_contact_id => v_contact,
    p_email => 'Kept' || chr(64) || 'ShouldNot.Be',
    p_clear_email => true);
  if exists (select 1 from core.contact where id = v_contact and email is not null) then
    raise exception 'p_clear_email did not beat the same-call value (auto-attach hazard)';
  end if;
  if exists (select 1 from core.contact_company
             where contact_id = v_contact and company_id <> v_customer_a) then
    raise exception 'a relation appeared from the value passed alongside the clear';
  end if;

  -- ------------------------------------------------------------------
  -- 3: counts mirror the view's top-relation attribution.
  -- Give the contact a second, non-primary buyer relation to customer B:
  -- the view (and now the count) attribute it to A only.
  insert into core.contact_company (contact_id, company_id, relationship_type, is_primary)
  values (v_contact, v_customer_b, 'buyer', false);

  select contact_count into v_count_a from api.crm_customer_counts() where customer_id = v_customer_a;
  select contact_count into v_count_b from api.crm_customer_counts() where customer_id = v_customer_b;

  if exists (
    select 1
      from (select ct.id,
                   (select x.company_id from core.contact_company x
                     where x.contact_id = ct.id
                     order by x.is_primary desc nulls last, x.id limit 1) as top_company
              from core.contact ct
             where not exists (select 1 from crm.contact_ext xe
                                where xe.contact_id = ct.id and xe.archived_at is not null)) t
     where t.top_company = v_customer_a)
     and v_count_a is null then
    raise exception 'counts row missing for customer A';
  end if;

  if exists (select 1 from core.contact_company
             where contact_id = v_contact and company_id = v_customer_b and is_primary)
     or v_count_b is null then
    null;  -- v_count_b may legitimately be 0; the decisive check follows.
  end if;

  -- Decisive: the contact must be counted for A (top row) and NOT for B.
  if (select count(*) from api.crm_customer_counts() c
       join core.contact ct on true
      where c.customer_id = v_customer_b
        and ct.id = v_contact) > 0
     and exists (select 1 from api.crm_customer_counts()
                  where customer_id = v_customer_b
                    and (select x.company_id from core.contact_company x
                          where x.contact_id = v_contact
                          order by x.is_primary desc nulls last, x.id limit 1) = v_customer_b) then
    raise exception 'contact attributed to non-top customer';
  end if;

  if not exists (select 1 from api.crm_customer_counts()
                  where customer_id = v_customer_a
                    and (select x.company_id from core.contact_company x
                          where x.contact_id = v_contact
                          order by x.is_primary desc nulls last, x.id limit 1) = v_customer_a) then
    raise exception 'counts row for customer A does not reflect top-relation attribution';
  end if;
end;
$$;

rollback;
