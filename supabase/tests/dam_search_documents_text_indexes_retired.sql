-- #4643: the five retired text indexes on dam_search_documents stay gone, and
-- the indexes that still serve readers remain.
reset role;
do $$
declare
  v_left text[];
  v_missing text[];
begin
  select array_agg(indexname order by indexname) into v_left
  from pg_indexes
  where schemaname = 'public' and tablename = 'dam_search_documents'
    and indexname in ('idx_dam_search_documents_tsv',
                      'idx_dam_search_documents_title_trgm',
                      'idx_dam_search_documents_path_trgm',
                      'idx_dam_search_documents_customer_trgm',
                      'idx_dam_search_documents_program_trgm');
  if v_left is not null then
    raise exception '#4643: retired indexes still present: %', v_left;
  end if;

  select array_agg(n order by n) into v_missing
  from unnest(array['dam_search_documents_pkey',
                    'idx_dam_search_documents_embedding_hnsw']) n
  where not exists (select 1 from pg_indexes
                    where schemaname = 'public' and indexname = n);
  if v_missing is not null then
    raise exception '#4643: required indexes missing: %', v_missing;
  end if;

  if not exists (select 1 from pg_indexes
                 where schemaname = 'public' and tablename = 'dam_search_keys'
                   and indexdef ilike '%using gin%') then
    raise exception '#4643: dam_search_keys has no GIN index to serve keyword search';
  end if;
end $$;
