-- Synthetic private tables only; exercise the installed definitions without
-- firing production asset/render triggers or depending on licensed source rows.
begin;
set local lock_timeout='500ms';
set local statement_timeout='2500ms';
set local transaction_timeout='3s';
set local search_path=pg_temp,public,extensions;
set local request.jwt.claim.role='service_role';
set local request.jwt.claims='{"role":"service_role"}';
create temporary table va_assets as select * from public.assets with no data;
create temporary table va_groups as select * from public.style_groups with no data;
create temporary table va_docs as select * from public.dam_search_documents with no data;
create temporary table va_render as select * from public.render_queue with no data;
alter table va_docs alter embedding_attempts set default 0, alter embedding_max_attempts set default 5;
create unique index va_docs_key on va_docs(document_type,entity_id);
create index va_save_hnsw on va_docs using hnsw (embedding extensions.vector_cosine_ops) where embedding is not null;
do $$ declare r record; s text; n text; begin
 for r in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace where
  (n.nspname='dam' and p.proname in ('search_embedding_image_provenance','search_embedding_inputs_match')) or
  (n.nspname='public' and p.proname in ('refresh_dam_search_asset_document','refresh_dam_search_style_group_document',
    'claim_dam_search_embedding_documents','upsert_dam_search_embedding','mark_dam_search_embedding_error',
    'refresh_dam_search_after_render_completion','refresh_dam_search_after_source_size_change'))
 loop
  s:=pg_get_functiondef(r.oid);
  s:=replace(replace(replace(replace(s,'public.assets','pg_temp.va_assets'),
    'public.style_groups','pg_temp.va_groups'),'public.dam_search_documents','pg_temp.va_docs'),'public.render_queue','pg_temp.va_render');
  s:=replace(s,'dam_search_documents.','va_docs.');
  foreach n in array array['dam.search_embedding_image_provenance','dam.search_embedding_inputs_match',
   'public.refresh_dam_search_asset_document','public.refresh_dam_search_style_group_document',
   'public.claim_dam_search_embedding_documents','public.upsert_dam_search_embedding','public.mark_dam_search_embedding_error',
   'public.refresh_dam_search_after_render_completion','public.refresh_dam_search_after_source_size_change']
  loop s:=replace(s,n,'pg_temp.va_'||split_part(n,'.',2)); end loop;
  execute s;
 end loop;
end $$;
create trigger va_render_completed after update of status,completed_at on va_render for each row
execute function pg_temp.va_refresh_dam_search_after_render_completion();
create trigger va_size_changed after update of file_size on va_assets for each row
when (old.file_size is distinct from new.file_size and old.modified_at is not distinct from new.modified_at
 and old.thumbnail_url is not distinct from new.thumbnail_url) execute function pg_temp.va_refresh_dam_search_after_source_size_change();
