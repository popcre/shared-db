-- #2336 retained relationship summaries. Raw tables remain authorized history reads.
-- No historical inference: all sixteen tables must remain empty at installation.
begin;

lock table core.property_character_associations, core.property_character_source_edge, core.property_franchise, core.property_franchise_source_edge, core.property_style_guide, core.property_style_guide_source_edge, core.style_guide_character, core.style_guide_character_source_edge, dam.asset_character, dam.asset_character_source_edge, dam.asset_franchise, dam.asset_franchise_source_edge, dam.asset_property, dam.asset_property_source_edge, dam.asset_style_guide, dam.asset_style_guide_source_edge in access exclusive mode;

do $empty$ begin
if exists(select 1 from core.property_character_associations) then raise exception 'licensing lifecycle installation refused: core.property_character_associations is not empty'; end if;
if exists(select 1 from core.property_character_source_edge) then raise exception 'licensing lifecycle installation refused: core.property_character_source_edge is not empty'; end if;
if exists(select 1 from core.property_style_guide) then raise exception 'licensing lifecycle installation refused: core.property_style_guide is not empty'; end if;
if exists(select 1 from core.property_style_guide_source_edge) then raise exception 'licensing lifecycle installation refused: core.property_style_guide_source_edge is not empty'; end if;
if exists(select 1 from core.property_franchise) then raise exception 'licensing lifecycle installation refused: core.property_franchise is not empty'; end if;
if exists(select 1 from core.property_franchise_source_edge) then raise exception 'licensing lifecycle installation refused: core.property_franchise_source_edge is not empty'; end if;
if exists(select 1 from core.style_guide_character) then raise exception 'licensing lifecycle installation refused: core.style_guide_character is not empty'; end if;
if exists(select 1 from core.style_guide_character_source_edge) then raise exception 'licensing lifecycle installation refused: core.style_guide_character_source_edge is not empty'; end if;
if exists(select 1 from dam.asset_property) then raise exception 'licensing lifecycle installation refused: dam.asset_property is not empty'; end if;
if exists(select 1 from dam.asset_property_source_edge) then raise exception 'licensing lifecycle installation refused: dam.asset_property_source_edge is not empty'; end if;
if exists(select 1 from dam.asset_character) then raise exception 'licensing lifecycle installation refused: dam.asset_character is not empty'; end if;
if exists(select 1 from dam.asset_character_source_edge) then raise exception 'licensing lifecycle installation refused: dam.asset_character_source_edge is not empty'; end if;
if exists(select 1 from dam.asset_style_guide) then raise exception 'licensing lifecycle installation refused: dam.asset_style_guide is not empty'; end if;
if exists(select 1 from dam.asset_style_guide_source_edge) then raise exception 'licensing lifecycle installation refused: dam.asset_style_guide_source_edge is not empty'; end if;
if exists(select 1 from dam.asset_franchise) then raise exception 'licensing lifecycle installation refused: dam.asset_franchise is not empty'; end if;
if exists(select 1 from dam.asset_franchise_source_edge) then raise exception 'licensing lifecycle installation refused: dam.asset_franchise_source_edge is not empty'; end if;
end $empty$;

alter table core.property_character_associations add column is_current boolean not null default true;
alter table core.property_character_associations add column retired_at timestamptz;
alter table core.property_character_associations add column retired_reason text;
alter table core.property_character_associations add constraint property_character_associations_lifecycle_chk check ((is_current and retired_at is null and retired_reason is null) or (not is_current and retired_at is not null and nullif(btrim(retired_reason),'') is not null));

create view core.property_character_associations_current with (security_invoker=true) as select * from core.property_character_associations where is_current;
revoke all on core.property_character_associations_current from public, anon, authenticated, service_role;

comment on view core.property_character_associations_current is 'Current relationships only; raw table remains authorized historical summary with explicit lifecycle flags.';

grant select on core.property_character_associations_current to authenticated;
grant select on core.property_character_associations_current to service_role;

alter table core.property_style_guide add column is_current boolean not null default true;
alter table core.property_style_guide add column retired_at timestamptz;
alter table core.property_style_guide add column retired_reason text;
alter table core.property_style_guide add constraint property_style_guide_lifecycle_chk check ((is_current and retired_at is null and retired_reason is null) or (not is_current and retired_at is not null and nullif(btrim(retired_reason),'') is not null));

create view core.property_style_guide_current with (security_invoker=true) as select * from core.property_style_guide where is_current;
revoke all on core.property_style_guide_current from public, anon, authenticated, service_role;

comment on view core.property_style_guide_current is 'Current relationships only; raw table remains authorized historical summary with explicit lifecycle flags.';

grant select on core.property_style_guide_current to authenticated;
grant select on core.property_style_guide_current to service_role;

alter table core.property_franchise add column is_current boolean not null default true;
alter table core.property_franchise add column retired_at timestamptz;
alter table core.property_franchise add column retired_reason text;
alter table core.property_franchise add constraint property_franchise_lifecycle_chk check ((is_current and retired_at is null and retired_reason is null) or (not is_current and retired_at is not null and nullif(btrim(retired_reason),'') is not null));

create view core.property_franchise_current with (security_invoker=true) as select * from core.property_franchise where is_current;
revoke all on core.property_franchise_current from public, anon, authenticated, service_role;

comment on view core.property_franchise_current is 'Current relationships only; raw table remains authorized historical summary with explicit lifecycle flags.';

grant select on core.property_franchise_current to authenticated;
grant select on core.property_franchise_current to service_role;

alter table core.style_guide_character add column is_current boolean not null default true;
alter table core.style_guide_character add column retired_at timestamptz;
alter table core.style_guide_character add column retired_reason text;
alter table core.style_guide_character add constraint style_guide_character_lifecycle_chk check ((is_current and retired_at is null and retired_reason is null) or (not is_current and retired_at is not null and nullif(btrim(retired_reason),'') is not null));

create view core.style_guide_character_current with (security_invoker=true) as select * from core.style_guide_character where is_current;
revoke all on core.style_guide_character_current from public, anon, authenticated, service_role;

comment on view core.style_guide_character_current is 'Current relationships only; raw table remains authorized historical summary with explicit lifecycle flags.';

grant select on core.style_guide_character_current to authenticated;
grant select on core.style_guide_character_current to service_role;

alter table dam.asset_property add column is_current boolean not null default true;
alter table dam.asset_property add column retired_at timestamptz;
alter table dam.asset_property add column retired_reason text;
alter table dam.asset_property add constraint asset_property_lifecycle_chk check ((is_current and retired_at is null and retired_reason is null) or (not is_current and retired_at is not null and nullif(btrim(retired_reason),'') is not null));

create view dam.asset_property_current with (security_invoker=true) as select * from dam.asset_property where is_current;
revoke all on dam.asset_property_current from public, anon, authenticated, service_role;

comment on view dam.asset_property_current is 'Current relationships only; raw table remains authorized historical summary with explicit lifecycle flags.';

grant select on dam.asset_property_current to service_role;

alter table dam.asset_character add column is_current boolean not null default true;
alter table dam.asset_character add column retired_at timestamptz;
alter table dam.asset_character add column retired_reason text;
alter table dam.asset_character add constraint asset_character_lifecycle_chk check ((is_current and retired_at is null and retired_reason is null) or (not is_current and retired_at is not null and nullif(btrim(retired_reason),'') is not null));

create view dam.asset_character_current with (security_invoker=true) as select * from dam.asset_character where is_current;
revoke all on dam.asset_character_current from public, anon, authenticated, service_role;

comment on view dam.asset_character_current is 'Current relationships only; raw table remains authorized historical summary with explicit lifecycle flags.';

grant select on dam.asset_character_current to authenticated;

alter table dam.asset_style_guide add column is_current boolean not null default true;
alter table dam.asset_style_guide add column retired_at timestamptz;
alter table dam.asset_style_guide add column retired_reason text;
alter table dam.asset_style_guide add constraint asset_style_guide_lifecycle_chk check ((is_current and retired_at is null and retired_reason is null) or (not is_current and retired_at is not null and nullif(btrim(retired_reason),'') is not null));

create view dam.asset_style_guide_current with (security_invoker=true) as select * from dam.asset_style_guide where is_current;
revoke all on dam.asset_style_guide_current from public, anon, authenticated, service_role;

comment on view dam.asset_style_guide_current is 'Current relationships only; raw table remains authorized historical summary with explicit lifecycle flags.';

grant select on dam.asset_style_guide_current to service_role;

alter table dam.asset_franchise add column is_current boolean not null default true;
alter table dam.asset_franchise add column retired_at timestamptz;
alter table dam.asset_franchise add column retired_reason text;
alter table dam.asset_franchise add constraint asset_franchise_lifecycle_chk check ((is_current and retired_at is null and retired_reason is null) or (not is_current and retired_at is not null and nullif(btrim(retired_reason),'') is not null));

create view dam.asset_franchise_current with (security_invoker=true) as select * from dam.asset_franchise where is_current;
revoke all on dam.asset_franchise_current from public, anon, authenticated, service_role;

comment on view dam.asset_franchise_current is 'Current relationships only; raw table remains authorized historical summary with explicit lifecycle flags.';

grant select on dam.asset_franchise_current to service_role;

create or replace function core.lock_canonical_relationship_pair()
returns trigger language plpgsql set search_path=pg_catalog,pg_temp as $lock$
declare v_keys text[] := array[]::text[]; v_key text;
begin
 if tg_op <> 'INSERT' then v_keys := array_append(v_keys,tg_argv[0]||':'||(to_jsonb(old)->>tg_argv[1])||':'||(to_jsonb(old)->>tg_argv[2])); end if;
 if tg_op <> 'DELETE' then v_keys := array_append(v_keys,tg_argv[0]||':'||(to_jsonb(new)->>tg_argv[1])||':'||(to_jsonb(new)->>tg_argv[2])); end if;
 for v_key in select distinct k from unnest(v_keys) k order by k loop
  if v_key is null then raise exception 'relationship pair lock requires nonnull exact endpoints'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_key,0));
 end loop;
 if tg_op='DELETE' then return old; end if; return new;
end $lock$;
revoke all on function core.lock_canonical_relationship_pair() from public,anon,authenticated,service_role;


create trigger lock_relationship_pair before insert or update or delete on core.property_character_associations for each row execute function core.lock_canonical_relationship_pair('core.property_character_associations','property_id','character_id');

create trigger lock_relationship_pair before insert or update or delete on core.property_character_source_edge for each row execute function core.lock_canonical_relationship_pair('core.property_character_associations','property_id','character_id');

create trigger lock_relationship_pair before insert or update or delete on core.property_style_guide for each row execute function core.lock_canonical_relationship_pair('core.property_style_guide','property_id','style_guide_id');

create trigger lock_relationship_pair before insert or update or delete on core.property_style_guide_source_edge for each row execute function core.lock_canonical_relationship_pair('core.property_style_guide','property_id','style_guide_id');

create trigger lock_relationship_pair before insert or update or delete on core.property_franchise for each row execute function core.lock_canonical_relationship_pair('core.property_franchise','property_id','franchise_id');

create trigger lock_relationship_pair before insert or update or delete on core.property_franchise_source_edge for each row execute function core.lock_canonical_relationship_pair('core.property_franchise','property_id','franchise_id');

create trigger lock_relationship_pair before insert or update or delete on core.style_guide_character for each row execute function core.lock_canonical_relationship_pair('core.style_guide_character','style_guide_id','character_id');

