-- Issue2336: selected current/history catalog and exact private physical-engine surface.
-- Read-only catalog proof; native capture and physical mutation/race behavior have separate isolated tests.
select exists (

with pairs(pair_table,edge_table,left_col,right_col,auth_read,service_read,check_name,check_def) as (values
('core.property_character_associations','core.property_character_source_edge','property_id','character_id',true,true,'property_character_associations_lifecycle_chk','CHECK (((is_current AND (retired_at IS NULL) AND (retired_reason IS NULL)) OR ((NOT is_current) AND (retired_at IS NOT NULL) AND (NULLIF(btrim(retired_reason), ''''::text) IS NOT NULL))))'),
('core.property_style_guide','core.property_style_guide_source_edge','property_id','style_guide_id',true,true,'property_style_guide_lifecycle_chk','CHECK (((is_current AND (retired_at IS NULL) AND (retired_reason IS NULL)) OR ((NOT is_current) AND (retired_at IS NOT NULL) AND (NULLIF(btrim(retired_reason), ''''::text) IS NOT NULL))))'),
('core.property_franchise','core.property_franchise_source_edge','property_id','franchise_id',true,true,'property_franchise_lifecycle_chk','CHECK (((is_current AND (retired_at IS NULL) AND (retired_reason IS NULL)) OR ((NOT is_current) AND (retired_at IS NOT NULL) AND (NULLIF(btrim(retired_reason), ''''::text) IS NOT NULL))))'),
('core.style_guide_character','core.style_guide_character_source_edge','style_guide_id','character_id',true,true,'style_guide_character_lifecycle_chk','CHECK (((is_current AND (retired_at IS NULL) AND (retired_reason IS NULL)) OR ((NOT is_current) AND (retired_at IS NOT NULL) AND (NULLIF(btrim(retired_reason), ''''::text) IS NOT NULL))))'),
('dam.asset_property','dam.asset_property_source_edge','asset_id','property_id',false,true,'asset_property_lifecycle_chk','CHECK (((is_current AND (retired_at IS NULL) AND (retired_reason IS NULL)) OR ((NOT is_current) AND (retired_at IS NOT NULL) AND (NULLIF(btrim(retired_reason), ''''::text) IS NOT NULL))))'),
('dam.asset_character','dam.asset_character_source_edge','asset_id','character_id',true,false,'asset_character_lifecycle_chk','CHECK (((is_current AND (retired_at IS NULL) AND (retired_reason IS NULL)) OR ((NOT is_current) AND (retired_at IS NOT NULL) AND (NULLIF(btrim(retired_reason), ''''::text) IS NOT NULL))))'),
('dam.asset_style_guide','dam.asset_style_guide_source_edge','asset_id','style_guide_id',false,true,'asset_style_guide_lifecycle_chk','CHECK (((is_current AND (retired_at IS NULL) AND (retired_reason IS NULL)) OR ((NOT is_current) AND (retired_at IS NOT NULL) AND (NULLIF(btrim(retired_reason), ''''::text) IS NOT NULL))))'),
('dam.asset_franchise','dam.asset_franchise_source_edge','asset_id','franchise_id',false,true,'asset_franchise_lifecycle_chk','CHECK (((is_current AND (retired_at IS NULL) AND (retired_reason IS NULL)) OR ((NOT is_current) AND (retired_at IS NOT NULL) AND (NULLIF(btrim(retired_reason), ''''::text) IS NOT NULL))))')), routines(signature,volatility,definer,service_execute) as (values
('plm.licensing_consolidation_capture_snapshot(text,uuid)','s',true,true),
('plm.licensing_consolidation_operation_state(jsonb)','s',true,false),
('plm.apply_licensing_support_operation(uuid,text,jsonb)','v',true,false),
('plm.plan_licensing_consolidation(text,uuid,text)','v',true,true),
('plm.apply_licensing_consolidation(uuid,text)','v',true,true),
('plm.plan_licensing_consolidation_rollback(uuid,text)','v',true,true),
('plm.licensing_consolidation_plan_immutable()','v',true,false),
('core.lock_canonical_relationship_pair()','v',false,false))
select 1 where
to_regclass('core.property_character_associations') is not null and to_regclass('core.property_character_source_edge') is not null and to_regclass('core.property_character_associations_current') is not null and
to_regclass('core.property_style_guide') is not null and to_regclass('core.property_style_guide_source_edge') is not null and to_regclass('core.property_style_guide_current') is not null and
to_regclass('core.property_franchise') is not null and to_regclass('core.property_franchise_source_edge') is not null and to_regclass('core.property_franchise_current') is not null and
to_regclass('core.style_guide_character') is not null and to_regclass('core.style_guide_character_source_edge') is not null and to_regclass('core.style_guide_character_current') is not null and
to_regclass('dam.asset_property') is not null and to_regclass('dam.asset_property_source_edge') is not null and to_regclass('dam.asset_property_current') is not null and
to_regclass('dam.asset_character') is not null and to_regclass('dam.asset_character_source_edge') is not null and to_regclass('dam.asset_character_current') is not null and
to_regclass('dam.asset_style_guide') is not null and to_regclass('dam.asset_style_guide_source_edge') is not null and to_regclass('dam.asset_style_guide_current') is not null and
to_regclass('dam.asset_franchise') is not null and to_regclass('dam.asset_franchise_source_edge') is not null and to_regclass('dam.asset_franchise_current') is not null and
to_regprocedure('plm.licensing_consolidation_capture_snapshot(text,uuid)') is not null and
to_regprocedure('plm.licensing_consolidation_operation_state(jsonb)') is not null and
to_regprocedure('plm.apply_licensing_support_operation(uuid,text,jsonb)') is not null and
to_regprocedure('plm.plan_licensing_consolidation(text,uuid,text)') is not null and
to_regprocedure('plm.apply_licensing_consolidation(uuid,text)') is not null and
to_regprocedure('plm.plan_licensing_consolidation_rollback(uuid,text)') is not null and
to_regprocedure('plm.licensing_consolidation_plan_immutable()') is not null and
to_regprocedure('core.lock_canonical_relationship_pair()') is not null
and to_regclass('plm.licensing_consolidation_plan') is not null
and to_regprocedure('core.require_direct_support_for_canonical_edge()') is not null
and to_regprocedure('core.assert_canonical_edge_still_supported()') is not null
and to_regprocedure('api.db_data_admin_licensor_property_tree(text,boolean,text,integer)') is not null
and not exists(select 1 from pairs x where
 not exists(select 1 from pg_attribute a where a.attrelid=to_regclass(x.pair_table) and a.attname='is_current' and a.atttypid='boolean'::regtype and a.attnotnull and not a.attisdropped and (select pg_get_expr(d.adbin,d.adrelid) from pg_attrdef d where d.adrelid=a.attrelid and d.adnum=a.attnum)='true')
 or not exists(select 1 from pg_attribute a where a.attrelid=to_regclass(x.pair_table) and a.attname='retired_at' and a.atttypid='timestamptz'::regtype and not a.attnotnull and not a.attisdropped)
 or not exists(select 1 from pg_attribute a where a.attrelid=to_regclass(x.pair_table) and a.attname='retired_reason' and a.atttypid='text'::regtype and not a.attnotnull and not a.attisdropped)
 or not exists(select 1 from pg_constraint k where k.conrelid=to_regclass(x.pair_table) and k.conname=x.check_name and k.contype='c' and k.convalidated and pg_get_constraintdef(k.oid)=x.check_def)
 or not exists(select 1 from pg_class c where c.oid=to_regclass(x.pair_table||'_current') and c.relkind='v' and c.reloptions @> array['security_invoker=true'] and pg_get_viewdef(c.oid) ~ 'WHERE ([a-z_]+[.])?is_current')
 or has_table_privilege('authenticated',to_regclass(x.pair_table||'_current'),'SELECT') is distinct from x.auth_read
 or has_table_privilege('service_role',to_regclass(x.pair_table||'_current'),'SELECT') is distinct from x.service_read
 or has_table_privilege('authenticated',to_regclass(x.pair_table),'SELECT') is distinct from x.auth_read
 or has_table_privilege('service_role',to_regclass(x.pair_table),'SELECT') is distinct from x.service_read
 or has_table_privilege('anon',to_regclass(x.pair_table||'_current'),'SELECT')
 or exists(select 1 from pg_class c cross join lateral aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) acl where c.oid=to_regclass(x.pair_table||'_current') and acl.grantee=0)
 or exists(select 1 from (values('anon'),('authenticated'),('service_role')) roles(name) where has_table_privilege(roles.name,to_regclass(x.pair_table||'_current'),'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'))
)
and not exists(select 1 from pairs x cross join lateral(values(x.pair_table),(x.edge_table)) targets(name) where not exists(
 select 1 from pg_trigger t where t.tgrelid=to_regclass(targets.name) and t.tgname='lock_relationship_pair' and t.tgfoid=to_regprocedure('core.lock_canonical_relationship_pair()') and t.tgtype=31 and t.tgenabled='O' and t.tgnargs=3 and t.tgargs=decode(encode(convert_to(x.pair_table,'UTF8'),'hex')||'00'||encode(convert_to(x.left_col,'UTF8'),'hex')||'00'||encode(convert_to(x.right_col,'UTF8'),'hex')||'00','hex')))
