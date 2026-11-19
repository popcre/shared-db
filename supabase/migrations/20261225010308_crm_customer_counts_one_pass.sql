-- Promotable re-issue of 20261225010004_crm_customer_counts_one_pass.sql (CRM audit batch, popcrm-web #39/#57/#68/#69/#40).
-- Claim: popcre/shared-db#6820 (CRM audit fixes batch); re-issue chain claim
-- filed alongside this PR. Version reserved atomically (refs/db-claims).
--
-- WHY RE-ISSUED: the original batch rehearsed on preview outside the dispatch
-- lane, leaving orphaned preview-ledger rows that no recovery or reconciliation
-- flow can clear (no dispatched run exists to prove), so neither the batch nor
-- any derived migration can pass the production base guard. This PR reverts the
-- whole unproductive chain from main and re-authors its content under fresh
-- versions, so every lane applies it normally.
--
-- CONTENT: byte-identical to 20261225010004_crm_customer_counts_one_pass.sql. Supersedes the shapes from 20261223010101/10102 (also reverted here) with this one-pass definition.
--
-- reverted-in-this-pr: 20261225010004_crm_customer_counts_one_pass.sql

create or replace function api.crm_customer_counts()
returns table (
  customer_id uuid,
  contact_count bigint,
  program_count bigint
)
language plpgsql
stable
security definer
set search_path = 'app', 'core', 'crm', 'public'
as $$
begin
  if not app.has_app_access('crm') then
    raise exception 'crm: not authorized' using errcode = 'insufficient_privilege';
  end if;

  return query
  with contact_top as (
    select ct.id as contact_id, t.company_id as company_id
    from core.contact ct
    left join lateral (
      select x.company_id
      from core.contact_company x
      where x.contact_id = ct.id
      order by x.is_primary desc nulls last, x.id
      limit 1
    ) t on true
    where not exists (
      select 1 from crm.contact_ext xe
      where xe.contact_id = ct.id and xe.archived_at is not null
    )
  ),
  contacts_per_customer as (
    select company_id, count(*) as n from contact_top group by company_id
  ),
  programs_per_customer as (
    select o.company_id, count(*) as n
    from crm.opportunity o
    where coalesce(o.status, '') <> 'archived'
    group by o.company_id
  )
  select c.id,
         coalesce(cp.n, 0),
         coalesce(pp.n, 0)
  from core.customer c
  left join contacts_per_customer cp on cp.company_id = c.id
  left join programs_per_customer pp on pp.company_id = c.id
  where not exists (
    select 1 from crm.customer_ext xe
    where xe.customer_id = c.id and xe.archived_at is not null
  );
end;
$$;

revoke all on function api.crm_customer_counts() from public;
revoke all on function api.crm_customer_counts() from anon;
revoke all on function api.crm_customer_counts() from authenticated;
grant execute on function api.crm_customer_counts() to authenticated;

comment on function api.crm_customer_counts() is
  'CRM per-customer counts, one lateral pass. contact_count mirrors api.crm_contact_list exactly: a contact counts for the customer of its TOP core.contact_company row (is_primary desc, id, any relationship_type), excluding CRM-archived contacts; program_count = non-archived crm.opportunity rows. One row per non-archived customer. Hard-gated on app.has_app_access(''crm'').';
