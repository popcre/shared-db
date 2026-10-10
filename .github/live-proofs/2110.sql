-- Live proof for issue #2110: frozen schema absent AND both FKs resolve to dflow.
SELECT
  (to_regnamespace('designflow_frozen_20260710') IS NULL
   AND (SELECT count(*) FROM pg_constraint con
        JOIN pg_class confrel ON confrel.oid = con.confrelid
        JOIN pg_namespace ns ON ns.oid = confrel.relnamespace
        WHERE con.contype = 'f'
          AND con.conname = 'art_piece_attachment_art_piece_id_fkey'
          AND ns.nspname = 'dflow') = 1
   AND (SELECT count(*) FROM pg_constraint con
        JOIN pg_class confrel ON confrel.oid = con.confrelid
        JOIN pg_namespace ns ON ns.oid = confrel.relnamespace
        WHERE con.contype = 'f'
          AND con.conname = 'RolePermissions_RoleId_fkey'
          AND ns.nspname = 'dflow') = 1) as passed
