-- Issue #4836 (author claim #4837): read-only Poppim diagnostic role for
-- Jessica Cortazar (Poppim admin), used by her own Claude to investigate data.
-- derived-from: none
--
-- Owner request (Albert Hazan): "her read-only access should cover only Poppim
-- data if that's possible. there are core.* tables that poppim needs that are
-- accessible by all applications."
--
-- WHAT THIS CREATES. One NOLOGIN role, poppim_readonly_jcortazar, with SELECT
-- only on the objects poppim-web reads (grep of src/ for .schema/.from/.rpc):
--   * every pim table (not the coldlion_* view);
--   * api views pm_product_board, pim_item_picker, pm_product_assets,
--     pm_customer_list, pm_factory_list. pm_product_board and pim_item_picker are
--     security_invoker views over plm.item; plm is deliberately NOT granted, so
--     those two views refuse for this role. pim.product is the direct source;
--   * app tables profile, activity, comment, notification, app_access,
--     user_role, role, file_object;
--   * core tables licensor, property, character, contact_company, contact,
--     customer, factory, product_type.
-- Nothing in crm, dam, plm, dflow*, coldlion, auth, vault, storage or ingest.
--
-- BYPASSRLS: these tables are RLS-scoped to the signed-in browser user
-- (auth.uid()). A direct database login has no browser identity, so without
-- BYPASSRLS every pim/app read returns zero rows and the role is useless for
-- diagnosis. Row visibility is widened, never write rights: the GRANT set below
-- is SELECT only, so BYPASSRLS cannot reach any table outside it.
--
-- WRITES: no INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER, no CREATE on any
-- schema, no function EXECUTE granted. The only PUBLIC-executable functions in
-- these four schemas (verified 2026-10-26) are stable lookups (current_profile_id,
-- has_role, has_any_role, has_app_access, jwt_role_names) and trigger-only
-- functions that cannot be called directly. default_transaction_read_only and a
-- 30s statement_timeout are role defaults as an extra guard.
--
-- LOGIN: the role is NOLOGIN here. Login and password are enabled afterwards
-- outside git; the password lives only in 1Password vibe_coding.

create role poppim_readonly_jcortazar nologin noinherit nosuperuser nocreatedb nocreaterole noreplication bypassrls connection limit 3;

comment on role poppim_readonly_jcortazar is
  'Issue #4836. Read-only Poppim diagnostic login for Jessica Cortazar (jcortazar@popcre.com). SELECT on pim, Poppim api views, Poppim app tables and needed core tables only.';

alter role poppim_readonly_jcortazar set statement_timeout = '30s';
alter role poppim_readonly_jcortazar set idle_in_transaction_session_timeout = '60s';
alter role poppim_readonly_jcortazar set default_transaction_read_only = on;

grant usage on schema pim, api, app, core to poppim_readonly_jcortazar;

grant select on
  pim.checklist_item, pim.customer_ext, pim.customer_order, pim.design,
  pim.design_asset, pim.design_collection, pim.factory_ext, pim.product,
  pim.product_assignee, pim.product_field, pim.product_file, pim.product_link,
  pim.product_sample, pim.product_style_group, pim.product_submission,
  pim.product_tag, pim.product_time_entry, pim.product_update, pim.project,
  pim.revision_request, pim.saved_view, pim.stage, pim.stage_history,
  pim.view_pref
  to poppim_readonly_jcortazar;

grant select on
  api.pm_product_board, api.pim_item_picker, api.pm_product_assets,
  api.pm_customer_list, api.pm_factory_list
  to poppim_readonly_jcortazar;

grant select on
  app.profile, app.activity, app.comment, app.notification, app.app_access,
  app.user_role, app.role, app.file_object
  to poppim_readonly_jcortazar;

grant select on
  core.licensor, core.property, core.character, core.contact_company,
  core.contact, core.customer, core.factory, core.product_type
  to poppim_readonly_jcortazar;
