-- Issue2336 exact current/history/private physical engine and serving key indexes.
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
('plm.licensing_operation_identity_predicate(jsonb)','i',false,false),
('plm.apply_licensing_support_operation(uuid,text,jsonb)','v',true,false),
('plm.plan_licensing_consolidation(text,uuid,text)','v',true,true),
('plm.apply_licensing_consolidation(uuid,text)','v',true,true),
('plm.plan_licensing_consolidation_rollback(uuid,text)','v',true,true),
('plm.licensing_consolidation_plan_immutable()','v',true,false),
('core.lock_canonical_relationship_pair()','v',false,false)), identity_targets(target,keys) as(values
('core.taxonomy_source_ref',array['source_id','source_system','source_table']::text[]),
('core.property',array['id']::text[]),
('core.property_character_associations',array['character_id','property_id']::text[]),
('core.property_style_guide',array['property_id','style_guide_id']::text[]),
('core.property_franchise',array['franchise_id','property_id']::text[]),
('core.style_guide_character',array['character_id','style_guide_id']::text[]),
('dam.asset_property',array['asset_id','property_id']::text[]),
('dam.asset_character',array['asset_id','character_id']::text[]),
('dam.asset_style_guide',array['asset_id','style_guide_id']::text[]),
('dam.asset_franchise',array['asset_id','franchise_id']::text[]),
('core.property_character_source_edge',array['id']::text[]),
('core.property_style_guide_source_edge',array['id']::text[]),
('core.property_franchise_source_edge',array['id']::text[]),
('core.style_guide_character_source_edge',array['id']::text[]),
('dam.asset_property_source_edge',array['id']::text[]),
('dam.asset_character_source_edge',array['id']::text[]),
('dam.asset_style_guide_source_edge',array['id']::text[]),
('dam.asset_franchise_source_edge',array['id']::text[]))
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
to_regprocedure('plm.licensing_operation_identity_predicate(jsonb)') is not null and
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
 or not exists(select 1 from pg_class c where c.oid=to_regclass(x.pair_table||'_current') and c.relkind='v' and c.reloptions @> array['security_invoker=true'] and pg_get_viewdef(c.oid)=format(E' SELECT %s\n   FROM %s\n  WHERE is_current' || chr(59),
   (select string_agg(quote_ident(a.attname),E',\n    ' order by a.attnum) from pg_attribute a where a.attrelid=to_regclass(x.pair_table) and a.attnum>0 and not a.attisdropped),x.pair_table)
   and not exists((select a.attname,a.atttypid,a.atttypmod,a.attcollation from pg_attribute a where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped except select a.attname,a.atttypid,a.atttypmod,a.attcollation from pg_attribute a where a.attrelid=to_regclass(x.pair_table) and a.attnum>0 and not a.attisdropped)
    union all (select a.attname,a.atttypid,a.atttypmod,a.attcollation from pg_attribute a where a.attrelid=to_regclass(x.pair_table) and a.attnum>0 and not a.attisdropped except select a.attname,a.atttypid,a.atttypmod,a.attcollation from pg_attribute a where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped)))
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
and not exists(select 1 from pairs x where not exists(select 1 from pg_trigger t where t.tgrelid=to_regclass(x.pair_table) and t.tgname='require_direct_support' and t.tgnargs=3 and not t.tgisinternal and t.tgargs=decode(encode(convert_to(x.edge_table,'UTF8'),'hex')||'00'||encode(convert_to(x.left_col,'UTF8'),'hex')||'00'||encode(convert_to(x.right_col,'UTF8'),'hex')||'00','hex') and  t.tgfoid=to_regprocedure('core.require_direct_support_for_canonical_edge()') and t.tgtype=23 and t.tgenabled='O') or not exists(select 1 from pg_trigger t where t.tgrelid=to_regclass(x.edge_table) and t.tgname='assert_canonical_edge_still_supported' and t.tgnargs=3 and not t.tgisinternal and t.tgargs=decode(encode(convert_to(x.pair_table,'UTF8'),'hex')||'00'||encode(convert_to(x.left_col,'UTF8'),'hex')||'00'||encode(convert_to(x.right_col,'UTF8'),'hex')||'00','hex') and  t.tgfoid=to_regprocedure('core.assert_canonical_edge_still_supported()') and t.tgtype=25 and t.tgdeferrable and t.tginitdeferred and t.tgenabled='O'))
and (select prosrc like ('%if not new.is_current then return new'||chr(59)||' end if'||chr(59)||'%') and prosecdef and proconfig @> array['search_path=pg_catalog, pg_temp'] from pg_proc where oid=to_regprocedure('core.require_direct_support_for_canonical_edge()'))
and (select prosrc like '%and b.is_current%' and prosecdef and proconfig @> array['search_path=pg_catalog, pg_temp'] from pg_proc where oid=to_regprocedure('core.assert_canonical_edge_still_supported()'))
and not exists(select 1 from routines r where not exists(select 1 from pg_proc p where p.oid=to_regprocedure(r.signature) and p.provolatile::text=r.volatility and p.prosecdef=r.definer and p.proconfig @> array[case r.signature when 'core.lock_canonical_relationship_pair()' then 'search_path=pg_catalog, pg_temp' else 'search_path=pg_catalog' end] and (r.signature in ('core.lock_canonical_relationship_pair()','plm.licensing_operation_identity_predicate(jsonb)') or p.proconfig @> array['TimeZone=UTC'])) or has_function_privilege('service_role',to_regprocedure(r.signature),'EXECUTE') is distinct from r.service_execute or has_function_privilege('authenticated',to_regprocedure(r.signature),'EXECUTE') or has_function_privilege('anon',to_regprocedure(r.signature),'EXECUTE') or exists(select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl where p.oid=to_regprocedure(r.signature) and acl.grantee=0))
and exists(select 1 from pg_attribute a where a.attrelid=to_regclass('plm.licensing_consolidation_plan') and a.attname='plan_schema_version' and a.atttypid='integer'::regtype and a.attnotnull and (select pg_get_expr(d.adbin,d.adrelid) from pg_attrdef d where d.adrelid=a.attrelid and d.adnum=a.attnum)='2')
and exists(select 1 from pg_attribute a where a.attrelid=to_regclass('plm.licensing_consolidation_plan') and a.attname='capture_snapshot' and a.atttypid='jsonb'::regtype and a.attnotnull and (select pg_get_expr(d.adbin,d.adrelid) from pg_attrdef d where d.adrelid=a.attrelid and d.adnum=a.attnum)='''{}''::jsonb')
and exists(select 1 from pg_attribute a where a.attrelid=to_regclass('plm.licensing_consolidation_plan') and a.attname='applied_state' and a.atttypid='jsonb'::regtype and not a.attnotnull and not a.attisdropped)
and exists(select 1 from pg_constraint where conrelid=to_regclass('plm.licensing_consolidation_plan') and conname='licensing_consolidation_plan_schema_version_chk' and convalidated and pg_get_constraintdef(oid)='CHECK ((plan_schema_version = ANY (ARRAY[1, 2])))')
and exists(select 1 from pg_constraint where conrelid=to_regclass('plm.licensing_consolidation_plan') and conname='licensing_consolidation_plan_capture_snapshot_chk' and convalidated and pg_get_constraintdef(oid)='CHECK ((jsonb_typeof(capture_snapshot) = ''object''::text))')
and exists(select 1 from pg_constraint where conrelid=to_regclass('plm.licensing_consolidation_plan') and conname='licensing_consolidation_plan_applied_state_chk' and convalidated and pg_get_constraintdef(oid)='CHECK (((applied_state IS NULL) OR (jsonb_typeof(applied_state) = ''object''::text)))')
and exists(select 1 from pg_class c where c.oid=to_regclass('plm.licensing_consolidation_plan') and c.relrowsecurity)
and not has_table_privilege('anon','plm.licensing_consolidation_plan','SELECT,INSERT,UPDATE,DELETE')
and has_table_privilege('authenticated','plm.licensing_consolidation_plan','SELECT') and has_table_privilege('service_role','plm.licensing_consolidation_plan','SELECT')
and not has_table_privilege('authenticated','plm.licensing_consolidation_plan','INSERT,UPDATE,DELETE') and not has_table_privilege('service_role','plm.licensing_consolidation_plan','INSERT,UPDATE,DELETE')
and exists(select 1 from pg_trigger t where t.tgrelid=to_regclass('plm.licensing_consolidation_plan') and t.tgname='licensing_consolidation_plan_immutable_trg' and t.tgtype=27 and t.tgnargs=0 and not t.tgisinternal and t.tgfoid=to_regprocedure('plm.licensing_consolidation_plan_immutable()') and t.tgenabled='O')
and (select prosrc like '%immutable consolidation%' or prosrc like '%consolidation immutable content changed%' from pg_proc where oid=to_regprocedure('plm.licensing_consolidation_plan_immutable()'))
and (select prosrc like '%plan_schema_version%' and prosrc like '%capture_snapshot%' from pg_proc where oid=to_regprocedure('plm.apply_licensing_consolidation(uuid,text)'))
and (select (length(prosrc)-length(replace(prosrc,'from core.property_character_associations a where a.is_current group by a.property_id','')))/length('from core.property_character_associations a where a.is_current group by a.property_id')=2 and position('from core.property_character_associations a group by a.property_id' in prosrc)=0 from pg_proc where oid=to_regprocedure('api.db_data_admin_licensor_property_tree(text,boolean,text,integer)'))
and (select pg_get_function_result(to_regprocedure('plm.licensing_operation_identity_predicate(jsonb)')))='text'
and not exists(select 1 from (values
('core.assert_canonical_edge_still_supported()','37cc92749ad0d21aa51cdf03171dfba2'),
('core.lock_canonical_relationship_pair()','b60bf1a1136df21fa5b1e17d6f08a7bd'),
('core.require_direct_support_for_canonical_edge()','63dcc74814a239088c1a81d52ceff16f'),
('plm.apply_licensing_consolidation(uuid,text)','0ff913b195c6f0d4190ae30a6e6a80b0'),
('plm.apply_licensing_support_operation(uuid,text,jsonb)','9a269e0a68794129b34da26d2bbce138'),
('plm.licensing_consolidation_capture_snapshot(text,uuid)','d71bc7c27e27854af851a733b6b741dd'),
('plm.licensing_consolidation_operation_state(jsonb)','29d8abcb694d990cbfa5d895867723e7'),
('plm.licensing_consolidation_plan_immutable()','f1fee5d87b66833891461106cc104bfb'),
('plm.licensing_operation_identity_predicate(jsonb)','ea67528b1eb6b0b34b608e6c406c2baf'),
('plm.plan_licensing_consolidation(text,uuid,text)','afb787614989a40b27e93969f19d98ef'),
('plm.plan_licensing_consolidation_rollback(uuid,text)','404a03544edb6982d9336746ad52fad2')
) pins(signature,body_md5) where not exists(select 1 from pg_proc p where p.oid=to_regprocedure(pins.signature) and md5(p.prosrc)=pins.body_md5))
and not exists(select 1 from (values
('core.property_character_source_edge_source_retirement_idx','CREATE INDEX property_character_source_edge_source_retirement_idx ON core.property_character_source_edge USING btree (source_system, id) WHERE (is_current AND (evidence_kind = ''direct_source_assertion''::core.relationship_evidence_kind))'),
('core.property_franchise_source_edge_source_retirement_idx','CREATE INDEX property_franchise_source_edge_source_retirement_idx ON core.property_franchise_source_edge USING btree (source_system, id) WHERE (is_current AND (evidence_kind = ''direct_source_assertion''::core.relationship_evidence_kind))'),
('core.property_style_guide_source_edge_source_retirement_idx','CREATE INDEX property_style_guide_source_edge_source_retirement_idx ON core.property_style_guide_source_edge USING btree (source_system, id) WHERE (is_current AND (evidence_kind = ''direct_source_assertion''::core.relationship_evidence_kind))'),
('core.style_guide_character_source_edge_source_retirement_idx','CREATE INDEX style_guide_character_source_edge_source_retirement_idx ON core.style_guide_character_source_edge USING btree (source_system, id) WHERE (is_current AND (evidence_kind = ''direct_source_assertion''::core.relationship_evidence_kind))'),
('dam.asset_character_source_edge_source_retirement_idx','CREATE INDEX asset_character_source_edge_source_retirement_idx ON dam.asset_character_source_edge USING btree (source_system, id) WHERE (is_current AND (evidence_kind = ''direct_source_assertion''::core.relationship_evidence_kind))'),
('dam.asset_franchise_source_edge_source_retirement_idx','CREATE INDEX asset_franchise_source_edge_source_retirement_idx ON dam.asset_franchise_source_edge USING btree (source_system, id) WHERE (is_current AND (evidence_kind = ''direct_source_assertion''::core.relationship_evidence_kind))'),
('dam.asset_property_source_edge_source_retirement_idx','CREATE INDEX asset_property_source_edge_source_retirement_idx ON dam.asset_property_source_edge USING btree (source_system, id) WHERE (is_current AND (evidence_kind = ''direct_source_assertion''::core.relationship_evidence_kind))'),
('dam.asset_style_guide_source_edge_source_retirement_idx','CREATE INDEX asset_style_guide_source_edge_source_retirement_idx ON dam.asset_style_guide_source_edge USING btree (source_system, id) WHERE (is_current AND (evidence_kind = ''direct_source_assertion''::core.relationship_evidence_kind))')
) pins(index_name,definition) where not exists(select 1 from pg_index i where i.indexrelid=to_regclass(pins.index_name) and i.indisvalid and i.indisready and pg_get_indexdef(i.indexrelid)=pins.definition))
and not exists(select 1 from identity_targets t where not exists(select 1 from pg_index i where i.indrelid=to_regclass(t.target) and i.indisunique and i.indisvalid and i.indisready and i.indpred is null and i.indexprs is null and (select array_agg(a.attname::text order by a.attname) from unnest(i.indkey) with ordinality keys(attnum,n) join pg_attribute a on a.attrelid=i.indrelid and a.attnum=keys.attnum where keys.n<=i.indnkeyatts)=t.keys))

) as passed;