create trigger lock_relationship_pair before insert or update or delete on core.style_guide_character_source_edge for each row execute function core.lock_canonical_relationship_pair('core.style_guide_character','style_guide_id','character_id');

create trigger lock_relationship_pair before insert or update or delete on dam.asset_property for each row execute function core.lock_canonical_relationship_pair('dam.asset_property','asset_id','property_id');

create trigger lock_relationship_pair before insert or update or delete on dam.asset_property_source_edge for each row execute function core.lock_canonical_relationship_pair('dam.asset_property','asset_id','property_id');

create trigger lock_relationship_pair before insert or update or delete on dam.asset_character for each row execute function core.lock_canonical_relationship_pair('dam.asset_character','asset_id','character_id');

create trigger lock_relationship_pair before insert or update or delete on dam.asset_character_source_edge for each row execute function core.lock_canonical_relationship_pair('dam.asset_character','asset_id','character_id');

create trigger lock_relationship_pair before insert or update or delete on dam.asset_style_guide for each row execute function core.lock_canonical_relationship_pair('dam.asset_style_guide','asset_id','style_guide_id');

create trigger lock_relationship_pair before insert or update or delete on dam.asset_style_guide_source_edge for each row execute function core.lock_canonical_relationship_pair('dam.asset_style_guide','asset_id','style_guide_id');

create trigger lock_relationship_pair before insert or update or delete on dam.asset_franchise for each row execute function core.lock_canonical_relationship_pair('dam.asset_franchise','asset_id','franchise_id');

create trigger lock_relationship_pair before insert or update or delete on dam.asset_franchise_source_edge for each row execute function core.lock_canonical_relationship_pair('dam.asset_franchise','asset_id','franchise_id');

create or replace function core.require_direct_support_for_canonical_edge()
returns trigger
language plpgsql
-- Round-3 review finding (hardening). This guard runs dynamic SQL, so its search_path
-- is pinned: every object it touches is written schema-qualified in this file, and
-- nothing may be resolved through a caller's or a temporary schema. EXECUTE is revoked
-- below so a signed-in caller cannot invoke the existence probe directly and use it as
-- an oracle over licensing evidence; firing a trigger does not require the privilege,
-- so nothing legitimate loses anything.
--
-- Round-4 review finding. SECURITY DEFINER, matching the convention of every comparable
-- guard in this repository (plm.reject_legacy_landing_resolution_write(),
-- public.sync_asset_effective_tags()). The guard reads catalog-of-record tables that the
-- WRITING role need not be able to read: service_role holds writes on the dam support-edge
-- tables but is granted no SELECT on dam.asset or dam.asset_character, so an invoker-rights
-- guard would fail with permission denied on the ordinary loader path. Widening the grants
-- instead would hand a write role standing read access it does not otherwise have, so the
-- definer is the narrower change as well as the conventional one. search_path is pinned
-- above and EXECUTE is revoked below, which is what makes the definer safe.
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_support   text := tg_argv[0];   -- fully qualified support-edge table
  v_left_col  text := tg_argv[1];
  v_right_col text := tg_argv[2];
  v_left      uuid;
  v_right     uuid;
  v_supported boolean;
begin
  if not new.is_current then return new; end if;
  -- to_jsonb rather than a composite parameter: a plpgsql trigger cannot reliably project
  -- a dynamically named column out of NEW, and this keeps one function serving all five
  -- bridges instead of five near-identical copies.
  v_left  := (to_jsonb(new) ->> v_left_col)::uuid;
  v_right := (to_jsonb(new) ->> v_right_col)::uuid;

  execute format(
    'select exists (select 1 from %s s where s.%I = $1 and s.%I = $2 '
    'and s.is_current '
    'and s.evidence_kind = ''direct_source_assertion''::core.relationship_evidence_kind)',
    v_support, v_left_col, v_right_col)
  into v_supported
  using v_left, v_right;

  if not v_supported then
    raise exception
      'Refused: canonical edge %.% (% = %, % = %) has no CURRENT direct source assertion in %. '
      'Inferred and co-occurrence evidence are never promoted to a canonical relationship -- '
      'record the licensor''s own assertion in the support-edge table first.',
      tg_table_schema, tg_table_name, v_left_col, v_left, v_right_col, v_right, v_support
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

create or replace function core.assert_canonical_edge_still_supported()
returns trigger
language plpgsql
-- Round-3 review finding (hardening). This guard runs dynamic SQL, so its search_path
-- is pinned: every object it touches is written schema-qualified in this file, and
-- nothing may be resolved through a caller's or a temporary schema. EXECUTE is revoked
-- below so a signed-in caller cannot invoke the existence probe directly and use it as
-- an oracle over licensing evidence; firing a trigger does not require the privilege,
-- so nothing legitimate loses anything.
--
-- Round-4 review finding. SECURITY DEFINER, matching the convention of every comparable
-- guard in this repository (plm.reject_legacy_landing_resolution_write(),
-- public.sync_asset_effective_tags()). The guard reads catalog-of-record tables that the
-- WRITING role need not be able to read: service_role holds writes on the dam support-edge
-- tables but is granted no SELECT on dam.asset or dam.asset_character, so an invoker-rights
-- guard would fail with permission denied on the ordinary loader path. Widening the grants
-- instead would hand a write role standing read access it does not otherwise have, so the
-- definer is the narrower change as well as the conventional one. search_path is pinned
-- above and EXECUTE is revoked below, which is what makes the definer safe.
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_bridge    text := tg_argv[0];   -- fully qualified canonical bridge table
  v_left_col  text := tg_argv[1];
  v_right_col text := tg_argv[2];
  v_left      uuid;
  v_right     uuid;
  v_bridged   boolean;
  v_supported boolean;
begin
  -- Only the loss of a current direct assertion can orphan anything.
  if not (old.is_current and old.evidence_kind = 'direct_source_assertion') then
    return null;
  end if;

  if tg_op = 'UPDATE'
     and new.is_current
     and new.evidence_kind = 'direct_source_assertion'
     and (to_jsonb(new) ->> v_left_col) is not distinct from (to_jsonb(old) ->> v_left_col)
     and (to_jsonb(new) ->> v_right_col) is not distinct from (to_jsonb(old) ->> v_right_col) then
    return null;
  end if;

  v_left  := (to_jsonb(old) ->> v_left_col)::uuid;
  v_right := (to_jsonb(old) ->> v_right_col)::uuid;

  execute format(
    'select exists (select 1 from %s b where b.%I = $1 and b.%I = $2 and b.is_current)',
    v_bridge, v_left_col, v_right_col)
  into v_bridged
  using v_left, v_right;

  if not v_bridged then
    return null;
  end if;

  -- At COMMIT the whole transaction is visible, so this sees the true end state: any
  -- replacement recorded anywhere in the transaction counts, and every withdrawal in it
  -- has already been applied.
  execute format(
    'select exists (select 1 from %I.%I s where s.%I = $1 and s.%I = $2 '
    'and s.is_current '
    'and s.evidence_kind = ''direct_source_assertion''::core.relationship_evidence_kind)',
    tg_table_schema, tg_table_name, v_left_col, v_right_col)
  into v_supported
  using v_left, v_right;

  if v_supported then
    return null;
  end if;

  raise exception
    'Refused at commit: the canonical edge in % (% = %, % = %) would be left with no current '
    'direct source assertion in %.%. Every direct assertion behind it was withdrawn or removed '
    'in this transaction. Record the replacing direct assertion in the same transaction, or '
    'retire the retained canonical summary in the same transaction.',
    v_bridge, v_left_col, v_left, v_right_col, v_right,
    tg_table_schema, tg_table_name
    using errcode = 'P0001';
end;
$$;

create trigger require_direct_support before insert or update on core.property_character_associations for each row execute function core.require_direct_support_for_canonical_edge('core.property_character_source_edge','property_id','character_id');

create trigger require_direct_support before insert or update on core.style_guide_character for each row execute function core.require_direct_support_for_canonical_edge('core.style_guide_character_source_edge','style_guide_id','character_id');

create trigger require_direct_support before insert or update on dam.asset_character for each row execute function core.require_direct_support_for_canonical_edge('dam.asset_character_source_edge','asset_id','character_id');

-- Preserve the current installed authorization and response contract; rewrite only
-- the two known association count sites, and fail on unexpected source shape.
do $tree$ declare v_definition text; v_old text := 'from core.property_character_associations a group by a.property_id';
begin
 select pg_get_functiondef('api.db_data_admin_licensor_property_tree(text,boolean,text,integer)'::regprocedure) into v_definition;
 if (length(v_definition)-length(replace(v_definition,v_old,'')))/length(v_old) <> 2 then raise exception 'licensing lifecycle tree count rewrite refused: expected exactly two current association count sites'; end if;
 v_definition := replace(v_definition,v_old,'from core.property_character_associations a where a.is_current group by a.property_id');
 execute v_definition;
end $tree$;














-- ENGINE GENERATION 3: complete physical consolidation, no history deletes.
lock table plm.licensing_consolidation_plan in access exclusive mode;
do $plans_empty$ begin
 if exists(select 1 from plm.licensing_consolidation_plan) then raise exception 'licensing engine forward refused: existing plans require separate migration'; end if;
end $plans_empty$;
alter table plm.licensing_consolidation_plan add column plan_schema_version integer not null default 2;
alter table plm.licensing_consolidation_plan add column capture_snapshot jsonb not null default '{}'::jsonb;
alter table plm.licensing_consolidation_plan add column applied_state jsonb;
alter table plm.licensing_consolidation_plan add constraint licensing_consolidation_plan_schema_version_chk check(plan_schema_version=2);
alter table plm.licensing_consolidation_plan add constraint licensing_consolidation_plan_capture_snapshot_chk check(jsonb_typeof(capture_snapshot)='object');
alter table plm.licensing_consolidation_plan add constraint licensing_consolidation_plan_applied_state_chk check(applied_state is null or jsonb_typeof(applied_state)='object');

