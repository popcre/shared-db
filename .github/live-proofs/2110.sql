-- Live proof for issue #2110: frozen schema absent, FKs resolve to exact dflow targets,
-- and child row counts are preserved (2,276 attachments, 4 role permissions).
SELECT
  (to_regnamespace('designflow_frozen_20260710') IS NULL
   AND (SELECT count(*) FROM plm.art_piece_attachment) = 2276
   AND (SELECT count(*) FROM app."RolePermissions") = 4
   AND (SELECT count(*) FROM pg_constraint con
        JOIN pg_class confrel ON confrel.oid = con.confrelid
        JOIN pg_namespace ns ON ns.oid = confrel.relnamespace
        JOIN pg_class conrel ON conrel.oid = con.conrelid
        JOIN pg_namespace nsc ON nsc.oid = conrel.relnamespace
        JOIN pg_attribute a_child ON a_child.attrelid = conrel.oid AND a_child.attnum = con.conkey[1]
        JOIN pg_attribute a_parent ON a_parent.attrelid = confrel.oid AND a_parent.attnum = con.confkey[1]
        WHERE con.contype = 'f'
          AND con.conname = 'art_piece_attachment_art_piece_id_fkey'
          AND ns.nspname = 'dflow' AND confrel.relname = 'art_piece'
          AND nsc.nspname = 'plm' AND conrel.relname = 'art_piece_attachment'
          AND a_child.attname = 'art_piece_id' AND a_parent.attname = 'id'
          AND con.convalidated AND array_length(con.conkey, 1) = 1 AND array_length(con.confkey, 1) = 1
          AND con.confupdtype = 'a' AND con.confdeltype = 'a'
          AND NOT con.condeferrable AND NOT con.condeferred AND con.confmatchtype = 's') = 1
   AND (SELECT count(*) FROM pg_constraint con
        JOIN pg_class confrel ON confrel.oid = con.confrelid
        JOIN pg_namespace ns ON ns.oid = confrel.relnamespace
        JOIN pg_class conrel ON conrel.oid = con.conrelid
        JOIN pg_namespace nsc ON nsc.oid = conrel.relnamespace
        JOIN pg_attribute a_child ON a_child.attrelid = conrel.oid AND a_child.attnum = con.conkey[1]
        JOIN pg_attribute a_parent ON a_parent.attrelid = confrel.oid AND a_parent.attnum = con.confkey[1]
        WHERE con.contype = 'f'
          AND con.conname = 'RolePermissions_RoleId_fkey'
          AND ns.nspname = 'dflow' AND confrel.relname = 'Roles'
          AND nsc.nspname = 'app' AND conrel.relname = 'RolePermissions'
          AND a_child.attname = 'RoleId' AND a_parent.attname = 'Id'
          AND con.convalidated AND array_length(con.conkey, 1) = 1 AND array_length(con.confkey, 1) = 1
          AND con.confupdtype = 'a' AND con.confdeltype = 'a'
          AND NOT con.condeferrable AND NOT con.condeferred AND con.confmatchtype = 's') = 1) as passed
