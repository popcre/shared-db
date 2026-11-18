-- #5758 Step 4: PopSG embedding queue state lives in the narrow jobs table,
-- the embedding RPCs no longer touch the wide document's queue columns, and
-- the hts_rag ingest-job retention is scheduled.
select
  exists(select 1 from supabase_migrations.schema_migrations where version='20261106153730')
  and to_regclass('public.style_guide_search_embedding_jobs') is not null
  and (select relrowsecurity from pg_class where oid=to_regclass('public.style_guide_search_embedding_jobs'))
  and not has_table_privilege('anon','public.style_guide_search_embedding_jobs','select')
  and not has_table_privilege('authenticated','public.style_guide_search_embedding_jobs','select')
  and (select count(*)=1 from pg_index where indrelid=to_regclass('public.style_guide_search_embedding_jobs'))
  and pg_get_functiondef('public.claim_sg_search_embedding_documents(integer,text,integer)'::regprocedure) like '%style_guide_search_embedding_jobs%'
  and pg_get_functiondef('public.claim_sg_search_embedding_documents(integer,text,integer)'::regprocedure) not like '%embedding_lease_token%'
  and pg_get_functiondef('public.upsert_sg_search_embedding(uuid,text,uuid,extensions.vector,text)'::regprocedure) not like '%embedding_lease_token%'
  and (select count(*)=1 and bool_and(active and schedule='15 8 * * 0'
         and command like '%hts_rag.prune_ruling_ingest_jobs(false)%')
         from cron.job where jobname='hts-rag-ingest-jobs-retention')
  and not has_function_privilege('anon','hts_rag.prune_ruling_ingest_jobs(boolean)','execute')
  as passed;