create or replace function plm.licensing_consolidation_capture_snapshot(p_source_system text,p_capture_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog as $snapshot$
declare v_root jsonb; v_entities jsonb:='[]';v_edges jsonb:='[]';v_rows jsonb;v_row jsonb;v_rec record;v_coverage jsonb;v_latest uuid;v_scope text;v_native text;v_e jsonb;v_count bigint;v_expected numeric;v_hash text;v_properties bigint;v_characters bigint;v_relationships bigint;v_memberships bigint;v_cross_scope bigint;
begin
 if p_source_system='nbcu' then
  select to_jsonb(c) into v_root from plm.nbcu_capture c where id=p_capture_id and status='complete';
  select id into v_latest from plm.nbcu_capture where status='complete' order by source_captured_at desc,load_completed_at desc,id desc limit 1;
  if v_root is null or v_latest<>p_capture_id then raise exception 'NBCU requires latest complete immutable capture';end if;
  if v_root->>'load_completed_at' is null or coalesce((v_root->>'media_downloaded')::bigint,-1)<>0 or v_root->'error_summary' is distinct from '[]'::jsonb
    or not exists(select 1 from plm.nbcu_scope where capture_id=p_capture_id)
    or exists(select 1 from plm.nbcu_scope where capture_id=p_capture_id and (terminal is distinct from true or cardinality(missing_offsets) is distinct from 0)) then raise exception 'NBCU complete portal scope or terminal evidence absent';end if;
  for v_rec in select * from (values ('assets','nbcu_asset'),('properties','nbcu_property'),('characters','nbcu_character'),('style_guides','nbcu_style_guide'),('scopes','nbcu_scope'),('ip_family_property','nbcu_ip_family_property'),('property_character','nbcu_property_character'),('asset_property','nbcu_asset_property'),('asset_character','nbcu_asset_character'),('asset_style_guide','nbcu_asset_style_guide'),('style_guide_property','nbcu_style_guide_property'),('asset_ip_family','nbcu_asset_ip_family')) q(count_key,table_name) loop
   if jsonb_typeof(v_root->'expected_counts'->v_rec.count_key) is distinct from 'number' then raise exception 'NBCU expected count missing or nonnumeric: %',v_rec.count_key;end if;
   v_expected:=(v_root->'expected_counts'->>v_rec.count_key)::numeric;
   if v_expected<0 or v_expected<>trunc(v_expected) or v_expected>9223372036854775807 then raise exception 'NBCU expected count invalid: %',v_rec.count_key;end if;
   execute format('select count(*) from plm.%I where capture_id=$1',v_rec.table_name) into v_count using p_capture_id;
   if v_count<>v_expected or (v_root->'observed_counts'->>v_rec.count_key)::numeric is distinct from v_expected then raise exception 'NBCU actual portal count disagrees: %',v_rec.count_key;end if;
  end loop;
  if exists(select 1 from plm.nbcu_asset a where capture_id=p_capture_id and not exists(select 1 from plm.nbcu_asset_metadata_value m where m.capture_id=a.capture_id and m.asset_source_key=a.asset_source_key)) then raise exception 'NBCU asset metadata absent';end if;
  if v_root->'expected_counts' ? 'excluded_unlicensed_assets' then
   if jsonb_typeof(v_root->'expected_counts'->'excluded_unlicensed_assets') is distinct from 'number' then raise exception 'NBCU expected exclusion count nonnumeric';end if;
   v_expected:=(v_root->'expected_counts'->>'excluded_unlicensed_assets')::numeric;
   if v_expected<0 or v_expected<>trunc(v_expected) or v_expected>2147483647 or v_expected is distinct from (v_root->>'excluded_unlicensed_assets')::numeric then raise exception 'NBCU exclusion count disagrees';end if;
  end if;
  if v_root->'expected_counts' ? 'failures' then
   if jsonb_typeof(v_root->'expected_counts'->'failures') is distinct from 'number' then raise exception 'NBCU expected failures nonnumeric';end if;
   if (v_root->'expected_counts'->>'failures')::numeric<>0 then raise exception 'NBCU complete capture has expected failures';end if;
  end if;
  select count(*) into v_count from plm.nbcu_asset_metadata_value where capture_id=p_capture_id;
  if (v_root->'observed_counts'->>'asset_metadata_values')::bigint is distinct from v_count then raise exception 'NBCU observed asset metadata count disagrees';end if;
  select count(*) into v_count from plm.nbcu_asset_scope where capture_id=p_capture_id;
  if (v_root->'observed_counts'->>'asset_scopes')::bigint is distinct from v_count then raise exception 'NBCU observed asset scope count disagrees';end if;
  if exists(select 1 from plm.nbcu_asset_property e left join plm.nbcu_property p on p.capture_id=e.capture_id and p.property_key=e.property_key where e.capture_id=p_capture_id and (p.property_label is null or p.property_label is distinct from e.property_label))
   or exists(select 1 from plm.nbcu_asset_ip_family e left join plm.nbcu_ip_family f on f.capture_id=e.capture_id and f.ip_family_key=e.ip_family_key where e.capture_id=p_capture_id and (f.ip_family_label is null or f.ip_family_label is distinct from e.ip_family_label)) then raise exception 'NBCU exact native endpoint label disagrees';end if;
  select jsonb_build_object('scopes',coalesce((select jsonb_agg(to_jsonb(s) order by scope_key) from plm.nbcu_scope s where capture_id=p_capture_id),'[]'),'asset_metadata_values',coalesce((select jsonb_agg(to_jsonb(m) order by to_jsonb(m)::text) from plm.nbcu_asset_metadata_value m where capture_id=p_capture_id),'[]')) into v_coverage;
 elsif p_source_system='paramount' then
  select to_jsonb(c) into v_root from plm.pmt_capture c where capture_id=p_capture_id and status='complete' and capture_kind='full';
  select capture_id into v_latest from plm.pmt_capture where status='complete' and capture_kind='full' order by completed_at desc,started_at desc,capture_id desc limit 1;
  if v_root is null or v_latest<>p_capture_id or v_root->>'source_system' is distinct from 'paramount_creative_library' then raise exception 'Paramount requires latest complete full native capture';end if;
  if not exists(select 1 from plm.pmt_authorized_title where capture_id=p_capture_id) or exists(select 1 from plm.pmt_authorized_title where capture_id=p_capture_id and capture_status not in ('captured','licensed_but_not_present_in_current_portal_view')) then raise exception 'Paramount authorized-title roster incomplete';end if;
  select jsonb_build_object('titles',coalesce((select jsonb_agg(to_jsonb(t) order by authorized_title_key) from plm.pmt_authorized_title t where capture_id=p_capture_id),'[]'),'mapping',coalesce((select jsonb_agg(to_jsonb(t) order by authorized_title_key,property_source_id) from plm.pmt_authorized_title_property t where capture_id=p_capture_id),'[]'),'expectations',coalesce((select jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text) from plm.pmt_capture_expectation t where capture_id=p_capture_id),'[]')) into v_coverage;
 elsif p_source_system='disney_opa' then
  select to_jsonb(c) into v_root from plm.opa_capture c where id=p_capture_id and status='complete';
  select id into v_latest from plm.opa_capture where status='complete' order by source_captured_at desc,load_completed_at desc,id desc limit 1;
  if v_root is null or v_latest<>p_capture_id then raise exception 'OPA requires latest coherent complete capture';end if;
  if (select count(*) from plm.opa_capture_scope where capture_id=p_capture_id)<>2
   or not exists(select 1 from plm.opa_capture_scope where capture_id=p_capture_id and (scope_key,region,branch,lob,submission_type,template_id,workflow_id)=('disney_home_standard','North America','Disney','200','Standard','21','49'))
   or not exists(select 1 from plm.opa_capture_scope where capture_id=p_capture_id and (scope_key,region,branch,lob,submission_type,template_id,workflow_id)=('lucas_home_standard','North America','Lucas','200','Standard','462','50'))
   or exists(select 1 from plm.opa_capture_scope where capture_id=p_capture_id and (status is distinct from 'complete' or authentication_evidence_sha256 is null or authenticated_at is null or finished_at is null or failure is not null or expected_duplicate_pair_count<>0 or observed_duplicate_pair_count is distinct from 0)) then raise exception 'OPA approved authenticated two-route coverage incomplete';end if;
  for v_rec in select * from plm.opa_capture_scope where capture_id=p_capture_id order by scope_key loop
   select count(distinct licensed_property_id),count(distinct character_id),count(*) filter(where character_id is not null),
    encode(extensions.digest(decode(string_agg(encode(convert_to(licensed_property_id::text,'UTF8')||decode('00','hex')||convert_to(property_name,'UTF8')||decode('00','hex')||convert_to(option_source_id::text,'UTF8')||decode('00','hex')||convert_to(character_id::text,'UTF8')||decode('00','hex')||convert_to(character_name,'UTF8')||decode('00','hex')||convert_to(brand_property_id::text,'UTF8'),'hex'),'0a' order by concat(licensed_property_id::text,chr(1),property_name,chr(1),option_source_id::text,chr(1),character_id::text,chr(1),character_name,chr(1),brand_property_id::text)) filter(where character_id is not null),'hex'),'sha256'),'hex')
    into v_properties,v_characters,v_relationships,v_hash from plm.opa_property_character_capture where capture_id=p_capture_id and scope_key=v_rec.scope_key;
   if v_properties is distinct from v_rec.expected_property_count or v_properties is distinct from v_rec.observed_property_count or v_characters is distinct from v_rec.expected_character_count or v_characters is distinct from v_rec.observed_character_count or v_relationships is distinct from v_rec.expected_relationship_count or v_relationships is distinct from v_rec.observed_relationship_count or v_hash is distinct from v_rec.expected_relationship_sha256 or v_hash is distinct from v_rec.observed_relationship_sha256 then raise exception 'OPA scoped actual counts or relationship hash disagree: %',v_rec.scope_key;end if;
  end loop;
  select count(distinct licensed_property_id),count(distinct character_id),count(*) filter(where character_id is not null),encode(extensions.digest(convert_to(string_agg(source_row_sha256,e'\n' order by source_row_sha256) filter(where character_id is not null),'UTF8'),'sha256'),'hex') into v_properties,v_characters,v_relationships,v_hash from plm.opa_property_character_capture where capture_id=p_capture_id;
  select coalesce(sum(n),0),count(*) filter(where n=2) into v_memberships,v_cross_scope from (select count(distinct scope_key)n from plm.opa_property_character_capture where capture_id=p_capture_id group by licensed_property_id) q;
  if v_root->>'load_completed_at' is null or v_root->'errors' is distinct from '[]'::jsonb or (v_root->>'expected_scope_count')::integer is distinct from 2 or (v_root->>'expected_duplicate_pair_count')::bigint is distinct from 0 or (v_root->>'observed_duplicate_pair_count')::bigint is distinct from 0
   or v_properties is distinct from (v_root->>'expected_unique_property_count')::bigint or v_properties is distinct from (v_root->>'observed_unique_property_count')::bigint
   or v_characters is distinct from (v_root->>'expected_unique_character_count')::bigint or v_characters is distinct from (v_root->>'observed_unique_character_count')::bigint
   or v_relationships is distinct from (v_root->>'expected_relationship_count')::bigint or v_relationships is distinct from (v_root->>'observed_relationship_count')::bigint
   or v_memberships is distinct from (v_root->>'expected_scope_membership_count')::bigint or v_memberships is distinct from (v_root->>'observed_scope_membership_count')::bigint
   or v_cross_scope is distinct from (v_root->>'expected_cross_scope_property_count')::bigint or v_cross_scope is distinct from (v_root->>'observed_cross_scope_property_count')::bigint
   or v_hash is distinct from v_root->>'observed_relationship_sha256' then raise exception 'OPA actual full capture counts or manifest disagree';end if;
  select jsonb_agg(to_jsonb(s) order by scope_key) into v_coverage from plm.opa_capture_scope s where capture_id=p_capture_id;
 else raise exception 'immutable comparable capture unsupported for source %',p_source_system;end if;
 for v_rec in select * from (values
 ('nbcu','property','plm.nbcu_property','property_key','property_label'),('nbcu','character','plm.nbcu_character','character_key','character_label'),('nbcu','style_guide','plm.nbcu_style_guide','style_guide_key','style_guide_label'),('nbcu','franchise','plm.nbcu_ip_family','ip_family_key','ip_family_label'),('nbcu','asset','plm.nbcu_asset','asset_source_key','file_name'),
 ('paramount','property','plm.pmt_property','property_source_id','property_name'),('paramount','character','plm.pmt_character','character_source_id','character_name'),('paramount','style_guide','plm.pmt_collection','collection_source_id','collection_name'),('paramount','franchise','plm.pmt_franchise','franchise_source_id','franchise_name'),('paramount','asset','plm.pmt_asset','asset_id','asset_name')
 ) m(source,kind,source_table,key_column,name_column) where source=p_source_system loop
  execute format('select coalesce(jsonb_agg(to_jsonb(t)-array[''core_property_id'',''core_character_id'',''core_style_guide_id'',''core_franchise_id'',''dam_asset_id'',''resolution_status'',''resolution_reason'',''resolved_at'',''resolved_by''] order by t.%I::text),''[]''::jsonb) from %s t where capture_id=$1',v_rec.key_column,v_rec.source_table) into v_rows using p_capture_id;
  for v_row in select value from jsonb_array_elements(v_rows) loop
   v_native:=v_row->>v_rec.key_column;
   if v_native is null or btrim(v_native)='' then raise exception 'native source identity absent';end if;
   -- Bare durable resolution IDs retain their established namespace. The engine-owned
   -- provenance tuple is separate and never rewrites those human decisions.
   v_e:=jsonb_build_object('kind',v_rec.kind,'source_table',v_rec.source_table,'native_id',v_native,'resolution_source_id',v_native,'source_id',jsonb_build_array(p_source_system,v_rec.source_table,v_rec.kind,v_native)::text,'name',v_row->>v_rec.name_column,'native',v_row);
   if p_source_system='paramount' and v_rec.kind='property' and not coalesce((v_row->>'is_licensed_selection')::boolean,false) then continue;end if;
   if p_source_system='nbcu' and v_rec.kind='property' and v_row->>'source_kind' not in ('property','franchise_asset') then continue;end if;
   v_entities:=v_entities||jsonb_build_array(v_e);
  end loop;
 end loop;
 if p_source_system='disney_opa' then
  for v_row in select to_jsonb(t) from plm.opa_property_character_capture t where capture_id=p_capture_id order by scope_key,licensed_property_id,character_id nulls first loop
   v_scope:=v_row->>'scope_key';
   v_entities:=v_entities||jsonb_build_array(jsonb_build_object('kind','property','source_table','plm.opa_property_character_capture','native_id',v_row->>'licensed_property_id','resolution_source_id',v_row->>'licensed_property_id','scope',v_scope,'source_id',jsonb_build_array(p_source_system,'plm.opa_property_character_capture','property',v_scope,v_row->>'licensed_property_id')::text,'name',v_row->>'property_name','native',v_row));
   if v_row->>'character_id' is not null then
    v_entities:=v_entities||jsonb_build_array(jsonb_build_object('kind','character','source_table','plm.opa_property_character_capture','native_id',v_row->>'character_id','resolution_source_id',v_row->>'character_id','scope',v_scope,'source_id',jsonb_build_array(p_source_system,'plm.opa_property_character_capture','character',v_scope,v_row->>'character_id')::text,'name',v_row->>'character_name','native',v_row));
    v_edges:=v_edges||jsonb_build_array(jsonb_build_object('kind','property_character','source_table','plm.opa_property_character_capture','left_kind','property','right_kind','character','left_native_id',v_row->>'licensed_property_id','right_native_id',v_row->>'character_id','scope',v_scope,'native',v_row));
   end if;
  end loop;
  if exists(select 1 from jsonb_array_elements(v_entities) e group by e->>'kind',e->>'native_id' having count(distinct e->>'scope')>1 or count(distinct e->>'name')>1) then raise exception 'OPA bare durable source identity ambiguously spans scoped routes';end if;
 end if;
 for v_rec in select * from (values
 ('nbcu','property_character','plm.nbcu_property_character','property','character','property_key','character_key'),('nbcu','property_style_guide','plm.nbcu_style_guide_property','property','style_guide','property_key','style_guide_key'),('nbcu','property_franchise','plm.nbcu_ip_family_property','property','franchise','property_key','ip_family_key'),('nbcu','asset_property','plm.nbcu_asset_property','asset','property','asset_source_key','property_key'),('nbcu','asset_character','plm.nbcu_asset_character','asset','character','asset_source_key','character_key'),('nbcu','asset_style_guide','plm.nbcu_asset_style_guide','asset','style_guide','asset_source_key','style_guide_key'),('nbcu','asset_franchise','plm.nbcu_asset_ip_family','asset','franchise','asset_source_key','ip_family_key'),
 ('paramount','property_character','plm.pmt_property_character','property','character','property_source_id','character_source_id'),('paramount','property_style_guide','plm.pmt_property_collection','property','style_guide','property_source_id','collection_source_id'),('paramount','asset_property','plm.pmt_asset_property','asset','property','asset_id','property_source_id'),('paramount','asset_character','plm.pmt_asset_character','asset','character','asset_id','character_source_id'),('paramount','asset_style_guide','plm.pmt_asset_collection','asset','style_guide','asset_id','collection_source_id'),('paramount','asset_franchise','plm.pmt_asset_franchise','asset','franchise','asset_id','franchise_source_id')
 ) m(source,kind,source_table,left_kind,right_kind,left_column,right_column) where source=p_source_system loop
  execute format('select coalesce(jsonb_agg(to_jsonb(t) order by t.%I::text,t.%I::text),''[]''::jsonb) from %s t where capture_id=$1',v_rec.left_column,v_rec.right_column,v_rec.source_table) into v_rows using p_capture_id;
  for v_row in select value from jsonb_array_elements(v_rows) loop
   if coalesce(v_row->>'evidence_type',v_row->>'source_evidence','')='' then raise exception 'direct native relationship evidence absent in %',v_rec.source_table;end if;
   if p_source_system='paramount' and v_row->>'source_evidence' is distinct from (case when v_rec.kind in ('property_character','property_style_guide') then 'explicit_cascading_pair' else 'full_asset_metadata' end) then raise exception 'Paramount native evidence is not the closed direct source kind';end if;
   if p_source_system='nbcu' and (v_row->>'evidence_type' ~* '(inferred|co.?occurrence)' or nullif(btrim(v_row->>'evidence_value'),'') is null) then raise exception 'NBCU inferred or missing evidence is not direct source authority';end if;
   v_edges:=v_edges||jsonb_build_array(jsonb_build_object('kind',v_rec.kind,'source_table',v_rec.source_table,'left_kind',v_rec.left_kind,'right_kind',v_rec.right_kind,'left_native_id',v_row->>v_rec.left_column,'right_native_id',v_row->>v_rec.right_column,'native',v_row));
  end loop;
 end loop;
 select coalesce(jsonb_agg(e order by e->>'source_id'),'[]') into v_entities from (select (jsonb_agg(x order by x::text)->0)||jsonb_build_object('native',jsonb_agg(x->'native' order by x::text)) as e from jsonb_array_elements(v_entities) x group by x->>'source_id') q;
 select coalesce(jsonb_agg(e order by e::text),'[]') into v_edges from (select distinct e from jsonb_array_elements(v_edges) e) q;
 if p_source_system='nbcu' then
 select jsonb_build_object('scopes',coalesce((select jsonb_agg(jsonb_build_array(scope_key,scope_href,scope_label) order by scope_key) from plm.nbcu_scope where capture_id=p_capture_id),'[]')) into v_scope;
 elsif p_source_system='paramount' then select jsonb_agg(jsonb_build_array(authorized_title_key,authorized_title_name) order by authorized_title_key)::text into v_scope from plm.pmt_authorized_title where capture_id=p_capture_id;
 else select jsonb_agg(jsonb_build_array(scope_key,region,branch,lob,submission_type,template_id,workflow_id) order by scope_key)::text into v_scope from plm.opa_capture_scope where capture_id=p_capture_id;end if;
 return jsonb_build_object('schema_version',2,'source_system',p_source_system,'capture_id',p_capture_id,'root',v_root,'coverage',v_coverage,'scope_namespace',v_scope::jsonb,'entities',v_entities,'edges',v_edges,'decisions',coalesce((select jsonb_agg(to_jsonb(d) order by entity_kind,source_id) from plm.source_resolution d where source_system=p_source_system),'[]'),'relationship_decisions',coalesce((select jsonb_agg(to_jsonb(d) order by licensor_id,relationship_kind,source_left_id,source_right_id) from plm.licensing_relationship_resolution d where source_system=p_source_system),'[]'),'source_authority',coalesce((select jsonb_agg(to_jsonb(d) order by licensor_id,source_purpose,scope_axis,permitted_kind) from plm.licensing_source_scope d where source_system=p_source_system),'[]'));
