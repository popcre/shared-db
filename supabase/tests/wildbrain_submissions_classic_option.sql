-- #3545: WildBrain Submissions Classic option is exposed under Submissions.
--
-- HOW IT IS RUN
--   .github/workflows/database-contract-tests.yml executes every supabase/tests/*.sql
--   against a THROWAWAY local Supabase stack, wrapped in a single
--   `begin; ... \ir <file>; rollback;` transaction.
--
-- EVERY VALUE IN THIS FILE IS EITHER THE ONE AUTHORIZED CLASSIC ID OR INVENTED.

begin;

do $$
declare
  v_definition text;
  v_n integer;
  v_label text;
begin
  if to_regclass('plm.wildbrain_submission_property_option') is null then
    raise exception 'wildbrain submission option table is missing';
  end if;

  select count(*) into v_n from plm.wildbrain_submission_property_option;
  if v_n <> 1 then
    raise exception 'expected exactly 1 WildBrain submission option, found %', v_n;
  end if;

  select exact_label into v_label
  from plm.wildbrain_submission_property_option
  where option_key = 'e608bfe3-a3e2-439a-899d-dc88a59e9b58';
  if v_label is distinct from 'Strawberry Shortcake Classic' then
    raise exception 'Classic option missing or mislabeled: %', v_label;
  end if;

  -- Positive: the exact row the wildbrain-submissions arm selects is present.
  select count(*) into v_n
  from plm.wildbrain_submission_property_option o
  where o.option_key = 'e608bfe3-a3e2-439a-899d-dc88a59e9b58'
    and o.exact_label = 'Strawberry Shortcake Classic';
  if v_n <> 1 then
    raise exception '#3545 positive inventory row missing: %', v_n;
  end if;

  select pg_get_functiondef(
    'api.db_data_admin_scraped_source_inventory(text,text,text,integer)'::regprocedure
  ) into v_definition;

  if position('plm.wildbrain_submission_property_option' in v_definition) = 0 then
    raise exception 'inventory function does not read the wildbrain submissions table';
  end if;

  if position('''wildbrain-submissions''' in v_definition) = 0 then
    raise exception 'inventory has no wildbrain-submissions arm';
  end if;

  if position('''Strawberry Shortcake - Submissions (MediaBox)''' in v_definition) = 0 then
    raise exception 'inventory has no Strawberry Shortcake Submissions heading';
  end if;

  if position('strawberry-shortcake-creative'', ''wildbrain-submissions'') then ''strawberry-shortcake'''
    in v_definition) = 0 then
    raise exception 'wildbrain-submissions does not group with Strawberry Shortcake Creative';
  end if;

  if has_table_privilege('authenticated', 'plm.wildbrain_submission_property_option', 'select')
     or has_table_privilege('anon', 'plm.wildbrain_submission_property_option', 'select') then
    raise exception 'client roles can read plm.wildbrain_submission_property_option';
  end if;
end $$;

rollback;
