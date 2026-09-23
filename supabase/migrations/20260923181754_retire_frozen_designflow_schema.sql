-- Work issue #2110; reserved author claim #3378.
-- Albert authorized retirement and repointing on 2026-09-06.
-- Recovery, backup fingerprint and reviewed historical differences:
-- docs/verification/2110-frozen-designflow-retirement.md
-- No row is moved or rewritten. All removals are explicit and RESTRICT.
BEGIN;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '120s';

-- Freeze both child sets, the proposed parents and every retiring table while
-- checking identity. SHARE blocks parent writes without changing parent data.
LOCK TABLE app."RolePermissions", plm.art_piece_attachment IN ACCESS EXCLUSIVE MODE;
LOCK TABLE dflow."Roles", dflow.art_piece IN SHARE MODE;
LOCK TABLE designflow_frozen_20260710."Factory",
  designflow_frozen_20260710."Roles", designflow_frozen_20260710.art_piece,
  designflow_frozen_20260710.artists, designflow_frozen_20260710.comments,
  designflow_frozen_20260710.customers,
  designflow_frozen_20260710.product_category IN ACCESS EXCLUSIVE MODE;

DO $retirement$
DECLARE
  actual text[];
  attachment_count bigint;
  permission_count bigint;
  child_oid oid;
  old_parent_oid oid;
  child_column text;
  parent_column text;
  constraint_name text;
  spec record;