end $snapshot$;
revoke all on function plm.licensing_consolidation_capture_snapshot(text,uuid) from public,anon,authenticated;
grant execute on function plm.licensing_consolidation_capture_snapshot(text,uuid) to service_role;

create or replace function plm.licensing_consolidation_operation_state(p_operation jsonb)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog as $state$
declare t text:=p_operation->>'target';v_state jsonb;
begin
 if t not in ('core.taxonomy_source_ref','core.property','core.property_character_associations','core.property_style_guide','core.property_franchise','core.style_guide_character','dam.asset_property','dam.asset_character','dam.asset_style_guide','dam.asset_franchise','core.property_character_source_edge','core.property_style_guide_source_edge','core.property_franchise_source_edge','core.style_guide_character_source_edge','dam.asset_property_source_edge','dam.asset_character_source_edge','dam.asset_style_guide_source_edge','dam.asset_franchise_source_edge') or jsonb_typeof(p_operation->'identity')<>'object' or p_operation->'identity'='{}'::jsonb then raise exception 'unsupported exact operation state identity';end if;
 execute format('select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),''[]''::jsonb) from %s t where to_jsonb(t) @> $1',t) into v_state using p_operation->'identity';
 if jsonb_array_length(v_state)>1 then raise exception 'operation identity is not unique';end if;
 if t='core.property' then
  return jsonb_build_object('rows',v_state,'aliases',coalesce((select jsonb_agg(to_jsonb(a) order by id) from core.property_alias a where property_id=(p_operation->'identity'->>'id')::uuid),'[]'));
 end if;
 return jsonb_build_object('rows',v_state);
end $state$;
revoke all on function plm.licensing_consolidation_operation_state(jsonb) from public,anon,authenticated,service_role;

