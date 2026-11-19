select (
  (select count(*) = 1
   from pg_class idx
   join pg_namespace ns on ns.oid = idx.relnamespace
   join pg_index i on i.indexrelid = idx.oid
   where ns.nspname = 'public'
     and idx.relname = 'idx_assets_sku_division_active'
     and i.indrelid = 'public.assets'::regclass
     and not i.indisunique
     and i.indisvalid and i.indisready
     and i.indnkeyatts = 2 and i.indnatts = 2
     and idx.relam = (select oid from pg_am where amname = 'btree')
     and pg_get_indexdef(idx.oid, 1, true) = 'sku'
     and pg_get_indexdef(idx.oid, 2, true) = 'division_code'
     and pg_get_expr(i.indpred, i.indrelid) = '(is_deleted = false)')
  and exists (
    select 1 from supabase_migrations.schema_migrations
    where version = '20261008041231'
  )
) as passed;
