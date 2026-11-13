-- shared-db issue #6239 - drop the empty leftover landing schema dflow_prod_old.
-- Owner authorization (Albert Hazan, chat 2026-11-13, verbatim: "drop the empty shelf").
-- Evidence: popcre/designflow-data-syncing#126 (zero readers; 127 tables, 0 rows).
-- Backup: gs://designflow-storage/backups/dflow-stale-cleanup-2026-11-12/prod_dflow_prod_old_schema.dump
-- Guard below refuses the drop if any table in the schema holds rows; the DROP
-- itself uses the default RESTRICT so it also refuses if anything outside the
-- schema depends on it.

do $guard$
declare
  t record;
  n bigint;
  v_bad text := '';
begin
  for t in
    select c.relname
      from pg_class c
      join pg_namespace ns on ns.oid = c.relnamespace
     where ns.nspname = 'dflow_prod_old'
       and c.relkind in ('r', 'p', 'm')
  loop
    execute format('select count(*) from %I.%I', 'dflow_prod_old', t.relname) into n;
    if n > 0 then
      v_bad := v_bad || t.relname || '=' || n || ' ';
    end if;
  end loop;
  if v_bad <> '' then
    raise exception 'dflow_prod_old is not empty, refusing to drop: %', v_bad;
  end if;
end
$guard$;

drop schema if exists dflow_prod_old;
