begin;

-- shared-db#4167: public.apply_erp_item_updates is service_role-only, validates its
-- payload, and returns one result per item in order. Rolled back.
do $$
declare
  v jsonb;
  v_msg text;
  v_cases text[] := array[
    '{"a":1}',
    '[1]',
    '[{"division_code":"X","updates":{"mg01_code":"A"}}]',
    '[{"sku":"S","division_code":"X","updates":{}}]',
    '[{"sku":"S","division_code":"X","updates":{"is_deleted":"true"}}]',
    '[{"sku":"S","division_code":"X","updates":{"mg01_code":5}}]'
  ];
  i int;
begin
  if has_function_privilege('authenticated', 'public.apply_erp_item_updates(jsonb)', 'execute')
     or has_function_privilege('anon', 'public.apply_erp_item_updates(jsonb)', 'execute') then
    raise exception 'apply_erp_item_updates must not be executable by anon/authenticated';
  end if;
  if not has_function_privilege('service_role', 'public.apply_erp_item_updates(jsonb)', 'execute') then
    raise exception 'service_role must execute apply_erp_item_updates';
  end if;

  v := public.apply_erp_item_updates('[]'::jsonb);
  if v <> '[]'::jsonb then raise exception 'empty page must return []: %', v; end if;

  v := public.apply_erp_item_updates(
    '[{"sku":"ZZ_TEST_NO_SUCH_SKU_4167","division_code":"ZZ","updates":{"mg01_code":"A","cover_description":null}},
      {"sku":"ZZ_TEST_NO_SUCH_SKU_4167b","division_code":"ZZ","updates":{"product_category":"B"}}]');
  if jsonb_array_length(v) <> 2
     or (v->0->>'asset_count')::int <> 0 or (v->0->>'group_count')::int <> 0
     or v->0->'asset_id' <> 'null'::jsonb or v->1->'group_id' <> 'null'::jsonb then
    raise exception 'unmatched items must report zero counts and null ids: %', v;
  end if;

  for i in 1 .. array_length(v_cases, 1) loop
    v_msg := null;
    begin
      perform public.apply_erp_item_updates(v_cases[i]::jsonb);
    exception when sqlstate '22023' then
      v_msg := sqlerrm;
    end;
    if v_msg is null then
      raise exception 'case % was not refused: %', i, v_cases[i];
    end if;
  end loop;
end;
$$;

rollback;
