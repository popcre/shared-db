-- #4634: production table-only acceptance. Management API enforces read_only.
SELECT to_regclass('dflow_prod.vendor_wechat_identity') IS NOT NULL
   AND EXISTS (SELECT 1 FROM pg_index i JOIN pg_attribute a
               ON a.attrelid=i.indrelid AND a.attnum=i.indkey[0]
               WHERE i.indrelid=to_regclass('dflow_prod.vendor_wechat_identity')
                 AND i.indisunique AND i.indisvalid AND i.indnkeyatts=1
                 AND i.indpred IS NULL AND i.indexprs IS NULL AND a.attname='wechat_key')
   AND has_table_privilege('designflow_prod_backend_runtime',
                          'dflow_prod.vendor_wechat_identity','SELECT')
   AND has_table_privilege('designflow_prod_backend_runtime',
                          'dflow_prod.vendor_wechat_identity','INSERT')
   AND has_table_privilege('designflow_prod_backend_runtime',
                          'dflow_prod.vendor_wechat_identity','UPDATE') as passed;
