-- Live proof for issue #2110: frozen schema designflow_frozen_20260710 is absent
-- and the two repointed foreign keys resolve to dflow parents.
-- Run read-only against production after the migration applies.
SELECT
  (to_regnamespace('designflow_frozen_20260710') IS NULL) AS schema_absent,
  (SELECT count(*) FROM plm.art_piece_attachment) AS attachment_rows,
  (SELECT count(*) FROM app."RolePermissions") AS role_permission_rows,
  (SELECT count(*)
   FROM pg_constraint con
   JOIN pg_class confrel ON confrel.oid = con.confrelid
   JOIN pg_namespace ns ON ns.oid = confrel.relnamespace
   WHERE con.contype = 'f'
     AND con.conname = 'art_piece_attachment_art_piece_id_fkey'
     AND ns.nspname = 'dflow') AS art_fk_to_dflow,
  (SELECT count(*)
   FROM pg_constraint con
   JOIN pg_class confrel ON confrel.oid = con.confrelid
   JOIN pg_namespace ns ON ns.oid = confrel.relnamespace
   WHERE con.contype = 'f'
     AND con.conname = 'RolePermissions_RoleId_fkey'
     AND ns.nspname = 'dflow') AS role_fk_to_dflow;
