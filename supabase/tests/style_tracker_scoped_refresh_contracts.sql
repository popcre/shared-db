-- #5639 / PopDAM #469. Synthetic disposable-database fixtures only.
-- The contract harness owns the surrounding transaction and rollback.
do $test$
begin
  if has_function_privilege('anon', 'public.refresh_style_tracker_item_bridge_rows(uuid[])', 'execute')
     or not has_function_privilege('authenticated', 'public.refresh_style_tracker_item_bridge_rows(uuid[])', 'execute')
     or has_function_privilege('authenticated', 'plm.refresh_style_tracker_item_bridge(uuid[])', 'execute')
     or has_function_privilege('authenticated', 'plm.apply_style_tracker_designer_resolutions(uuid[])', 'execute') then
    raise exception 'scoped refresh execution boundary is incorrect';
  end if;
end $test$;

insert into core.creative_designer(id, name) values
  ('00000000-5639-4000-8000-000000000001', 'ZZ5639 SharedOne'),
  ('00000000-5639-4000-8000-000000000002', 'ZZ5639 SharedTwo');
insert into plm.item(id, item_number, style_number, description, source_system, source_id)
values ('00000000-5639-4000-8000-000000000010', 'ZZ5639-SHARED', 'ZZ5639-SHARED', 'ZZ5639 item', 'zztest', '5639-shared');
insert into public.style_tracker_rows(id, source_sheet, source_row_number, tracker_type, sku, designer, description, row_data) values
  ('00000000-5639-4000-8000-000000000101', 'Generic.Style', 9563901, 'generic', 'ZZ5639-SHARED', 'ZZ5639 SharedOne', 'ZZ5639 before', '{"origin":"user_added"}'),
  ('00000000-5639-4000-8000-000000000102', 'Generic.Style', 9563902, 'generic', 'ZZ5639-SHARED', 'ZZ5639 SharedTwo', 'ZZ5639 unrelated', '{"origin":"user_added"}'),
  ('00000000-5639-4000-8000-000000000103', 'Generic.Style', 9563903, 'generic', 'ZZ5639-AMBIGUOUS', 'ZZ5639', 'ZZ5639 ambiguous', '{"origin":"user_added"}');
select * from public.refresh_style_tracker_item_bridge();
do $test$
begin
  if (select count(*) from plm.style_tracker_item_bridge
      where style_tracker_row_id in ('00000000-5639-4000-8000-000000000101', '00000000-5639-4000-8000-000000000102')
        and plm_item_id='00000000-5639-4000-8000-000000000010') <> 2 then
    raise exception 'cross-row fixture must genuinely share its canonical PLM item';
  end if;
end $test$;

create temporary table zz5639_preimages as
select style_tracker_row_id, to_jsonb(b) as preimage from plm.style_tracker_item_bridge b
where style_tracker_row_id in ('00000000-5639-4000-8000-000000000102', '00000000-5639-4000-8000-000000000103');
create temporary table zz5639_item_preimage as
select to_jsonb(i) as preimage from plm.item i where id='00000000-5639-4000-8000-000000000010';
update public.style_tracker_rows set description='ZZ5639 changed'
where id='00000000-5639-4000-8000-000000000101';

-- The ordinary non-admin bootstrap user must retain settled Styles access.
select set_config('request.jwt.claim.sub', '00000000-7541-4000-8000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"00000000-7541-4000-8000-000000000002","role":"authenticated"}', true);
set local role authenticated;
do $test$
declare result record;
begin
  select * into result from public.refresh_style_tracker_item_bridge_rows(array['00000000-5639-4000-8000-000000000101'::uuid]);
  if result.inserted_count <> 0 or result.updated_count <> 1 or result.total_count <> 1 then
    raise exception 'bounded result did not count exactly its one existing bridge row';
  end if;
end $test$;
do $test$
declare ids uuid[];
begin
  for ids in select value from (values
    (array[]::uuid[]), (array[null::uuid]),
    (array['00000000-5639-4000-8000-000000000101'::uuid,'00000000-5639-4000-8000-000000000101'::uuid])
  ) invalid(value) loop
    begin
      perform public.refresh_style_tracker_item_bridge_rows(ids);
      raise exception 'invalid scoped IDs were accepted';
    exception when invalid_parameter_value then null;
    end;
  end loop;
  begin
    perform public.refresh_style_tracker_item_bridge_rows(null::uuid[]);
    raise exception 'NULL became a full refresh';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform public.refresh_style_tracker_item_bridge_rows(array(select gen_random_uuid() from generate_series(1,26)));
    raise exception 'more than 25 IDs were accepted';
  exception when invalid_parameter_value then null;
  end;
end $test$;
reset role;

do $test$
begin
  if not exists(select 1 from plm.style_tracker_item_bridge where style_tracker_row_id='00000000-5639-4000-8000-000000000101'
                and description='ZZ5639 changed' and creative_designer_id='00000000-5639-4000-8000-000000000001') then
    raise exception 'edited bridge row did not refresh with its designer';
  end if;
  if exists(select 1 from zz5639_preimages p join plm.style_tracker_item_bridge b using(style_tracker_row_id)
            where p.preimage is distinct from to_jsonb(b)) then
    raise exception 'unrelated/shared-target bridge changed, including timestamp or metadata';
  end if;
  if exists(select 1 from plm.item i, zz5639_item_preimage p where i.id='00000000-5639-4000-8000-000000000010'
            and to_jsonb(i) is distinct from p.preimage) then
    raise exception 'conflicting cross-row designers changed canonical PLM item';
  end if;
  if exists(select 1 from plm.style_tracker_item_bridge where style_tracker_row_id='00000000-5639-4000-8000-000000000103'
            and creative_designer_id is not null) then
    raise exception 'global ambiguous first-name evidence was hidden';
  end if;
end $test$;

-- Full wrappers still update every original candidate; private/full and public
-- full produce identical bridge values inside this fixed-time transaction.
update public.style_tracker_rows set description='ZZ5639 full refresh'
where id='00000000-5639-4000-8000-000000000102';
select * from plm.refresh_style_tracker_item_bridge(null::uuid[]);
select plm.apply_style_tracker_designer_resolutions(null::uuid[]);
create temporary table zz5639_full_preimages as
select id, to_jsonb(b) preimage from plm.style_tracker_item_bridge b;
select * from public.refresh_style_tracker_item_bridge();
do $test$
begin
  if exists(select 1 from zz5639_full_preimages p join plm.style_tracker_item_bridge b using(id)
            where p.preimage is distinct from to_jsonb(b)) then
    raise exception 'zero-argument full-refresh compatibility changed';
  end if;
end $test$;

select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{}', true);
do $test$
begin
  begin
    perform public.refresh_style_tracker_item_bridge_rows(array['00000000-5639-4000-8000-000000000101'::uuid]);
    raise exception 'unsigned caller was accepted';
  exception when insufficient_privilege then null;
  end;
end $test$;
