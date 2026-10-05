-- Live proof for #3891 (migration 20261002161522). Read-only.
-- Proves on production: the migration is in the ledger and both foreign keys are
-- validated, single-column, on the expected child column, reference the dflow
-- parent's expected key column, and keep NO ACTION / NO ACTION, NOT DEFERRABLE, MATCH SIMPLE.
select (
  exists (select 1 from supabase_migrations.schema_migrations where version = '20261002161522')
  and (
    select count(*) from (values
      ('plm.art_piece_attachment', 'art_piece_attachment_art_piece_id_fkey', 'art_piece_id', 'dflow.art_piece', 'id'),
      ('app."RolePermissions"', 'RolePermissions_RoleId_fkey', 'RoleId', 'dflow."Roles"', 'Id')
    ) v(t, n, col, p, pc)
    join pg_catalog.pg_constraint c
      on c.contype = 'f' and c.convalidated
     and c.conrelid = pg_catalog.to_regclass(v.t) and c.conname = v.n
     and c.confrelid = pg_catalog.to_regclass(v.p)
     and c.confupdtype = 'a' and c.confdeltype = 'a'
     and not c.condeferrable and not c.condeferred and c.confmatchtype = 's'
     and array_length(c.conkey, 1) = 1 and array_length(c.confkey, 1) = 1
    join pg_catalog.pg_attribute ca on ca.attrelid = c.conrelid and ca.attnum = c.conkey[1] and ca.attname = v.col
    join pg_catalog.pg_attribute pa on pa.attrelid = c.confrelid and pa.attnum = c.confkey[1] and pa.attname = v.pc
  ) = 2
) as passed;
