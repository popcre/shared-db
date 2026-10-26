-- Issue #4832; claim #4833. Restore the existing admin role editor's save.
-- derived-from: none
-- The service always updates these three columns, including for a name-only edit.
-- Keep INSERT, DELETE, kind, Id, app_role_id and sequence access unchanged.
-- Recovery: a new reviewed migration revoking this exact column UPDATE grant.
BEGIN;
GRANT UPDATE ("Name", parent_id, is_active)
  ON TABLE dflow_prod."Roles" TO designflow_prod_backend_grants;
COMMIT;
