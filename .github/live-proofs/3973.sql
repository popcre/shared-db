select (
  (select count(*) = 1
   from pg_class idx
   join pg_namespace ns on ns.oid = idx.relnamespace
   join pg_index i on i.indexrelid = idx.oid
   where ns.nspname = 'ingest'
     and idx.relname = 'sync_run_source_name_source_system_status_started_at_idx'
     and i.indrelid = 'ingest.sync_run'::regclass
     and not i.indisunique
     and i.indpred is null
     and i.indisvalid and i.indisready
     and i.indnkeyatts = 4 and i.indnatts = 4
     and idx.relam = (select oid from pg_am where amname = 'btree')
     and pg_get_indexdef(idx.oid, 1, true) = 'source_name'
     and pg_get_indexdef(idx.oid, 2, true) = 'source_system'
     and pg_get_indexdef(idx.oid, 3, true) = 'status'
     and pg_get_indexdef(idx.oid, 4, true) = 'started_at DESC')
  and exists (
    select 1 from supabase_migrations.schema_migrations
    where version = '20261006170117'
  )
) as passed;
