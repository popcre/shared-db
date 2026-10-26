-- Version: 20261025180137
-- derived-from: 20260930185929
-- Issue: popcre/shared-db#4437 (app u2giants/popdam3#107)
-- PopSG semantic-plus-keyword search, stage 1: embedding foundation.
--
-- Model decision: the issue's bounded design (2026-10-18) named gte-small/384;
-- the worker/edge embedding mechanism it says to "reuse" moved to
-- google/siglip2-base-patch16-naflex/768 on 2026-10-23 (#4664, owner decision
-- Albert 2026-10-22) and the old 384 text vectors were cleared as incompatible.
-- This migration therefore stores 768-dim SigLIP2 vectors: document vectors
-- come from style_guide_files.thumbnail_url via the owner GPU worker, query
-- vectors arrive through the same SigLIP2 shared space. Corpus separation from
-- DAM is by table: public.style_guide_search_documents is PopSG-only.
--
-- Content identity: sha256(source_identity || '|' || coalesce(thumbnail_url,''))
-- -- everything the embedding derives from, plus the document's text identity.
-- A content change clears the stored vector and requeues it safely; the worker
-- stays the sole claimer (service_role-only claim/upsert/mark RPCs, lease
-- token + expiry, bounded retries with backoff, permanent-error category).
--
-- Stage 2 (separate version under the same claim #4768) threads
-- p_query_embedding into search_style_guide_library_v2: authorization and
-- filters first, then semantic candidate ranking, preserving keyword matches,
-- totals, facets, sorting and pagination; semantic outage degrades to keyword.
-- This stage does not touch the search function: nothing here can change any
-- query result.

set statement_timeout = '15min';

-- 1) Embedding storage on the existing PopSG search documents table.
alter table public.style_guide_search_documents
  add column if not exists embedding extensions.vector(768),
  add column if not exists embedding_model text,
  add column if not exists embedding_updated_at timestamptz,
  add column if not exists embedding_error text,
  add column if not exists embedding_error_category text,
  add column if not exists embedding_next_retry_at timestamptz,
  add column if not exists embedding_attempts integer not null default 0,
  add column if not exists embedding_max_attempts integer not null default 5,
  add column if not exists embedding_lease_token uuid,
  add column if not exists embedding_lease_owner text,
  add column if not exists embedding_lease_expires_at timestamptz,
  add column if not exists content_sha256 text;

comment on column public.style_guide_search_documents.embedding is
  'Issue #4437. google/siglip2-base-patch16-naflex/768 image vector of thumbnail_url, written only by upsert_sg_search_embedding under a claim lease. Null = not yet embedded or invalidated by a content change.';

create index if not exists idx_sg_search_documents_embedding_hnsw
  on public.style_guide_search_documents
  using hnsw (embedding extensions.vector_cosine_ops)
  where embedding is not null;

-- 2) refresh_style_guide_matviews: maintain content_sha256 and invalidate
--    embeddings on content change. Unchanged content keeps the vector, its
--    model stamp, and its retry state; changed content clears the vector,
--    resets attempts and releases any lease. Reproduced from 20260930185929
--    with only the identity/embedding lines added.
create or replace function public.refresh_style_guide_matviews(
  p_run_id uuid,
  p_search_batch_size integer,
  p_step text
)
returns table (
  refreshed_at timestamptz,
  search_documents_synced integer
)
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_batch integer := greatest(0, least(coalesce(p_search_batch_size, 5000), 50000));
  v_synced integer := 0;
  v_now timestamptz;
  v_started timestamptz := clock_timestamp();
  v_step text := coalesce(p_step, '');
