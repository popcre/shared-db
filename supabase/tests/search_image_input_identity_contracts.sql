-- Synthetic private tables only; exercise the installed definitions without
-- firing production asset/render triggers or depending on licensed source rows.
begin;
set local search_path=pg_temp,public,extensions;
set local request.jwt.claim.role='service_role';
set local request.jwt.claims='{"role":"service_role"}';
create temporary table va_assets as select * from public.assets with no data;
create temporary table va_groups as select * from public.style_groups with no data;
create temporary table va_docs as select * from public.dam_search_documents with no data;
create temporary table va_render as select * from public.render_queue with no data;
alter table va_docs alter embedding_attempts set default 0, alter embedding_max_attempts set default 5;
create unique index va_docs_key on va_docs(document_type,entity_id);
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
do $$
declare id uuid:='00000000-0000-4000-8000-000000056340'; gid uuid:='00000000-0000-4000-8000-000000056341';
 j record; before_doc record; after_doc record; v extensions.vector:=('[1,'||repeat('0,',766)||'0]')::extensions.vector;
 old_fp text; new_fp text;
begin
 insert into va_assets(id,filename,relative_path,file_type,is_deleted,thumbnail_url,ai_description,updated_at,modified_at,file_size)
 values(id,'synthetic.png','fixture/synthetic.png','png',false,'https://example.invalid/stable.png','original',now(),now()-interval '1 day',100);
 perform pg_temp.va_refresh_dam_search_asset_document(id);
 select * into j from pg_temp.va_claim_dam_search_embedding_documents(1,'fixture',300);
 select * into before_doc from va_docs where entity_id=id;
 update va_assets set ai_description='new exact keywords';
 perform pg_temp.va_refresh_dam_search_asset_document(id);
 select * into after_doc from va_docs where entity_id=id;
 perform pg_temp.va_assert(before_doc.embedding_lease_token=after_doc.embedding_lease_token,'text refresh preserves lease');
 perform pg_temp.va_assert(before_doc.content_sha256<>after_doc.content_sha256,'keyword hash still updates exactly');
 perform pg_temp.va_assert(pg_temp.va_upsert_dam_search_embedding(j.document_type,j.entity_id,j.content_sha256,j.lease_token,v,
   'google/siglip2-base-patch16-naflex'),'original poller claim completes after text change');
 update va_assets set ai_description='more keywords'; perform pg_temp.va_refresh_dam_search_asset_document(id);
 perform pg_temp.va_assert((select embedding is not null from va_docs where entity_id=id),'text preserves vector');
 update va_assets set modified_at=now()-interval '1 minute',file_size=101; perform pg_temp.va_refresh_dam_search_asset_document(id);
 perform pg_temp.va_assert((select embedding is null from va_docs where entity_id=id),'same URL source revision invalidates');
 select * into j from pg_temp.va_claim_dam_search_embedding_documents(1,'fixture',300);
 update va_assets set ai_description='keywords during lease'; perform pg_temp.va_refresh_dam_search_asset_document(id);
 perform pg_temp.va_assert(pg_temp.va_mark_dam_search_embedding_error(j.document_type,j.entity_id,j.content_sha256,j.lease_token,
   'fixture error','transient'),'original claim reports error after text change');
 update va_docs set embedding_next_retry_at=null;
 select * into j from pg_temp.va_claim_dam_search_embedding_documents(1,'fixture',300);
 insert into va_render(id,asset_id,status,completed_at) values(gen_random_uuid(),id,'pending',null);
 update va_render set status='completed',completed_at=now()-interval '30 seconds';
 perform pg_temp.va_assert((select embedding_lease_token is null from va_docs where entity_id=id),'same URL render clears old lease');
 perform pg_temp.va_assert(not pg_temp.va_upsert_dam_search_embedding(j.document_type,j.entity_id,j.content_sha256,j.lease_token,v,
   'google/siglip2-base-patch16-naflex'),'stale image completion rejected');
 select * into j from pg_temp.va_claim_dam_search_embedding_documents(1,'fixture',300);
 perform pg_temp.va_assert(not pg_temp.va_upsert_dam_search_embedding(j.document_type,j.entity_id,j.content_sha256,j.lease_token,v,
   'wrong/model'),'wrong model rejected');
 perform pg_temp.va_assert(not pg_temp.va_upsert_dam_search_embedding(j.document_type,j.entity_id,j.content_sha256,gen_random_uuid(),v,
   'google/siglip2-base-patch16-naflex'),'wrong token rejected');
 update va_docs set embedding_lease_expires_at=now()-interval '1 second';
 perform pg_temp.va_assert(not pg_temp.va_upsert_dam_search_embedding(j.document_type,j.entity_id,j.content_sha256,j.lease_token,v,
   'google/siglip2-base-patch16-naflex'),'expired completion rejected');
 select * into j from pg_temp.va_claim_dam_search_embedding_documents(1,'fixture',300);
 perform pg_temp.va_assert(pg_temp.va_upsert_dam_search_embedding(j.document_type,j.entity_id,j.content_sha256,j.lease_token,v,
   'google/siglip2-base-patch16-naflex'),'current image claim completes');
 delete from va_render; perform pg_temp.va_refresh_dam_search_asset_document(id);
 perform pg_temp.va_assert((select embedding is not null from va_docs where entity_id=id),'render retention preserves vector');
 insert into va_groups(id,sku,folder_path,primary_asset_id,primary_thumbnail_url,updated_at)
 values(gid,'FIXTURE','fixture',id,'https://example.invalid/stable.png',now());
 perform pg_temp.va_refresh_dam_search_style_group_document(gid);
 perform pg_temp.va_assert((select embedding is not null from va_docs where entity_id=gid),'new nightly group reuses exact asset image');
 update va_groups set group_ai_description='group keywords'; perform pg_temp.va_refresh_dam_search_style_group_document(gid);
 perform pg_temp.va_assert((select embedding is not null from va_docs where entity_id=gid),'group text preserves vector');
 update va_docs set metadata=metadata-'_embedding_input' where entity_id=id;
 perform pg_temp.va_refresh_dam_search_asset_document(id);
 perform pg_temp.va_assert((select embedding is not null from va_docs where entity_id=id),'proven legacy image bootstrap avoids re-embedding');
 perform set_config('TimeZone','America/New_York',true);
 old_fp:=pg_temp.va_search_embedding_image_provenance(id,'https://example.invalid/stable.png','{}')->>'sha256';
 perform set_config('TimeZone','UTC',true);
 new_fp:=pg_temp.va_search_embedding_image_provenance(id,'https://example.invalid/stable.png','{}')->>'sha256';
 perform pg_temp.va_assert(old_fp=new_fp,'session timezone cannot change image identity');
 update va_assets set file_size=102;
 perform pg_temp.va_assert((select embedding is null from va_docs where entity_id=id),'size-only trigger invalidates image');
 update va_assets set thumbnail_url='https://example.invalid/new.png'; perform pg_temp.va_refresh_dam_search_asset_document(id);
 perform pg_temp.va_assert((select embedding is null from va_docs where entity_id=id),'changed URL invalidates');
end $$;
rollback;
