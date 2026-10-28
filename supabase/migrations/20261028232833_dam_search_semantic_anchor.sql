-- #4999: cheap "best picture score" for one query embedding.
-- derived-from: none
-- dam-search-ai passes p_min_semantic_score = best_score - 0.045 to
-- search_dam_documents so only near-best picture matches survive. Getting the best
-- score through search_dam_documents itself costs ~2.4 s; this reads one row.
-- Index paths mirror search_dam_documents (20261027010904):
--   * any requested type other than style_group: HNSW order-by-distance, limit 1;
--   * style_group only: exact distance sort with the literal document_type and
--     "+ 0" so the planner stays off the HNSW index (a filtered HNSW walk over the
--     asset-dominated index is far slower for style groups).
-- Access: public.require_dam_access(), like search_dam_documents; not executable
-- by PUBLIC/anon.

create or replace function public.dam_search_semantic_anchor(
  p_query_embedding vector,
  p_document_types text[] default null
)
returns real
language sql
stable
security definer
set search_path = public, extensions
set statement_timeout = '30s'
as $$
  select set_config('hnsw.ef_search', '100', true);
  select set_config('hnsw.iterative_scan', 'relaxed_order', true);
  select set_config('hnsw.max_scan_tuples', '20000', true);
  with params as materialized (
    select 1 ok
    where public.require_dam_access() and p_query_embedding is not null
  ), semantic_ann as materialized (
    select greatest(0, 1 - (d.embedding <=> p_query_embedding))::real score
    from params p
    join public.dam_search_documents d
      on d.embedding is not null
      and d.embedding_model = 'google/siglip2-base-patch16-naflex'
    where (p_document_types is null
        or exists (select 1 from unnest(p_document_types) t where t is distinct from 'style_group'))
      and (p_document_types is null or d.document_type = any(p_document_types))
    order by d.embedding <=> p_query_embedding
    limit 1
  ), semantic_exact as materialized (
    select greatest(0, 1 - (d.embedding <=> p_query_embedding))::real score
    from params p
    join public.dam_search_documents d
      on d.embedding is not null
      and d.embedding_model = 'google/siglip2-base-patch16-naflex'
    where p_document_types is not null and not ('asset' = any(p_document_types))
      and 'style_group' = any(p_document_types)
      and d.document_type = 'style_group'  -- literal: a parameter here makes the planner seq-scan
    order by (d.embedding <=> p_query_embedding) + 0
    limit 1
  )
  select max(s.score)::real
  from (select score from semantic_ann union all select score from semantic_exact) s;
$$;

revoke all on function public.dam_search_semantic_anchor(vector, text[]) from public, anon;
grant execute on function public.dam_search_semantic_anchor(vector, text[]) to authenticated, service_role;

comment on function public.dam_search_semantic_anchor(vector, text[]) is
  'Best SigLIP2 cosine score (0..1) for a query embedding over dam_search_documents; DAM access required (#4999).';
