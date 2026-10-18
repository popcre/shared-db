-- Issue #2598 delivered-guard proof only: this read-only catalog check proves the exact
-- installed snapshot function partitions NBCU co-tag candidates and retains derived IP Family
-- provenance. It does not prove current capture authority, source-authenticated adapter work,
-- preview cycles, planner/apply behavior, or business acceptance; #2598 remains open for those.
select coalesce((
 select p.prorettype='jsonb'::regtype
  and p.prosecdef
  and p.provolatile='s'
  and p.proconfig @> array['search_path=pg_catalog','TimeZone=UTC']::text[]
  and exists(select 1 from supabase_migrations.schema_migrations where version='20261018164004')
  and md5(p.prosrc)='e5e4afca9f65ee6963e7c52b18f6253f'
  and position('candidate_edges' in p.prosrc)>0
  and position('nbcu_adapter_contract_version' in p.prosrc)>0
  and position('observed_asset_co_tag' in p.prosrc)>0
  and position('candidate_reason' in p.prosrc)>0
  and position('source_term' in p.prosrc)>0
  and pg_catalog.has_function_privilege('service_role',p.oid,'EXECUTE')
  and not pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE')
  and not pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE')
  and not exists(
   select 1
   from pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) acl
   where acl.grantee not in (p.proowner,'service_role'::regrole::oid)
     and acl.privilege_type='EXECUTE'
  )
 from pg_proc p
 where p.oid=pg_catalog.to_regprocedure('plm.licensing_consolidation_capture_snapshot(text,uuid)')
),false) as passed;
