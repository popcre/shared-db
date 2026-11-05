-- #5662: primary refresh visits every group and preserves search catch-up while
-- writing only changed cached primary fields. Synthetic fixtures; rollback only.
begin;
-- Transaction-local function statistics count invocations even when a future
-- canonical no-op refresh performs no document write. Throwaway database only.
set local track_functions = 'all';
create temporary table primary_noop_group_writes(id uuid);
create temporary table primary_noop_search_writes(id uuid);
create function pg_temp.primary_noop_group_counter() returns trigger language plpgsql as $$
begin insert into pg_temp.primary_noop_group_writes values(new.id); return new; end $$;
create function pg_temp.primary_noop_search_counter() returns trigger language plpgsql as $$
begin
  if new.document_type = 'style_group' then
    insert into pg_temp.primary_noop_search_writes values(new.entity_id);
  end if;
  return new;
end $$;
create trigger primary_noop_group_counter after update on public.style_groups
for each row execute function pg_temp.primary_noop_group_counter();
create trigger primary_noop_search_counter after insert or update on public.dam_search_documents
for each row execute function pg_temp.primary_noop_search_counter();

do $$
declare
  ids uuid[];
  n integer;
  unchanged integer;
  calls_before bigint;
  calls_after bigint;
begin
  insert into public.style_groups(id,sku,folder_path)
  select ('ffffffff-5662-4000-8000-' || lpad(i::text,12,'0'))::uuid,
    'ZZ5662-' || txid_current() || '-' || i, 'ZZ5662/' || i
  from generate_series(1,25) i;
  select array_agg(id order by id) into ids from public.style_groups
  where id::text like 'ffffffff-5662-4000-8000-%';

  insert into public.assets(id,filename,relative_path,file_type,quick_hash,
    modified_at,style_group_id,is_deleted,thumbnail_url,created_at)
  select ('ffffffff-5662-4001-8000-' || lpad(i::text,12,'0'))::uuid,
    'ZZ5662_design.psd','ZZ5662/' || i || '/design.psd','psd',
    'zz5662-' || txid_current() || '-' || i, now(),
    ('ffffffff-5662-4000-8000-' || lpad(i::text,12,'0'))::uuid,false,
    'https://example.invalid/zz5662.png', now()
  from generate_series(1,25) i;
  perform public.refresh_style_group_primaries(ids);

  -- Deliberately stale cache in five groups; candidate selection is unchanged.
  update public.style_groups set primary_thumbnail_error='ZZ5662 stale'
  where id = any(ids[1:5]);
  create temporary table primary_noop_preimages as
    select * from public.style_groups where id = any(ids);
  -- Force stale search hashes so independently owned no-op search guards can
  -- still demonstrate one necessary repair for every visited group.
  update public.dam_search_documents set content_sha256=repeat('0',64)
  where document_type='style_group' and entity_id=any(ids);
  truncate pg_temp.primary_noop_group_writes, pg_temp.primary_noop_search_writes;

  select coalesce((select calls from pg_stat_xact_user_functions
    where funcid='public.refresh_dam_search_style_group_document(uuid)'::regprocedure),0)
  into calls_before;
  n := public.refresh_style_group_primaries(ids);
  select coalesce((select calls from pg_stat_xact_user_functions
    where funcid='public.refresh_dam_search_style_group_document(uuid)'::regprocedure),0)
  into calls_after;
  if calls_after-calls_before <> 25 then
    raise exception '5662: canonical refresh invocations %, expected25',calls_after-calls_before;
  end if;
  if n <> 25 then raise exception '5662: visited count %, expected25', n; end if;
  if (select count(*) from pg_temp.primary_noop_group_writes) <> 5 then
    raise exception '5662: expected exactly5 primary row updates';
  end if;
  if (select count(*) from pg_temp.primary_noop_search_writes) <> 25
    or (select count(distinct id) from pg_temp.primary_noop_search_writes) <> 25 then
    raise exception '5662: expected exactly one search refresh per visited group';
  end if;
  select count(*) into unchanged from pg_temp.primary_noop_preimages b
  join public.style_groups s using(id) where to_jsonb(b)=to_jsonb(s);
  if unchanged <> 20 then raise exception '5662: unchanged preimages %, expected20',unchanged; end if;
  if exists(select 1 from pg_temp.primary_noop_preimages b join public.style_groups s using(id)
    where b.style_group_changed_at is distinct from s.style_group_changed_at) then
    raise exception '5662: business watermark changed';
  end if;
  if public.refresh_style_group_primaries(null) <> 0
    or public.refresh_style_group_primaries('{}'::uuid[]) <> 0
    or public.refresh_style_group_primaries(array['ffffffff-5662-4999-8000-000000000000']::uuid[]) <> 0 then
    raise exception '5662: null/empty/missing boundary';
  end if;
  -- Master-name edits have no association-row event; nightly refresh must catch up.
  insert into core.character(id,name)
  values('ffffffff-5662-4002-8000-000000000001','ZZ5662 Before');
  insert into public.asset_licensor_characters(asset_id,character_id)
  values('ffffffff-5662-4001-8000-000000000001','ffffffff-5662-4002-8000-000000000001');
  perform public.refresh_style_group_primaries(array[ids[1]]);
  update core.character set name='ZZ5662 Renamed'
  where id='ffffffff-5662-4002-8000-000000000001';
  truncate pg_temp.primary_noop_group_writes,pg_temp.primary_noop_search_writes;
  n := public.refresh_style_group_primaries(array[ids[1]]);
  if n <> 1 or exists(select 1 from pg_temp.primary_noop_group_writes)
    or (select count(*) from pg_temp.primary_noop_search_writes) <> 1
    or not exists(select 1 from public.dam_search_documents
      where document_type='style_group' and entity_id=ids[1]
        and search_text like '%ZZ5662 Renamed%') then
    raise exception '5662: character-name-only search catch-up';
  end if;
  update public.dam_search_documents set content_sha256=repeat('0',64)
  where document_type='style_group' and entity_id=ids[1];
  truncate pg_temp.primary_noop_group_writes,pg_temp.primary_noop_search_writes;
  n := public.refresh_style_group_primaries(array[ids[1],ids[1]]);
  if n <> 1
    or exists(select 1 from pg_temp.primary_noop_group_writes)
    or (select count(*) from pg_temp.primary_noop_search_writes) <> 1 then
    raise exception '5662: duplicate/unchanged boundary';
  end if;
end $$;
rollback;
