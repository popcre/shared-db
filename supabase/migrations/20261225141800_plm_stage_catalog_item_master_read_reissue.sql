-- Re-issue of 20261225141700 (PR #7155, designflow-tracking#130, claim #7154).
-- 20261225141700 was held by review-finding #7156 and failed on the standalone
-- DesignFlow sandbox (run 45852863298) because designflow_prod_* roles do not
-- exist on the sandbox; 20261225141700 never applied to sandbox, preview, or
-- production.
--
-- Fixes #7156 findings 1 & 2 and sandbox compatibility:
--   1. Grants directly to the LOGIN role designflow_prod_item_master_runtime
--      (the #4464 option (c) pattern, matching 20261020125826) and revokes any
--      Stage Catalog group grants 20261225141700 left on
--      designflow_prod_item_master_grants during ephemeral/preview replays.
--      USAGE ON SCHEMA plm on designflow_prod_item_master_grants is untouched
--      because 20261225120100 relies on it for plm.designflow_item.
--   2. Uses DROP POLICY IF EXISTS before CREATE POLICY for idempotent replay.
--   3. Guards role-specific DDL with IF to_regrole('designflow_prod_item_master_runtime') IS NULL
--      so sandbox apply skips cleanly with NOTICE (matching 20261225141200).
--
-- derived-from: none
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if to_regrole('designflow_prod_item_master_runtime') is null then
    raise notice '#7154: designflow_prod_item_master_runtime absent; nothing to change';
    return;
  end if;

  if to_regrole('designflow_prod_item_master_grants') is not null then
    revoke all on table plm.stage_list, plm.stage, plm.stage_duration
      from designflow_prod_item_master_grants;
  end if;

  drop policy if exists stage_list_dflow_prod_item_master_read on plm.stage_list;
  drop policy if exists stage_dflow_prod_item_master_read on plm.stage;
  drop policy if exists stage_duration_dflow_prod_item_master_read on plm.stage_duration;

  grant usage on schema plm to designflow_prod_item_master_runtime;

  grant select (id, key) on table plm.stage_list to designflow_prod_item_master_runtime;
  grant select (id, stage_list_id, name, done_signal, sequence, active)
    on table plm.stage to designflow_prod_item_master_runtime;
  grant select (stage_id, scope_kind, scope_value, duration)
    on table plm.stage_duration to designflow_prod_item_master_runtime;

  create policy stage_list_dflow_prod_item_master_read on plm.stage_list
    for select to designflow_prod_item_master_runtime using (true);
  create policy stage_dflow_prod_item_master_read on plm.stage
    for select to designflow_prod_item_master_runtime using (true);
  create policy stage_duration_dflow_prod_item_master_read on plm.stage_duration
    for select to designflow_prod_item_master_runtime using (true);
end
$g$;

commit;