create function pg_temp.va_assert(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'image input contract: %',label; end if; end $$;
create temporary table va_save_audit(n integer);
create function pg_temp.va_count_doc_update() returns trigger language plpgsql as $$
begin insert into va_save_audit values(1); return new; end $$;
create trigger va_doc_update_count after update on va_docs for each row execute function pg_temp.va_count_doc_update();
do $$
declare aid uuid:='00000000-0000-4000-8000-000000056650'; gid uuid:='00000000-0000-4000-8000-000000056651';
 v extensions.vector:=('[1,'||repeat('0,',766)||'0]')::extensions.vector;
 old_row jsonb; old_tid tid; old_hash text; old_token uuid; n integer;
begin
 insert into va_assets(id,filename,relative_path,file_type,is_deleted,thumbnail_url,ai_description,updated_at,modified_at,file_size)
 values(aid,'synthetic.png','fixture/synthetic.png','png',false,'https://example.invalid/stable.png','original',now(),now()-interval '1 day',100);
 perform pg_temp.va_refresh_dam_search_asset_document(aid);
 insert into va_groups(id,sku,folder_path,primary_asset_id,primary_thumbnail_url,updated_at)
 values(gid,'FIXTURE','fixture',aid,'https://example.invalid/stable.png',now());
 update va_assets set style_group_id=gid where id=aid;
 perform pg_temp.va_refresh_dam_search_style_group_document(gid);
 update va_docs set embedding=v,embedding_model='google/siglip2-base-patch16-naflex',embedding_updated_at=now(),metadata=metadata-'_embedding_input';
 delete from va_save_audit;
 select to_jsonb(d),ctid,content_sha256 into old_row,old_tid,old_hash from va_docs d where entity_id=gid;
 perform pg_temp.va_refresh_dam_search_style_group_document(gid);
 perform pg_temp.va_assert((select ctid=old_tid and to_jsonb(d)=old_row from va_docs d where entity_id=gid),'unchanged legacy group preserves full row/ctid/vector without provenance bootstrap');
 perform pg_temp.va_assert((select count(*)=0 from va_save_audit),'unchanged legacy group performs zero document updates');
 update va_groups set group_ai_description='actual changed search keywords';
 perform pg_temp.va_refresh_dam_search_style_group_document(gid);
 perform pg_temp.va_assert((select content_sha256<>old_hash and search_text like '%actual changed search keywords%' and embedding=v from va_docs where entity_id=gid),'real keyword change still refreshes exact text and retains canonical image vector');
 -- A genuine active legacy job remains valid; no-op must not replace its lease.
 update va_docs set embedding=null,embedding_model=null,embedding_updated_at=null,metadata=metadata-'_embedding_input',
   embedding_lease_token=gen_random_uuid(),embedding_lease_owner='normal-worker',embedding_lease_expires_at=now()+interval '5 minutes',indexed_at=now()
 where entity_id=gid;
 select to_jsonb(d),ctid,embedding_lease_token into old_row,old_tid,old_token from va_docs d where entity_id=gid;
 perform pg_temp.va_refresh_dam_search_style_group_document(gid);
 perform pg_temp.va_assert((select ctid=old_tid and to_jsonb(d)=old_row from va_docs d where entity_id=gid),'unchanged legacy pending job preserves full lease and queue age');
 -- New render revision at the SAME URL must defeat the no-op guard.
 insert into va_render(id,asset_id,status,completed_at) values(gen_random_uuid(),aid,'completed',now()+interval '1 second');
 perform pg_temp.va_refresh_dam_search_style_group_document(gid);
 perform pg_temp.va_assert((select embedding_lease_token is null and metadata ? '_embedding_input' from va_docs where entity_id=gid),'same URL newer authoritative render invalidates legacy lease');
 -- Unknown/wrong model may not be retained by the no-op guard.
 update va_docs set embedding=v,embedding_model='wrong/model',embedding_updated_at=now();
 perform pg_temp.va_refresh_dam_search_style_group_document(gid);
 perform pg_temp.va_assert((select embedding is null from va_docs where entity_id=gid),'wrong model cannot take early no-op');
 -- Source-size invalidation remains scoped and functional via its actual trigger.
 update va_docs set embedding=v,embedding_model='google/siglip2-base-patch16-naflex',embedding_updated_at=now()+interval '2 seconds';
 update va_assets set file_size=101 where id=aid;
 perform pg_temp.va_assert((select embedding is null from va_docs where entity_id=gid),'actual size-only source trigger still invalidates group vector');
 -- Real business metadata changes also refresh despite unchanged text.
 update va_groups set asset_count=42;
 perform pg_temp.va_refresh_dam_search_style_group_document(gid);
 perform pg_temp.va_assert((select metadata->>'asset_count'='42' from va_docs where entity_id=gid),'business metadata update is retained');
 -- Direct group-path negatives: do not rely on asset-only refresh coverage.
 update va_docs set embedding=v,embedding_model='google/siglip2-base-patch16-naflex',embedding_updated_at=now()+interval '2 seconds' where entity_id=gid;
 update va_assets set modified_at=now()+interval '3 seconds' where id=aid;
 perform pg_temp.va_refresh_dam_search_style_group_document(gid);
 perform pg_temp.va_assert((select embedding is null from va_docs where entity_id=gid),'changed authoritative source modified_at defeats group no-op');
 update va_docs set embedding=v,embedding_model='google/siglip2-base-patch16-naflex',embedding_updated_at=now()+interval '4 seconds' where entity_id=gid;
 update va_assets set thumbnail_url='https://example.invalid/new-thumbnail.png' where id=aid;
 update va_groups set primary_thumbnail_url='https://example.invalid/new-thumbnail.png' where id=gid;
 perform pg_temp.va_refresh_dam_search_style_group_document(gid);
 perform pg_temp.va_assert((select embedding is null and metadata->>'thumbnail_url'='https://example.invalid/new-thumbnail.png' from va_docs where entity_id=gid),'changed group thumbnail defeats group no-op and refreshes metadata');
end $$;
rollback;
