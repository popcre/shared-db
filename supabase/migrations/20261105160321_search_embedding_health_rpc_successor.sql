-- derived-from: none
-- Issue #5622. Fresh RPC-only successor; immutable preview73920 is preserved.
set local lock_timeout='500ms';
set local statement_timeout='2500ms';
set local transaction_timeout='3s';

-- Standalone target-independent successor: old73920 is deliberately NOT a
-- production ledger dependency. Preview's exact existing body is accepted; a
-- production target with all three functions absent is accepted. No mixed or
-- divergent function prestate, missing index, or foreign index definition is accepted.
do $health_prestate$
declare r record; p record; v_oid oid; v_seen integer:=0;
begin
  if to_regprocedure('public.reset_dam_search_embedding_errors(text,uuid[])') is null then
    raise exception 'legacy reset overload must already exist and be preserved' using errcode='55000';
  end if;
  for r in select * from (values
    ('dam_search_health_errored_idx', 'CREATE INDEX dam_search_health_errored_idx ON public.dam_search_documents USING btree (entity_id) WHERE (embedding_error IS NOT NULL)'),
    ('dam_search_health_last_write_idx', 'CREATE INDEX dam_search_health_last_write_idx ON public.dam_search_documents USING btree (embedding_updated_at DESC) WHERE (embedding_updated_at IS NOT NULL)'),
    ('sg_search_health_last_write_idx', 'CREATE INDEX sg_search_health_last_write_idx ON public.style_guide_search_documents USING btree (embedding_updated_at DESC) WHERE (is_active AND (embedding_updated_at IS NOT NULL))')
  ) as expected(name,definition)
  loop
    select i.indisvalid,i.indisready,pg_get_indexdef(c.oid) definition,pg_get_userbyid(c.relowner) owner
      into p from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace
      join pg_catalog.pg_index i on i.indexrelid=c.oid where n.nspname='public' and c.relname=r.name;
    if not found or not p.indisvalid or not p.indisready or p.owner<>'postgres'
       or p.definition is distinct from r.definition then
      raise exception 'exact valid ready health index prerequisite absent: %',r.name using errcode='55000';
    end if;
  end loop;
  for r in select * from (values
    ('public.get_search_embedding_health()','1f404c3d730606d9d9b406f6425a8ddd42b11dd492ffe4d2996cbb62c05aa15b','plpgsql',true,'s','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}'::aclitem[]),
    ('public.reset_dam_search_embedding_errors(text,integer,text)','3b47031187255283cbab0681ac3df45908b9c52d0fee5615ea74561a2f2b8a82','plpgsql',true,'v','{postgres=X/postgres,service_role=X/postgres}'::aclitem[]),
    ('public.reset_dam_search_embedding_errors(text,integer)','a6d59328ad78134fa372e8f49cc27328da6c0896c3038847f9a66e72dbc4407f','sql',false,'v','{postgres=X/postgres,service_role=X/postgres}'::aclitem[])
  ) as expected(signature,body_sha256,language,definer,volatility,acl)
  loop
    v_oid:=to_regprocedure(r.signature);
    if v_oid is not null then
      v_seen:=v_seen+1;
      select encode(extensions.digest(f.prosrc,'sha256'),'hex') body_sha256,l.lanname language,
        f.prosecdef definer,f.provolatile::text volatility,f.proacl acl,f.proconfig,
        pg_get_userbyid(f.proowner) owner into p
      from pg_catalog.pg_proc f join pg_catalog.pg_language l on l.oid=f.prolang where f.oid=v_oid;
      if p.body_sha256 is distinct from r.body_sha256 or p.language is distinct from r.language
         or p.definer is distinct from r.definer or p.volatility is distinct from r.volatility
         or array(select x::text from unnest(p.acl) x order by x::text) is distinct from array(select x::text from unnest(r.acl) x order by x::text) or p.proconfig is distinct from array['search_path=public']
         or p.owner is distinct from 'postgres' then
        raise exception 'health RPC prestate is not the exact historical preview contract: %',r.signature using errcode='55000';
      end if;
    end if;
  end loop;
  if v_seen not in (0,3) then
    raise exception 'mixed health RPC prestate refused' using errcode='55000';
  end if;
end $health_prestate$;

-- Existing reset overload is preserved; only compact indexed health reads.
create or replace function public.get_search_embedding_health()
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

create or replace function public.reset_dam_search_embedding_errors(p_category text,p_limit integer,p_document_type text)
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
create or replace function public.reset_dam_search_embedding_errors(p_category text,p_limit integer)
returns integer language sql security invoker set search_path = public
as $function$
  select public.reset_dam_search_embedding_errors(p_category,p_limit,null::text);
$function$;
revoke all on function public.reset_dam_search_embedding_errors(text,integer) from public,anon,authenticated;
grant execute on function public.reset_dam_search_embedding_errors(text,integer) to service_role;

-- Default privileges must not widen the published health/reset contract.
do $health_acl$
declare r record; actual aclitem[];
begin
  for r in select * from (values
    ('public.get_search_embedding_health()','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}'::aclitem[]),
    ('public.reset_dam_search_embedding_errors(text,integer,text)','{postgres=X/postgres,service_role=X/postgres}'::aclitem[]),
    ('public.reset_dam_search_embedding_errors(text,integer)','{postgres=X/postgres,service_role=X/postgres}'::aclitem[])
  ) as expected(signature,acl)
  loop
    select proacl into actual from pg_catalog.pg_proc where oid=to_regprocedure(r.signature);
    if array(select x::text from unnest(actual) x order by x::text) is distinct from array(select x::text from unnest(r.acl) x order by x::text) then
      raise exception 'health/reset ACL differs from the exact published contract: %',r.signature using errcode='55000';
    end if;
  end loop;
end $health_acl$;

-- Publish new RPC signatures only when this atomic file and ledger commit.
notify pgrst, 'reload schema';
