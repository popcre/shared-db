-- derived-from: none
-- Issue #5622; application u2giants/popdam3#706 and #663.
-- Additive health contract and bounded retry path; existing overload is unchanged.
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
  with meters as (
    select 'dam'::text name, public.get_dam_search_embedding_status() meter,
           (select max(d.embedding_updated_at) from public.dam_search_documents d) written
    union all
    select 'popsg', public.get_sg_search_embedding_status(),
           (select max(d.embedding_updated_at) from public.style_guide_search_documents d where d.is_active)
  ), health as (
    select name, (meter->>'pending_documents')::bigint pending_count,
           (meter->>'errored_documents')::bigint error_count, written,
           coalesce(written, (meter->>'oldest_pending_indexed_at')::timestamptz,
                    (meter->>'oldest_pending_updated_at')::timestamptz) activity
    from meters
  )
  select name, pending_count, error_count, written,
         extract(epoch from (now()-written))/60,
         pending_count > 0 and (activity is null or activity <= now()-interval '120 minutes')
  from health;
end;
$function$;
revoke all on function public.get_search_embedding_health() from public,anon;
grant execute on function public.get_search_embedding_health() to authenticated,service_role;

create function public.reset_dam_search_embedding_errors(p_category text,p_limit integer)
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
revoke all on function public.reset_dam_search_embedding_errors(text,integer) from public,anon,authenticated;
grant execute on function public.reset_dam_search_embedding_errors(text,integer) to service_role;
