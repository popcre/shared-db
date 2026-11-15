-- derived-from: none
-- Claim popcre/shared-db#6343. Work issue popcre/designflow-item-master#205,
-- plan plan_merch-group-environment-parity.md step 3.1 (remaining links).
-- PRODUCTION SHAPE (schema dflow_prod, project qsllyeztdwjgirsysgai), promoted
-- by the normal shared preview -> production lanes. Not needed on DesignFlow
-- non-production: there all ten keys already reference dflow."merchGroup"
-- (read-only 2026-11-15 1:10 AM EST).
--
-- Why: production DesignFlow services read and write dflow_prod."merchGroup";
-- core."merchGroup" is a stale copy due to be renamed (step 3.2). Ten keys on
-- dflow.art_piece (9) and dflow.artists (1) still reference it. This drops and
-- re-adds each same-named key against dflow_prod."merchGroup"(mg_id), keeping
-- its actions (ON UPDATE/ON DELETE NO ACTION): added NOT VALID, then VALIDATE.
--
-- Read-only before authoring (2026-11-15 1:08 AM EST): 1,116 art_piece rows,
-- 14 artists rows, 0 values absent from dflow_prod."merchGroup" (4,417 rows).
-- The self-check refuses (never deletes or edits rows) if any orphan appears.
-- Empty-parent guard (pattern of 20261114231235): ONLY when
-- dflow_prod."merchGroup" holds no row (unseeded preview, fresh database) the
-- orphan refusal and VALIDATE are skipped, so the keys stay NOT VALID there;
-- new rows are still checked. A key already on dflow_prod is left alone
-- (re-apply is a no-op); a missing table is skipped.
-- Rollback: drop each constraint and re-add it referencing core."merchGroup"(mg_id).

begin;
set local lock_timeout = '5s';
set local statement_timeout = '5min';

do $repoint$
declare
  k record;
  n bigint;
  parent_empty boolean;
  target oid;
begin
  if to_regclass('dflow_prod."merchGroup"') is null then
    raise exception '#6343/20261115060819 self-check: dflow_prod."merchGroup" is missing; production-shape migration only'
      using errcode = 'feature_not_supported';
  end if;
  target := 'dflow_prod."merchGroup"'::regclass;
  parent_empty := not exists (select 1 from dflow_prod."merchGroup");

  for k in
    select * from (values
      ('art_piece', 'age_group_id',    'art_piece_age_group_id_fkey'),
      ('art_piece', 'art_source_id',   'art_piece_art_source_id_fkey'),
      ('art_piece', 'art_type_id',     'art_piece_art_type_id_fkey'),
      ('art_piece', 'artist_id',       'art_piece_artist_id_fkey'),
      ('art_piece', 'big_theme_id',    'art_piece_big_theme_id_fkey'),
      ('art_piece', 'licensor_id',     'art_piece_licensor_id_fkey'),
      ('art_piece', 'little_theme_id', 'art_piece_little_theme_id_fkey'),
      ('art_piece', 'property_id',     'art_piece_property_id_fkey'),
      ('art_piece', 'style_guide_id',  'art_piece_style_guide_id_fkey'),
      ('artists',   'art_source_id',   'artists_art_source_id_fkey')
    ) v(tbl, col, con)
  loop
    if to_regclass(format('dflow.%I', k.tbl)) is null then
      raise notice '#6343: dflow.% absent here; skipped', k.tbl;
      continue;
    end if;
    if exists (select 1 from pg_constraint
               where conrelid = format('dflow.%I', k.tbl)::regclass
                 and conname = k.con and confrelid = target) then
      continue;
    end if;
    if not parent_empty then
      execute format(
        'select count(*) from dflow.%I t where t.%I is not null and not exists (select 1 from dflow_prod."merchGroup" m where m.mg_id = t.%I)',
        k.tbl, k.col, k.col) into n;
      if n <> 0 then
        raise exception '#6343/20261115060819: % dflow.%.% values are absent from dflow_prod."merchGroup"; refuse (nothing deleted)', n, k.tbl, k.col
          using errcode = 'foreign_key_violation';
      end if;
    end if;
    execute format('alter table dflow.%I drop constraint if exists %I', k.tbl, k.con);
    execute format(
      'alter table dflow.%I add constraint %I foreign key (%I) references dflow_prod."merchGroup"(mg_id) on update no action on delete no action not valid',
      k.tbl, k.con, k.col);
    if parent_empty then
      raise notice '#6343: dflow_prod."merchGroup" is empty; % left NOT VALID', k.con;
    else
      execute format('alter table dflow.%I validate constraint %I', k.tbl, k.con);
    end if;
  end loop;
end
$repoint$;

commit;
