-- Promotable re-issue of 20261223010104_crm_ignore_rule_increment_skipped.sql (CRM audit batch, popcrm-web #39/#57/#68/#69/#40).
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
-- CONTENT: byte-identical to 20261223010104_crm_ignore_rule_increment_skipped.sql.
--
-- reverted-in-this-pr: 20261223010104_crm_ignore_rule_increment_skipped.sql

create or replace function crm.increment_ignore_rule_emails_skipped(
  p_rule_id uuid,
  p_n integer default 1
)
returns void
language plpgsql
security definer
set search_path = 'app', 'core', 'crm', 'public'
as $$
begin
  update crm.ignore_rule
     set emails_skipped = emails_skipped + greatest(coalesce(p_n, 1), 0)
   where id = p_rule_id;
end;
$$;

revoke all on function crm.increment_ignore_rule_emails_skipped(uuid, integer) from public;
revoke all on function crm.increment_ignore_rule_emails_skipped(uuid, integer) from anon;
revoke all on function crm.increment_ignore_rule_emails_skipped(uuid, integer) from authenticated;
grant execute on function crm.increment_ignore_rule_emails_skipped(uuid, integer) to service_role;

comment on function crm.increment_ignore_rule_emails_skipped(uuid, integer) is
'Atomic crm.ignore_rule.emails_skipped increment for the popcrm-web worker (service_role only): adds greatest(coalesce(p_n,1),0), never decreases. Replaces the read-modify-write that lost counts under concurrency.';
