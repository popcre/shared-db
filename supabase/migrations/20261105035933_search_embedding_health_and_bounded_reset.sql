-- derived-from: none
-- Issue #5622; application u2giants/popdam3#706 and #663.
-- Additive health contract and bounded retry path; existing overload is unchanged.
-- Compact partial indexes avoid the embedding heaps and the whole coverage
-- meters, which both hit the live eight-second request ceiling on 2026-11-04.
create index dam_search_health_pending_idx on public.dam_search_documents(indexed_at)
where embedding is null and embedding_attempts < embedding_max_attempts
  and embedding_error_category is distinct from 'permanent'
  and nullif(metadata->>'thumbnail_url','') is not null;
create index dam_search_health_errored_idx on public.dam_search_documents(entity_id)
where embedding_error is not null;
create index dam_search_health_last_write_idx on public.dam_search_documents(embedding_updated_at desc)
where embedding_updated_at is not null;
create index sg_search_health_last_write_idx on public.style_guide_search_documents(embedding_updated_at desc)
where is_active and embedding_updated_at is not null;

create function public.get_search_embedding_health()
returns table(corpus text, pending bigint, errored bigint, last_write timestamptz,
              minutes_since_last_write numeric, stale boolean)
language plpgsql stable security definer set search_path = public
as $function$
begin
  if coalesce(current_setting('request.jwt.claim.role',true),'') <> 'service_role'
     and coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb->>'role' is distinct from 'service_role'
     and not coalesce(public.has_role(auth.uid(),'admin'),false) then
    raise exception 'admin required' using errcode='42501';
  end if;
  return query
  with counts as (
    select 'dam'::text name,
      (select count(*) from public.dam_search_documents d
       where d.embedding is null and d.embedding_attempts<d.embedding_max_attempts
         and d.embedding_error_category is distinct from 'permanent'
         and nullif(d.metadata->>'thumbnail_url','') is not null) pending_count,
      (select count(*) from public.dam_search_documents d where d.embedding_error is not null) error_count,
      (select max(d.embedding_updated_at) from public.dam_search_documents d where d.embedding_updated_at is not null) written,
      (select min(d.indexed_at) from public.dam_search_documents d
       where d.embedding is null and d.embedding_attempts<d.embedding_max_attempts
         and d.embedding_error_category is distinct from 'permanent'
         and nullif(d.metadata->>'thumbnail_url','') is not null) oldest
    union all
    select 'popsg',
      (select count(*) from public.style_guide_search_documents d
       where d.is_active and d.content_sha256 is not null and d.embedding is null
         and d.embedding_attempts<d.embedding_max_attempts and d.embedding_error_category is distinct from 'permanent'
         and exists(select 1 from public.style_guide_files f where f.id=d.style_guide_file_id and f.thumbnail_url is not null)),
      (select count(*) from public.style_guide_search_documents d where d.embedding_error is not null),
      (select max(d.embedding_updated_at) from public.style_guide_search_documents d where d.is_active and d.embedding_updated_at is not null),
      (select min(d.document_updated_at) from public.style_guide_search_documents d
       where d.is_active and d.content_sha256 is not null and d.embedding is null
         and d.embedding_attempts<d.embedding_max_attempts and d.embedding_error_category is distinct from 'permanent'
         and exists(select 1 from public.style_guide_files f where f.id=d.style_guide_file_id and f.thumbnail_url is not null))
  )
  select name,pending_count,error_count,written,extract(epoch from(now()-written))/60,
    pending_count>0 and (coalesce(written,oldest) is null or coalesce(written,oldest)<=now()-interval '120 minutes')
  from counts;
end;
$function$;
revoke all on function public.get_search_embedding_health() from public,anon;
grant execute on function public.get_search_embedding_health() to authenticated,service_role;

create function public.reset_dam_search_embedding_errors(p_category text,p_limit integer,p_document_type text)
returns integer language plpgsql security definer set search_path = public
as $function$
declare affected integer;
begin
  if coalesce(current_setting('request.jwt.claim.role',true),'') <> 'service_role'
     and coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb->>'role' is distinct from 'service_role' then
    raise exception 'service role required' using errcode='42501';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 5000 then
    raise exception 'limit must be between 1 and 5000' using errcode='22023';
  end if;
  with candidates as (
    select d.document_type,d.entity_id
    from public.dam_search_documents d
    where d.embedding is null and d.embedding_error is not null
      and (p_category is null or d.embedding_error_category=p_category)
      and (p_document_type is null or d.document_type=p_document_type)
      and nullif(btrim(d.metadata->>'thumbnail_url'),'') is not null
      and (d.embedding_lease_expires_at is null or d.embedding_lease_expires_at <= now())
    order by d.indexed_at,d.document_type,d.entity_id
    limit p_limit for update skip locked
  )
  update public.dam_search_documents d
  set embedding_error=null,embedding_error_category=null,embedding_attempts=0,
      embedding_next_retry_at=null,embedding_lease_token=null,
      embedding_lease_owner=null,embedding_lease_expires_at=null
  from candidates c where d.document_type=c.document_type and d.entity_id=c.entity_id;
  get diagnostics affected=row_count;
  return affected;
end;
$function$;
revoke all on function public.reset_dam_search_embedding_errors(text,integer,text) from public,anon,authenticated;
grant execute on function public.reset_dam_search_embedding_errors(text,integer,text) to service_role;

-- Keep the plan's two-argument contract, while the explicit three-argument
-- form preserves the existing admin action's optional document-type filter.
create function public.reset_dam_search_embedding_errors(p_category text,p_limit integer)
returns integer language sql security invoker set search_path = public
as $function$
  select public.reset_dam_search_embedding_errors(p_category,p_limit,null::text);
$function$;
revoke all on function public.reset_dam_search_embedding_errors(text,integer) from public,anon,authenticated;
grant execute on function public.reset_dam_search_embedding_errors(text,integer) to service_role;