create or replace function plm.apply_licensing_support_operation(p_plan_id uuid,p_plan_hash text,p_operation jsonb)
returns jsonb language plpgsql volatile security definer set search_path=pg_catalog as $operation$
declare v_plan plm.licensing_consolidation_plan;v_state jsonb;t text:=p_operation->>'target';k text:=p_operation->>'kind';a jsonb:=p_operation->'after';b jsonb;v_rec record;v_left text;v_right text;v_count integer:=0;v_owner uuid;v_endpoint uuid;v_old_name text;v_alias text;v_source text;v_proof jsonb;v_entity jsonb;v_resolution record;v_mapped uuid;v_side text;v_kind text;v_expected uuid;
begin
 select * into v_plan from plm.licensing_consolidation_plan where id=p_plan_id for update;
 if v_plan.id is null or v_plan.plan_hash<>p_plan_hash or v_plan.plan_status<>'preview' or v_plan.plan_schema_version<>2 or not exists(select 1 from jsonb_array_elements(v_plan.operations) x where x=p_operation) then raise exception 'support operation requires exact locked immutable preview plan membership';end if;
 if k not in ('entity_source','relationship_source','canonical_pair','property_name') then raise exception 'unknown physical support operation';end if;
 -- Lock the same exact target row whose whole before-image was pinned.
 perform plm.licensing_consolidation_operation_state(p_operation);
 execute format('select 1 from %s t where to_jsonb(t) @> $1 for update',t) using p_operation->'identity';
 v_state:=plm.licensing_consolidation_operation_state(p_operation);
 if v_state is distinct from p_operation->'before' then raise exception 'physical support operation before-state changed' using errcode='40001';end if;
 b:=v_state->'rows'->0;v_source:=v_plan.source_system;
 v_owner:=(p_operation->>'licensor_id')::uuid;
 if v_owner is null or not exists(select 1 from plm.licensing_source_scope where licensor_id=v_owner and source_system=v_source and source_purpose=case when k in ('relationship_source','canonical_pair') then 'relationship_evidence' else 'canonical_identity' end and scope_axis=case when k in ('relationship_source','canonical_pair') then 'relationship' else 'entity' end and permitted_kind=p_operation->>'entity_kind' and authorized_at is not null and authorized_by is not null) then raise exception 'operation current source authority absent';end if;
 for v_rec in select value->>'table' as owner_table,value->>'id' as owner_id from jsonb_array_elements(p_operation->'owners') loop
  if v_rec.owner_table not in ('core.property','core.character','core.style_guide','core.franchise','dam.asset') then raise exception 'unknown canonical owner endpoint';end if;
  execute format('select licensor_id from %s where id=$1 for update',v_rec.owner_table) into v_endpoint using v_rec.owner_id::uuid;
  if v_endpoint is distinct from v_owner then raise exception 'canonical endpoint current owner changed or missing';end if;
 end loop;
 if b is not null and b @> a then return jsonb_build_object('changes',0,'state',v_state);end if;
 if k='entity_source' and a->>'missing_since' is null then
  select x into v_entity from jsonb_array_elements(v_plan.capture_snapshot->'entities') x where x->>'source_id'=a->>'source_id';
  if v_entity is null then raise exception 'current entity support absent from qualified capture';end if;
  select * into v_resolution from plm.source_resolution where source_system=v_source and entity_kind=v_entity->>'kind' and source_id=v_entity->>'resolution_source_id';
  v_mapped:=case v_entity->>'kind' when 'property' then v_resolution.core_property_id when 'character' then v_resolution.core_character_id when 'style_guide' then v_resolution.core_style_guide_id when 'franchise' then v_resolution.core_franchise_id when 'asset' then v_resolution.dam_asset_id end;
  if v_resolution.resolution_status is distinct from 'matched' or v_mapped::text is distinct from a->>'entity_id' then raise exception 'current durable entity mapping no longer matches support';end if;
 end if;
 if k='relationship_source' and a->>'is_current'='true' then
  if jsonb_array_length(coalesce(a->'metadata'->'native_provenance','[]'))=0 then raise exception 'direct support requires retained native provenance';end if;
  for v_proof in select value from jsonb_array_elements(a->'metadata'->'native_provenance') loop
   if not exists(select 1 from jsonb_array_elements(v_plan.capture_snapshot->'edges') x where x->>'source_table'=v_proof->>'source_table' and x->>'left_native_id'=v_proof->>'left_native_id' and x->>'right_native_id'=v_proof->>'right_native_id' and coalesce(x->>'scope','')=coalesce(v_proof->>'scope','')) then raise exception 'direct support lacks qualified current native membership';end if;
   foreach v_side in array array['left','right'] loop
    v_kind:=v_proof->>(v_side||'_kind');
    select x into v_entity from jsonb_array_elements(v_plan.capture_snapshot->'entities') x where x->>'kind'=v_kind and x->>'native_id'=v_proof->>(v_side||'_native_id') and coalesce(x->>'scope','')=coalesce(v_proof->>'scope','');
    select * into v_resolution from plm.source_resolution where source_system=v_source and entity_kind=v_kind and source_id=v_entity->>'resolution_source_id';
    v_mapped:=case v_kind when 'property' then v_resolution.core_property_id when 'character' then v_resolution.core_character_id when 'style_guide' then v_resolution.core_style_guide_id when 'franchise' then v_resolution.core_franchise_id when 'asset' then v_resolution.dam_asset_id end;
    v_expected:=(p_operation->'owners'->case v_side when 'left' then 0 else 1 end->>'id')::uuid;
    if v_entity is null or v_resolution.resolution_status is distinct from 'matched' or v_mapped is distinct from v_expected then raise exception 'direct support durable endpoint mapping changed';end if;
   end loop;
  end loop;
 end if;
 if k='entity_source' then
  if t<>'core.taxonomy_source_ref' then raise exception 'entity source target invalid';end if;
  if b is null then
   insert into core.taxonomy_source_ref(id,entity_schema,entity_table,entity_id,source_system,source_table,source_id,source_name,confidence,raw,source_licensor_id,first_seen_at,last_seen_at,missing_since)
   values((a->>'id')::uuid,a->>'entity_schema',a->>'entity_table',(a->>'entity_id')::uuid,v_source,a->>'source_table',a->>'source_id',a->>'source_name','verified',a->'raw',v_owner,(a->>'first_seen_at')::timestamptz,(a->>'last_seen_at')::timestamptz,(a->>'missing_since')::timestamptz);
  else
   if b->>'entity_id'<>a->>'entity_id' or b->>'entity_table'<>a->>'entity_table' or b->>'entity_schema'<>a->>'entity_schema' then raise exception 'durable source reference mapping must not change';end if;
   update core.taxonomy_source_ref set source_name=a->>'source_name',raw=a->'raw',first_seen_at=(a->>'first_seen_at')::timestamptz,last_seen_at=(a->>'last_seen_at')::timestamptz,missing_since=(a->>'missing_since')::timestamptz where id=(b->>'id')::uuid;
  end if;
  get diagnostics v_count=row_count;
 elsif k='relationship_source' then
  select * into v_rec from (values
   ('core.property_character_source_edge','property_id','character_id'),('core.property_style_guide_source_edge','property_id','style_guide_id'),('core.property_franchise_source_edge','property_id','franchise_id'),('core.style_guide_character_source_edge','style_guide_id','character_id'),('dam.asset_property_source_edge','asset_id','property_id'),('dam.asset_character_source_edge','asset_id','character_id'),('dam.asset_style_guide_source_edge','asset_id','style_guide_id'),('dam.asset_franchise_source_edge','asset_id','franchise_id')) m(target,left_col,right_col) where target=t;
  if not found or a->>'source_system'<>v_source or a->>'evidence_kind'<>'direct_source_assertion' then raise exception 'relationship support target/direct namespace invalid';end if;
  v_left:=v_rec.left_col;v_right:=v_rec.right_col;
  if b is null then
   execute format('insert into %s(id,%I,%I,licensor_id,source_system,source_id,source_evidence,evidence_kind,is_current,superseded_at,superseded_reason,metadata) values($1,$2,$3,$4,$5,$6,$7,''direct_source_assertion'',$8,$9,$10,$11)',t,v_left,v_right)
   using (a->>'id')::uuid,(a->>v_left)::uuid,(a->>v_right)::uuid,v_owner,v_source,a->>'source_id',a->>'source_evidence',(a->>'is_current')::boolean,(a->>'superseded_at')::timestamptz,a->>'superseded_reason',a->'metadata';
  else
   if b->>'source_system'<>v_source or b->>v_left<>a->>v_left or b->>v_right<>a->>v_right or b->>'licensor_id'<>a->>'licensor_id' then raise exception 'source history identity cannot be repointed';end if;
   execute format('update %s set is_current=$1,superseded_at=$2,superseded_reason=$3 where id=$4',t)
   using (a->>'is_current')::boolean,(a->>'superseded_at')::timestamptz,a->>'superseded_reason',(b->>'id')::uuid;
  end if;
  get diagnostics v_count=row_count;
 elsif k='canonical_pair' then
  select * into v_rec from (values
   ('core.property_character_associations','property_id','character_id'),('core.property_style_guide','property_id','style_guide_id'),('core.property_franchise','property_id','franchise_id'),('core.style_guide_character','style_guide_id','character_id'),('dam.asset_property','asset_id','property_id'),('dam.asset_character','asset_id','character_id'),('dam.asset_style_guide','asset_id','style_guide_id'),('dam.asset_franchise','asset_id','franchise_id')) m(target,left_col,right_col) where target=t;
  if not found then raise exception 'canonical pair target invalid';end if;
  if b is null then
   execute format('insert into %s(%I,%I,is_current,retired_at,retired_reason) values($1,$2,$3,$4,$5)',t,v_rec.left_col,v_rec.right_col)
   using (a->>v_rec.left_col)::uuid,(a->>v_rec.right_col)::uuid,(a->>'is_current')::boolean,(a->>'retired_at')::timestamptz,a->>'retired_reason';
  else
   execute format('update %s set is_current=$1,retired_at=$2,retired_reason=$3 where %I=$4 and %I=$5',t,v_rec.left_col,v_rec.right_col)
   using (a->>'is_current')::boolean,(a->>'retired_at')::timestamptz,a->>'retired_reason',(b->>v_rec.left_col)::uuid,(b->>v_rec.right_col)::uuid;
  end if;
  get diagnostics v_count=row_count;
 else
  if t<>'core.property' or b is null or a->>'name' is null or btrim(a->>'name')='' then raise exception 'protected exact property name target invalid';end if;
  if b->>'name'=a->>'name' then return jsonb_build_object('changes',0,'state',v_state);end if;
  v_old_name:=b->>'name';
  insert into plm.licensing_write_authorization(backend_pid,transaction_id,target_table,write_kind,plan_id,plan_hash,actor,protected_columns,expires_at)
  values(pg_backend_pid(),txid_current(),'core.property','scrape_consolidation',v_plan.id,v_plan.plan_hash,v_plan.planned_by,array['name'],clock_timestamp()+interval '1 minute');
  update core.property set name=a->>'name' where id=(b->>'id')::uuid;
  get diagnostics v_count=row_count;
  if core.normalize_popsg_property_observation(v_old_name) not in (core.normalize_popsg_property_observation(a->>'name'),core.normalize_popsg_property_observation(coalesce(b->>'code',''))) and not exists(select 1 from core.property_alias where property_id=(b->>'id')::uuid and normalized_alias=core.normalize_popsg_property_observation(v_old_name)) then
   insert into core.property_alias(property_id,licensor_id,alias,source_system,evidence_notes) values((b->>'id')::uuid,v_owner,v_old_name,v_source,'Preserved previous official/internal spelling by exact consolidation plan '||v_plan.id);
   v_count:=v_count+1;
  end if;
 end if;
 return jsonb_build_object('changes',v_count,'state',plm.licensing_consolidation_operation_state(p_operation));
end $operation$;
revoke all on function plm.apply_licensing_support_operation(uuid,text,jsonb) from public,anon,authenticated,service_role;

