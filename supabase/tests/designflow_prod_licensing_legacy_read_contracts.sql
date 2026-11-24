-- #4707: DesignFlow runtimes read live dflow_prod licensing rows for the plm
-- comparison, by column, never writing; the stale plm camelCase copies stay closed.
do $test$
declare
  r text;
  tbl text;
  legacy_tables text[] := array['dflow_prod."licensingStatus"', 'dflow_prod."licensingMilestone"',
    'dflow_prod."licensingFeedbackReply"'];
begin
  if to_regnamespace('dflow_prod') is null
     or to_regrole('designflow_prod_tracking_runtime') is null then
    return;
  end if;
  if not has_column_privilege('designflow_prod_tracking_runtime', 'dflow_prod."licensingMilestone"', 'milestone_date', 'SELECT')
     or not has_column_privilege('designflow_prod_tracking_runtime', 'dflow_prod."licensingFeedbackReply"', 'tagged_user_ids', 'SELECT')
     or has_column_privilege('designflow_prod_tracking_runtime', 'dflow_prod."licensingFeedbackReply"', 'comment', 'SELECT')
     or not has_column_privilege('designflow_prod_item_master_runtime', 'dflow_prod."licensingMilestone"', 'itemheader_id_fk', 'SELECT') then
    raise exception 'DesignFlow legacy licensing read scope is wrong';
  end if;
  foreach tbl in array legacy_tables loop
    if exists (
      select from pg_catalog.pg_attribute a
      where a.attrelid = tbl::regclass and a.attnum > 0 and not a.attisdropped
        and not has_column_privilege('designflow_prod_backend_runtime', tbl, a.attnum, 'SELECT')
    ) then
      raise exception 'DesignFlow backend cannot read whole % rows', tbl;
    end if;
  end loop;
  foreach r in array array['designflow_prod_tracking_runtime', 'designflow_prod_item_master_runtime',
    'designflow_prod_backend_runtime'] loop
    foreach tbl in array array['plm."licensingStatus"', 'plm."licensingMilestone"', 'plm."licensingFeedbackReply"'] loop
      if to_regclass(tbl) is not null and has_any_column_privilege(r, tbl, 'SELECT, INSERT, UPDATE') then
        raise exception '% reaches the stale snapshot %', r, tbl;
      end if;
    end loop;
    foreach tbl in array legacy_tables loop
      -- Item Master already writes legacy statuses and replies.
      if r = 'designflow_prod_item_master_runtime' and tbl <> 'dflow_prod."licensingMilestone"' then
        continue;
      end if;
      if has_any_column_privilege(r, tbl, 'INSERT, UPDATE')
         or has_table_privilege(r, tbl, 'DELETE, TRUNCATE') then
        raise exception '% has write access to %', r, tbl;
      end if;
    end loop;
  end loop;
end
$test$;
