-- #4936: link CRM ingested email domains to the customer they belong to.
-- derived-from: 20260629034600
--
-- Owner (Albert Hazan, 2026-10-27): "they need to be linked" (CRM email
-- domains and customers). This supersedes the "no customer association"
-- contract of 20260629034600. It links only to EXISTING customers; nothing
-- here creates, promotes or source-references a customer from a domain, and
-- no domain status is changed.
--
-- Match rule: the ingested domain equals the customer's domain, or is a
-- subdomain of it. A domain matching two or more customers stays unlinked.

begin;

alter table crm.ingested_domain
  add column if not exists customer_id uuid
    references core.customer(id) on delete set null;

create index if not exists crm_ingested_domain_customer_id_idx
  on crm.ingested_domain (customer_id) where customer_id is not null;

comment on column crm.ingested_domain.customer_id is
  'Existing customer this email domain belongs to (exact or subdomain match on core.customer.domain). Null when none or ambiguous.';

-- The single customer whose domain matches p_domain, or null if none or ambiguous.
create or replace function crm.match_ingested_domain_customer(p_domain text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  with m as (
    select c.id
    from core.customer c
    cross join lateral (
      select lower(trim(both '.' from regexp_replace(btrim(c.domain), '^(https?://)?(www\.)?([^/:?#]*).*$', '\3', 'i'))) as cd
    ) n
    where nullif(n.cd, '') is not null
      and (lower(btrim(p_domain)) = n.cd or lower(btrim(p_domain)) like '%.' || n.cd)
  )
  select case when count(*) = 1 then min(id::text)::uuid end from m;
$$;

revoke all on function crm.match_ingested_domain_customer(text) from public, anon, authenticated;

-- New or renamed ingested domains auto-link when unlinked.
create or replace function crm.ingested_domain_link_customer()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.customer_id is null then
    new.customer_id := crm.match_ingested_domain_customer(new.domain::text);
  end if;
  return new;
end;
$$;

revoke all on function crm.ingested_domain_link_customer() from public, anon, authenticated;

drop trigger if exists ingested_domain_link_customer on crm.ingested_domain;
create trigger ingested_domain_link_customer
  before insert or update of domain on crm.ingested_domain
  for each row execute function crm.ingested_domain_link_customer();

-- A customer domain set or changed: drop this customer's links that no longer
-- match, then link unlinked domains under the new domain that now match
-- exactly one customer. Only candidate domains are re-matched.
create or replace function crm.customer_domain_link_ingested()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cd text := lower(trim(both '.' from regexp_replace(btrim(coalesce(new.domain, '')), '^(https?://)?(www\.)?([^/:?#]*).*$', '\3', 'i')));
begin
  if tg_op = 'UPDATE' then
    update crm.ingested_domain d
       set customer_id = null
     where d.customer_id = new.id
       and crm.match_ingested_domain_customer(d.domain::text) is distinct from new.id;
  end if;
  if v_cd <> '' then
    update crm.ingested_domain d
       set customer_id = crm.match_ingested_domain_customer(d.domain::text)
     where d.customer_id is null
       and (lower(d.domain::text) = v_cd or lower(d.domain::text) like '%.' || v_cd)
       and crm.match_ingested_domain_customer(d.domain::text) is not null;
  end if;
  return null;
end;
$$;

revoke all on function crm.customer_domain_link_ingested() from public, anon, authenticated;

drop trigger if exists customer_link_ingested_domains on core.customer;
create trigger customer_link_ingested_domains
  after insert or update of domain on core.customer
  for each row
  execute function crm.customer_domain_link_ingested();

-- A canonical Customer merge must carry the loser's domain links to the survivor.
do $$
declare
  v_definition text;
  v_anchor text :=
    '  update public.style_tracker_rows set customer_id = p_survivor where customer_id = p_loser;';
  v_replacement text :=
    '  update crm.ingested_domain set customer_id = p_survivor where customer_id = p_loser;' || E'\n' ||
    v_anchor;
begin
  v_definition := pg_get_functiondef('core.merge_customer(uuid,uuid,boolean)'::regprocedure);
  if position(v_anchor in v_definition) = 0 then
    raise exception 'core.merge_customer changed: expected insertion anchor is absent';
  end if;
  if position('update crm.ingested_domain set customer_id' in v_definition) = 0 then
    execute replace(v_definition, v_anchor, v_replacement);
  end if;
end
$$;

-- Backfill (status untouched).
update crm.ingested_domain d
   set customer_id = m.cid
  from (select id, crm.match_ingested_domain_customer(domain::text) as cid
          from crm.ingested_domain) m
 where d.id = m.id and m.cid is not null and d.customer_id is distinct from m.cid;

create or replace view api.crm_ingested_domain_list
with (security_invoker = true) as
select
  d.id,
  d.domain::text as domain,
  d.display_name,
  d.status,
  d.email_count,
  d.first_seen_at,
  d.last_seen_at,
  d.last_sender::text as last_sender,
  d.sample_subject,
  d.updated_at,
  d.customer_id,
  c.name as customer_name,
  c.status::text as customer_status
from crm.ingested_domain d
left join core.customer c on c.id = d.customer_id;

comment on view api.crm_ingested_domain_list is
  'CRM-private ingested email-domain triage list, with the existing customer each domain is linked to (customer_id/name/status; null when unmatched or ambiguous).';

grant select on api.crm_ingested_domain_list to authenticated;

commit;
