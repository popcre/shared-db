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
--   * core tables licensor, character, contact_company, contact,
--     customer, product_type.
-- core.property and core.factory are deferred: active claims #4809 and #4749
-- hold them; a follow-up grants them.
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
  'Issue #4836. Read-only Poppim diagnostic login for Jessica Cortazar. SELECT on pim, Poppim api views, Poppim app tables and needed core tables only.';

alter role poppim_readonly_jcortazar set statement_timeout = '30s';
alter role poppim_readonly_jcortazar set idle_in_transaction_session_timeout = '60s';
alter role poppim_readonly_jcortazar set default_transaction_read_only = on;

grant usage on schema pim to poppim_readonly_jcortazar;
grant usage on schema api to poppim_readonly_jcortazar;
grant usage on schema app to poppim_readonly_jcortazar;
grant usage on schema core to poppim_readonly_jcortazar;

grant select on pim.checklist_item to poppim_readonly_jcortazar;
grant select on pim.customer_ext to poppim_readonly_jcortazar;
grant select on pim.customer_order to poppim_readonly_jcortazar;
grant select on pim.design to poppim_readonly_jcortazar;
grant select on pim.design_asset to poppim_readonly_jcortazar;
grant select on pim.design_collection to poppim_readonly_jcortazar;
grant select on pim.factory_ext to poppim_readonly_jcortazar;
grant select on pim.product to poppim_readonly_jcortazar;
grant select on pim.product_assignee to poppim_readonly_jcortazar;
grant select on pim.product_field to poppim_readonly_jcortazar;
grant select on pim.product_file to poppim_readonly_jcortazar;
grant select on pim.product_link to poppim_readonly_jcortazar;
grant select on pim.product_sample to poppim_readonly_jcortazar;
grant select on pim.product_style_group to poppim_readonly_jcortazar;
grant select on pim.product_submission to poppim_readonly_jcortazar;
grant select on pim.product_tag to poppim_readonly_jcortazar;
grant select on pim.product_time_entry to poppim_readonly_jcortazar;
grant select on pim.product_update to poppim_readonly_jcortazar;
grant select on pim.project to poppim_readonly_jcortazar;
grant select on pim.revision_request to poppim_readonly_jcortazar;
grant select on pim.saved_view to poppim_readonly_jcortazar;
grant select on pim.stage to poppim_readonly_jcortazar;
grant select on pim.stage_history to poppim_readonly_jcortazar;
grant select on pim.view_pref to poppim_readonly_jcortazar;

grant select on api.pm_product_board to poppim_readonly_jcortazar;
grant select on api.pim_item_picker to poppim_readonly_jcortazar;
grant select on api.pm_product_assets to poppim_readonly_jcortazar;
grant select on api.pm_customer_list to poppim_readonly_jcortazar;
grant select on api.pm_factory_list to poppim_readonly_jcortazar;

grant select on app.profile to poppim_readonly_jcortazar;
grant select on app.activity to poppim_readonly_jcortazar;
grant select on app.comment to poppim_readonly_jcortazar;
grant select on app.notification to poppim_readonly_jcortazar;
grant select on app.app_access to poppim_readonly_jcortazar;
grant select on app.user_role to poppim_readonly_jcortazar;
grant select on app.role to poppim_readonly_jcortazar;
grant select on app.file_object to poppim_readonly_jcortazar;

grant select on core.licensor to poppim_readonly_jcortazar;
grant select on core.character to poppim_readonly_jcortazar;
grant select on core.contact_company to poppim_readonly_jcortazar;
grant select on core.contact to poppim_readonly_jcortazar;
grant select on core.customer to poppim_readonly_jcortazar;
grant select on core.product_type to poppim_readonly_jcortazar;
