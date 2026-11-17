-- #4708 read-only live proof: the owner-ruled factory fields and link tables exist with row security.
select
  (select count(*) from pg_catalog.pg_attribute a
    where a.attrelid = 'core.factory'::regclass and not a.attisdropped
      and a.attname in ('party_type', 'designflow_vendor_id', 'trade_name', 'orders_completed', 'orders_with_problem')) = 5
  and (select count(*) from pg_catalog.pg_class c
        where c.oid in (to_regclass('core.product_category'), to_regclass('core.factory_product_category'),
                        to_regclass('core.factory_representation'), to_regclass('core.factory_rep'),
                        to_regclass('core.factory_vendor_login'))
          and c.relrowsecurity) = 5
  and not has_table_privilege('anon', 'core.factory_vendor_login', 'select')
  and exists (select 1 from pg_catalog.pg_index i
              where i.indexrelid = to_regclass('core.factory_designflow_vendor_id_key') and i.indisunique)
  and (select count(*) from pg_catalog.pg_policies p where p.schemaname = 'core'
        and p.tablename in ('product_category', 'factory_product_category', 'factory_representation',
                            'factory_rep', 'factory_vendor_login')) = 9
  and position('core.factory_vendor_login' in pg_get_functiondef('core.merge_factory(uuid,uuid,boolean)'::regprocedure)) > 0
  as passed;