create or replace function plm.plan_licensing_consolidation(p_source_system text,p_capture_id uuid,p_entity_source_id text default null)
returns plm.licensing_consolidation_plan language plpgsql security definer set search_path=pg_catalog as $planner$
declare snap jsonb;entities jsonb:='[]';groups jsonb:='[]';ops jsonb:='[]';inverse jsonb:='[]';e jsonb;edge jsonb;left_e jsonb;right_e jsonb;g jsonb;op jsonb;before_state jsonb;after_row jsonb;existing jsonb;v_id uuid;v_owner uuid;v_table text;v_col text;v_rec record;v_scope jsonb;v_time timestamptz;v_pair text;v_support text;v_left text;v_right text;v_key text;v_hash text;v_result plm.licensing_consolidation_plan;v_filtered text;v_now_current boolean;
begin
 if p_source_system is null or btrim(p_source_system)='' or p_capture_id is null then raise exception 'exact source and capture required' using errcode='22023';end if;
 if p_entity_source_id is not null and btrim(p_entity_source_id)='' then raise exception 'empty filtered identity' using errcode='22023';end if;
 if p_source_system not in ('nbcu','paramount','disney_opa') then raise exception 'unsupported qualified capture source';end if;
 perform pg_advisory_xact_lock(hashtextextended('licensing-source:'||p_source_system,0));
 if p_source_system='nbcu' then lock table plm.nbcu_capture in share mode;
 elsif p_source_system='paramount' then lock table plm.pmt_capture in share mode;
 else lock table plm.opa_capture in share mode;end if;
 perform 1 from plm.licensing_source_scope where source_system=p_source_system order by licensor_id,source_purpose,scope_axis,permitted_kind for update;
 perform 1 from plm.source_resolution where source_system=p_source_system order by entity_kind,source_id for update;
 perform 1 from plm.licensing_relationship_resolution where source_system=p_source_system order by licensor_id,relationship_kind,source_left_id,source_right_id for update;
 snap:=plm.licensing_consolidation_capture_snapshot(p_source_system,p_capture_id);
 v_scope:=snap->'scope_namespace';v_time:=coalesce((snap->'root'->>'source_captured_at')::timestamptz,(snap->'root'->>'completed_at')::timestamptz,(snap->'root'->>'load_completed_at')::timestamptz);
 if v_time is null or v_scope is null then raise exception 'capture scope namespace or clock absent';end if;
 if p_entity_source_id is not null then
  select min(x->>'source_id') into v_filtered from jsonb_array_elements(snap->'entities') x where x->>'source_id'=p_entity_source_id or x->>'resolution_source_id'=p_entity_source_id;
  if (select count(distinct x->>'source_id') from jsonb_array_elements(snap->'entities') x where x->>'source_id'=p_entity_source_id or x->>'resolution_source_id'=p_entity_source_id)<>1 then raise exception 'filtered identity must select exactly one qualified namespace candidate' using errcode='22023';end if;
 end if;
 snap:=snap||jsonb_build_object('filter',v_filtered);
 select * into v_result from plm.licensing_consolidation_plan where source_system=p_source_system and capture_id=p_capture_id and plan_schema_version=2 and capture_snapshot=snap and rollback_of is null order by planned_at desc limit 1;
 if found then return v_result;end if;
 for e in select value from jsonb_array_elements(snap->'entities') order by value->>'source_id' loop
  select * into v_rec from plm.source_resolution where source_system=p_source_system and entity_kind=e->>'kind' and source_id=e->>'resolution_source_id';
  if not found or v_rec.resolution_status<>'matched' then continue;end if;
  v_table:=case e->>'kind' when 'property' then 'core.property' when 'character' then 'core.character' when 'style_guide' then 'core.style_guide' when 'franchise' then 'core.franchise' when 'asset' then 'dam.asset' end;
  v_id:=case e->>'kind' when 'property' then v_rec.core_property_id when 'character' then v_rec.core_character_id when 'style_guide' then v_rec.core_style_guide_id when 'franchise' then v_rec.core_franchise_id when 'asset' then v_rec.dam_asset_id end;
  if v_id is null then raise exception 'matched native decision has no canonical endpoint';end if;
  execute format('select licensor_id from %s where id=$1 for update',v_table) into v_owner using v_id;
  if v_owner is null or not exists(select 1 from plm.licensing_source_scope where source_system=p_source_system and licensor_id=v_owner and scope_axis='entity' and source_purpose='canonical_identity' and permitted_kind=e->>'kind' and authorized_at is not null and authorized_by is not null) then raise exception 'matched native decision lacks current owner/source authority';end if;
  e:=e||jsonb_build_object('canonical_id',v_id,'canonical_table',v_table,'licensor_id',v_owner);
  entities:=entities||jsonb_build_array(e);
  if v_filtered is not null and e->>'source_id'<>v_filtered then continue;end if;
  if exists(select 1 from core.taxonomy_source_ref where source_system=p_source_system and entity_id=v_id and source_id<>e->>'source_id' and (raw->>'engine_schema_version') is distinct from '2') then raise exception 'existing source reference uses incompatible provenance namespace; not rewritten';end if;
  op:=jsonb_build_object('kind','entity_source','entity_kind',e->>'kind','target','core.taxonomy_source_ref','identity',jsonb_build_object('source_system',p_source_system,'source_table',e->>'source_table','source_id',e->>'source_id'),'licensor_id',v_owner,'owners',jsonb_build_array(jsonb_build_object('table',v_table,'id',v_id)),'op_key','10:entity:'||(e->>'source_id'));
  before_state:=plm.licensing_consolidation_operation_state(op);existing:=before_state->'rows'->0;
  if existing is not null and (existing->>'entity_id'<>v_id::text or existing->>'entity_table'<>split_part(v_table,'.',2)) then raise exception 'existing durable source reference points to incompatible canonical identity';end if;
  after_row:=coalesce(existing,'{}')||jsonb_build_object('id',coalesce(existing->>'id',gen_random_uuid()::text),'entity_schema',split_part(v_table,'.',1),'entity_table',split_part(v_table,'.',2),'entity_id',v_id,'source_system',p_source_system,'source_table',e->>'source_table','source_id',e->>'source_id','source_name',e->>'name','first_seen_at',coalesce(existing->>'first_seen_at',v_time::text),'last_seen_at',v_time,'missing_since',null,'raw',coalesce(existing->'raw','{}')||jsonb_build_object('engine_schema_version',2,'capture_id',p_capture_id,'scope_namespace',v_scope,'native_provenance',e->'native'));
  op:=op||jsonb_build_object('before',before_state,'after',after_row);ops:=ops||jsonb_build_array(op);
  if e->>'kind'='property' then
   op:=jsonb_build_object('kind','property_name','entity_kind','property','target','core.property','identity',jsonb_build_object('id',v_id),'licensor_id',v_owner,'owners',jsonb_build_array(jsonb_build_object('table','core.property','id',v_id)),'op_key','40:name:'||v_id::text);
   before_state:=plm.licensing_consolidation_operation_state(op);
   if before_state->'rows'->0->>'name'<>e->>'name' then ops:=ops||jsonb_build_array(op||jsonb_build_object('before',before_state,'after',jsonb_build_object('name',e->>'name')));end if;
  end if;
 end loop;
 for edge in select value from jsonb_array_elements(snap->'edges') order by value::text loop
  select x into left_e from jsonb_array_elements(entities) x where x->>'kind'=edge->>'left_kind' and x->>'native_id'=edge->>'left_native_id' and coalesce(x->>'scope','')=coalesce(edge->>'scope','');
  select x into right_e from jsonb_array_elements(entities) x where x->>'kind'=edge->>'right_kind' and x->>'native_id'=edge->>'right_native_id' and coalesce(x->>'scope','')=coalesce(edge->>'scope','');
  if left_e is null or right_e is null then continue;end if;
  if v_filtered is not null and left_e->>'source_id'<>v_filtered and right_e->>'source_id'<>v_filtered then continue;end if;
  if left_e->>'licensor_id'<>right_e->>'licensor_id' then raise exception 'native direct pair canonical owners disagree';end if;
  v_owner:=(left_e->>'licensor_id')::uuid;
  if not exists(select 1 from plm.licensing_source_scope where source_system=p_source_system and licensor_id=v_owner and scope_axis='relationship' and source_purpose='relationship_evidence' and permitted_kind=edge->>'kind' and authorized_at is not null and authorized_by is not null) then raise exception 'direct pair source relationship authority missing';end if;
  if exists(select 1 from plm.licensing_relationship_resolution where source_system=p_source_system and licensor_id=v_owner and relationship_kind=edge->>'kind' and source_left_id=edge->>'left_native_id' and source_right_id=edge->>'right_native_id' and (resolution_status<>'matched' or not is_direct_source_relationship or evidence_kind<>'direct_source_assertion')) then raise exception 'durable relationship decision conflicts with native direct assertion';end if;
  v_key:=jsonb_build_array(p_source_system,edge->>'kind',v_owner,left_e->>'canonical_id',right_e->>'canonical_id')::text;
  select x into g from jsonb_array_elements(groups) x where x->>'source_id'=v_key;
  if g is null then groups:=groups||jsonb_build_array(jsonb_build_object('kind',edge->>'kind','source_id',v_key,'left',left_e,'right',right_e,'proof',jsonb_build_array(edge)));
  else
   select jsonb_agg(case when x->>'source_id'=v_key then x||jsonb_build_object('proof',x->'proof'||jsonb_build_array(edge)) else x end order by x->>'source_id') into groups from jsonb_array_elements(groups) x;
  end if;
 end loop;
 for v_rec in select * from (values
 ('property_character','core.property_character_associations','core.property_character_source_edge','property_id','character_id','property','character'),('property_style_guide','core.property_style_guide','core.property_style_guide_source_edge','property_id','style_guide_id','property','style_guide'),('property_franchise','core.property_franchise','core.property_franchise_source_edge','property_id','franchise_id','property','franchise'),('style_guide_character','core.style_guide_character','core.style_guide_character_source_edge','style_guide_id','character_id','style_guide','character'),('asset_property','dam.asset_property','dam.asset_property_source_edge','asset_id','property_id','asset','property'),('asset_character','dam.asset_character','dam.asset_character_source_edge','asset_id','character_id','asset','character'),('asset_style_guide','dam.asset_style_guide','dam.asset_style_guide_source_edge','asset_id','style_guide_id','asset','style_guide'),('asset_franchise','dam.asset_franchise','dam.asset_franchise_source_edge','asset_id','franchise_id','asset','franchise')) m(kind,pair,support,left_col,right_col,left_kind,right_kind) loop
  v_pair:=v_rec.pair;v_support:=v_rec.support;v_left:=v_rec.left_col;v_right:=v_rec.right_col;
  for g in select value from jsonb_array_elements(groups) where value->>'kind'=v_rec.kind order by value->>'source_id' loop
   v_owner:=(g->'left'->>'licensor_id')::uuid;
   op:=jsonb_build_object('kind','relationship_source','entity_kind',v_rec.kind,'target',v_support,'licensor_id',v_owner,'owners',jsonb_build_array(jsonb_build_object('table',g->'left'->>'canonical_table','id',g->'left'->>'canonical_id'),jsonb_build_object('table',g->'right'->>'canonical_table','id',g->'right'->>'canonical_id')));
   execute format('select to_jsonb(t) from %s t where %I=$1 and %I=$2 and source_system=$3 and is_current and evidence_kind=''direct_source_assertion'' for update',v_support,v_left,v_right) into existing using (g->'left'->>'canonical_id')::uuid,(g->'right'->>'canonical_id')::uuid,p_source_system;
   if existing is not null then
    if existing->>'source_id'<>g->>'source_id' or existing->'metadata'->>'engine_schema_version' is distinct from '2' then raise exception 'current support uses incompatible namespace';end if;
    op:=op||jsonb_build_object('identity',jsonb_build_object('id',existing->>'id'),'op_key','20:retire:'||(existing->>'id'));
    before_state:=plm.licensing_consolidation_operation_state(op);
    ops:=ops||jsonb_build_array(op||jsonb_build_object('before',before_state,'after',existing||jsonb_build_object('is_current',false,'superseded_at',v_time,'superseded_reason','Replaced by qualified complete capture')));
   end if;
   after_row:=jsonb_build_object('id',gen_random_uuid(),v_left,g->'left'->>'canonical_id',v_right,g->'right'->>'canonical_id','licensor_id',v_owner,'source_system',p_source_system,'source_id',g->>'source_id','source_evidence','Qualified exact native complete-capture direct assertion','evidence_kind','direct_source_assertion','is_current',true,'superseded_at',null,'superseded_reason',null,'metadata',jsonb_build_object('engine_schema_version',2,'capture_id',p_capture_id,'scope_namespace',v_scope,'native_provenance',g->'proof','entity_source_ids',jsonb_build_array(g->'left'->>'source_id',g->'right'->>'source_id')));
   op:=op||jsonb_build_object('identity',jsonb_build_object('id',after_row->>'id'),'op_key','21:support:'||(g->>'source_id'));ops:=ops||jsonb_build_array(op||jsonb_build_object('before',plm.licensing_consolidation_operation_state(op),'after',after_row));
   op:=jsonb_build_object('kind','canonical_pair','entity_kind',v_rec.kind,'target',v_pair,'identity',jsonb_build_object(v_left,g->'left'->>'canonical_id',v_right,g->'right'->>'canonical_id'),'licensor_id',v_owner,'owners',op->'owners','op_key','30:pair:'||(g->>'source_id'));
   before_state:=plm.licensing_consolidation_operation_state(op);existing:=before_state->'rows'->0;
   if existing is null or not (existing->>'is_current')::boolean then ops:=ops||jsonb_build_array(op||jsonb_build_object('before',before_state,'after',coalesce(existing,'{}')||op->'identity'||jsonb_build_object('is_current',true,'retired_at',null,'retired_reason',null)));end if;
  end loop;
  -- Missing support retirement applies only to previously engine-qualified comparable
  -- scope, and only to the uniquely filtered candidate when a filter was requested.
  execute format('select coalesce(jsonb_agg(to_jsonb(t) order by id),''[]'') from %s t where source_system=$1 and is_current and evidence_kind=''direct_source_assertion''',v_support) into existing using p_source_system;
  for after_row in select value from jsonb_array_elements(coalesce(existing,'[]')) loop
   if exists(select 1 from jsonb_array_elements(groups) x where x->>'source_id'=after_row->>'source_id') then continue;end if;
   if v_filtered is not null and not (after_row->'metadata'->'entity_source_ids' @> jsonb_build_array(v_filtered)) then continue;end if;
   if after_row->'metadata'->>'engine_schema_version' is distinct from '2' or after_row->'metadata'->'scope_namespace' is distinct from v_scope then raise exception 'missing support lacks comparable complete-capture namespace';end if;
   if p_source_system='disney_opa' and v_rec.kind<>'property_character' or p_source_system='paramount' and v_rec.kind in ('property_franchise','style_guide_character') or p_source_system='nbcu' and v_rec.kind='style_guide_character' then raise exception 'unsupported source relationship membership cannot prove absence';end if;
   v_owner:=(after_row->>'licensor_id')::uuid;
   op:=jsonb_build_object('kind','relationship_source','entity_kind',v_rec.kind,'target',v_support,'identity',jsonb_build_object('id',after_row->>'id'),'licensor_id',v_owner,'owners',jsonb_build_array(jsonb_build_object('table',case v_rec.left_kind when 'asset' then 'dam.asset' else 'core.'||v_rec.left_kind end,'id',after_row->>v_left),jsonb_build_object('table','core.'||v_rec.right_kind,'id',after_row->>v_right)),'op_key','20:retire:'||(after_row->>'id'));
   ops:=ops||jsonb_build_array(op||jsonb_build_object('before',plm.licensing_consolidation_operation_state(op),'after',after_row||jsonb_build_object('is_current',false,'superseded_at',v_time,'superseded_reason','Absent from qualified comparable complete capture')));
   execute format('select exists(select 1 from %s where %I=$1 and %I=$2 and source_system<>$3 and is_current and evidence_kind=''direct_source_assertion'')',v_support,v_left,v_right) into v_now_current using (after_row->>v_left)::uuid,(after_row->>v_right)::uuid,p_source_system;
   if not v_now_current then
    op:=jsonb_build_object('kind','canonical_pair','entity_kind',v_rec.kind,'target',v_pair,'identity',jsonb_build_object(v_left,after_row->>v_left,v_right,after_row->>v_right),'licensor_id',v_owner,'owners',op->'owners','op_key','30:pair:'||(after_row->>'source_id'));
    before_state:=plm.licensing_consolidation_operation_state(op);
    if before_state->'rows'->0 is not null and (before_state->'rows'->0->>'is_current')::boolean then ops:=ops||jsonb_build_array(op||jsonb_build_object('before',before_state,'after',before_state->'rows'->0||jsonb_build_object('is_current',false,'retired_at',v_time,'retired_reason','No remaining qualified direct source support')));end if;
   end if;
  end loop;
 end loop;
 for existing in select to_jsonb(r) from core.taxonomy_source_ref r where source_system=p_source_system and missing_since is null order by source_table,source_id for update loop
  if v_filtered is not null and existing->>'source_id'<>v_filtered then continue;end if;
  if exists(select 1 from jsonb_array_elements(entities) x where x->>'source_id'=existing->>'source_id') then continue;end if;
  if existing->'raw'->>'engine_schema_version' is distinct from '2' or existing->'raw'->'scope_namespace' is distinct from v_scope then raise exception 'missing entity reference lacks comparable qualified capture namespace';end if;
  v_table:=(existing->>'entity_schema')||'.'||(existing->>'entity_table');
  op:=jsonb_build_object('kind','entity_source','entity_kind',existing->>'entity_table','target','core.taxonomy_source_ref','identity',jsonb_build_object('source_system',p_source_system,'source_table',existing->>'source_table','source_id',existing->>'source_id'),'licensor_id',existing->>'source_licensor_id','owners',jsonb_build_array(jsonb_build_object('table',v_table,'id',existing->>'entity_id')),'op_key','10:entity:'||(existing->>'source_id'));
  ops:=ops||jsonb_build_array(op||jsonb_build_object('before',plm.licensing_consolidation_operation_state(op),'after',existing||jsonb_build_object('missing_since',v_time)));
 end loop;
 if jsonb_array_length(ops)>512 then raise exception 'consolidation whole plan exceeds512operations';end if;
 if (select count(*) from jsonb_array_elements(ops))<>(select count(distinct x->>'op_key') from jsonb_array_elements(ops) x) then raise exception 'consolidation operation collision';end if;
 select coalesce(jsonb_agg(x order by x->>'op_key'),'[]') into ops from jsonb_array_elements(ops) x;
 select coalesce(jsonb_agg(jsonb_build_object('forward_op_key',x->>'op_key','kind',x->>'kind','target',x->>'target','identity',x->'identity','original_before',x->'before') order by x->>'op_key'),'[]') into inverse from jsonb_array_elements(ops) x;
 v_hash:=encode(extensions.digest(jsonb_build_object('schema_version',2,'source_system',p_source_system,'capture_id',p_capture_id,'capture_snapshot',snap,'operations',ops,'rollback_operations',inverse,'rollback_of',null)::text,'sha256'),'hex');
 insert into plm.licensing_consolidation_plan(source_system,capture_id,plan_hash,capture_complete,source_scope_checked,operations,rollback_operations,planned_by,plan_schema_version,capture_snapshot,entity_operation_count,relationship_operation_count,retire_operation_count)
 values(p_source_system,p_capture_id,v_hash,true,true,ops,inverse,coalesce(auth.uid()::text,session_user),2,snap,(select count(*) from jsonb_array_elements(ops) x where x->>'kind' in('entity_source','property_name')),(select count(*) from jsonb_array_elements(ops) x where x->>'kind'='relationship_source'),(select count(*) from jsonb_array_elements(ops) x where x->'after'->>'is_current'='false' or x->'after'->>'missing_since' is not null)) returning * into v_result;
 return v_result;
