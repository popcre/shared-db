-- Issue #2873. Version reserved by migration-author claim #3739.
-- Least-privilege dflow_prod service identities for the DesignFlow production
-- cutover (popcre/designflow-backend#94): one NOLOGIN grant role and one LOGIN
-- runtime identity for each of backend, Item Master, Tracking and Data Sync.
--
-- The grant matrix below is the exact union of what each service's current
-- production (`main`) and cutover (`develop`) code reads and writes in
-- single-schema mode: Sequelize models and the operations the code performs on
-- them, raw SQL, the canonical functions each service calls, serial sequences of
-- tables it inserts into, and the tables written by the SECURITY INVOKER
-- functions and triggers those calls reach. Identity columns need no sequence
-- grant. The full evidence (file:line per object) is published on #2873.
--
-- Boundaries:
--   * Privileges sit only on the NOLOGIN grant roles. Each LOGIN role holds only
--     membership (INHERIT) in its own grant role and nothing else, and is
--     NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS with a
--     connection limit (Qwen 3.8 Max review conditions, #2873, 2026-09-23).
--   * No password is set here. Credentials are provisioned separately through
--     1Password and ALTER ROLE ... PASSWORD after canonical promotion; until
--     then the LOGIN roles cannot authenticate.
--   * Only USAGE on schema dflow_prod. No CREATE, TRUNCATE, REFERENCES, TRIGGER,
--     ownership, or any access to dflow, plm, public or hts_rag. Backend HTS
--     access stays on designflow_hts_prod_runtime / worker and is not touched.
--   * Owner decision 2026-09-23 (docs/security/pg-net-direct-login-rule.md):
--     these four are trusted in-house server services, the only permitted kind
--     of new direct login. Like every role they inherit Supabase's PUBLIC grant
--     on schema `net` (pg_net), which cannot be removed; that is accepted.
--   * No application rows change.
-- Depends on #2874, #2875 and #3737 (objects granted below).

begin;

do $pre$
declare v_missing text;
begin
  if exists (select 1 from pg_roles where rolname like 'designflow\_prod\_%\_grants' or rolname like 'designflow\_prod\_%\_runtime')
  then raise exception '#2873: a designflow_prod service role already exists'; end if;
  select string_agg(x, ', ') into v_missing from (values
    ('table','AdditionalUserEmail'),
    ('table','AuditLog'),
    ('table','FOBCountry'),
    ('table','Factory'),
    ('table','GridAccessLevel'),
    ('table','GridChildrenLayout'),
    ('table','GridChildrenLayoutOrder'),
    ('table','GridLayout'),
    ('table','GridViewState'),
    ('table','RFQContainer'),
    ('table','RFQGroup'),
    ('table','RFQItem'),
    ('table','RFQItemStatus'),
    ('table','RFQStep'),
    ('table','RFQVendor'),
    ('table','RFQWhse'),
    ('table','RolePermissions'),
    ('table','Roles'),
    ('table','SeasonCode'),
    ('table','StandardizedDetail'),
    ('table','StandardizedGroup'),
    ('table','StandardizedProductElement'),
    ('table','StandardizedProductElementValue'),
    ('table','StandardizedProductType'),
    ('table','StandardizedSize'),
    ('table','StandardizedVendor'),
    ('table','StandardizedVersion'),
    ('table','UDFComponent'),
    ('table','UDFElement'),
    ('table','UDFElementType'),
    ('table','UDFGroup'),
    ('table','UDFTable'),
    ('table','UIElements'),
    ('table','age_group'),
    ('table','ai_cache_events'),
    ('table','app_settings'),
    ('table','art_types'),
    ('table','artist_types'),
    ('table','artists'),
    ('table','auth_token'),
    ('table','comments'),
    ('table','companyCode'),
    ('table','customers'),
    ('table','deliveryLocation'),
    ('table','divisionCode'),
    ('table','email_logs'),
    ('table','grid_cell_notes'),
    ('table','itemAttachment'),
    ('table','itemDepth'),
    ('table','itemHeader'),
    ('table','itemSize'),
    ('table','item_character_associations'),
    ('table','item_user_assignment'),
    ('table','item_workflow_action'),
    ('table','licenseList'),
    ('table','merchGroup'),
    ('table','merchGroupHeaders'),
    ('table','properties_and_characters'),
    ('table','property_character_associations'),
    ('table','quote_auth_token'),
    ('table','user_notification'),
    ('table','users'),
    ('table','vendor'),
    ('table','vendorGroup'),
    ('view','item_workflow_handoff'),
    ('sequence','AdditionalUserEmail_id_seq'),
    ('sequence','AuditLog_id_seq'),
    ('sequence','FOBCountry_FOBCountry_id_seq'),
    ('sequence','Factory_id_seq'),
    ('sequence','GridChildrenLayoutOrder_id_seq'),
    ('sequence','GridChildrenLayout_id_seq'),
    ('sequence','GridViewState_id_seq'),
    ('sequence','RFQContainer_RFQContainer_id_seq'),
    ('sequence','RFQCustomLayout_RFQCustomLayout_id_seq'),
    ('sequence','RFQGroup_RFQGroup_id_seq'),
    ('sequence','RFQItem_rfqItem_id_seq'),
    ('sequence','RFQLayout_id_seq'),
    ('sequence','RFQVendor_RFQVendor_id_seq'),
    ('sequence','RolePermissions_Id_seq'),
    ('sequence','StandardizedDetail_id_seq'),
    ('sequence','StandardizedGroup_id_seq'),
    ('sequence','StandardizedProductElement_id_seq'),
    ('sequence','StandardizedProductType_id_seq'),
    ('sequence','StandardizedSize_id_seq'),
    ('sequence','StandardizedVendor_id_seq'),
    ('sequence','StandardizedVersion_id_seq1'),
    ('sequence','UIElements_Id_seq'),
    ('sequence','deliveryLocation_deliveryLocation_id_seq'),
    ('sequence','itemDepth__id_seq'),
    ('sequence','itemPackage_item_package_id_seq'),
    ('sequence','itemSize_itemSize_id_seq'),
    ('sequence','licenseList_licenseList_id_seq'),
    ('sequence','signUpToken_id_seq'),
    ('sequence','vendorGroup_id_seq'),
    ('sequence','age_group_id_seq'),
    ('sequence','art_types_id_seq'),
    ('sequence','artist_types_id_seq'),
    ('sequence','artists_id_seq'),
    ('sequence','auth_token_id_seq'),
    ('sequence','comments_id_seq'),
    ('sequence','customers_customers_id_seq'),
    ('sequence','email_logs_id_seq'),
    ('sequence','user_notification_id_seq'),
    ('sequence','users_id_seq'),
    ('sequence','vendor_vendor_id_seq'),
    ('function','record_item_workflow_action'),
    ('function','set_item_user_assignment'),
    ('table','LicenseFeedBacks'),
    ('table','LicensingTime'),
    ('table','ProdOrderDetail'),
    ('table','art_piece'),
    ('table','art_piece_attachment'),
    ('table','groups'),
    ('table','itemType'),
    ('table','licensingFeedbackReply'),
    ('table','licensingStatus'),
    ('table','productUserAssignment'),
    ('sequence','itemHeader_item_num_id_pk _seq'),
    ('sequence','itemType_item_type_id_seq'),
    ('sequence','licensingFeedbackReply_id_seq'),
    ('sequence','licensingStatus_id_seq'),
    ('sequence','productUserAssignment_id_seq'),
    ('sequence','art_piece_attachment_id_seq'),
    ('sequence','art_piece_id_seq'),
    ('table','DesignTeamTime'),
    ('table','FactoryTime'),
    ('table','ProdOrderHeader'),
    ('table','externalCustomer'),
    ('table','externalVendor'),
    ('table','itemLicenseImage'),
    ('table','item_prod_order_detail_associations'),
    ('table','product_type_factory_time'),
    ('table','sample'),
    ('table','sample_approval_event'),
    ('table','sample_attachment'),
    ('table','sample_box'),
    ('table','sample_carrier'),
    ('table','sample_comments'),
    ('table','sample_creation_batch'),
    ('table','sample_event'),
    ('table','sample_factory_group'),
    ('table','sample_factory_visit'),
    ('table','sample_factory_visit_event'),
    ('table','sample_import_job'),
    ('table','sample_import_row'),
    ('table','sample_inventory_balance'),
    ('table','sample_movement'),
    ('table','sample_path_revision'),
    ('table','sample_piece_lineage'),
    ('table','sample_remote_request'),
    ('table','sample_remote_request_history'),
    ('table','sample_remote_request_item'),
    ('table','sample_reservation'),
    ('table','sample_shipment'),
    ('table','sample_shipment_item'),
    ('table','sample_shipment_line'),
    ('table','sample_shipment_notice'),
    ('table','sample_shipment_notice_recipient'),
    ('table','sample_stop_closeout'),
    ('table','sample_workflow'),
    ('view','sample_approval_current'),
    ('view','sample_balance_by_location'),
    ('view','sample_global_status'),
    ('view','sample_in_transit'),
    ('view','sample_open_stop_work'),
    ('view','sample_receipt_discrepancy'),
    ('view','sample_visit_plan'),
    ('sequence','FactoryTime_id_seq'),
    ('sequence','groups_id_seq'),
    ('sequence','sample_attachment_sample_attachment_id_seq'),
    ('sequence','sample_box_box_id_pk_seq'),
    ('sequence','sample_comments_id_seq'),
    ('sequence','sample_event_event_id_pk_seq'),
    ('sequence','sample_factory_group_factory_group_id_pk_seq'),
    ('sequence','sample_sample_id_pk_seq'),
    ('sequence','sample_shipment_item_shipment_item_id_pk_seq'),
    ('function','claim_sample_shipment_notice'),
    ('function','pack_sample_reservation'),
    ('function','post_sample_approval_event'),
    ('function','post_sample_movement'),
    ('function','post_sample_piece_split'),
    ('function','post_sample_remote_request_event'),
    ('function','reserve_sample_remote_request_item'),
    ('table','externalApi'),
    ('table','itemDetail'),
    ('sequence','ProdOrderDetail_id_seq'),
    ('sequence','ProdOrderHeader_id_seq'),
    ('sequence','externalCustomer_id_seq'),
    ('sequence','externalVendor_id_seq'),
    ('sequence','itemDetail_item_pk_seq'),
    ('sequence','item_prod_order_detail_associations_id_seq')
  ) v(kind, name) cross join lateral (select v.kind||' '||v.name as x) z
  where case v.kind
    when 'function' then not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='dflow_prod' and p.proname=v.name)
    when 'sequence' then to_regclass(format('dflow_prod.%I', v.name)) is null
    else to_regclass(format('dflow_prod.%I', v.name)) is null end;
  if v_missing is not null then raise exception '#2873: dflow_prod objects missing: %', v_missing; end if;
end $pre$;

create role designflow_prod_backend_grants nologin noinherit nosuperuser nocreatedb nocreaterole noreplication nobypassrls;
create role designflow_prod_backend_runtime login inherit nosuperuser nocreatedb nocreaterole noreplication nobypassrls connection limit 20;
grant designflow_prod_backend_grants to designflow_prod_backend_runtime with inherit true, set false, admin false;
comment on role designflow_prod_backend_grants is 'NOLOGIN least-privilege dflow_prod grants for DesignFlow designflow-backend (#2873).';
comment on role designflow_prod_backend_runtime is 'LOGIN runtime identity for DesignFlow designflow-backend on dflow_prod; holds only designflow_prod_backend_grants. Trusted in-house server service; can reach pg_net via PUBLIC (owner decision 2026-09-23). Password set outside this repository (#2873).';

create role designflow_prod_item_master_grants nologin noinherit nosuperuser nocreatedb nocreaterole noreplication nobypassrls;
create role designflow_prod_item_master_runtime login inherit nosuperuser nocreatedb nocreaterole noreplication nobypassrls connection limit 10;
grant designflow_prod_item_master_grants to designflow_prod_item_master_runtime with inherit true, set false, admin false;
comment on role designflow_prod_item_master_grants is 'NOLOGIN least-privilege dflow_prod grants for DesignFlow designflow-item-master (#2873).';
comment on role designflow_prod_item_master_runtime is 'LOGIN runtime identity for DesignFlow designflow-item-master on dflow_prod; holds only designflow_prod_item_master_grants. Trusted in-house server service; can reach pg_net via PUBLIC (owner decision 2026-09-23). Password set outside this repository (#2873).';

create role designflow_prod_tracking_grants nologin noinherit nosuperuser nocreatedb nocreaterole noreplication nobypassrls;
create role designflow_prod_tracking_runtime login inherit nosuperuser nocreatedb nocreaterole noreplication nobypassrls connection limit 10;
grant designflow_prod_tracking_grants to designflow_prod_tracking_runtime with inherit true, set false, admin false;
comment on role designflow_prod_tracking_grants is 'NOLOGIN least-privilege dflow_prod grants for DesignFlow designflow-tracking (#2873).';
comment on role designflow_prod_tracking_runtime is 'LOGIN runtime identity for DesignFlow designflow-tracking on dflow_prod; holds only designflow_prod_tracking_grants. Trusted in-house server service; can reach pg_net via PUBLIC (owner decision 2026-09-23). Password set outside this repository (#2873).';

create role designflow_prod_data_sync_grants nologin noinherit nosuperuser nocreatedb nocreaterole noreplication nobypassrls;
create role designflow_prod_data_sync_runtime login inherit nosuperuser nocreatedb nocreaterole noreplication nobypassrls connection limit 10;
grant designflow_prod_data_sync_grants to designflow_prod_data_sync_runtime with inherit true, set false, admin false;
comment on role designflow_prod_data_sync_grants is 'NOLOGIN least-privilege dflow_prod grants for DesignFlow designflow-data-syncing (#2873).';
comment on role designflow_prod_data_sync_runtime is 'LOGIN runtime identity for DesignFlow designflow-data-syncing on dflow_prod; holds only designflow_prod_data_sync_grants. Trusted in-house server service; can reach pg_net via PUBLIC (owner decision 2026-09-23). Password set outside this repository (#2873).';

grant usage on schema dflow_prod to designflow_prod_backend_grants, designflow_prod_item_master_grants, designflow_prod_tracking_grants, designflow_prod_data_sync_grants;

-- designflow-backend
grant select, insert on table dflow_prod."AdditionalUserEmail" to designflow_prod_backend_grants;
grant select, insert on table dflow_prod."AuditLog" to designflow_prod_backend_grants;
grant select, insert, update on table dflow_prod."FOBCountry" to designflow_prod_backend_grants;
grant select, insert, update on table dflow_prod."Factory" to designflow_prod_backend_grants;
grant select, insert, update on table dflow_prod."GridAccessLevel" to designflow_prod_backend_grants;
grant select, insert on table dflow_prod."GridChildrenLayout" to designflow_prod_backend_grants;
grant select, insert, update on table dflow_prod."GridChildrenLayoutOrder" to designflow_prod_backend_grants;
grant select, insert, update on table dflow_prod."GridLayout" to designflow_prod_backend_grants;
grant select, insert, update on table dflow_prod."GridViewState" to designflow_prod_backend_grants;
grant select, insert, update on table dflow_prod."RFQContainer" to designflow_prod_backend_grants;
grant select, insert, update on table dflow_prod."RFQGroup" to designflow_prod_backend_grants;
grant select, insert, update, delete on table dflow_prod."RFQItem" to designflow_prod_backend_grants;
grant select on table dflow_prod."RFQItemStatus" to designflow_prod_backend_grants;
grant select, update on table dflow_prod."RFQStep" to designflow_prod_backend_grants;
grant select, insert, update, delete on table dflow_prod."RFQVendor" to designflow_prod_backend_grants;
grant select, update on table dflow_prod."RFQWhse" to designflow_prod_backend_grants;
grant select, insert, update on table dflow_prod."RolePermissions" to designflow_prod_backend_grants;
grant select on table dflow_prod."Roles" to designflow_prod_backend_grants;
grant select on table dflow_prod."SeasonCode" to designflow_prod_backend_grants;
grant select, insert on table dflow_prod."StandardizedDetail" to designflow_prod_backend_grants;
grant select, insert on table dflow_prod."StandardizedGroup" to designflow_prod_backend_grants;
grant select, insert, update on table dflow_prod."StandardizedProductElement" to designflow_prod_backend_grants;
grant select on table dflow_prod."StandardizedProductElementValue" to designflow_prod_backend_grants;
grant select, insert on table dflow_prod."StandardizedProductType" to designflow_prod_backend_grants;
grant select, insert, update on table dflow_prod."StandardizedSize" to designflow_prod_backend_grants;
grant select, insert, update on table dflow_prod."StandardizedVendor" to designflow_prod_backend_grants;
grant select, insert on table dflow_prod."StandardizedVersion" to designflow_prod_backend_grants;
grant select on table dflow_prod."UDFComponent" to designflow_prod_backend_grants;
grant select on table dflow_prod."UDFElement" to designflow_prod_backend_grants;
grant select on table dflow_prod."UDFElementType" to designflow_prod_backend_grants;
grant select on table dflow_prod."UDFGroup" to designflow_prod_backend_grants;
grant select on table dflow_prod."UDFTable" to designflow_prod_backend_grants;
grant select, insert on table dflow_prod."UIElements" to designflow_prod_backend_grants;
grant select, insert, update on table dflow_prod."age_group" to designflow_prod_backend_grants;
grant select, insert on table dflow_prod."ai_cache_events" to designflow_prod_backend_grants;
grant select, insert, update on table dflow_prod."app_settings" to designflow_prod_backend_grants;
grant select, insert, update on table dflow_prod."art_types" to designflow_prod_backend_grants;
grant select, insert, update on table dflow_prod."artist_types" to designflow_prod_backend_grants;
grant select, insert, update on table dflow_prod."artists" to designflow_prod_backend_grants;
grant select, insert, update on table dflow_prod."auth_token" to designflow_prod_backend_grants;
grant select, insert, update, delete on table dflow_prod."comments" to designflow_prod_backend_grants;
grant select on table dflow_prod."companyCode" to designflow_prod_backend_grants;
grant select, insert, update, delete on table dflow_prod."customers" to designflow_prod_backend_grants;
grant select, insert, update on table dflow_prod."deliveryLocation" to designflow_prod_backend_grants;
grant select on table dflow_prod."divisionCode" to designflow_prod_backend_grants;
grant insert on table dflow_prod."email_logs" to designflow_prod_backend_grants;
grant select, insert, update, delete on table dflow_prod."grid_cell_notes" to designflow_prod_backend_grants;
grant select, insert, update, delete on table dflow_prod."itemAttachment" to designflow_prod_backend_grants;
grant select, insert, update, delete on table dflow_prod."itemDepth" to designflow_prod_backend_grants;
grant select, update on table dflow_prod."itemHeader" to designflow_prod_backend_grants;
grant select, insert, update, delete on table dflow_prod."itemSize" to designflow_prod_backend_grants;
grant select on table dflow_prod."item_character_associations" to designflow_prod_backend_grants;
grant select on table dflow_prod."item_user_assignment" to designflow_prod_backend_grants;
grant select on table dflow_prod."item_workflow_action" to designflow_prod_backend_grants;
grant select, insert, update on table dflow_prod."licenseList" to designflow_prod_backend_grants;
grant select, update on table dflow_prod."merchGroup" to designflow_prod_backend_grants;
grant select on table dflow_prod."merchGroupHeaders" to designflow_prod_backend_grants;
grant select on table dflow_prod."properties_and_characters" to designflow_prod_backend_grants;
grant select on table dflow_prod."property_character_associations" to designflow_prod_backend_grants;
grant select, insert, update on table dflow_prod."quote_auth_token" to designflow_prod_backend_grants;
grant select, insert, update, delete on table dflow_prod."user_notification" to designflow_prod_backend_grants;
grant select, insert, update on table dflow_prod."users" to designflow_prod_backend_grants;
grant select, insert, update on table dflow_prod."vendor" to designflow_prod_backend_grants;
grant select, insert, update, delete on table dflow_prod."vendorGroup" to designflow_prod_backend_grants;
grant select on table dflow_prod."item_workflow_handoff" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."AdditionalUserEmail_id_seq" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."AuditLog_id_seq" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."FOBCountry_FOBCountry_id_seq" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."Factory_id_seq" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."GridChildrenLayoutOrder_id_seq" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."GridChildrenLayout_id_seq" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."GridViewState_id_seq" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."RFQContainer_RFQContainer_id_seq" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."RFQCustomLayout_RFQCustomLayout_id_seq" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."RFQGroup_RFQGroup_id_seq" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."RFQItem_rfqItem_id_seq" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."RFQLayout_id_seq" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."RFQVendor_RFQVendor_id_seq" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."RolePermissions_Id_seq" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."StandardizedDetail_id_seq" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."StandardizedGroup_id_seq" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."StandardizedProductElement_id_seq" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."StandardizedProductType_id_seq" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."StandardizedSize_id_seq" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."StandardizedVendor_id_seq" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."StandardizedVersion_id_seq1" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."UIElements_Id_seq" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."deliveryLocation_deliveryLocation_id_seq" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."itemDepth__id_seq" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."itemPackage_item_package_id_seq" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."itemSize_itemSize_id_seq" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."licenseList_licenseList_id_seq" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."signUpToken_id_seq" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."vendorGroup_id_seq" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."age_group_id_seq" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."art_types_id_seq" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."artist_types_id_seq" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."artists_id_seq" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."auth_token_id_seq" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."comments_id_seq" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."customers_customers_id_seq" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."email_logs_id_seq" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."user_notification_id_seq" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."users_id_seq" to designflow_prod_backend_grants;
grant usage on sequence dflow_prod."vendor_vendor_id_seq" to designflow_prod_backend_grants;
do $f$ declare r record; begin
  for r in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='dflow_prod' and p.proname = any (array['record_item_workflow_action', 'set_item_user_assignment']) loop
    execute format('grant execute on function %s to designflow_prod_backend_grants', r.sig);
  end loop; end $f$;

-- designflow-item-master
grant insert on table dflow_prod."AuditLog" to designflow_prod_item_master_grants;
grant select on table dflow_prod."GridAccessLevel" to designflow_prod_item_master_grants;
grant select on table dflow_prod."GridLayout" to designflow_prod_item_master_grants;
grant select on table dflow_prod."LicenseFeedBacks" to designflow_prod_item_master_grants;
grant select on table dflow_prod."LicensingTime" to designflow_prod_item_master_grants;
grant select on table dflow_prod."ProdOrderDetail" to designflow_prod_item_master_grants;
grant select on table dflow_prod."RFQItem" to designflow_prod_item_master_grants;
grant select on table dflow_prod."SeasonCode" to designflow_prod_item_master_grants;
grant select, insert, delete on table dflow_prod."art_piece" to designflow_prod_item_master_grants;
grant select, insert, delete on table dflow_prod."art_piece_attachment" to designflow_prod_item_master_grants;
grant select on table dflow_prod."customers" to designflow_prod_item_master_grants;
grant select on table dflow_prod."divisionCode" to designflow_prod_item_master_grants;
grant select, insert, update, delete on table dflow_prod."grid_cell_notes" to designflow_prod_item_master_grants;
grant select on table dflow_prod."groups" to designflow_prod_item_master_grants;
grant select, insert, update on table dflow_prod."itemAttachment" to designflow_prod_item_master_grants;
grant select, insert on table dflow_prod."itemHeader" to designflow_prod_item_master_grants;
grant select, insert on table dflow_prod."itemType" to designflow_prod_item_master_grants;
grant select, insert, update, delete on table dflow_prod."licensingFeedbackReply" to designflow_prod_item_master_grants;
grant select, insert, update, delete on table dflow_prod."licensingStatus" to designflow_prod_item_master_grants;
grant select on table dflow_prod."merchGroup" to designflow_prod_item_master_grants;
grant select, insert, update, delete on table dflow_prod."productUserAssignment" to designflow_prod_item_master_grants;
grant select on table dflow_prod."users" to designflow_prod_item_master_grants;
grant usage on sequence dflow_prod."AuditLog_id_seq" to designflow_prod_item_master_grants;
grant usage on sequence dflow_prod."itemHeader_item_num_id_pk _seq" to designflow_prod_item_master_grants;
grant usage on sequence dflow_prod."itemPackage_item_package_id_seq" to designflow_prod_item_master_grants;
grant usage on sequence dflow_prod."itemType_item_type_id_seq" to designflow_prod_item_master_grants;
grant usage on sequence dflow_prod."licensingFeedbackReply_id_seq" to designflow_prod_item_master_grants;
grant usage on sequence dflow_prod."licensingStatus_id_seq" to designflow_prod_item_master_grants;
grant usage on sequence dflow_prod."productUserAssignment_id_seq" to designflow_prod_item_master_grants;
grant usage on sequence dflow_prod."art_piece_attachment_id_seq" to designflow_prod_item_master_grants;
grant usage on sequence dflow_prod."art_piece_id_seq" to designflow_prod_item_master_grants;

-- designflow-tracking
grant select, update on table dflow_prod."DesignTeamTime" to designflow_prod_tracking_grants;
grant select on table dflow_prod."Factory" to designflow_prod_tracking_grants;
grant select, insert, update, delete on table dflow_prod."FactoryTime" to designflow_prod_tracking_grants;
grant select on table dflow_prod."GridAccessLevel" to designflow_prod_tracking_grants;
grant select on table dflow_prod."GridLayout" to designflow_prod_tracking_grants;
grant select on table dflow_prod."LicenseFeedBacks" to designflow_prod_tracking_grants;
grant select, update on table dflow_prod."LicensingTime" to designflow_prod_tracking_grants;
grant select on table dflow_prod."ProdOrderDetail" to designflow_prod_tracking_grants;
grant select, update on table dflow_prod."ProdOrderHeader" to designflow_prod_tracking_grants;
grant select on table dflow_prod."RolePermissions" to designflow_prod_tracking_grants;
grant select on table dflow_prod."UDFTable" to designflow_prod_tracking_grants;
grant select on table dflow_prod."UIElements" to designflow_prod_tracking_grants;
grant select on table dflow_prod."comments" to designflow_prod_tracking_grants;
grant select on table dflow_prod."customers" to designflow_prod_tracking_grants;
grant select on table dflow_prod."deliveryLocation" to designflow_prod_tracking_grants;
grant select, insert on table dflow_prod."email_logs" to designflow_prod_tracking_grants;
grant select on table dflow_prod."externalCustomer" to designflow_prod_tracking_grants;
grant select on table dflow_prod."externalVendor" to designflow_prod_tracking_grants;
grant select, insert, update, delete on table dflow_prod."grid_cell_notes" to designflow_prod_tracking_grants;
grant select, insert, update, delete on table dflow_prod."groups" to designflow_prod_tracking_grants;
grant select, insert on table dflow_prod."itemAttachment" to designflow_prod_tracking_grants;
grant select, update on table dflow_prod."itemHeader" to designflow_prod_tracking_grants;
grant select on table dflow_prod."itemLicenseImage" to designflow_prod_tracking_grants;
grant select on table dflow_prod."item_prod_order_detail_associations" to designflow_prod_tracking_grants;
grant select on table dflow_prod."licensingStatus" to designflow_prod_tracking_grants;
grant select on table dflow_prod."merchGroup" to designflow_prod_tracking_grants;
grant select, insert, update, delete on table dflow_prod."product_type_factory_time" to designflow_prod_tracking_grants;
grant select, insert, update, delete on table dflow_prod."sample" to designflow_prod_tracking_grants;
grant select, insert, delete on table dflow_prod."sample_approval_event" to designflow_prod_tracking_grants;
grant select, insert, delete on table dflow_prod."sample_attachment" to designflow_prod_tracking_grants;
grant select, insert, update, delete on table dflow_prod."sample_box" to designflow_prod_tracking_grants;
grant select on table dflow_prod."sample_carrier" to designflow_prod_tracking_grants;
grant select, insert, update, delete on table dflow_prod."sample_comments" to designflow_prod_tracking_grants;
grant select, insert, delete on table dflow_prod."sample_creation_batch" to designflow_prod_tracking_grants;
grant select, insert, delete on table dflow_prod."sample_event" to designflow_prod_tracking_grants;
grant select, insert, update, delete on table dflow_prod."sample_factory_group" to designflow_prod_tracking_grants;
grant select, insert, update, delete on table dflow_prod."sample_factory_visit" to designflow_prod_tracking_grants;
grant select, insert, delete on table dflow_prod."sample_factory_visit_event" to designflow_prod_tracking_grants;
grant select, insert, update, delete on table dflow_prod."sample_import_job" to designflow_prod_tracking_grants;
grant select, insert, update, delete on table dflow_prod."sample_import_row" to designflow_prod_tracking_grants;
grant insert on table dflow_prod."sample_inventory_balance" to designflow_prod_tracking_grants;
grant select, insert on table dflow_prod."sample_movement" to designflow_prod_tracking_grants;
grant select, insert, delete on table dflow_prod."sample_path_revision" to designflow_prod_tracking_grants;
grant select, insert, delete on table dflow_prod."sample_piece_lineage" to designflow_prod_tracking_grants;
grant select, insert, delete on table dflow_prod."sample_remote_request" to designflow_prod_tracking_grants;
grant select, delete on table dflow_prod."sample_remote_request_history" to designflow_prod_tracking_grants;
grant select, insert, delete on table dflow_prod."sample_remote_request_item" to designflow_prod_tracking_grants;
grant select, delete on table dflow_prod."sample_reservation" to designflow_prod_tracking_grants;
grant select, insert, update, delete on table dflow_prod."sample_shipment" to designflow_prod_tracking_grants;
grant select, insert, delete on table dflow_prod."sample_shipment_item" to designflow_prod_tracking_grants;
grant select, insert, update on table dflow_prod."sample_shipment_line" to designflow_prod_tracking_grants;
grant select, insert, update on table dflow_prod."sample_shipment_notice" to designflow_prod_tracking_grants;
grant insert on table dflow_prod."sample_shipment_notice_recipient" to designflow_prod_tracking_grants;
grant select, insert, update on table dflow_prod."sample_stop_closeout" to designflow_prod_tracking_grants;
grant select, insert, update, delete on table dflow_prod."sample_workflow" to designflow_prod_tracking_grants;
grant select on table dflow_prod."users" to designflow_prod_tracking_grants;
grant select on table dflow_prod."sample_approval_current" to designflow_prod_tracking_grants;
grant select on table dflow_prod."sample_balance_by_location" to designflow_prod_tracking_grants;
grant select on table dflow_prod."sample_global_status" to designflow_prod_tracking_grants;
grant select on table dflow_prod."sample_in_transit" to designflow_prod_tracking_grants;
grant select on table dflow_prod."sample_open_stop_work" to designflow_prod_tracking_grants;
grant select on table dflow_prod."sample_receipt_discrepancy" to designflow_prod_tracking_grants;
grant select on table dflow_prod."sample_visit_plan" to designflow_prod_tracking_grants;
grant usage on sequence dflow_prod."FactoryTime_id_seq" to designflow_prod_tracking_grants;
grant usage on sequence dflow_prod."itemPackage_item_package_id_seq" to designflow_prod_tracking_grants;
grant usage on sequence dflow_prod."email_logs_id_seq" to designflow_prod_tracking_grants;
grant usage on sequence dflow_prod."groups_id_seq" to designflow_prod_tracking_grants;
grant usage on sequence dflow_prod."sample_attachment_sample_attachment_id_seq" to designflow_prod_tracking_grants;
grant usage on sequence dflow_prod."sample_box_box_id_pk_seq" to designflow_prod_tracking_grants;
grant usage on sequence dflow_prod."sample_comments_id_seq" to designflow_prod_tracking_grants;
grant usage on sequence dflow_prod."sample_event_event_id_pk_seq" to designflow_prod_tracking_grants;
grant usage on sequence dflow_prod."sample_factory_group_factory_group_id_pk_seq" to designflow_prod_tracking_grants;
grant usage on sequence dflow_prod."sample_sample_id_pk_seq" to designflow_prod_tracking_grants;
grant usage on sequence dflow_prod."sample_shipment_item_shipment_item_id_pk_seq" to designflow_prod_tracking_grants;
do $f$ declare r record; begin
  for r in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='dflow_prod' and p.proname = any (array['claim_sample_shipment_notice', 'pack_sample_reservation', 'post_sample_approval_event', 'post_sample_movement', 'post_sample_piece_split', 'post_sample_remote_request_event', 'reserve_sample_remote_request_item']) loop
    execute format('grant execute on function %s to designflow_prod_tracking_grants', r.sig);
  end loop; end $f$;

-- designflow-data-syncing
grant select, insert on table dflow_prod."ProdOrderDetail" to designflow_prod_data_sync_grants;
grant select, insert, update on table dflow_prod."ProdOrderHeader" to designflow_prod_data_sync_grants;
grant select on table dflow_prod."UDFTable" to designflow_prod_data_sync_grants;
grant select on table dflow_prod."externalApi" to designflow_prod_data_sync_grants;
grant insert on table dflow_prod."externalCustomer" to designflow_prod_data_sync_grants;
grant insert on table dflow_prod."externalVendor" to designflow_prod_data_sync_grants;
grant select on table dflow_prod."itemAttachment" to designflow_prod_data_sync_grants;
grant insert on table dflow_prod."itemDetail" to designflow_prod_data_sync_grants;
grant select on table dflow_prod."itemHeader" to designflow_prod_data_sync_grants;
grant select, insert, update on table dflow_prod."item_prod_order_detail_associations" to designflow_prod_data_sync_grants;
grant select on table dflow_prod."merchGroup" to designflow_prod_data_sync_grants;
grant select on table dflow_prod."merchGroupHeaders" to designflow_prod_data_sync_grants;
grant usage on sequence dflow_prod."ProdOrderDetail_id_seq" to designflow_prod_data_sync_grants;
grant usage on sequence dflow_prod."ProdOrderHeader_id_seq" to designflow_prod_data_sync_grants;
grant usage on sequence dflow_prod."externalCustomer_id_seq" to designflow_prod_data_sync_grants;
grant usage on sequence dflow_prod."externalVendor_id_seq" to designflow_prod_data_sync_grants;
grant usage on sequence dflow_prod."itemDetail_item_pk_seq" to designflow_prod_data_sync_grants;
grant usage on sequence dflow_prod."item_prod_order_detail_associations_id_seq" to designflow_prod_data_sync_grants;

do $post$
declare v_role text;
begin
  foreach v_role in array array['designflow_prod_backend_runtime','designflow_prod_item_master_runtime','designflow_prod_tracking_runtime','designflow_prod_data_sync_runtime'] loop
    if exists (select 1 from pg_roles where rolname=v_role and (rolsuper or rolcreatedb or rolcreaterole or rolreplication or rolbypassrls or not rolcanlogin or rolconnlimit < 1))
    then raise exception '#2873 VERIFY FAILED: % attributes', v_role; end if;
    if (select count(*) from pg_auth_members m where m.member=(select oid from pg_roles where rolname=v_role)) <> 1
    then raise exception '#2873 VERIFY FAILED: % must hold exactly one membership', v_role; end if;
    if has_schema_privilege(v_role,'dflow_prod','CREATE') or has_schema_privilege(v_role,'dflow','USAGE')
       or has_schema_privilege(v_role,'hts_rag','USAGE') or (to_regnamespace('plm') is not null and has_schema_privilege(v_role,'plm','USAGE'))
    then raise exception '#2873 VERIFY FAILED: % has a forbidden schema privilege', v_role; end if;
  end loop;
  if exists (select 1 from information_schema.role_table_grants g
             where g.grantee like 'designflow\_prod\_%' and (g.table_schema <> 'dflow_prod' or g.privilege_type in ('TRUNCATE','REFERENCES','TRIGGER')))
  then raise exception '#2873 VERIFY FAILED: forbidden table privilege granted'; end if;
end $post$;

commit;
