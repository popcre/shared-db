-- #4508: DAM search query-shape contract tests (synthetic, disposable transaction).
-- Covers: no-match summary envelope, out-of-range summary, signature identity,
-- substring guard on expand_dam_search_queries, grants.
-- Model-predicate and >10k caps are not exercised here (no embedding fixture).

-- Prefer the superuser/session path so require_dam_access is satisfied in CI
-- without a JWT. service_role is granted execute for production callers.
reset role;
do $$
begin
  if not (select public.require_dam_access()) then
    raise exception 'test cannot obtain DAM access';
  end if;
end $$;

-- 1. No-match precision: nonsense token must return the summary envelope
--    (exactly one summary-only row; never a phantom hit).
do $$
declare
  n int;
  total bigint;
begin
  select count(*), min(total_count) into n, total
  from public.search_dam_documents('zzzz-not-a-real-object-qqq', '{}'::jsonb, 10, 0, null, null, 0);
  if n <> 1 then
    raise exception 'no-match query returned % rows (expected 1 summary-only)', n;
  end if;
  if coalesce(total, 0) <> 0 then
    raise exception 'no-match query reported total_count=%', total;
  end if;
end $$;

-- 2. Summary on out-of-range page: offset past end still yields total_count/facets.
do $$
declare
  r record;
  saw_row boolean := false;
begin
  for r in
    select * from public.search_dam_documents('holiday', '{}'::jsonb, 5, 1000000, null, null, 0)
  loop
    saw_row := true;
    if r.total_count is null then
      raise exception 'out-of-range page lost total_count';
    end if;
    if r.facets is null then
      raise exception 'out-of-range page lost facets';
    end if;
  end loop;
  if not saw_row then
    raise exception 'out-of-range page returned zero rows (summary envelope missing)';
  end if;
end $$;

-- 3. Signature is still 8-arg with p_min_semantic_score trailing
--    (search-path independent via to_regprocedure).
do $$
begin
  if to_regprocedure(
    'public.search_dam_documents(text,jsonb,integer,integer,text[],extensions.vector,real,real)'
  ) is null then
    raise exception 'search_dam_documents signature drifted from the 8-arg contract';
  end if;
end $$;

-- 4. Substring guard: punctuation-only expands enable no substring matching;
--    alphanumeric codes (3FZ) do.
do $$
declare
  allow_punct boolean;
  allow_code boolean;
begin
  select bool_or(length(q.query_text) >= 3 and q.query_text ~ '[[:alnum:]]{3,}')
  into allow_punct
  from public.expand_dam_search_queries('!!!') q;
  if coalesce(allow_punct, false) then
    raise exception 'punctuation-only query enabled substring matching';
  end if;
  select bool_or(length(q.query_text) >= 3 and q.query_text ~ '[[:alnum:]]{3,}')
  into allow_code
  from public.expand_dam_search_queries('3FZ') q;
  if not coalesce(allow_code, false) then
    raise exception 'alphanumeric code 3FZ failed the substring token guard';
  end if;
end $$;

-- 5. Grants: authenticated/service_role only.
do $$
begin
  if has_function_privilege('anon', 'public.search_dam_documents(text,jsonb,int,int,text[],extensions.vector,real,real)', 'EXECUTE') then
    raise exception 'anon can execute search_dam_documents';
  end if;
  if not has_function_privilege('authenticated', 'public.search_dam_documents(text,jsonb,int,int,text[],extensions.vector,real,real)', 'EXECUTE') then
    raise exception 'authenticated cannot execute search_dam_documents';
  end if;
end $$;

-- 6. Empty/out-of-range page returns exactly one summary row with null entity_id.
do $$
declare
  n int;
  saw_null_id boolean := false;
begin
  select count(*) into n
  from public.search_dam_documents('zzzz-not-a-real-object-qqq', '{}'::jsonb, 10, 1000000, null, null, 0);
  if n <> 1 then
    raise exception 'out-of-range/no-match expected 1 summary row, got %', n;
  end if;
  select bool_or(entity_id is null) into saw_null_id
  from public.search_dam_documents('zzzz-not-a-real-object-qqq', '{}'::jsonb, 10, 1000000, null, null, 0);
  if not coalesce(saw_null_id, false) then
    raise exception 'summary-only row must have null entity_id';
  end if;
end $$;

-- 7. Foreign-model / wrong-dims embeddings are excluded from the semantic leg.
do $$
declare
  hit int;
begin
  delete from public.dam_search_documents where entity_id = '34570000-0000-4000-8000-000000000099';
  insert into public.dam_search_documents
    (document_type, entity_id, asset_id, title, path, embedding, embedding_model)
  values
    ('asset','34570000-0000-4000-8000-000000000099','34570000-0000-4000-8000-000000000099',
     'zz4508 foreign model canvas','zz4508-foreign.ai',
     (select array_fill(0.0::real, array[384])::extensions.vector), 'other-model');
  select count(*) into hit
  from public.search_dam_documents(
    'zz4508 foreign model canvas', '{}'::jsonb, 10, 0, array['asset']::text[],
    (select array_fill(0.0::real, array[384])::extensions.vector), 0, 0.0);
  -- keyword may still hit the title; semantic leg must not treat it as a vector hit
  -- so semantic_rank must be null on that row
  if exists (
    select 1 from public.search_dam_documents(
      'zz4508 foreign model canvas', '{}'::jsonb, 10, 0, array['asset']::text[],
      (select array_fill(0.0::real, array[384])::extensions.vector), 0, 0.0)
    where entity_id = '34570000-0000-4000-8000-000000000099' and semantic_rank is not null
  ) then
    raise exception 'foreign embedding_model was admitted to the semantic leg';
  end if;
  delete from public.dam_search_documents where entity_id = '34570000-0000-4000-8000-000000000099';
end $$;
