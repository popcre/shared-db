begin;
-- shared-db#4577 (claim #4626): HTS precheck search indexes on hts_rag_rulings. Rolled back.
do $$
begin
  assert public.hts_rag_fold_text(E'Décor Café Straße İSTANBUL') = 'decor cafe stra e istanbul',
    'fold must match the backend scorer (NFD, strip marks, lowercase; leftover non-ASCII is a word break)';
  assert public.hts_rag_tariff_subheadings('["6913.90.5000","6913905010","12.34",null,7117190000]'::jsonb) = array['691390','711719'],
    'subheadings are distinct first-six digits of tariffs with at least six digits';
  assert public.hts_rag_tariff_subheadings('{}'::jsonb) = '{}'::text[], 'non-array tariffs yield no subheadings';
  assert to_regclass('public.hts_rag_rulings_search_trgm_idx') is not null, 'public text index missing';
  assert to_regclass('public.hts_rag_rulings_subheadings_idx') is not null, 'public subheading index missing';
  assert to_regclass('hts_rag.hts_rag_rulings_search_trgm_idx') is not null, 'hts_rag text index missing';
  assert to_regclass('hts_rag.hts_rag_rulings_subheadings_idx') is not null, 'hts_rag subheading index missing';
  assert has_function_privilege('designflow_hts_alsand_runtime', 'public.hts_rag_fold_text(text)', 'EXECUTE'),
    'isolated HTS runtime role must call the fold helper';
end $$;
rollback;