BEGIN
  SELECT array_agg(c.relname::text ORDER BY c.relname::text) INTO actual
  FROM pg_class c WHERE c.relnamespace='designflow_frozen_20260710'::regnamespace
    AND c.relkind IN ('r','p','v','m','f');
  IF actual IS DISTINCT FROM ARRAY['Factory','Roles','art_piece','artists','comments','customers','product_category'] THEN
    RAISE EXCEPTION '2110: frozen relation inventory changed';
  END IF;
  SELECT array_agg(c.relname::text ORDER BY c.relname::text) INTO actual
  FROM pg_class c WHERE c.relnamespace='designflow_frozen_20260710'::regnamespace AND c.relkind='S';
  IF actual IS DISTINCT FROM ARRAY['Factory_id_seq','Roles_Id_seq','StandardizedVersionDetail_id_seq','StandardizedVersion_id_seq','art_piece_id_seq','artists_id_seq','comments_id_seq','customers_customers_id_seq','product_category_id_seq'] THEN
    RAISE EXCEPTION '2110: frozen sequence inventory changed';
  END IF;
  IF EXISTS (SELECT FROM pg_proc WHERE pronamespace='designflow_frozen_20260710'::regnamespace) THEN
    RAISE EXCEPTION '2110: unexpected frozen routine';
  END IF;
  -- PL/pgSQL text references are not necessarily catalog dependencies. Refuse
  -- any newly introduced mention rather than deleting its target silently.
  IF EXISTS (SELECT FROM pg_proc WHERE prosrc ILIKE '%designflow_frozen_20260710%') THEN
    RAISE EXCEPTION '2110: routine text references frozen schema';
  END IF;
  IF (SELECT count(*) FROM designflow_frozen_20260710."Factory") <> 175
    OR (SELECT count(*) FROM designflow_frozen_20260710."Roles") <> 5
    OR (SELECT count(*) FROM designflow_frozen_20260710.art_piece) <> 1114
    OR (SELECT count(*) FROM designflow_frozen_20260710.artists) <> 14
    OR (SELECT count(*) FROM designflow_frozen_20260710.comments) <> 13
    OR (SELECT count(*) FROM designflow_frozen_20260710.customers) <> 57
    OR (SELECT count(*) FROM designflow_frozen_20260710.product_category) <> 7 THEN
    RAISE EXCEPTION '2110: frozen row inventory no longer matches verified recovery capture';
  END IF;

  -- Reject every normal external dependency except these two exact constraints.
  -- Internal defaults, indexes and constraints are removed with their tables.
  IF EXISTS (
    SELECT FROM pg_depend dep JOIN pg_class target ON target.oid=dep.refobjid
    WHERE dep.refclassid='pg_class'::regclass
      AND target.relnamespace='designflow_frozen_20260710'::regnamespace
      AND dep.deptype='n'
      AND NOT EXISTS (SELECT FROM pg_class own WHERE dep.classid='pg_class'::regclass AND own.oid=dep.objid AND own.relnamespace=target.relnamespace)
      AND NOT EXISTS (SELECT FROM pg_attrdef ad JOIN pg_class own ON own.oid=ad.adrelid WHERE dep.classid='pg_attrdef'::regclass AND ad.oid=dep.objid AND own.relnamespace=target.relnamespace)
      AND NOT EXISTS (SELECT FROM pg_constraint con WHERE dep.classid='pg_constraint'::regclass AND con.oid=dep.objid AND (con.connamespace=target.relnamespace OR
        (con.conrelid='app."RolePermissions"'::regclass AND con.conname='RolePermissions_RoleId_fkey') OR
        (con.conrelid='plm.art_piece_attachment'::regclass AND con.conname='art_piece_attachment_art_piece_id_fkey')))
  ) THEN RAISE EXCEPTION '2110: unknown external dependency'; END IF;

  -- Frozen art-source and update metadata were superseded in dflow. They are
  -- deliberately neither compared nor copied back. Every other field matches.
  IF EXISTS (
    SELECT FROM designflow_frozen_20260710.art_piece f
    LEFT JOIN dflow.art_piece p ON p.id=f.id
    WHERE p.id IS NULL OR
      (to_jsonb(f)-ARRAY['art_source_id','updated_at','updated_by']) IS DISTINCT FROM
      (to_jsonb(p)-ARRAY['art_source_id','updated_at','updated_by'])
  ) THEN RAISE EXCEPTION '2110: art parent identity changed'; END IF;
  -- app_role_id is the live-only identity bridge; all frozen role fields match.
  IF EXISTS (
    SELECT FROM app."RolePermissions" child
    LEFT JOIN designflow_frozen_20260710."Roles" f ON f."Id"=child."RoleId"
    LEFT JOIN dflow."Roles" p ON p."Id"=child."RoleId"
    WHERE f."Id" IS NULL OR p."Id" IS NULL OR to_jsonb(f) IS DISTINCT FROM (to_jsonb(p)-'app_role_id')
  ) THEN RAISE EXCEPTION '2110: role parent identity changed'; END IF;
  IF EXISTS (
    SELECT FROM plm.art_piece_attachment child LEFT JOIN dflow.art_piece p ON p.id=child.art_piece_id
    WHERE p.id IS NULL
  ) THEN RAISE EXCEPTION '2110: attachment lacks live parent'; END IF;

  SELECT count(*) INTO attachment_count FROM plm.art_piece_attachment;
  SELECT count(*) INTO permission_count FROM app."RolePermissions";

  FOR spec IN SELECT * FROM (VALUES
    ('app."RolePermissions"','dflow."Roles"','designflow_frozen_20260710."Roles"','RoleId','Id','RolePermissions_RoleId_fkey','retirement_2110_role_fkey'),
    ('plm.art_piece_attachment','dflow.art_piece','designflow_frozen_20260710.art_piece','art_piece_id','id','art_piece_attachment_art_piece_id_fkey','retirement_2110_art_fkey')
  ) AS s(child_table,parent_table,old_parent,child_key,parent_key,old_name,new_name)
  LOOP
    child_oid := spec.child_table::regclass;
    old_parent_oid := spec.old_parent::regclass;
    child_column := spec.child_key;
    parent_column := spec.parent_key;
    constraint_name := spec.old_name;
    IF NOT EXISTS (
      SELECT FROM pg_constraint c
      WHERE c.conrelid=child_oid AND c.conname=constraint_name AND c.contype='f'
        AND c.confrelid=old_parent_oid AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred
        AND c.confupdtype='a' AND c.confdeltype='a' AND c.confmatchtype='s'
        AND c.conkey=ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid=child_oid AND attname=child_column)]::smallint[]
        AND c.confkey=ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid=old_parent_oid AND attname=parent_column)]::smallint[]
    ) THEN RAISE EXCEPTION '2110: original foreign key contract changed for %', constraint_name; END IF;
  END LOOP;

  ALTER TABLE app."RolePermissions" ADD CONSTRAINT retirement_2110_role_fkey
    FOREIGN KEY ("RoleId") REFERENCES dflow."Roles"("Id")
    ON UPDATE NO ACTION ON DELETE NO ACTION NOT DEFERRABLE NOT VALID;
  ALTER TABLE app."RolePermissions" VALIDATE CONSTRAINT retirement_2110_role_fkey;
  ALTER TABLE app."RolePermissions" DROP CONSTRAINT "RolePermissions_RoleId_fkey" RESTRICT;
  ALTER TABLE app."RolePermissions" RENAME CONSTRAINT retirement_2110_role_fkey TO "RolePermissions_RoleId_fkey";
  ALTER TABLE plm.art_piece_attachment ADD CONSTRAINT retirement_2110_art_fkey
    FOREIGN KEY (art_piece_id) REFERENCES dflow.art_piece(id)
    ON UPDATE NO ACTION ON DELETE NO ACTION NOT DEFERRABLE NOT VALID;
  ALTER TABLE plm.art_piece_attachment VALIDATE CONSTRAINT retirement_2110_art_fkey;
  ALTER TABLE plm.art_piece_attachment DROP CONSTRAINT art_piece_attachment_art_piece_id_fkey RESTRICT;
  ALTER TABLE plm.art_piece_attachment RENAME CONSTRAINT retirement_2110_art_fkey TO art_piece_attachment_art_piece_id_fkey;

  -- One statement allows internal references among the explicitly named set.
  DROP TABLE designflow_frozen_20260710."Factory",
    designflow_frozen_20260710."Roles", designflow_frozen_20260710.art_piece,
    designflow_frozen_20260710.artists, designflow_frozen_20260710.comments,
    designflow_frozen_20260710.customers,
    designflow_frozen_20260710.product_category RESTRICT;
  -- Owned sequences already left with their owner. The two orphan sequences
  -- and any explicitly listed unowned remainder are still removed explicitly.
  DROP SEQUENCE IF EXISTS designflow_frozen_20260710."Factory_id_seq",
    designflow_frozen_20260710."Roles_Id_seq",
    designflow_frozen_20260710."StandardizedVersionDetail_id_seq",
    designflow_frozen_20260710."StandardizedVersion_id_seq",
    designflow_frozen_20260710.art_piece_id_seq,
    designflow_frozen_20260710.artists_id_seq,
    designflow_frozen_20260710.comments_id_seq,
    designflow_frozen_20260710.customers_customers_id_seq,
    designflow_frozen_20260710.product_category_id_seq RESTRICT;
  DROP SCHEMA designflow_frozen_20260710 RESTRICT;
  IF to_regnamespace('designflow_frozen_20260710') IS NOT NULL
    OR (SELECT count(*) FROM plm.art_piece_attachment) <> attachment_count
    OR (SELECT count(*) FROM app."RolePermissions") <> permission_count THEN
    RAISE EXCEPTION '2110: retirement postcondition failed';
  END IF;
END
$retirement$;
COMMIT;
