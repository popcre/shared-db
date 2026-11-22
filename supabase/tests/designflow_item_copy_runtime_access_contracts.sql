-- #4707: migration access stays with the exact Data Syncing login.
do $test$
declare
  runtime_role constant name := 'designflow_prod_data_sync_runtime';
  grants_role constant name := 'designflow_prod_data_sync_grants';
  candidate record;
begin
  if not pg_has_role(runtime_role, grants_role, 'USAGE')
     or (select rolbypassrls from pg_roles where rolname=runtime_role)
     or not has_schema_privilege(runtime_role, 'plm', 'USAGE')
     or not has_schema_privilege(runtime_role, 'app', 'USAGE') then
    raise exception 'DesignFlow item copy is not bound to the restricted runtime role';
  end if;

  if not has_column_privilege(runtime_role, 'dflow_prod.users', 'id', 'SELECT')
     or has_table_privilege(runtime_role, 'dflow_prod.users', 'SELECT')
     or has_table_privilege(runtime_role, 'dflow_prod."licensingStatus"', 'SELECT')
     or not has_column_privilege(runtime_role, 'dflow_prod."licensingStatus"', 'attachments', 'SELECT')
     or not has_column_privilege(runtime_role, 'dflow_prod."licensingMilestone"', 'milestone_date', 'SELECT') then
    raise exception 'DesignFlow source privileges lost required fields or exposed unrelated fields';
  end if;

  for candidate in select * from (values
    ('plm.designflow_item','legacy_item_id'),
    ('plm.item_merch_group','legacy_merch_group_id'),
    ('plm.item_custom_value','slot_number'),
    ('plm.item_price','price_level'),
    ('plm.licensing_status','designflow_source_assignee_ids'),
    ('plm.licensing_feedback','designflow_author_id'),
    ('plm.licensing_status_assignee','designflow_user_id'),
    ('plm.licensing_feedback_mention','designflow_user_id'),
    ('plm.licensing_attachment','source_reference'),
    ('app.file_object','source_id')
  ) targets(relation, field)
  loop
    if not (select relrowsecurity from pg_class where oid=candidate.relation::regclass)
       or not has_column_privilege(runtime_role, candidate.relation, candidate.field, 'SELECT')
       or not has_column_privilege(runtime_role, candidate.relation, candidate.field, 'INSERT')
       or has_any_column_privilege(runtime_role, candidate.relation, 'UPDATE')
       or exists (
         select from pg_policy where polrelid=candidate.relation::regclass
           and (select oid from pg_roles where rolname=grants_role)=any(polroles)
           and polcmd not in ('a','r')
       )
       or has_table_privilege(runtime_role, candidate.relation, 'DELETE')
       or has_table_privilege(runtime_role, candidate.relation, 'TRUNCATE') then
      raise exception 'Unexpected copy privileges for %', candidate.relation;
    end if;
  end loop;
  if has_table_privilege(runtime_role, 'app.file_object', 'INSERT')
     or has_table_privilege(runtime_role, 'app.file_object', 'SELECT')
     or has_table_privilege(runtime_role, 'plm.licensing_status', 'INSERT')
     or has_table_privilege(runtime_role, 'plm.licensing_status', 'SELECT')
     or has_table_privilege(runtime_role, 'plm.licensing_feedback', 'INSERT')
     or has_table_privilege(runtime_role, 'plm.licensing_feedback', 'SELECT')
     or has_any_column_privilege(runtime_role, 'plm.item', 'INSERT')
     or has_any_column_privilege(runtime_role, 'plm.item', 'UPDATE')
     or has_any_column_privilege(runtime_role, 'core.merch_group_review_hold', 'INSERT')
     or has_any_column_privilege(runtime_role, 'core.merch_group_review_hold', 'UPDATE')
     or has_any_column_privilege(runtime_role, 'core.merch_group', 'INSERT')
     or has_any_column_privilege(runtime_role, 'core.merch_group', 'UPDATE') then
    raise exception 'The item copy can affect data outside its owned shadow scope';
  end if;
end
$test$;