exception when sqlstate 'P0001' then
 -- Preserve the existing durable refusal capability; refused plans carry no partial writes.
 snap:=jsonb_build_object('schema_version',2,'refusal',sqlerrm,'filter',p_entity_source_id);ops:='[]'::jsonb;inverse:='[]'::jsonb;
 v_hash:=encode(extensions.digest(jsonb_build_object('schema_version',2,'source_system',p_source_system,'capture_id',p_capture_id,'capture_snapshot',snap,'operations',ops,'rollback_operations',inverse,'rollback_of',null)::text,'sha256'),'hex');
 insert into plm.licensing_consolidation_plan(source_system,capture_id,plan_hash,plan_status,capture_complete,source_scope_checked,operations,rollback_operations,planned_by,plan_schema_version,capture_snapshot,refusal_reason)
 values(p_source_system,p_capture_id,v_hash,'refused',false,false,ops,inverse,coalesce(auth.uid()::text,session_user),2,snap,sqlerrm) on conflict(source_system,capture_id,plan_hash) do nothing;
 select * into v_result from plm.licensing_consolidation_plan where source_system=p_source_system and capture_id=p_capture_id and plan_hash=v_hash;return v_result;
end $planner$;
revoke all on function plm.plan_licensing_consolidation(text,uuid,text) from public,anon,authenticated;
grant execute on function plm.plan_licensing_consolidation(text,uuid,text) to service_role;

create or replace function plm.licensing_consolidation_plan_immutable()
returns trigger language plpgsql security definer set search_path=pg_catalog as $immutable$
begin
 if tg_op='DELETE' then raise exception 'consolidation plan audit facts cannot be deleted' using errcode='42501';end if;
 if (to_jsonb(new)-array['plan_status','applied_at','applied_by','applied_state','entity_operation_count','relationship_operation_count','retire_operation_count']) is distinct from (to_jsonb(old)-array['plan_status','applied_at','applied_by','applied_state','entity_operation_count','relationship_operation_count','retire_operation_count']) then raise exception 'consolidation immutable content changed' using errcode='42501';end if;
 if old.plan_status='applied' and to_jsonb(new) is distinct from to_jsonb(old) then raise exception 'applied consolidation audit is immutable' using errcode='42501';end if;
 if old.plan_status<>'preview' or new.plan_status not in ('preview','applied') or new.plan_status='preview' and (new.applied_state is distinct from old.applied_state or new.entity_operation_count<>old.entity_operation_count or new.relationship_operation_count<>old.relationship_operation_count or new.retire_operation_count<>old.retire_operation_count) then raise exception 'invalid consolidation lifecycle transition' using errcode='42501';end if;
 if new.plan_status='applied' and (new.applied_state is null or new.applied_by is null or new.applied_at is null) then raise exception 'physical applied state and actor required';end if;
 return new;
end $immutable$;

