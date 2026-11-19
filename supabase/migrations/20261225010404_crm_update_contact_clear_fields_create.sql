-- api.crm_update_contact: the approved clear-field shape, delivered as a
-- single CREATE OR REPLACE with no retired-name references (popcrm-web #39).
-- Claim: popcre/shared-db#6820 (CRM audit fixes batch; folded, comment
-- 7015729095). Version 20261225010404 reserved atomically (refs/db-claims).
--
-- WHY THIS SHAPE: the batch history (20261223010101 -> 20261225010001 ->
-- 20261225010003 -> 20261225010104 -> 20261225010304) cannot promote —
-- production's ledger never recorded the legacy-overload drop that every
-- restoration marker and derived-from declaration in that chain names, so the
-- production preflight refuses each of them ("history shows no recorded prior
-- drop", run 44577050283). This file carries the identical approved function
-- body with NO marker and NO derivation: a plain create-or-replace of a name
-- production still has (the 15-argument pre-batch overload). The companion
-- migration 20261225010405 drops that overload once this re-creation has made
-- the name live again, so the create/drop pair needs no restoration marker on
-- any database.
--
-- derived-from: none

CREATE OR REPLACE FUNCTION api.crm_update_contact(p_contact_id uuid, p_first_name text DEFAULT NULL::text, p_last_name text DEFAULT NULL::text, p_full_name text DEFAULT NULL::text, p_email text DEFAULT NULL::text, p_phone text DEFAULT NULL::text, p_job_title text DEFAULT NULL::text, p_company_id uuid DEFAULT NULL::uuid, p_crm_department_id uuid DEFAULT NULL::uuid, p_contact_type text DEFAULT NULL::text, p_scope text DEFAULT NULL::text, p_clear_company boolean DEFAULT false, p_clear_crm_department boolean DEFAULT false, p_clear_contact_type boolean DEFAULT false, p_clear_scope boolean DEFAULT false, p_clear_email boolean DEFAULT false, p_clear_phone boolean DEFAULT false, p_clear_job_title boolean DEFAULT false)
 RETURNS core.contact
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'core', 'crm', 'public'
AS $function$
declare
  result core.contact;
  v_dept_company uuid;
  -- Same normalization as api.crm_create_contact (20261106144600): trim (and
  -- for email lowercase) before storing, so both RPCs write identical shapes.
  v_email text := nullif(lower(btrim(coalesce(p_email, ''))), '');
  v_phone text := nullif(btrim(coalesce(p_phone, '')), '');
  v_title text := nullif(btrim(coalesce(p_job_title, '')), '');
begin
  if not app.has_app_access('crm') then
    raise exception 'crm: not authorized' using errcode = 'insufficient_privilege';
  end if;

  if p_crm_department_id is not null then
    select d.company_id into v_dept_company
    from crm.department d
    where d.id = p_crm_department_id;

    if v_dept_company is null then
      raise exception 'crm: department % not found', p_crm_department_id using errcode = 'no_data_found';
    end if;

    if p_company_id is not null and p_company_id <> v_dept_company then
      raise exception 'crm: department % belongs to a different company', p_crm_department_id using errcode = 'foreign_key_violation';
    end if;
  end if;

  -- Precedence: a p_clear_* flag beats a same-call value. Passing both is
  -- defined as "clear" (the value is ignored), which also keeps the
  -- auto-attach trigger from ever seeing an address on a clearing save.
  update core.contact ct
  set
    first_name = coalesce(p_first_name, ct.first_name),
    last_name  = coalesce(p_last_name, ct.last_name),
    full_name  = coalesce(
      p_full_name,
      nullif(trim(concat_ws(' ', coalesce(p_first_name, ct.first_name), coalesce(p_last_name, ct.last_name))), ''),
      ct.full_name
    ),
    email      = case when p_clear_email then null else coalesce(v_email::extensions.citext, ct.email) end,
    phone      = case when p_clear_phone then null else coalesce(v_phone, ct.phone) end,
    title      = case when p_clear_job_title then null else coalesce(v_title, ct.title) end
  where ct.id = p_contact_id
  returning ct.* into result;

  if not found then
    raise exception 'crm: contact % not found', p_contact_id using errcode = 'no_data_found';
  end if;

  if p_clear_company then
    delete from core.contact_company cc
    where cc.contact_id = p_contact_id
      and cc.relationship_type = 'buyer';
  end if;

  if p_company_id is not null then
    update core.contact_company cc
    set is_primary = false
    where cc.contact_id = p_contact_id
      and cc.relationship_type = 'buyer'
      and cc.company_id <> p_company_id;

    insert into core.contact_company (
      contact_id,
      company_id,
      relationship_type,
      contact_type,
      scope,
      crm_department_id,
      is_primary
    )
    values (
      p_contact_id,
      p_company_id,
      'buyer',
      case when p_clear_contact_type then null else p_contact_type end,
      case
        when p_clear_scope then null
        when p_scope is not null then p_scope
        when p_crm_department_id is not null then 'DEPARTMENT'
        else null
      end,
      case when p_clear_crm_department then null else p_crm_department_id end,
      true
    )
    on conflict (contact_id, company_id, relationship_type) do update
    set
      contact_type = case
        when p_clear_contact_type then null
        when excluded.contact_type is not null then excluded.contact_type
        else core.contact_company.contact_type
      end,
      scope = case
        when p_clear_scope then null
        when p_scope is not null then p_scope
        when p_crm_department_id is not null then 'DEPARTMENT'
        when p_clear_crm_department and core.contact_company.scope = 'DEPARTMENT' then 'COMPANY_WIDE'
        else core.contact_company.scope
      end,
      crm_department_id = case
        when p_clear_crm_department then null
        when excluded.crm_department_id is not null then excluded.crm_department_id
        else core.contact_company.crm_department_id
      end,
      is_primary = true;
  elsif not p_clear_company and (
    p_clear_crm_department
    or p_clear_contact_type
    or p_clear_scope
    or p_crm_department_id is not null
    or p_contact_type is not null
    or p_scope is not null
  ) then
    update core.contact_company cc
    set
      contact_type = case
        when p_clear_contact_type then null
        when p_contact_type is not null then p_contact_type
        else cc.contact_type
      end,
      scope = case
        when p_clear_scope then null
        when p_scope is not null then p_scope
        when p_crm_department_id is not null then 'DEPARTMENT'
        when p_clear_crm_department and cc.scope = 'DEPARTMENT' then 'COMPANY_WIDE'
        else cc.scope
      end,
      crm_department_id = case
        when p_clear_crm_department then null
        when p_crm_department_id is not null then p_crm_department_id
        else cc.crm_department_id
      end
    where cc.id = (
      select x.id
      from core.contact_company x
      where x.contact_id = p_contact_id
        and x.relationship_type = 'buyer'
      order by x.is_primary desc nulls last, x.id
      limit 1
    );

    -- A department-only call for a contact with no buyer relation row used to
    -- land here, match nothing, and still report success. Create the row from
    -- the department's own company, the same inherit rule the flyout applies.
    -- (p_contact_type-only / p_scope-only calls on a relation-less contact stay
    -- intentional no-ops: there is no relation row to carry them.)
    if not found and p_crm_department_id is not null then
      insert into core.contact_company (
        contact_id,
        company_id,
        relationship_type,
        contact_type,
        scope,
        crm_department_id,
        is_primary
      )
      values (
        p_contact_id,
        v_dept_company,
        'buyer',
        case when p_clear_contact_type then null else p_contact_type end,
        case
          when p_clear_scope then null
          when p_scope is not null then p_scope
          else 'DEPARTMENT'
        end,
        case when p_clear_crm_department then null else p_crm_department_id end,
        not exists (
          select 1 from core.contact_company x
          where x.contact_id = p_contact_id
            and x.relationship_type = 'buyer'
            and x.is_primary
        )
      );
    end if;
  end if;

  return result;
end;
$function$;

revoke all on function api.crm_update_contact(uuid, text, text, text, text, text, text, uuid, uuid, text, text, boolean, boolean, boolean, boolean, boolean, boolean, boolean) from public;
revoke all on function api.crm_update_contact(uuid, text, text, text, text, text, text, uuid, uuid, text, text, boolean, boolean, boolean, boolean, boolean, boolean, boolean) from anon;
grant execute on function api.crm_update_contact(uuid, text, text, text, text, text, text, uuid, uuid, text, text, boolean, boolean, boolean, boolean, boolean, boolean, boolean) to authenticated;

comment on function api.crm_update_contact(uuid, text, text, text, text, text, text, uuid, uuid, text, text, boolean, boolean, boolean, boolean, boolean, boolean, boolean) is
  'CRM contact update. Precedence: p_clear_email / p_clear_phone / p_clear_job_title beat a same-call value (both = clear). Values are normalized like crm_create_contact (email lowercased+trimmed, phone/title trimmed).';

drop function if exists api.crm_update_contact(
  uuid, text, text, text, text, text, text, uuid, uuid, text, text,
  boolean, boolean, boolean, boolean
);
