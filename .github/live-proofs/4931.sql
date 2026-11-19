-- #4931: production acceptance. Management API enforces read_only.
SELECT (SELECT count(*) FROM pg_attribute a
        WHERE a.attrelid = 'api.dam_order_list'::regclass AND a.attnum > 0 AND NOT a.attisdropped) = 94
   AND (SELECT a.attname FROM pg_attribute a
        WHERE a.attrelid = 'api.dam_order_list'::regclass AND a.attnum = 93) = 'coldlion_quantity_ordered'
   AND (SELECT a.attname FROM pg_attribute a
        WHERE a.attrelid = 'api.dam_order_list'::regclass AND a.attnum = 94) = 'coldlion_import_po'
   AND (SELECT c.reloptions @> array['security_invoker=true'] FROM pg_class c
        WHERE c.oid = 'api.dam_order_list'::regclass) as passed;