begin
  if v_step not in ('all', 'file_groups', 'folders', 'search') then
    raise exception
      'refresh_style_guide_matviews: unknown p_step %, expected all|file_groups|folders|search',
      p_step;
  end if;

  if p_run_id is not null then
    update public.style_guide_crawl_runs
       set lifecycle_state = case when lifecycle_state in ('completed','failed','attention_required')
                                  then lifecycle_state else 'refreshing' end,
           refresh_started_at = coalesce(refresh_started_at, now())
     where id = p_run_id;
  end if;

  if v_step in ('all', 'file_groups') then
    refresh materialized view concurrently public.style_guide_file_groups;
  end if;

  if v_step in ('all', 'folders') then
    refresh materialized view concurrently public.style_guide_folders;
  end if;

  if v_step in ('all', 'search') and v_batch > 0 then
    with candidates as (
      select f.id,
             f.root_label,
             f.licensor_name,
             f.property_folder,
             f.style_guide_folder,
             coalesce(nullif(f.style_guide_folder, ''), nullif(f.property_folder, ''),
                      f.licensor_name, 'Unfiled') as style_guide_name,
             f.directory_path,
             f.relative_path,
             f.filename,
             f.file_extension,
             f.tag_names,
             f.size_bytes,
             f.modified_at,
             f.thumbnail_url,
             f.is_active,
             md5(f.relative_path || '|' || coalesce(f.size_bytes::text, '') || '|' ||
                 coalesce(f.modified_at::text, '') || '|' || coalesce(f.tag_search_text, '') || '|' ||
                 coalesce(f.style_guide_folder, '') || '|' || coalesce(f.property_folder, '') || '|' ||
                 coalesce(f.licensor_name, '') || '|' || f.is_active::text) as source_identity
        from public.style_guide_search_sync_queue q
        join public.style_guide_files f on f.id = q.style_guide_file_id
        left join public.style_guide_search_documents d on d.style_guide_file_id = f.id
       where (p_run_id is null or f.crawl_run_id = p_run_id)
         and f.is_active
         and (d.style_guide_file_id is null
              -- A file that went stale and later came back unchanged keeps its
              -- stored source_identity, but reconcile_stale_sg_files_batch left
              -- the document is_active = false. Without this clause the row is
              -- never re-selected and stays invisible to unified search forever.
              or d.is_active is distinct from f.is_active
              or d.source_identity is distinct from
                 md5(f.relative_path || '|' || coalesce(f.size_bytes::text, '') || '|' ||
                     coalesce(f.modified_at::text, '') || '|' || coalesce(f.tag_search_text, '') || '|' ||
                     coalesce(f.style_guide_folder, '') || '|' || coalesce(f.property_folder, '') || '|' ||
                     coalesce(f.licensor_name, '') || '|' || f.is_active::text))
       order by q.style_guide_file_id
       limit v_batch
    ), upserted as (
      insert into public.style_guide_search_documents as d (
        style_guide_file_id, root_label, licensor_name, property_folder, style_guide_folder,
        style_guide_name, directory_path, relative_path, filename, file_extension,
        tag_names, size_bytes, modified_at, thumbnail_url, is_active,
        pdf_text_status, pdf_text_length, source_identity, content_sha256, search_vector,
        document_updated_at)
      select c.id, c.root_label, c.licensor_name, c.property_folder, c.style_guide_folder,
             c.style_guide_name, c.directory_path, c.relative_path, c.filename, c.file_extension,
             c.tag_names, c.size_bytes, c.modified_at, c.thumbnail_url, c.is_active,
             t.status, coalesce(t.text_length, 0), c.source_identity,
             encode(extensions.digest(c.source_identity || '|' || coalesce(c.thumbnail_url, ''), 'sha256'), 'hex'),
             setweight(to_tsvector('simple', coalesce(c.filename, '')), 'A')
             || setweight(to_tsvector('simple', coalesce(c.style_guide_name, '') || ' ' ||
                                                coalesce(c.property_folder, '') || ' ' ||
                                                coalesce(c.licensor_name, '')), 'B')
             || setweight(to_tsvector('simple', coalesce(c.relative_path, '') || ' ' ||
                                                array_to_string(c.tag_names, ' ')), 'C')
             || setweight(to_tsvector('simple', left(coalesce(t.extracted_text, ''), 200000)), 'D'),
             now()
        from candidates c
        left join public.style_guide_pdf_text t on t.style_guide_file_id = c.id
      on conflict (style_guide_file_id) do update
        set root_label = excluded.root_label,
            licensor_name = excluded.licensor_name,
            property_folder = excluded.property_folder,
            style_guide_folder = excluded.style_guide_folder,
            style_guide_name = excluded.style_guide_name,
            directory_path = excluded.directory_path,
            relative_path = excluded.relative_path,
            filename = excluded.filename,
            file_extension = excluded.file_extension,
            tag_names = excluded.tag_names,
            size_bytes = excluded.size_bytes,
            modified_at = excluded.modified_at,
            thumbnail_url = excluded.thumbnail_url,
            is_active = excluded.is_active,
            pdf_text_status = excluded.pdf_text_status,
            pdf_text_length = excluded.pdf_text_length,
            source_identity = excluded.source_identity,
            content_sha256 = excluded.content_sha256,
            -- #4437: a changed content identity invalidates the embedding and
            -- requeues it; unchanged content keeps vector, stamp and retry state.
            embedding = case when d.content_sha256
                                  = excluded.content_sha256
                        then d.embedding end,
            embedding_model = case when d.content_sha256
                                        = excluded.content_sha256
                              then d.embedding_model end,
            embedding_updated_at = case when d.content_sha256
                                              = excluded.content_sha256
                                  then d.embedding_updated_at end,
            embedding_error = case when d.content_sha256
                                        = excluded.content_sha256
                              then d.embedding_error end,
            embedding_error_category = case when d.content_sha256
                                                  = excluded.content_sha256
                                        then d.embedding_error_category end,
            embedding_next_retry_at = case when d.content_sha256
                                                  = excluded.content_sha256
                                        then d.embedding_next_retry_at end,
            embedding_attempts = case when d.content_sha256
                                            = excluded.content_sha256
                                then d.embedding_attempts else 0 end,
            embedding_max_attempts = case when d.content_sha256
                                                = excluded.content_sha256
                                    then d.embedding_max_attempts
                                    else 5 end,
            embedding_lease_token = case when d.content_sha256
                                                = excluded.content_sha256
                                        then d.embedding_lease_token end,
            embedding_lease_owner = case when d.content_sha256
                                                = excluded.content_sha256
                                        then d.embedding_lease_owner end,
            embedding_lease_expires_at = case when d.content_sha256
                                                    = excluded.content_sha256
                                            then d.embedding_lease_expires_at end,
            search_vector = excluded.search_vector,
            document_updated_at = now()
      returning d.style_guide_file_id
    )
    select count(*)::integer into v_synced from upserted;

    -- Retire queue entries that are satisfied: the file is gone or inactive
    -- (reconcile deactivates file and document together, and reactivation
    -- requeues), or its document already matches the file's current identity.
    -- Only entries queued before this call started are retired. The trigger
    -- re-stamps queued_at on every change, which locks the entry, so a change
    -- that races this call is re-checked and kept for the next call.
    delete from public.style_guide_search_sync_queue q
     where q.queued_at < v_started
       and not exists (
       select 1
         from public.style_guide_files f
         left join public.style_guide_search_documents d on d.style_guide_file_id = f.id
        where f.id = q.style_guide_file_id
          and f.is_active
          and (d.style_guide_file_id is null
               or d.is_active is distinct from f.is_active
               or d.source_identity is distinct from
                 md5(f.relative_path || '|' || coalesce(f.size_bytes::text, '') || '|' ||
                     coalesce(f.modified_at::text, '') || '|' || coalesce(f.tag_search_text, '') || '|' ||
                     coalesce(f.style_guide_folder, '') || '|' || coalesce(f.property_folder, '') || '|' ||
                     coalesce(f.licensor_name, '') || '|' || f.is_active::text)));
  end if;

  v_now := now();

  -- Completion stamp only on the step that can finish the refresh work.
  -- Matview-only steps leave the run in 'refreshing' with refresh_completed_at
  -- untouched so a later 'search' call (or a caller that knows no search is
  -- needed) closes the run. 'search' and 'all' accumulate the synced count the
  -- existing popdam3 loop already reads.
  if p_run_id is not null and v_step in ('all', 'search') and v_batch > 0 then
    update public.style_guide_crawl_runs
       set refresh_completed_at = v_now,
           -- qualified: `search_documents_synced` is also this function's output
           -- parameter, so the bare name would be ambiguous
           search_documents_synced = style_guide_crawl_runs.search_documents_synced + v_synced
     where id = p_run_id;
  end if;

  refreshed_at := v_now;
  search_documents_synced := v_synced;
  return next;
