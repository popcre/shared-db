-- #4707: DesignFlow runtimes read live dflow_prod licensing rows for the plm
-- comparison, by column, never writing; the stale plm camelCase copies stay closed.
do $test$
declare
  r text;
  tbl text;
begin
  if to_regnamespace('dflow_prod') is null
     or to_regrole('designflow_prod_tracking_runtime') is null then
    return;
  end if;
  if not has_column_privilege('designflow_prod_tracking_runtime', 'dflow_prod."licensingMilestone"', 'milestone_date', 'SELECT')
     or not has_column_privilege('designflow_prod_tracking_runtime', 'dflow_prod."licensingFeedbackReply"', 'tagged_user_ids', 'SELECT')
     or has_column_privilege('designflow_prod_tracking_runtime', 'dflow_prod."licensingFeedbackReply"', 'comment', 'SELECT')
     or not has_column_privilege('designflow_prod_item_master_runtime', 'dflow_prod."licensingMilestone"', 'itemheader_id_fk', 'SELECT')
     or not has_column_privilege('designflow_prod_backend_runtime', 'dflow_prod."licensingStatus"', 'assignee_ids', 'SELECT')
     or not has_column_privilege('designflow_prod_backend_runtime', 'dflow_prod."licensingFeedbackReply"', 'comment', 'SELECT')
     or not has_column_privilege('designflow_prod_backend_runtime', 'dflow_prod."licensingMilestone"', 'updated_at', 'SELECT') then
    raise exception 'DesignFlow legacy licensing read scope is wrong';
  end if;
  foreach r in array array['designflow_prod_tracking_runtime', 'designflow_prod_item_master_runtime',
    'designflow_prod_backend_runtime'] loop
    foreach tbl in array array['plm."licensingStatus"', 'plm."licensingMilestone"', 'plm."licensingFeedbackReply"'] loop
      if to_regclass(tbl) is not null and has_any_column_privilege(r, tbl, 'SELECT, INSERT, UPDATE') then
        raise exception '% reaches the stale snapshot %', r, tbl;
      end if;
    end loop;
  end loop;
  if has_any_column_privilege('designflow_prod_backend_runtime', 'dflow_prod."licensingMilestone"', 'INSERT, UPDATE')
     or has_table_privilege('designflow_prod_backend_runtime', 'dflow_prod."licensingMilestone"', 'DELETE')
     or has_any_column_privilege('designflow_prod_tracking_runtime', 'dflow_prod."licensingMilestone"', 'INSERT, UPDATE')
     or has_table_privilege('designflow_prod_tracking_runtime', 'dflow_prod."licensingMilestone"', 'DELETE') then
    raise exception 'legacy milestone read gained a write';
  end if;
end
$test$;