create or replace function plm.apply_licensing_consolidation(p_plan_id uuid,p_expected_hash text)
returns plm.licensing_consolidation_plan language plpgsql security definer set search_path=pg_catalog as $apply$
declare plan plm.licensing_consolidation_plan;snap jsonb;op jsonb;result jsonb;states jsonb:='[]';v_hash text;v_entities integer:=0;v_rel integer:=0;v_retire integer:=0;
begin
 select * into plan from plm.licensing_consolidation_plan where id=p_plan_id for update;
 if plan.id is null or plan.plan_schema_version<>2 or plan.plan_hash is distinct from p_expected_hash then raise exception 'exact schema2 plan hash required';end if;
 v_hash:=encode(extensions.digest(jsonb_build_object('schema_version',2,'source_system',plan.source_system,'capture_id',plan.capture_id,'capture_snapshot',plan.capture_snapshot,'operations',plan.operations,'rollback_operations',plan.rollback_operations,'rollback_of',plan.rollback_of)::text,'sha256'),'hex');
 if v_hash<>plan.plan_hash then raise exception 'immutable consolidation payload hash mismatch';end if;
 -- True retry: no capture refresh, mutation or authorization token on an applied plan.
 if plan.plan_status='applied' then return plan;end if;
 if plan.plan_status<>'preview' or not plan.capture_complete or not plan.source_scope_checked or jsonb_array_length(plan.operations)>512 then raise exception 'qualified bounded preview plan required';end if;
 perform pg_advisory_xact_lock(hashtextextended('licensing-source:'||plan.source_system,0));
 if plan.source_system='nbcu' then lock table plm.nbcu_capture in share mode;
 elsif plan.source_system='paramount' then lock table plm.pmt_capture in share mode;
 elsif plan.source_system='disney_opa' then lock table plm.opa_capture in share mode;
 else raise exception 'capture source unsupported';end if;
 perform 1 from plm.licensing_source_scope where source_system=plan.source_system order by licensor_id,source_purpose,scope_axis,permitted_kind for update;
 perform 1 from plm.source_resolution where source_system=plan.source_system order by entity_kind,source_id for update;
 perform 1 from plm.licensing_relationship_resolution where source_system=plan.source_system order by licensor_id,relationship_kind,source_left_id,source_right_id for update;
 snap:=plm.licensing_consolidation_capture_snapshot(plan.source_system,plan.capture_id)||jsonb_build_object('filter',plan.capture_snapshot->'filter');
 if snap is distinct from plan.capture_snapshot then raise exception 'qualified capture or durable authority changed after planning' using errcode='40001';end if;
 for op in select value from jsonb_array_elements(plan.operations) order by value->>'op_key' loop
  if plm.licensing_consolidation_operation_state(op) is distinct from op->'before' then raise exception 'whole-plan before-state changed before any writes' using errcode='40001';end if;
 end loop;
 for op in select value from jsonb_array_elements(plan.operations) order by value->>'op_key' loop
  result:=plm.apply_licensing_support_operation(plan.id,plan.plan_hash,op);
  states:=states||jsonb_build_array(jsonb_build_object('op_key',op->>'op_key','state',result->'state','changes',result->'changes'));
  if op->>'kind' in ('entity_source','property_name') then v_entities:=v_entities+(result->>'changes')::integer;else v_rel:=v_rel+(result->>'changes')::integer;end if;
  if op->'after'->>'is_current'='false' or op->'after'->>'missing_since' is not null then v_retire:=v_retire+(result->>'changes')::integer;end if;
 end loop;
 set constraints all immediate;
 set constraints all deferred;
 update plm.licensing_consolidation_plan set plan_status='applied',applied_at=clock_timestamp(),applied_by=coalesce(auth.uid()::text,session_user),applied_state=jsonb_build_object('operations',states,'entity_changes',v_entities,'relationship_changes',v_rel,'retire_changes',v_retire),entity_operation_count=v_entities,relationship_operation_count=v_rel,retire_operation_count=v_retire where id=plan.id returning * into plan;
 return plan;
end $apply$;
revoke all on function plm.apply_licensing_consolidation(uuid,text) from public,anon,authenticated;
grant execute on function plm.apply_licensing_consolidation(uuid,text) to service_role;

create or replace function plm.plan_licensing_consolidation_rollback(p_applied_plan_id uuid,p_expected_applied_state_hash text)
returns plm.licensing_consolidation_plan language plpgsql security definer set search_path=pg_catalog as $rollback$
declare original plm.licensing_consolidation_plan;result plm.licensing_consolidation_plan;snap jsonb;ops jsonb:='[]';inverse jsonb:='[]';op jsonb;state jsonb;before_state jsonb;a jsonb;row_before jsonb;v_hash text;v_capture uuid;v_proof jsonb;v_native jsonb;v_meta jsonb;v_row jsonb;v_table text;v_left text;v_right text;v_keep boolean;v_rec record;v_owner uuid;v_owner_now uuid;
begin
 select * into original from plm.licensing_consolidation_plan where id=p_applied_plan_id for update;
 if original.id is null or original.plan_status<>'applied' or original.plan_schema_version<>2 or encode(extensions.digest(original.applied_state::text,'sha256'),'hex') is distinct from p_expected_applied_state_hash then raise exception 'rollback requires exact applied-state hash';end if;
 perform pg_advisory_xact_lock(hashtextextended('licensing-source:'||original.source_system,0));
 if original.source_system='nbcu' then lock table plm.nbcu_capture in share mode;select id into v_capture from plm.nbcu_capture where status='complete' order by source_captured_at desc,load_completed_at desc,id desc limit 1;
 elsif original.source_system='paramount' then lock table plm.pmt_capture in share mode;select capture_id into v_capture from plm.pmt_capture where status='complete' and capture_kind='full' order by completed_at desc,started_at desc,capture_id desc limit 1;
 elsif original.source_system='disney_opa' then lock table plm.opa_capture in share mode;select id into v_capture from plm.opa_capture where status='complete' order by source_captured_at desc,load_completed_at desc,id desc limit 1;
 else raise exception 'rollback source capture unsupported';end if;
 perform 1 from plm.licensing_source_scope where source_system=original.source_system order by licensor_id,source_purpose,scope_axis,permitted_kind for update;
 perform 1 from plm.source_resolution where source_system=original.source_system order by entity_kind,source_id for update;
 perform 1 from plm.licensing_relationship_resolution where source_system=original.source_system order by licensor_id,relationship_kind,source_left_id,source_right_id for update;
 snap:=plm.licensing_consolidation_capture_snapshot(original.source_system,v_capture)||jsonb_build_object('filter',original.capture_snapshot->'filter');
 for op in select value from jsonb_array_elements(original.operations) order by value->>'op_key' loop
  v_owner:=(op->>'licensor_id')::uuid;
  if not exists(select 1 from plm.licensing_source_scope where source_system=original.source_system and licensor_id=v_owner and source_purpose=case when op->>'kind' in ('relationship_source','canonical_pair') then 'relationship_evidence' else 'canonical_identity' end and scope_axis=case when op->>'kind' in ('relationship_source','canonical_pair') then 'relationship' else 'entity' end and permitted_kind=op->>'entity_kind' and authorized_at is not null and authorized_by is not null) then raise exception 'rollback current source authority absent';end if;
  for v_rec in select value->>'table' owner_table,value->>'id' owner_id from jsonb_array_elements(op->'owners') order by value->>'table',value->>'id' loop
   execute format('select licensor_id from %s where id=$1 for update',v_rec.owner_table) into v_owner_now using v_rec.owner_id::uuid;
   if v_owner_now is distinct from v_owner then raise exception 'rollback current canonical owner changed';end if;
  end loop;
  select x->'state' into state from jsonb_array_elements(original.applied_state->'operations') x where x->>'op_key'=op->>'op_key';
  before_state:=plm.licensing_consolidation_operation_state(op);
  if state is null or before_state is distinct from state then raise exception 'rollback actual post-state changed' using errcode='40001';end if;
  row_before:=op->'before'->'rows'->0;v_row:=before_state->'rows'->0;
  if op->>'kind'='property_name' then
   a:=jsonb_build_object('name',row_before->>'name');
   if exists(select 1 from core.property_alias where property_id=(op->'identity'->>'id')::uuid and normalized_alias=core.normalize_popsg_property_observation(a->>'name')) then raise exception 'rollback old spelling is retained alias; cannot erase history to satisfy redundancy guard';end if;
  elsif row_before is not null then a:=row_before;
  elsif op->>'kind'='entity_source' then a:=v_row||jsonb_build_object('missing_since',clock_timestamp());
  elsif op->>'kind'='relationship_source' then a:=v_row||jsonb_build_object('is_current',false,'superseded_at',clock_timestamp(),'superseded_reason','Conditional inverse of exact consolidation plan');
  else a:=v_row||jsonb_build_object('is_current',false,'retired_at',clock_timestamp(),'retired_reason','Conditional inverse retains original pair identity');end if;
  if op->>'kind'='relationship_source' and a->>'is_current'='true' then
   v_meta:=a->'metadata';
   for v_proof in select value from jsonb_array_elements(v_meta->'native_provenance') loop
    if not exists(select 1 from jsonb_array_elements(snap->'edges') x where x->>'source_table'=v_proof->>'source_table' and x->>'left_native_id'=v_proof->>'left_native_id' and x->>'right_native_id'=v_proof->>'right_native_id' and coalesce(x->>'scope','')=coalesce(v_proof->>'scope','')) then raise exception 'rollback support no longer has qualified current native assertion';end if;
   end loop;
  end if;
  -- An inverse cannot retire a pair now independently supported by another source.
  if op->>'kind'='canonical_pair' and a->>'is_current'='false' then
   select * into v_rec from (values
    ('core.property_character_associations','core.property_character_source_edge','property_id','character_id'),('core.property_style_guide','core.property_style_guide_source_edge','property_id','style_guide_id'),('core.property_franchise','core.property_franchise_source_edge','property_id','franchise_id'),('core.style_guide_character','core.style_guide_character_source_edge','style_guide_id','character_id'),('dam.asset_property','dam.asset_property_source_edge','asset_id','property_id'),('dam.asset_character','dam.asset_character_source_edge','asset_id','character_id'),('dam.asset_style_guide','dam.asset_style_guide_source_edge','asset_id','style_guide_id'),('dam.asset_franchise','dam.asset_franchise_source_edge','asset_id','franchise_id')) m(pair_table,edge_table,left_col,right_col) where pair_table=op->>'target';
   execute format('select exists(select 1 from %s where %I=$1 and %I=$2 and is_current and source_system<>$3)',v_rec.edge_table,v_rec.left_col,v_rec.right_col) into v_keep using (v_row->>v_rec.left_col)::uuid,(v_row->>v_rec.right_col)::uuid,original.source_system;
   if v_keep then continue;end if;
  end if;
  op:=op||jsonb_build_object('op_key',case op->>'kind' when 'relationship_source' then case when a->>'is_current'='false' then '20:' else '21:' end when 'canonical_pair' then '30:' when 'entity_source' then '10:' else '40:' end||'rollback:'||(op->>'op_key'),'before',before_state,'after',a);
  ops:=ops||jsonb_build_array(op);
 end loop;
 if jsonb_array_length(ops)>512 then raise exception 'rollback whole plan exceeds512operations';end if;
 select coalesce(jsonb_agg(x order by case x->>'kind' when 'entity_source' then 1 when 'relationship_source' then 2 when 'canonical_pair' then 3 else 4 end,x->>'op_key'),'[]') into ops from jsonb_array_elements(ops) x;
 v_hash:=encode(extensions.digest(jsonb_build_object('schema_version',2,'source_system',original.source_system,'capture_id',v_capture,'capture_snapshot',snap,'operations',ops,'rollback_operations',inverse,'rollback_of',original.id)::text,'sha256'),'hex');
 insert into plm.licensing_consolidation_plan(source_system,capture_id,plan_hash,capture_complete,source_scope_checked,operations,rollback_operations,planned_by,plan_schema_version,capture_snapshot,rollback_of)
 values(original.source_system,v_capture,v_hash,true,true,ops,inverse,coalesce(auth.uid()::text,session_user),2,snap,original.id) returning * into result;
 return result;
end $rollback$;
revoke all on function plm.plan_licensing_consolidation_rollback(uuid,text) from public,anon,authenticated;
grant execute on function plm.plan_licensing_consolidation_rollback(uuid,text) to service_role;

commit;