end;
$function$;

-- 3) Worker claim: bounded batch of not-yet-embedded active documents.
create function public.claim_sg_search_embedding_documents(
  p_limit integer default 100,
  p_worker_id text default null,
  p_lease_seconds integer default 300
)
returns table (
  style_guide_file_id uuid,
  search_text text,
  thumbnail_url text,
  content_sha256 text,
  lease_token uuid,
  lease_expires_at timestamptz,
  attempt integer
)
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if (select auth.role()) <> 'service_role' or nullif(btrim(p_worker_id),'') is null then
    raise exception 'service_role and worker id required' using errcode = '42501';
  end if;
  return query with candidates as (
    select d.style_guide_file_id from public.style_guide_search_documents d
    where d.is_active and d.content_sha256 is not null
      and d.embedding is null and d.embedding_attempts < d.embedding_max_attempts
      and (d.embedding_next_retry_at is null or d.embedding_next_retry_at <= now())
      and (d.embedding_lease_expires_at is null or d.embedding_lease_expires_at <= now())
      and d.embedding_error_category is distinct from 'permanent'
    order by d.document_updated_at, d.style_guide_file_id for update skip locked
    limit greatest(1, least(coalesce(p_limit, 100), 1000))
  ), claimed as (
    update public.style_guide_search_documents d
       set embedding_lease_token = gen_random_uuid(),
           embedding_lease_owner = p_worker_id,
           embedding_lease_expires_at = now() + make_interval(secs => greatest(30, least(coalesce(p_lease_seconds, 300), 3600))),
           embedding_attempts = d.embedding_attempts + 1
      from candidates c
     where d.style_guide_file_id = c.style_guide_file_id
    returning d.*)
  select c.style_guide_file_id,
         left(c.filename || ' ' || c.style_guide_name || ' ' || coalesce(c.property_folder, '') || ' ' ||
              coalesce(c.licensor_name, ''), 8000),
         c.thumbnail_url, c.content_sha256, c.embedding_lease_token, c.embedding_lease_expires_at,
         c.embedding_attempts
    from claimed c;
