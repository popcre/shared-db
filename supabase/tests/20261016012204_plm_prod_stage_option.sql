begin;
do $$
begin
  assert to_regclass('plm.prod_stage_option') is not null, 'order options table missing';
  assert (select relrowsecurity from pg_class where oid='plm.prod_stage_option'::regclass), 'RLS must be enabled';
  assert not has_table_privilege('anon','plm.prod_stage_option','SELECT'), 'anon must not read order choices';
  assert not has_table_privilege('authenticated','plm.prod_stage_option','UPDATE'), 'browser must not write order choices';
  assert has_table_privilege('service_role','plm.prod_stage_option','UPDATE'), 'service must retain write capability';
end $$;
rollback;
