-- Work issue #2110; reserved author claim #4155.
-- Drop frozen schema designflow_frozen_20260710.
-- Albert authorized retirement on 2026-09-06 ("delete it").
-- FK repoints to dflow parents landed in PR #3893 (merged 2026-10-02, production-verified 2026-10-06).
-- Backup: 1Password vault vibe_coding item zepc66j5xajdg4novzttmmrtg4 (SHA-256 916be84f...).
-- derived-from: none
BEGIN;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '120s';

-- Lock every retiring table to prevent concurrent writes during the drop.
LOCK TABLE designflow_frozen_20260710."Factory",
  designflow_frozen_20260710."Roles",
  designflow_frozen_20260710.art_piece,
  designflow_frozen_20260710.artists,
  designflow_frozen_20260710.comments,
  designflow_frozen_20260710.customers,
  designflow_frozen_20260710.product_category
  IN ACCESS EXCLUSIVE MODE;

DO $drop_frozen$
DECLARE
  actual text[];
  seq_actual text[];
  fn_actual text[];
  fk_count int;
BEGIN
  -- Precondition: frozen schema must exist.
  IF to_regnamespace('designflow_frozen_20260710') IS NULL THEN
    RAISE EXCEPTION '2110: frozen schema already absent';
  END IF;

  -- Precondition: exactly seven base tables.
  SELECT array_agg(c.relname::text ORDER BY c.relname::text) INTO actual
  FROM pg_class c
  WHERE c.relnamespace = 'designflow_frozen_20260710'::regnamespace
    AND c.relkind = 'r';
  IF actual IS DISTINCT FROM ARRAY['Factory', 'Roles', 'art_piece', 'artists', 'comments', 'customers', 'product_category'] THEN
    RAISE EXCEPTION '2110: frozen table inventory changed: %', actual;
  END IF;

  -- Precondition: exactly nine sequences.
  SELECT array_agg(c.relname::text ORDER BY c.relname::text) INTO seq_actual
  FROM pg_class c
  WHERE c.relnamespace = 'designflow_frozen_20260710'::regnamespace
    AND c.relkind = 'S';
  IF seq_actual IS DISTINCT FROM ARRAY['Factory_id_seq', 'Roles_Id_seq', 'StandardizedVersionDetail_id_seq', 'StandardizedVersion_id_seq', 'art_piece_id_seq', 'artists_id_seq', 'comments_id_seq', 'customers_customers_id_seq', 'product_category_id_seq'] THEN
    RAISE EXCEPTION '2110: frozen sequence inventory changed: %', seq_actual;
  END IF;

  -- Precondition: known functions in the frozen schema (assert and drop explicitly).
  SELECT array_agg(p.proname::text ORDER BY p.proname::text) INTO fn_actual
  FROM pg_proc p
  WHERE p.pronamespace = 'designflow_frozen_20260710'::regnamespace;
  IF fn_actual IS NOT NULL AND fn_actual NOT IN (ARRAY['get_child_id', 'get_parent_id'], ARRAY['get_parent_id', 'get_child_id']) THEN
    RAISE EXCEPTION '2110: unexpected frozen function inventory: %', fn_actual;
  END IF;

  -- Precondition: no inbound FK from outside the frozen schema.
  SELECT count(*) INTO fk_count
  FROM pg_constraint con
  JOIN pg_class confrel ON confrel.oid = con.confrelid
  JOIN pg_namespace ns_parent ON ns_parent.oid = confrel.relnamespace
  JOIN pg_class conrel ON conrel.oid = con.conrelid
  JOIN pg_namespace ns_child ON ns_child.oid = conrel.relnamespace
  WHERE con.contype = 'f'
    AND ns_parent.nspname = 'designflow_frozen_20260710'
    AND ns_child.nspname <> 'designflow_frozen_20260710';
  IF fk_count > 0 THEN
    RAISE EXCEPTION '2110: % inbound foreign keys still reference the frozen schema', fk_count;
  END IF;

  -- Precondition: art_piece_attachment FK resolves to dflow.art_piece(id).
  IF (SELECT count(*) FROM pg_constraint con
      JOIN pg_class confrel ON confrel.oid = con.confrelid
      JOIN pg_namespace ns ON ns.oid = confrel.relnamespace
      JOIN pg_class conrel ON conrel.oid = con.conrelid
      JOIN pg_namespace nsc ON nsc.oid = conrel.relnamespace
      WHERE con.contype = 'f'
        AND con.conname = 'art_piece_attachment_art_piece_id_fkey'
        AND ns.nspname = 'dflow' AND confrel.relname = 'art_piece'
        AND nsc.nspname = 'plm' AND conrel.relname = 'art_piece_attachment') <> 1 THEN
    RAISE EXCEPTION '2110: art_piece_attachment FK does not resolve to dflow.art_piece';
  END IF;

  -- Precondition: RolePermissions FK resolves to dflow."Roles"("Id").
  IF (SELECT count(*) FROM pg_constraint con
      JOIN pg_class confrel ON confrel.oid = con.confrelid
      JOIN pg_namespace ns ON ns.oid = confrel.relnamespace
      JOIN pg_class conrel ON conrel.oid = con.conrelid
      JOIN pg_namespace nsc ON nsc.oid = conrel.relnamespace
      WHERE con.contype = 'f'
        AND con.conname = 'RolePermissions_RoleId_fkey'
        AND ns.nspname = 'dflow' AND confrel.relname = 'Roles'
        AND nsc.nspname = 'app' AND conrel.relname = 'RolePermissions') <> 1 THEN
    RAISE EXCEPTION '2110: RolePermissions FK does not resolve to dflow.Roles';
  END IF;

  -- Drop functions explicitly (RESTRICT).
  IF fn_actual IS NOT NULL THEN
    IF 'get_child_id' = ANY(fn_actual) THEN
      EXECUTE 'DROP FUNCTION designflow_frozen_20260710.get_child_id() RESTRICT';
    END IF;
    IF 'get_parent_id' = ANY(fn_actual) THEN
      EXECUTE 'DROP FUNCTION designflow_frozen_20260710.get_parent_id() RESTRICT';
    END IF;
  END IF;

  -- Drop tables explicitly (RESTRICT). Owned sequences drop implicitly.
  DROP TABLE designflow_frozen_20260710."Factory",
    designflow_frozen_20260710."Roles",
    designflow_frozen_20260710.art_piece,
    designflow_frozen_20260710.artists,
    designflow_frozen_20260710.comments,
    designflow_frozen_20260710.customers,
    designflow_frozen_20260710.product_category
    RESTRICT;

  -- Drop remaining sequences (unowned orphans survive table drops).
  DROP SEQUENCE IF EXISTS
    designflow_frozen_20260710."Factory_id_seq",
    designflow_frozen_20260710."Roles_Id_seq",
    designflow_frozen_20260710."StandardizedVersionDetail_id_seq",
    designflow_frozen_20260710."StandardizedVersion_id_seq",
    designflow_frozen_20260710.art_piece_id_seq,
    designflow_frozen_20260710.artists_id_seq,
    designflow_frozen_20260710.comments_id_seq,
    designflow_frozen_20260710.customers_customers_id_seq,
    designflow_frozen_20260710.product_category_id_seq
    RESTRICT;

  -- Drop the schema itself (RESTRICT, no CASCADE).
  DROP SCHEMA designflow_frozen_20260710 RESTRICT;

  -- Postcondition: schema is gone.
  IF to_regnamespace('designflow_frozen_20260710') IS NOT NULL THEN
    RAISE EXCEPTION '2110: schema still exists after drop';
  END IF;
END
$drop_frozen$;
COMMIT;