end;
$$;

-- 4) Worker write: lease-token + content-identity guarded; stale writes rejected.
create function public.upsert_sg_search_embedding(
  p_style_guide_file_id uuid,
  p_content_sha256 text,
  p_lease_token uuid,
  p_embedding extensions.vector(768),
  p_embedding_model text default 'google/siglip2-base-patch16-naflex'
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if (select auth.role()) <> 'service_role' then raise exception 'service_role required' using errcode = '42501'; end if;
  if p_embedding_model is distinct from 'google/siglip2-base-patch16-naflex'
     or extensions.vector_dims(p_embedding) is distinct from 768 then
    raise exception 'unsupported embedding model or dimension' using errcode = '22023';
  end if;
  update public.style_guide_search_documents
     set embedding = p_embedding,
         embedding_model = p_embedding_model,
         embedding_updated_at = now(),
         embedding_error = null,
         embedding_error_category = null,
         embedding_next_retry_at = null,
         embedding_lease_token = null,
         embedding_lease_owner = null,
         embedding_lease_expires_at = null
   where style_guide_file_id = p_style_guide_file_id
     and content_sha256 = p_content_sha256
     and embedding_lease_token = p_lease_token
     and embedding_lease_expires_at > now();
  return found;
end;
$$;

-- 5) Worker failure report: bounded backoff, transient/permanent categories.
create function public.mark_sg_search_embedding_error(
  p_style_guide_file_id uuid,
  p_content_sha256 text,
  p_lease_token uuid,
  p_error text,
  p_category text default 'transient'
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if (select auth.role()) <> 'service_role' or p_category not in ('transient','permanent') then
    raise exception 'invalid embedding error' using errcode = '42501';
  end if;
  update public.style_guide_search_documents
     set embedding_error = left(coalesce(p_error, 'unknown embedding error'), 1000),
         embedding_error_category = case when p_category = 'permanent'
                                              or embedding_attempts >= embedding_max_attempts
                                         then 'permanent' else 'transient' end,
         embedding_next_retry_at = case when p_category = 'transient'
                                             and embedding_attempts < embedding_max_attempts
                                        then now() + make_interval(secs => least(3600, 30 * (2 ^ greatest(0, embedding_attempts - 1))::int)) end,
         embedding_lease_token = null,
         embedding_lease_owner = null,
         embedding_lease_expires_at = null
   where style_guide_file_id = p_style_guide_file_id
     and content_sha256 = p_content_sha256
     and embedding_lease_token = p_lease_token
     and embedding_lease_expires_at > now();
  return found;
end;
$$;

-- 6) Coverage meter for the #4437 acceptance ("coverage measured separately
--    for DAM and SG").
create function public.get_sg_search_embedding_status() returns jsonb
language sql
stable
security definer
set search_path = public
as $$
select jsonb_build_object(
  'total_documents', count(*),
  'embedded_documents', count(*) filter (where embedding is not null),
  'pending_documents', count(*) filter (where embedding is null
                                        and content_sha256 is not null
                                        and embedding_attempts < embedding_max_attempts
                                        and embedding_error_category is distinct from 'permanent'),
  'unidentified_documents', count(*) filter (where content_sha256 is null),
  'leased_documents', count(*) filter (where embedding_lease_expires_at > now()),
  'errored_documents', count(*) filter (where embedding_error is not null),
  'exhausted_documents', count(*) filter (where embedding is null
                                          and (embedding_attempts >= embedding_max_attempts
                                               or embedding_error_category = 'permanent')),
  'oldest_pending_updated_at', min(document_updated_at) filter (where embedding is null),
  'newest_updated_at', max(document_updated_at))
  from public.style_guide_search_documents;
