-- Read-only post-apply search contract. Performance proof remains on #4210.
select exists (select 1 from pg_proc where oid = to_regprocedure('public.search_style_guide_library_v2(text,text,text[],text[],text[],text[],text[],text[],text[],text[],timestamptz,timestamptz,text,integer,integer)')
  and md5(prosrc) = '033f1ab9b85d01db271906613802fe1d' and prosecdef and provolatile = 's'
  and proconfig @> array['search_path=pg_catalog, auth','work_mem=64MB'])
  and has_function_privilege('authenticated','public.search_style_guide_library_v2(text,text,text[],text[],text[],text[],text[],text[],text[],text[],timestamptz,timestamptz,text,integer,integer)','execute')
  and not has_function_privilege('anon','public.search_style_guide_library_v2(text,text,text[],text[],text[],text[],text[],text[],text[],text[],timestamptz,timestamptz,text,integer,integer)','execute') as passed;
