-- #5609 read-only successor acceptance; successor baseline UNSET (fail closed).
-- Historical failed-window probe preserved byte-for-byte at
-- docs/verification/issue-5609-trigger-acceptance/5609-original-failed-window.sql
-- SHA256 4db994c5425617fe5c211f688b6d35dd520f2af5449ef80d7c7e0c96d6a0eb9f
-- Original post-apply baseline observed November 5, 2026,
-- 12:36:57 AM EST after automatic run41974228042 applied the immutable source.
-- Its catalog-recovery verification remains distinct; never reapply this source.
-- Frozen pre-change main PATCH baseline: November 4, 2026, 10:37 PM EST.
-- Frozen document rate: 8,829 updates / 5,050.846546 seconds, ending
-- November 5, 2026, 12:01:25 AM EST, while the migration was still absent.
-- No writes, timers, helpers, grants, or relaxed limits are introduced.
with baseline as (
 select
   null::timestamptz as observed_at,
   null::timestamptz as statement_stats_reset,
   null::timestamptz as entry_stats_since,
   null::timestamptz as database_stats_reset,
   null::timestamptz as postmaster_started_at,
   null::bigint as calls,
   null::numeric as total_exec_time,
   null::numeric as wal_bytes,
   null::bigint as asset_updates,
   null::bigint as document_updates,
   170.077045367033::numeric as pre_mean_ms,
   59888.980667756245::numeric as pre_wal_per_call,
   (8829::numeric / 5050.846546::numeric) as pre_document_updates_per_second
), query_stats as (
 select calls,total_exec_time,wal_bytes,stats_since
 from extensions.pg_stat_statements
 where queryid='8695287796313115953'::bigint
   and userid='16486'::oid and dbid='5'::oid and toplevel
), table_stats as (
 select
  (select n_tup_upd from pg_stat_user_tables where relid='public.assets'::regclass) as asset_updates,
  (select n_tup_upd from pg_stat_user_tables where relid='public.dam_search_documents'::regclass) as document_updates
), expected as (
 select * from (values
  ('trg_auto_queue_render','public.auto_queue_render()',17,array['6d292c5ad846cc05bb3290b926bf1d20','f4a2b5b6f5877746b78d4058f55835bb']),
  ('trg_auto_queue_render_ins_del','public.auto_queue_render()',5,array['caa4f524dd84c8e24d36fc8d68c59c89']),
  ('trg_dam_search_assets_refresh','public.trg_refresh_dam_asset_search_document()',17,array['3adf740fb4f20406f6620052b23e28c3','543a6d307f7d8cb6f17c1ae4c83bdd6a']),
  ('trg_dam_search_assets_refresh_ins_del','public.trg_refresh_dam_asset_search_document()',13,array['9fb1930126a935df0ff11d05bbcfdd4b']),
  ('trg_sync_cover_description_to_style_group','public.sync_cover_description_to_style_group()',17,array['dac32eaf299fd77dfa9ac6827a18211a','9711807e2187b18a28d47bf567089328']),
  ('trg_sync_cover_description_to_style_group_ins_del','public.sync_cover_description_to_style_group()',5,array['b4ddc43b9e60e91649c6fca65ad10f6e']),
  ('trg_sync_designer_to_style_group','public.sync_designer_to_style_group()',17,array['a2037258e3fd300113b8489f25ee62a9','ad1e03640d8163a324e9a7d54db77d6f']),
  ('trg_sync_designer_to_style_group_ins_del','public.sync_designer_to_style_group()',5,array['24a12b32508aee5a6b24075d011e6897']),
  ('trg_sync_primary_on_thumbnail','public.sync_primary_asset_on_thumbnail()',17,array['224aa60d20a0b9f58a052b6f603598b8','28c25be1dbde678c718bc372439edeb4']),
  ('trg_sync_primary_on_thumbnail_ins_del','public.sync_primary_asset_on_thumbnail()',5,array['f7870cdb13d8aedf4901696cf1bc5622'])
 )e(trigger_name,function_name,event_type,definition_md5s)
), recent as (
 select a.* from public.assets a tablesample system(1) repeatable(5609) cross join baseline b
 where not a.is_deleted and a.last_seen_at>=greatest(b.observed_at,now()-interval '24 hours')
   and a.last_seen_at<=now() limit 3
), metadata_source as (
 select a.id,a.modified_at,a.file_size,a.thumbnail_url,
  d.metadata as actual_metadata,d.indexed_at,d.source_updated_at,q.render_completed_at as current_queue_render,d.embedding_lease_token,d.embedding_lease_owner,d.embedding_lease_expires_at,
  jsonb_strip_nulls(jsonb_build_object(
   'file_type',a.file_type,'asset_type',a.asset_type,'content_type',a.content_type,
   'item_description',sg.item_description,'group_ai_description',sg.group_ai_description,
   'product_material',a.product_material,'product_dimensions',a.product_dimensions,
   'workflow_status',a.workflow_status,'is_licensed',a.is_licensed,
   'licensor_name',case when a.style_group_id is null then a.licensor_name else sg.licensor_name end,
   'property_name',case when a.style_group_id is null then a.property_name else sg.property_name end,
   'product_category',a.product_category,'thumbnail_url',a.thumbnail_url)) as core_metadata,
  -- #05074126 retains a previous completed render after queue retention.
  -- Invalid JSON dates abstain; never invoke its service-only VOLATILE helper.
  greatest(q.render_completed_at,case
    when d.metadata->'_embedding_input'->>'asset_id'=a.id::text
     and pg_input_is_valid(d.metadata->'_embedding_input'->>'render_completed_at','timestamp with time zone')
    then (d.metadata->'_embedding_input'->>'render_completed_at')::timestamptz end) as retained_render,
  coalesce(not coalesce(d.metadata->'_embedding_input' ? 'render_completed_at',false) or
    (jsonb_typeof(d.metadata->'_embedding_input'->'render_completed_at')='string'
     and pg_input_is_valid(d.metadata->'_embedding_input'->>'render_completed_at','timestamp with time zone')),false) as render_valid
 from recent a left join public.style_groups sg on sg.id=a.style_group_id
 left join public.dam_search_documents d on d.document_type='asset' and d.entity_id=a.id
 left join lateral(select rq.completed_at as render_completed_at from public.render_queue rq
    where rq.asset_id=a.id and rq.status='completed' and rq.completed_at is not null
    order by rq.completed_at desc limit 1)q on true
), provenance_input as (
 select m.*,case when nullif(btrim(thumbnail_url),'') is not null
    and (modified_at is not null or retained_render is not null)
  then jsonb_strip_nulls(jsonb_build_object(
   'version',1,'model','google/siglip2-base-patch16-naflex','image_transform','uncropped-thumbnail',
   'asset_id',id,'thumbnail_url',thumbnail_url,
   -- Match the authoritative helper's SET timezone=UTC JSON encoding without SET.
   'source_modified_at',case when modified_at is null then null when isfinite(modified_at)
     then (to_jsonb(modified_at at time zone 'UTC') #>> '{}')||'+00:00' else modified_at::text end,
   'source_file_size',file_size,
   'render_completed_at',case when retained_render is null then null when isfinite(retained_render)
     then (to_jsonb(retained_render at time zone 'UTC') #>> '{}')||'+00:00' else retained_render::text end)) end as expected_input_base
 from metadata_source m
), metadata_checked as (
 select p.*,
  -- Grandfather only unchanged pre-cutover documents; present JSON NULL is not absence.
  coalesce(not (actual_metadata ? '_embedding_input')
    and indexed_at<'2026-11-05T07:30:57-05:00'::timestamptz
    and source_updated_at<'2026-11-05T07:30:57-05:00'::timestamptz
    and (modified_at is null or (modified_at<=indexed_at and modified_at<=source_updated_at))
    and (current_queue_render is null or
      (current_queue_render<=indexed_at and current_queue_render<=source_updated_at)),false) as legacy_unchanged,
  case when expected_input_base is not null then
    expected_input_base||jsonb_build_object('sha256',encode(extensions.digest(expected_input_base::text,'sha256'),'hex')) end as expected_input,
  case when embedding_lease_token is null then
    embedding_lease_owner is null and embedding_lease_expires_at is null
      and not (actual_metadata ? '_embedding_lease_input_sha256')
   else nullif(btrim(embedding_lease_owner),'') is not null
    and embedding_lease_expires_at is not null and isfinite(embedding_lease_expires_at)
    and jsonb_typeof(actual_metadata->'_embedding_lease_input_sha256')='string'
    and (actual_metadata->>'_embedding_lease_input_sha256') ~ '^[0-9a-f]{64}$' end as lease_valid
 from provenance_input p
), current_metadata as (
 select count(*) as checked,
  bool_and(coalesce(render_valid and lease_valid
    and actual_metadata is not distinct from
      core_metadata||case when expected_input is null or legacy_unchanged then '{}'::jsonb
        else jsonb_build_object('_embedding_input',expected_input) end
      ||case when embedding_lease_token is null then '{}'::jsonb else
        jsonb_build_object('_embedding_lease_input_sha256',actual_metadata->'_embedding_lease_input_sha256') end,false)) as all_match
 from metadata_checked
)
select case
 when b.observed_at is null or b.calls is null or b.total_exec_time is null
   or b.wal_bytes is null or b.asset_updates is null or b.document_updates is null
   or b.statement_stats_reset is null or b.entry_stats_since is null or b.postmaster_started_at is null
   or now()<b.observed_at+interval '24 hours' then false
 else coalesce(
  current_user='supabase_read_only_user'
  and pg_has_role(current_user,'pg_read_all_stats','member')
  and not exists(select 1 from unnest(array[
    'public.assets','public.style_groups','public.dam_search_documents',
    'extensions.pg_stat_statements','extensions.pg_stat_statements_info','public.render_queue',
    'supabase_migrations.schema_migrations'])r(rel)
    where not has_table_privilege(current_user,rel,'select'))
  and pg_postmaster_start_time()=b.postmaster_started_at
  and (select stats_reset from extensions.pg_stat_statements_info)=b.statement_stats_reset
  and (select stats_reset from pg_stat_database where datname=current_database())
      is not distinct from b.database_stats_reset
  and exists(select 1 from supabase_migrations.schema_migrations where version='20261105033827')
  and exists(select 1 from supabase_migrations.schema_migrations where version='20261105074126')
  and (select count(*) from query_stats)=1
  and exists(select 1 from query_stats q where q.stats_since=b.entry_stats_since
    and q.calls-b.calls>=100
    and q.total_exec_time>=b.total_exec_time and q.wal_bytes>=b.wal_bytes
    and (q.total_exec_time-b.total_exec_time)/nullif(q.calls-b.calls,0)<b.pre_mean_ms*0.5
    and (q.wal_bytes-b.wal_bytes)/nullif(q.calls-b.calls,0)<b.pre_wal_per_call*0.5)
  and exists(select 1 from table_stats t where t.asset_updates>b.asset_updates
    and t.document_updates>=b.document_updates
    and (t.document_updates-b.document_updates)
        /extract(epoch from now()-b.observed_at)<b.pre_document_updates_per_second)
  and (select count(*) from expected)=10
  and not exists(select 1 from expected e where not exists(
    select 1 from pg_trigger t where t.tgrelid=to_regclass('public.assets')
      and t.tgname=e.trigger_name and t.tgtype=e.event_type and t.tgenabled='O'
      and not t.tgisinternal and not t.tgdeferrable and not t.tginitdeferred
      and t.tgnargs=0 and t.tgattr=''::int2vector
      and (t.tgqual is not null)=(e.event_type=17)
      and t.tgfoid=to_regprocedure(e.function_name)
      and md5(split_part(pg_get_triggerdef(t.oid,false),' EXECUTE FUNCTION ',1))=any(e.definition_md5s)))
  and (select count(*) from pg_trigger where tgrelid=to_regclass('public.assets')
    and tgfoid in(select to_regprocedure(function_name) from expected))=10
  and (select count(*) from pg_trigger where tgrelid=to_regclass('public.assets')
    and tgfoid in(select to_regprocedure(function_name) from expected) and tgtype=17)=5
  and (select count(*) from pg_trigger where tgrelid=to_regclass('public.assets')
    and tgfoid in(select to_regprocedure(function_name) from expected) and tgtype in(5,13))=5
  and exists(select 1 from pg_trigger t where t.tgrelid=to_regclass('public.assets')
    and t.tgname='trg_assets_enqueue_image_embed' and t.tgenabled='O' and t.tgtype=21
    and not t.tgisinternal and not t.tgdeferrable and not t.tginitdeferred and t.tgnargs=0
    and t.tgqual is null and t.tgfoid=to_regprocedure('dam.assets_enqueue_image_embed_trg_fn()')
    and t.tgattr::text=(select attnum::text from pg_attribute
      where attrelid=to_regclass('public.assets') and attname='thumbnail_url' and not attisdropped))
  and not exists(select 1 from public.style_groups sg join lateral(
      select a.thumbnail_url,a.thumbnail_error from public.assets a where a.id=sg.primary_asset_id limit 1
    )a on true where sg.primary_asset_id is not null
      and (sg.primary_thumbnail_url is distinct from a.thumbnail_url
           or sg.primary_thumbnail_error is distinct from a.thumbnail_error))
  and (select checked=3 and all_match from current_metadata)
 ,false)
end as passed
from baseline b;
