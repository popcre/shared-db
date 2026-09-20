-- Issue #2995, atomic author claim #3377.
-- Background classification turns are idempotent per determination and turn.
-- Workers share the HTS evidence store; provenance is authenticated on INSERT
-- and cannot be rewritten. Creator visibility is enforced by the backend.
-- RFQ identifiers refer to application databases, so no cross-database FK exists.
create table hts_rag.hts_rag_classification_jobs (
  id uuid not null default gen_random_uuid(),
  determination_id uuid not null,
  session_id uuid not null,
  turn_index integer not null,
  kind text not null,
  status text not null default 'queued',
  owner_key text not null,
  created_by jsonb,
  input jsonb not null,
  result jsonb,
  error_code text,
  error_message text,
  rfq_id integer,
  rfq_item_id integer,
  source text not null default 'hts_lookup',
  source_environment text not null,
  claimed_at timestamptz,
  claimed_by text,
  lease_expires_at timestamptz,
  attempt_count integer not null default 0,
  max_attempts integer not null default 3,
  estimated_cost_usd numeric,
  actual_cost_usd numeric,
  notified_at timestamptz,
  applied_at timestamptz,
  applied_by jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint hts_rag_classification_jobs_pkey primary key (id),
  constraint hts_rag_classification_jobs_determination_fkey
    foreign key (determination_id) references hts_rag.hts_rag_determinations(id) on delete restrict,
  constraint hts_rag_classification_jobs_determination_turn_uq
    unique (determination_id, turn_index),
  constraint hts_rag_classification_jobs_turn_check check (turn_index >= 0),
  constraint hts_rag_classification_jobs_kind_check check (kind in ('initial', 'answer')),
  constraint hts_rag_classification_jobs_status_check
    check (status in ('queued', 'running', 'needs_answer', 'ready', 'applied', 'failed', 'cancelled')),
  constraint hts_rag_classification_jobs_source_check check (source in ('hts_lookup', 'rfq')),
  constraint hts_rag_classification_jobs_environment_check
    check (source_environment in ('production', 'alsand')),
  constraint hts_rag_classification_jobs_attempt_check check (attempt_count >= 0),
  constraint hts_rag_classification_jobs_max_attempts_check check (max_attempts >= 1)
);

create index hts_rag_classification_jobs_status_idx
  on hts_rag.hts_rag_classification_jobs (status, created_at);
create index hts_rag_classification_jobs_owner_idx
  on hts_rag.hts_rag_classification_jobs (owner_key, status);
create index hts_rag_classification_jobs_rfq_idx
  on hts_rag.hts_rag_classification_jobs (rfq_id, rfq_item_id);

alter table hts_rag.hts_rag_classification_jobs enable row level security;
revoke all on hts_rag.hts_rag_classification_jobs
  from public, anon, authenticated, service_role,
       designflow_hts_prod_runtime, designflow_hts_alsand_runtime,
       designflow_hts_prod_worker, designflow_hts_alsand_worker;
grant select, insert on hts_rag.hts_rag_classification_jobs
  to designflow_hts_prod_worker, designflow_hts_alsand_worker;
-- Launch identity, provenance, input and retry ceiling are immutable to workers.
-- Cost estimates may change as the worker discovers the required model turns.
grant update (status, result, error_code, error_message,
  claimed_at, claimed_by, lease_expires_at, attempt_count,
  estimated_cost_usd, actual_cost_usd, notified_at, applied_at, applied_by, updated_at)
  on hts_rag.hts_rag_classification_jobs
  to designflow_hts_prod_worker, designflow_hts_alsand_worker;

create policy hts_rag_prod_worker_access on hts_rag.hts_rag_classification_jobs
  for select to designflow_hts_prod_worker using (true);
create policy hts_rag_prod_worker_insert on hts_rag.hts_rag_classification_jobs
  for insert to designflow_hts_prod_worker with check (source_environment = 'production');
create policy hts_rag_prod_worker_update on hts_rag.hts_rag_classification_jobs
  for update to designflow_hts_prod_worker using (true) with check (true);
create policy hts_rag_alsand_worker_access on hts_rag.hts_rag_classification_jobs
  for select to designflow_hts_alsand_worker using (true);
create policy hts_rag_alsand_worker_insert on hts_rag.hts_rag_classification_jobs
  for insert to designflow_hts_alsand_worker with check (source_environment = 'alsand');
create policy hts_rag_alsand_worker_update on hts_rag.hts_rag_classification_jobs
  for update to designflow_hts_alsand_worker using (true) with check (true);
