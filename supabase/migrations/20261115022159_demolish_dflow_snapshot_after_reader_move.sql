-- shared-db issue: demolish the production dflow snapshot after its two readers move.
-- Owner rulings: 2026-11-13 verbatim "drop the empty shelf" (done, dflow_prod_old);
-- 2026-11-14 verbatim "moot" - the historical MG reclassification never ran and is
-- not revived; its helper retires in this migration.
-- Audit (2026-11-14, issue popcre/designflow-data-syncing#126): the ONLY outside
-- dependents of schema dflow are public.style_tracker_rows_with_bridge (relation
-- level) and api.resolve_item_mg_category (function level). This migration moves
-- both - the view body is byte-identical except the RFQ source now reads the live
-- app schema dflow_prod - then demolishes the snapshot behind a live dependent
-- guard (TOAST/pg_temp excluded; they travel with their parents under CASCADE).
-- Backup: gs://designflow-storage/backups/dflow-stale-cleanup-2026-11-12/prod_dflow_full_schema.dump
-- (53 MB, pg_restore --list verified).

CREATE OR REPLACE VIEW public.style_tracker_rows_with_bridge AS SELECT r.id,
    r.source_workbook_id,
    r.source_sheet,
    r.source_row_number,
    r.tracker_type,
    r.sku,
    r.group_id,
    r.description,
    r.customer,
    r.designer,
    r.commissioned,
    r.upc,
    r.customer_sku,
    r.licensor,
    r.license_status,
    r.royalty,
    r.concept_status,
    r.pre_production_status,
    r.production_status,
    r.default_vendor,
    r.discontinued,
    r.notes,
    r.row_data,
    r.imported_at,
    r.created_at,
    r.updated_at,
    r.updated_by,
    b.id AS bridge_id,
    b.erp_item_id,
    b.style_group_id,
    b.company_id,
    b.public_licensor_id,
    b.core_licensor_id,
    b.factory_id,
    b.plm_item_id,
    b.match_status,
    b.match_confidence,
    b.match_notes,
    b.last_matched_at,
    erp.item_description AS canonical_description,
    COALESCE(selected_customer.display_name, selected_customer.name, bridge_customer.display_name, bridge_customer.name) AS canonical_customer_name,
    COALESCE(core_lic.name, public_lic.name) AS canonical_licensor_name,
    factory.name AS canonical_factory_name,
    sg.sku AS style_group_sku,
    erp.style_number AS erp_style_number,
    b.creative_designer_id,
    creative.name AS canonical_designer_name,
    r.customer_id,
    COALESCE(rfq.rfq_groups, '[]'::jsonb) AS rfq_groups
   FROM style_tracker_rows r
     LEFT JOIN plm.style_tracker_item_bridge b ON b.style_tracker_row_id = r.id
     LEFT JOIN LATERAL ( SELECT i.description AS item_description,
            i.item_number AS style_number
           FROM plm.item i
          WHERE i.id = b.erp_item_id AND i.source_system = 'coldlion'::text AND NOT ((EXISTS ( SELECT 1
                   FROM plm.legacy_erp_item_identity l
                  WHERE l.external_id = i.item_number)) AND i.id = (( SELECT p.id
                   FROM plm.item p
                     LEFT JOIN plm.legacy_erp_item_identity lp ON lp.external_id = p.item_number
                  WHERE p.source_system = 'coldlion'::text AND upper(TRIM(BOTH FROM p.item_number)) = upper(TRIM(BOTH FROM i.item_number)) AND p.item_number = i.item_number
                  ORDER BY (
                        CASE
                            WHEN lp.division_code IS NOT NULL AND lp.division_code = (p.raw ->> 'divisionCode'::text) THEN 0
                            ELSE 1
                        END), p.source_id, p.id
                 LIMIT 1)))
        UNION ALL
         SELECT r1.description,
            r1.item_number
           FROM plm.legacy_erp_item_identity l2
             JOIN LATERAL ( SELECT p2.id,
                    p2.description,
                    p2.item_number
                   FROM plm.item p2
                  WHERE p2.source_system = 'coldlion'::text AND upper(TRIM(BOTH FROM p2.item_number)) = upper(TRIM(BOTH FROM l2.external_id)) AND p2.item_number = l2.external_id
                  ORDER BY (
                        CASE
                            WHEN l2.division_code IS NOT NULL AND l2.division_code = (p2.raw ->> 'divisionCode'::text) THEN 0
                            ELSE 1
                        END), p2.source_id, p2.id
                 LIMIT 1) r1 ON true
          WHERE l2.id = b.erp_item_id
 LIMIT 1) erp ON true
     LEFT JOIN style_groups sg ON sg.id = b.style_group_id
     LEFT JOIN core.customer bridge_customer ON bridge_customer.id = b.company_id
     LEFT JOIN core.customer selected_customer ON selected_customer.id = r.customer_id
     LEFT JOIN licensors public_lic ON public_lic.id = b.public_licensor_id
     LEFT JOIN core.licensor core_lic ON core_lic.id = b.core_licensor_id
     LEFT JOIN core.creative_designer creative ON creative.id = b.creative_designer_id
     LEFT JOIN core.factory factory ON factory.id = b.factory_id
     LEFT JOIN LATERAL ( SELECT jsonb_agg(jsonb_build_object('id', per_group.id, 'name', per_group.name, 'linked_at', to_char(timezone('UTC'::text, per_group.linked_at), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'::text)) ORDER BY per_group.linked_at DESC NULLS LAST, per_group.id DESC) AS rfq_groups
           FROM ( SELECT g."RFQGroup_id" AS id,
                    COALESCE(NULLIF(TRIM(BOTH FROM g."RFQGroup_name"), ''::text), 'RFQ Group #'::text || g."RFQGroup_id"::text) AS name,
                    max(COALESCE(i."rfqItem_date_modified"::timestamp with time zone, i."rfqItem_created_date", g.data_added::timestamp with time zone)) AS linked_at
                   FROM dflow_prod."RFQItem" i
                     JOIN dflow_prod."RFQGroup" g ON g."RFQGroup_id" = i."rfqItem_rfq_group"
                  WHERE upper(TRIM(BOTH FROM i."rfqItem_style_number")) = upper(TRIM(BOTH FROM r.row_data ->> 'rfq_code'::text)) AND NULLIF(TRIM(BOTH FROM r.row_data ->> 'rfq_code'::text), ''::text) IS NOT NULL AND i."rfqItem_rfq_group" IS NOT NULL
                  GROUP BY g."RFQGroup_id", g."RFQGroup_name") per_group) rfq ON true;

;
DROP FUNCTION IF EXISTS api.resolve_item_mg_category(integer);

do $guard$
declare
  v_outside integer;
begin
  with inside as (
    select oid from pg_namespace where nspname = 'dflow'
    union all
    select c.oid from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'dflow'
    union all
    select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'dflow'
  ), dependents as (
    select d.objid,
           coalesce(
             (select n.nspname from pg_class c join pg_namespace n on n.oid = c.relnamespace
               where c.oid = d.objid and d.classid = 'pg_class'::regclass),
             (select n.nspname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where p.oid = d.objid and d.classid = 'pg_proc'::regclass),
             (select n.nspname from pg_rewrite rw join pg_class c on c.oid = rw.ev_class
               join pg_namespace n on n.oid = c.relnamespace
               where rw.oid = d.objid and d.classid = 'pg_rewrite'::regclass),
             (select n.nspname from pg_trigger t join pg_class c on c.oid = t.tgrelid
               join pg_namespace n on n.oid = c.relnamespace
               where t.oid = d.objid and d.classid = 'pg_trigger'::regclass),
             'internal') as dep_schema
      from pg_depend d
     where d.refobjid in (select oid from inside)
  )
  select count(*) into v_outside from dependents
   where dep_schema not in ('dflow', 'internal')
     and dep_schema not like 'pg_toast%'
     and dep_schema not like 'pg_temp%';
  if v_outside > 0 then
    raise exception 'dflow has % outside dependent object(s); refusing cascade drop', v_outside;
  end if;
end
$guard$;

drop schema if exists dflow cascade;
