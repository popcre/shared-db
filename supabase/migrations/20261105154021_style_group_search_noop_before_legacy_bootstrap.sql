-- derived-from: 20261105074126
-- Issue #5665, parent #5634; actual designer-save failure u2giants/popdam3#680.
set local lock_timeout='500ms';
set local statement_timeout='2500ms';
set local transaction_timeout='3s';

CREATE OR REPLACE FUNCTION public.refresh_dam_search_style_group_document(p_style_group_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'dam', 'extensions'
AS $function$
declare v_text text; v_hash text; v_input jsonb;
begin
  if not exists(select 1 from public.style_groups where id=p_style_group_id) then
    delete from public.dam_search_documents where document_type='style_group' and entity_id=p_style_group_id; return;
  end if;
  select coalesce(concat_ws(' ',sg.sku,sg.folder_path,sg.cover_description,sg.item_description,sg.group_ai_description,
    dam.jsonb_leaf_text(sg.rich_metadata),sg.customer,sg.program,sg.licensor_name,sg.property_name,sg.product_category,
    sg.division_name,sg.mg01_name,sg.mg02_name,sg.mg03_name,sg.size_name,gtg.tags,chars.names),'') into v_text
  from public.style_groups sg
  left join lateral(select string_agg(t.tag,' ' order by lower(t.tag),t.tag) tags from public.style_group_tags t
    where t.style_group_id=sg.id and t.status='active') gtg on true
  left join lateral(select string_agg(c.name,' ' order by lower(c.name),c.id) names from (select c.id,c.name from public.assets a
    join public.asset_characters ac on ac.asset_id=a.id join public.characters c on c.id=ac.character_id
    where a.style_group_id=sg.id and not a.is_deleted
    union all select lc.id,lc.name from public.assets a
    join public.asset_licensor_characters alc on alc.asset_id=a.id join core.character lc on lc.id=alc.character_id
    where a.style_group_id=sg.id and not a.is_deleted) c) chars on true where sg.id=p_style_group_id;
  v_hash:=encode(digest(v_text,'sha256'),'hex');
  select dam.search_embedding_image_provenance(sg.primary_asset_id,sg.primary_thumbnail_url,d.metadata->'_embedding_input') into v_input
  from public.style_groups sg left join public.dam_search_documents d on d.document_type='style_group' and d.entity_id=sg.id where sg.id=p_style_group_id;
  -- A non-search edit must not bootstrap legacy provenance by rewriting an
  -- otherwise identical vector-bearing document. Image identity still uses the
  -- same authoritative source/render/size guard; real keyword changes continue.
  if exists (
    select 1 from public.style_groups sg
    join public.dam_search_documents d on d.document_type='style_group' and d.entity_id=sg.id
    cross join lateral (select jsonb_strip_nulls(jsonb_build_object(
      'asset_count',sg.asset_count,'workflow_status',sg.workflow_status,
      'is_licensed',sg.is_licensed,'licensor_name',sg.licensor_name,'property_name',sg.property_name,
      'product_category',sg.product_category,'item_description_source',sg.item_description_source,
      'group_ai_description_source',sg.group_ai_description_source,'group_ai_description_model',sg.group_ai_description_model,
      'rich_metadata_source',sg.rich_metadata_source,'thumbnail_url',sg.primary_thumbnail_url,'_embedding_input',v_input)) metadata) proposed
    where sg.id=p_style_group_id
      and row(d.style_group_id,d.title,d.path,d.customer,d.program,d.search_text,d.content_sha256,
              d.metadata-'_embedding_lease_input_sha256'-'_embedding_input')
        is not distinct from row(sg.id,coalesce(sg.sku,''),coalesce(sg.folder_path,''),sg.customer,sg.program,v_text,v_hash,
                                 proposed.metadata-'_embedding_input')
      and dam.search_embedding_inputs_match(d.metadata,proposed.metadata,d.content_sha256,v_hash,
                                           d.embedding_model,d.embedding_updated_at,d.indexed_at)
  ) then return; end if;
  insert into public.dam_search_documents(document_type,entity_id,style_group_id,title,path,customer,program,search_text,
    content_sha256,metadata,source_updated_at,indexed_at,embedding,embedding_model,embedding_updated_at)
  select 'style_group',sg.id,sg.id,coalesce(sg.sku,''),coalesce(sg.folder_path,''),sg.customer,sg.program,v_text,v_hash,
    jsonb_strip_nulls(jsonb_build_object('asset_count',sg.asset_count,'workflow_status',sg.workflow_status,
      'is_licensed',sg.is_licensed,'licensor_name',sg.licensor_name,'property_name',sg.property_name,
      'product_category',sg.product_category,'item_description_source',sg.item_description_source,
      'group_ai_description_source',sg.group_ai_description_source,'group_ai_description_model',sg.group_ai_description_model,
      'rich_metadata_source',sg.rich_metadata_source,'thumbnail_url',sg.primary_thumbnail_url,'_embedding_input',v_input)),
    greatest(coalesce(sg.updated_at,'-infinity'),coalesce(sg.latest_file_date,'-infinity')),now(),
    case when reuse.ok then ad.embedding end,case when reuse.ok then ad.embedding_model end,case when reuse.ok then ad.embedding_updated_at end
  from public.style_groups sg
  left join public.dam_search_documents ad on ad.document_type='asset' and ad.entity_id=sg.primary_asset_id
  left join lateral(select ad.embedding is not null and ad.embedding_model='google/siglip2-base-patch16-naflex' and v_input is not null
    and dam.search_embedding_inputs_match(ad.metadata,jsonb_build_object('thumbnail_url',sg.primary_thumbnail_url,'_embedding_input',v_input),
      ad.content_sha256,v_hash,ad.embedding_model,ad.embedding_updated_at,ad.indexed_at) ok) reuse on true
  where sg.id=p_style_group_id
  on conflict(document_type,entity_id) do update set style_group_id=excluded.style_group_id,title=excluded.title,path=excluded.path,
    customer=excluded.customer,program=excluded.program,search_text=excluded.search_text,content_sha256=excluded.content_sha256,
    metadata=case when dam.search_embedding_inputs_match(dam_search_documents.metadata,excluded.metadata,dam_search_documents.content_sha256,excluded.content_sha256,dam_search_documents.embedding_model,dam_search_documents.embedding_updated_at,dam_search_documents.indexed_at) and dam_search_documents.embedding_lease_token is not null then excluded.metadata||jsonb_build_object('_embedding_lease_input_sha256',coalesce(dam_search_documents.metadata->>'_embedding_lease_input_sha256',dam_search_documents.content_sha256)) else excluded.metadata end,source_updated_at=excluded.source_updated_at,indexed_at=case when dam.search_embedding_inputs_match(dam_search_documents.metadata,excluded.metadata,dam_search_documents.content_sha256,excluded.content_sha256,dam_search_documents.embedding_model,dam_search_documents.embedding_updated_at,dam_search_documents.indexed_at) then dam_search_documents.indexed_at else now() end,
    embedding=case when dam.search_embedding_inputs_match(dam_search_documents.metadata,excluded.metadata,dam_search_documents.content_sha256,excluded.content_sha256,dam_search_documents.embedding_model,dam_search_documents.embedding_updated_at,dam_search_documents.indexed_at) then dam_search_documents.embedding else excluded.embedding end,
    embedding_model=case when dam.search_embedding_inputs_match(dam_search_documents.metadata,excluded.metadata,dam_search_documents.content_sha256,excluded.content_sha256,dam_search_documents.embedding_model,dam_search_documents.embedding_updated_at,dam_search_documents.indexed_at) then dam_search_documents.embedding_model else excluded.embedding_model end,
    embedding_updated_at=case when dam.search_embedding_inputs_match(dam_search_documents.metadata,excluded.metadata,dam_search_documents.content_sha256,excluded.content_sha256,dam_search_documents.embedding_model,dam_search_documents.embedding_updated_at,dam_search_documents.indexed_at) then dam_search_documents.embedding_updated_at else excluded.embedding_updated_at end,
    embedding_error=case when dam.search_embedding_inputs_match(dam_search_documents.metadata,excluded.metadata,dam_search_documents.content_sha256,excluded.content_sha256,dam_search_documents.embedding_model,dam_search_documents.embedding_updated_at,dam_search_documents.indexed_at) then dam_search_documents.embedding_error end,
    embedding_error_category=case when dam.search_embedding_inputs_match(dam_search_documents.metadata,excluded.metadata,dam_search_documents.content_sha256,excluded.content_sha256,dam_search_documents.embedding_model,dam_search_documents.embedding_updated_at,dam_search_documents.indexed_at) then dam_search_documents.embedding_error_category end,
    embedding_attempts=case when dam.search_embedding_inputs_match(dam_search_documents.metadata,excluded.metadata,dam_search_documents.content_sha256,excluded.content_sha256,dam_search_documents.embedding_model,dam_search_documents.embedding_updated_at,dam_search_documents.indexed_at) then dam_search_documents.embedding_attempts else 0 end,
    embedding_lease_token=case when dam.search_embedding_inputs_match(dam_search_documents.metadata,excluded.metadata,dam_search_documents.content_sha256,excluded.content_sha256,dam_search_documents.embedding_model,dam_search_documents.embedding_updated_at,dam_search_documents.indexed_at) then dam_search_documents.embedding_lease_token end,embedding_lease_owner=case when dam.search_embedding_inputs_match(dam_search_documents.metadata,excluded.metadata,dam_search_documents.content_sha256,excluded.content_sha256,dam_search_documents.embedding_model,dam_search_documents.embedding_updated_at,dam_search_documents.indexed_at) then dam_search_documents.embedding_lease_owner end,embedding_lease_expires_at=case when dam.search_embedding_inputs_match(dam_search_documents.metadata,excluded.metadata,dam_search_documents.content_sha256,excluded.content_sha256,dam_search_documents.embedding_model,dam_search_documents.embedding_updated_at,dam_search_documents.indexed_at) then dam_search_documents.embedding_lease_expires_at end,embedding_next_retry_at=case when dam.search_embedding_inputs_match(dam_search_documents.metadata,excluded.metadata,dam_search_documents.content_sha256,excluded.content_sha256,dam_search_documents.embedding_model,dam_search_documents.embedding_updated_at,dam_search_documents.indexed_at) then dam_search_documents.embedding_next_retry_at end
  where row(dam_search_documents.style_group_id,dam_search_documents.title,dam_search_documents.path,dam_search_documents.customer,dam_search_documents.program,dam_search_documents.search_text,dam_search_documents.content_sha256,dam_search_documents.metadata-'_embedding_lease_input_sha256')
    is distinct from row(excluded.style_group_id,excluded.title,excluded.path,excluded.customer,excluded.program,excluded.search_text,excluded.content_sha256,excluded.metadata)
    or dam.search_embedding_inputs_match(dam_search_documents.metadata,excluded.metadata,dam_search_documents.content_sha256,excluded.content_sha256,dam_search_documents.embedding_model,dam_search_documents.embedding_updated_at,dam_search_documents.indexed_at) is not true;
end $function$
;
