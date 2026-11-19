-- Promotable re-issue of 20261223010103_crm_meeting_note_unique_transcript_and_retry.sql (CRM audit batch, popcrm-web #39/#57/#68/#69/#40).
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
-- CONTENT: byte-identical to 20261223010103_crm_meeting_note_unique_transcript_and_retry.sql.
--
-- reverted-in-this-pr: 20261223010103_crm_meeting_note_unique_transcript_and_retry.sql

create unique index if not exists crm_meeting_note_fireflies_transcript_uidx
  on crm.meeting_note (fireflies_transcript_id)
  where fireflies_transcript_id is not null;

-- (b) Retry parking for failed Fireflies transcript fetches.
create table if not exists crm.fireflies_retry (
  meeting_id text primary key,
  payload jsonb not null,
  attempts integer not null default 0,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table crm.fireflies_retry is
'Fireflies webhook retry parking: one row per meeting_id whose transcript fetch/parse failed, holding the raw payload for the popcrm-web worker to retry with backoff. Worker-private: RLS enabled and FORCED with zero policies; public/anon/authenticated fully revoked; only the worker (service_role) reads and writes it directly.';

comment on column crm.fireflies_retry.meeting_id is
'Fireflies meeting id from the webhook. Primary key: one retry entry per meeting, redeliveries upsert.';
comment on column crm.fireflies_retry.payload is
'The raw webhook payload exactly as received, retried verbatim. Never parsed here.';
comment on column crm.fireflies_retry.attempts is
'How many retry attempts have been made. Monotonic; the worker owns the increment.';
comment on column crm.fireflies_retry.last_error is
'Last failure reason, truncated by the worker. Diagnostic only.';

revoke all on crm.fireflies_retry from public;
revoke all on crm.fireflies_retry from anon;
revoke all on crm.fireflies_retry from authenticated;
revoke all on crm.fireflies_retry from service_role;
grant select, insert, update, delete on crm.fireflies_retry to service_role;

-- Deny-everything for every role without BYPASSRLS; owner included.
alter table crm.fireflies_retry enable row level security;
alter table crm.fireflies_retry force row level security;
