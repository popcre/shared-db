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
  fk_count int;
BEGIN
  -- Precondition: the frozen schema must exist with exactly seven tables.
  SELECT array_agg(c.relname::text ORDER BY c.relname::text) INTO actual
  FROM pg_class c
  WHERE c.relnamespace = 'designflow_frozen_20260710'::regnamespace
    AND c.relkind IN ('r', 'p', 'v', 'm', 'f');
  IF actual IS DISTINCT FROM ARRAY['Factory', 'Roles', 'art_piece', 'artists', 'comments', 'customers', 'product_category'] THEN
    RAISE EXCEPTION '2110: frozen relation inventory changed: %', actual;
  END IF;

  -- Precondition: no inbound FK from outside the frozen schema.
  -- (Both known inbound FKs were repointed to dflow by PR #3893.)
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

  -- Precondition: no routine text references the frozen schema.
  IF EXISTS (SELECT FROM pg_proc WHERE prosrc ILIKE '%designflow_frozen_20260710%') THEN
    RAISE EXCEPTION '2110: routine text references frozen schema';
  END IF;

  -- Drop tables explicitly (RESTRICT). One statement allows internal FKs among them.
  DROP TABLE designflow_frozen_20260710."Factory",
    designflow_frozen_20260710."Roles",
    designflow_frozen_20260710.art_piece,
    designflow_frozen_20260710.artists,
    designflow_frozen_20260710.comments,
    designflow_frozen_20260710.customers,
    designflow_frozen_20260710.product_category
    RESTRICT;

  -- Drop sequences explicitly (RESTRICT). Some are orphaned (no owner table).
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
