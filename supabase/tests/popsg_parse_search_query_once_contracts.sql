begin;
-- Read-only post-apply search contract. Performance proof remains on #4210.
select exists (select 1 from pg_proc where oid = to_regprocedure('public.search_style_guide_library_v2(text,text,text[],text[],text[],text[],text[],text[],text[],text[],timestamptz,timestamptz,text,integer,integer)')
  and md5(prosrc) = '9d5dd045810fa3fce5cc3d508e1210ff' and prosecdef and provolatile = 's'
  and proconfig @> array['search_path=pg_catalog, auth','work_mem=64MB'])
  and has_function_privilege('authenticated','public.search_style_guide_library_v2(text,text,text[],text[],text[],text[],text[],text[],text[],text[],timestamptz,timestamptz,text,integer,integer)','execute')
  and not has_function_privilege('anon','public.search_style_guide_library_v2(text,text,text[],text[],text[],text[],text[],text[],text[],text[],timestamptz,timestamptz,text,integer,integer)','execute') as passed;

do $contract$
declare b text; passed boolean;
begin
 select exists (select 1 from pg_proc where oid = to_regprocedure('public.search_style_guide_library_v2(text,text,text[],text[],text[],text[],text[],text[],text[],text[],timestamptz,timestamptz,text,integer,integer)')
  and md5(prosrc) = '9d5dd045810fa3fce5cc3d508e1210ff' and prosecdef and provolatile = 's'
  and proconfig @> array['search_path=pg_catalog, auth','work_mem=64MB'])
  and has_function_privilege('authenticated','public.search_style_guide_library_v2(text,text,text[],text[],text[],text[],text[],text[],text[],text[],timestamptz,timestamptz,text,integer,integer)','execute')
  and not has_function_privilege('anon','public.search_style_guide_library_v2(text,text,text[],text[],text[],text[],text[],text[],text[],text[],timestamptz,timestamptz,text,integer,integer)','execute') into passed;
 if passed is distinct from true then raise exception 'Search identity, settings or grants changed'; end if;
 select prosrc into b from pg_proc where oid = to_regprocedure('public.search_style_guide_library_v2(text,text,text[],text[],text[],text[],text[],text[],text[],text[],timestamptz,timestamptz,text,integer,integer)');
 if position('execute $guides_query$' in b)=0
   or position('$guides_query$ into v_result using v_mode, p_query, p_licensors' in b)=0
   or position('page_children as materialized' in b)=0
   or position('page_metadata as materialized' in b)=0
   or position('page_tags as materialized' in b)=0 then
   raise exception 'Search must use bound guide planning and separate tag/page metadata';
 end if;
end
$contract$;
rollback;