and not exists(select 1 from pairs x where not exists(select 1 from pg_trigger t where t.tgrelid=to_regclass(x.pair_table) and t.tgname='require_direct_support' and t.tgfoid=to_regprocedure('core.require_direct_support_for_canonical_edge()') and t.tgtype=23 and t.tgenabled='O') or not exists(select 1 from pg_trigger t where t.tgrelid=to_regclass(x.edge_table) and t.tgname='assert_canonical_edge_still_supported' and t.tgfoid=to_regprocedure('core.assert_canonical_edge_still_supported()') and t.tgtype=25 and t.tgdeferrable and t.tginitdeferred and t.tgenabled='O'))
and (select prosrc like '%if not new.is_current then return new; end if;%' and prosecdef and proconfig @> array['search_path=pg_catalog, pg_temp'] from pg_proc where oid=to_regprocedure('core.require_direct_support_for_canonical_edge()'))
and (select prosrc like '%and b.is_current%' and prosecdef and proconfig @> array['search_path=pg_catalog, pg_temp'] from pg_proc where oid=to_regprocedure('core.assert_canonical_edge_still_supported()'))
and not exists(select 1 from routines r where not exists(select 1 from pg_proc p where p.oid=to_regprocedure(r.signature) and p.provolatile::text=r.volatility and p.prosecdef=r.definer and p.proconfig @> array[case r.signature when 'core.lock_canonical_relationship_pair()' then 'search_path=pg_catalog, pg_temp' else 'search_path=pg_catalog' end]) or has_function_privilege('service_role',to_regprocedure(r.signature),'EXECUTE') is distinct from r.service_execute or has_function_privilege('authenticated',to_regprocedure(r.signature),'EXECUTE') or has_function_privilege('anon',to_regprocedure(r.signature),'EXECUTE') or exists(select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl where p.oid=to_regprocedure(r.signature) and acl.grantee=0))
and exists(select 1 from pg_attribute a where a.attrelid=to_regclass('plm.licensing_consolidation_plan') and a.attname='plan_schema_version' and a.atttypid='integer'::regtype and a.attnotnull and (select pg_get_expr(d.adbin,d.adrelid) from pg_attrdef d where d.adrelid=a.attrelid and d.adnum=a.attnum)='2')
and exists(select 1 from pg_attribute a where a.attrelid=to_regclass('plm.licensing_consolidation_plan') and a.attname='capture_snapshot' and a.atttypid='jsonb'::regtype and a.attnotnull and (select pg_get_expr(d.adbin,d.adrelid) from pg_attrdef d where d.adrelid=a.attrelid and d.adnum=a.attnum)='''{}''::jsonb')
and exists(select 1 from pg_attribute a where a.attrelid=to_regclass('plm.licensing_consolidation_plan') and a.attname='applied_state' and a.atttypid='jsonb'::regtype and not a.attnotnull and not a.attisdropped)
and exists(select 1 from pg_constraint where conrelid=to_regclass('plm.licensing_consolidation_plan') and conname='licensing_consolidation_plan_schema_version_chk' and convalidated and pg_get_constraintdef(oid)='CHECK ((plan_schema_version = 2))')
and exists(select 1 from pg_constraint where conrelid=to_regclass('plm.licensing_consolidation_plan') and conname='licensing_consolidation_plan_capture_snapshot_chk' and convalidated and pg_get_constraintdef(oid)='CHECK ((jsonb_typeof(capture_snapshot) = ''object''::text))')
and exists(select 1 from pg_constraint where conrelid=to_regclass('plm.licensing_consolidation_plan') and conname='licensing_consolidation_plan_applied_state_chk' and convalidated and pg_get_constraintdef(oid)='CHECK (((applied_state IS NULL) OR (jsonb_typeof(applied_state) = ''object''::text)))')
and exists(select 1 from pg_class c where c.oid=to_regclass('plm.licensing_consolidation_plan') and c.relrowsecurity)
and not has_table_privilege('anon','plm.licensing_consolidation_plan','SELECT,INSERT,UPDATE,DELETE')
and has_table_privilege('authenticated','plm.licensing_consolidation_plan','SELECT') and has_table_privilege('service_role','plm.licensing_consolidation_plan','SELECT')
and not has_table_privilege('authenticated','plm.licensing_consolidation_plan','INSERT,UPDATE,DELETE') and not has_table_privilege('service_role','plm.licensing_consolidation_plan','INSERT,UPDATE,DELETE')
and exists(select 1 from pg_trigger t where t.tgrelid=to_regclass('plm.licensing_consolidation_plan') and t.tgname='licensing_consolidation_plan_immutable_trg' and t.tgfoid=to_regprocedure('plm.licensing_consolidation_plan_immutable()') and t.tgenabled='O')
and (select prosrc like '%immutable consolidation%' or prosrc like '%consolidation immutable content changed%' from pg_proc where oid=to_regprocedure('plm.licensing_consolidation_plan_immutable()'))
and (select prosrc like '%plan_schema_version%' and prosrc like '%capture_snapshot%' from pg_proc where oid=to_regprocedure('plm.apply_licensing_consolidation(uuid,text)'))
and (select (length(prosrc)-length(replace(prosrc,'from core.property_character_associations a where a.is_current group by a.property_id','')))/length('from core.property_character_associations a where a.is_current group by a.property_id')=2 and position('from core.property_character_associations a group by a.property_id' in prosrc)=0 from pg_proc where oid=to_regprocedure('api.db_data_admin_licensor_property_tree(text,boolean,text,integer)'))

) as passed;
