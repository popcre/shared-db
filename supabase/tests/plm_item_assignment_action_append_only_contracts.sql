begin;

-- shared-db#3595: the plm final homes are append-only and carry the four source
-- lookup indexes. Exercised with throwaway rows; everything is rolled back.
do $test$
declare
  v_item integer;
  v_step integer;
  v_asg bigint;
  v_closed bigint;
  v_act bigint;
  v_state text;
  idx text;
begin
  foreach idx in array array[
    'item_user_assignment_active_lookup', 'item_workflow_action_item_time',
    'item_workflow_action_open_handoff_lookup', 'item_workflow_action_admin_review'
  ] loop
    if pg_catalog.to_regclass('plm.' || idx) is null then
      raise exception 'missing index plm.%', idx;
    end if;
    if pg_catalog.to_regclass('dflow.' || idx) is not null
       and pg_catalog.replace(pg_catalog.pg_get_indexdef(pg_catalog.to_regclass('dflow.' || idx)), ' ON dflow.', ' ON plm.')
           <> pg_catalog.pg_get_indexdef(pg_catalog.to_regclass('plm.' || idx)) then
      raise exception 'index plm.% differs from its dflow source', idx;
    end if;
  end loop;

  v_item := (select coalesce(max("rfqItem_id"), 0) + 1000000 from plm."RFQItem");
  v_step := (select coalesce(max("RFQStep_id"), 0) + 1000000 from plm."RFQStep");
  insert into plm."RFQItem"("rfqItem_id") overriding system value values (v_item);
  insert into plm."RFQStep"("RFQStep_id") overriding system value values (v_step);

  insert into plm.item_user_assignment (rfq_item_id, function_key, user_id, assigned_by_user_id)
  values (v_item, 'sales', 1, 1) returning id into v_asg;
  -- Already-closed history must still be insertable (identity-preserving row move).
  insert into plm.item_user_assignment (rfq_item_id, function_key, user_id, assigned_by_user_id,
                                        effective_from, effective_to)
  values (v_item, 'sales', 2, 1, now() - interval '2 day', now() - interval '1 day')
  returning id into v_closed;

  -- Rewriting a fact is refused.
  begin
    update plm.item_user_assignment set user_id = 3 where id = v_asg;
    raise exception 'assignment fact rewrite was accepted';
  exception when sqlstate '55000' then null;
  end;
  -- Deleting is refused.
  begin
    delete from plm.item_user_assignment where id = v_asg;
    raise exception 'assignment delete was accepted';
  exception when sqlstate '55000' then null;
  end;
  -- Closing an active assignment once is the one permitted change.
  update plm.item_user_assignment set effective_to = clock_timestamp() + interval '1 second' where id = v_asg;
  -- Re-closing or reopening is refused.
  begin
    update plm.item_user_assignment set effective_to = clock_timestamp() + interval '1 hour' where id = v_asg;
    raise exception 'second close was accepted';
  exception when sqlstate '55000' then null;
  end;
  begin
    update plm.item_user_assignment set effective_to = null where id = v_closed;
    raise exception 'reopen was accepted';
  exception when sqlstate '55000' then null;
  end;
  -- RFQItem deletion cascading into assignment history is refused.
  begin
    delete from plm."RFQItem" where "rfqItem_id" = v_item;
    raise exception 'RFQItem delete cascaded through assignment history';
  exception when sqlstate '55000' then null;
  end;

  perform pg_catalog.set_config('request.designflow.actor_id', '1', true);
  perform pg_catalog.set_config('request.designflow.actor_email', 'contract@example.test', true);
  insert into plm.item_workflow_action (rfq_item_id, actor_user_id, new_step_id, action_key, correlation_key)
  values (v_item, 1, v_step, 'send_to_sourcing', gen_random_uuid()) returning id into v_act;

  begin
    update plm.item_workflow_action set action_key = 'other' where id = v_act;
    raise exception 'workflow action update was accepted';
  exception when sqlstate '55000' then null;
  end;
  begin
    update plm.item_workflow_action set requires_admin_review = true where id = v_act;
    raise exception 'workflow action flag update was accepted';
  exception when sqlstate '55000' then null;
  end;
  begin
    delete from plm.item_workflow_action where id = v_act;
    raise exception 'workflow action delete was accepted';
  exception when sqlstate '55000' then null;
  end;

  -- No API role gained any access.
  if exists (
    select 1 from unnest(array['anon','authenticated','service_role']) r(role_name)
    cross join unnest(array['plm.item_user_assignment','plm.item_workflow_action']) t(rel)
    cross join unnest(array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE']) p(priv)
    where pg_catalog.has_table_privilege(r.role_name, t.rel, p.priv)
  ) then
    raise exception 'deny-by-default boundary changed';
  end if;
end
$test$;

rollback;