$$;

-- 7) Admin/worker reset of exhausted retries.
create or replace function public.reset_sg_search_embedding_errors(
  p_style_guide_file_ids uuid[] default null
) returns integer
language plpgsql
security definer
set search_path = public
as $$
declare v_count int;
begin
  if (select auth.role()) <> 'service_role'
     and not public.has_role(auth.uid(), 'admin') then
    raise exception 'admin required' using errcode = '42501';
  end if;
  update public.style_guide_search_documents
     set embedding_error = null,
         embedding_error_category = null,
         embedding_attempts = 0,
         embedding_next_retry_at = null,
         embedding_lease_token = null,
         embedding_lease_owner = null,
         embedding_lease_expires_at = null
   where embedding is null
     and (p_style_guide_file_ids is null or style_guide_file_id = any (p_style_guide_file_ids));
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- 8) Grants: the worker (service_role) is the sole claimer and writer.
revoke all on function public.claim_sg_search_embedding_documents(integer, text, integer) from public, anon, authenticated;
revoke all on function public.upsert_sg_search_embedding(uuid, text, uuid, extensions.vector(768), text) from public, anon, authenticated;
revoke all on function public.mark_sg_search_embedding_error(uuid, text, uuid, text, text) from public, anon, authenticated;
revoke all on function public.get_sg_search_embedding_status() from public, anon, authenticated;
revoke all on function public.reset_sg_search_embedding_errors(uuid[]) from public, anon, authenticated;
grant execute on function public.claim_sg_search_embedding_documents(integer, text, integer) to service_role;
grant execute on function public.upsert_sg_search_embedding(uuid, text, uuid, extensions.vector(768), text) to service_role;
grant execute on function public.mark_sg_search_embedding_error(uuid, text, uuid, text, text) to service_role;
grant execute on function public.get_sg_search_embedding_status() to service_role;
grant execute on function public.reset_sg_search_embedding_errors(uuid[]) to service_role;

revoke all on function public.refresh_style_guide_matviews(uuid, integer, text) from public;
revoke all on function public.refresh_style_guide_matviews(uuid, integer, text) from anon;
revoke all on function public.refresh_style_guide_matviews(uuid, integer, text) from authenticated;
grant execute on function public.refresh_style_guide_matviews(uuid, integer, text) to service_role;

-- Catalogue-only self verification (no data scans). search_path is pinned so
-- pg_get_function_identity_arguments renders the vector parameter schema-
-- qualified (extensions.vector(768)) regardless of the applying session's
-- path; with extensions visible it renders bare and the comparison would
-- fail on every clean replay (CI caught this via the contract test).
do $verify$
declare
  v_missing text[] := array[]::text[];
  v_name text;
begin
  perform set_config('search_path', 'public', true);
  foreach v_name in array array[
    'public.refresh_style_guide_matviews(uuid,integer,text)',
    'public.claim_sg_search_embedding_documents(integer,text,integer)',
    'public.upsert_sg_search_embedding(uuid,text,uuid,extensions.vector(768),text)',
    'public.mark_sg_search_embedding_error(uuid,text,uuid,text,text)',
    'public.get_sg_search_embedding_status()',
    'public.reset_sg_search_embedding_errors(uuid[])'] loop
    if not exists (
      select 1 from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = split_part(v_name, '.', 1)
         -- match on proname: the v_name label carries a dotted type
         -- (extensions.vector) that would break a split_part('.', 2) key
         and p.proname = split_part(split_part(v_name, '.', 2), '(', 1)
         and pg_get_function_identity_arguments(p.oid)
             = case p.proname
                 when 'refresh_style_guide_matviews' then 'p_run_id uuid, p_search_batch_size integer, p_step text'
                 when 'claim_sg_search_embedding_documents' then 'p_limit integer, p_worker_id text, p_lease_seconds integer'
                 when 'upsert_sg_search_embedding' then 'p_style_guide_file_id uuid, p_content_sha256 text, p_lease_token uuid, p_embedding extensions.vector, p_embedding_model text'
                 when 'mark_sg_search_embedding_error' then 'p_style_guide_file_id uuid, p_content_sha256 text, p_lease_token uuid, p_error text, p_category text'
                 when 'get_sg_search_embedding_status' then ''
                 when 'reset_sg_search_embedding_errors' then 'p_style_guide_file_ids uuid[]'
               end) then
      v_missing := v_missing || v_name;
    end if;
  end loop;
  if array_length(v_missing, 1) > 0 then
    raise exception 'catalogue verification failed, missing: %', v_missing;
  end if;
end;
$verify$;
