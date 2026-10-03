-- #3910: plm.import_item_master_data writes only changed rows, and a sweep that no
-- longer returns out-of-scope division EP001 promotes (retiring EP001) instead of
-- failing. Run inside begin; ... rollback; by database-contract-tests. ZZT values only.
do $$
declare
  v_run uuid;
  v_items jsonb := jsonb_build_array(
    jsonb_build_object('companyCode','EDGEHOME','divisionCode','CW001','itemNo','ZZT-A','itemDesc','Alpha'),
    jsonb_build_object('companyCode','EDGEHOME','divisionCode','CW001','itemNo','ZZT-B','itemDesc','Beta'),
    jsonb_build_object('companyCode','EDGEHOME','divisionCode','EP001','itemNo','ZZT-E','itemDesc','Edge'));
begin
  perform * from plm.import_item_master_data(jsonb_build_object(
    'sweepId',gen_random_uuid(),'terminalReached',true,'minimumSilverRatio',0.1,'items',v_items));
  if (select count(*) from plm.item where source_id like 'EDGEHOME|%|ZZT-%') <> 3 then
    raise exception 'T1: first sweep did not land 3 items';
  end if;

  -- Backdate, then repeat the identical sweep: unchanged rows must keep updated_at.
  -- (set_updated_at would overwrite a plain backdate, so bypass it for this one write)
  alter table plm.item disable trigger set_updated_at;
  update plm.item set updated_at = '2001-01-01' where source_id like 'EDGEHOME|%|ZZT-%';
  alter table plm.item enable trigger set_updated_at;
  alter table plm.item_import disable trigger user;
  update plm.item_import set updated_at = '2001-01-01', imported_at = '2001-01-01' where item_no like 'ZZT-%';
  alter table plm.item_import enable trigger user;
  update ingest.raw_record set imported_at = '2001-01-01' where source_table = 'items' and source_id like 'EDGEHOME|%|ZZT-%';
  perform * from plm.import_item_master_data(jsonb_build_object(
    'sweepId',gen_random_uuid(),'terminalReached',true,'minimumSilverRatio',0.1,'items',v_items));
  if exists (select 1 from plm.item where source_id like 'EDGEHOME|%|ZZT-%' and updated_at <> '2001-01-01') then
    raise exception 'T2: an unchanged sweep bumped plm.item.updated_at';
  end if;
  if exists (select 1 from ingest.raw_record where source_table = 'items' and source_id like 'EDGEHOME|%|ZZT-%' and imported_at <> '2001-01-01') then
    raise exception 'T2c: an unchanged sweep rewrote ingest.raw_record';
  end if;
  if exists (select 1 from plm.item_import where item_no like 'ZZT-%' and (updated_at <> '2001-01-01' or imported_at <> '2001-01-01')) then
    raise exception 'T2b: an unchanged sweep rewrote plm.item_import';
  end if;

  -- A real change still updates that one row.
  perform * from plm.import_item_master_data(jsonb_build_object(
    'sweepId',gen_random_uuid(),'terminalReached',true,'minimumSilverRatio',0.1,'items',jsonb_set(v_items,'{0,itemDesc}','"Alpha 2"')));
  if (select count(*) from plm.item where source_id like 'EDGEHOME|%|ZZT-%' and updated_at <> '2001-01-01') <> 1 then
    raise exception 'T3: a changed item was not the only row updated';
  end if;

  -- EP001 disappears from the sweep: promotes and retires it from silver.
  select r.sync_run_id into v_run from plm.import_item_master_data(jsonb_build_object(
    'sweepId',gen_random_uuid(),'terminalReached',true,'minimumSilverRatio',0.1,
    'items',jsonb_build_array(v_items->0, v_items->1))) r;
  if exists (select 1 from plm.item_import where division_code = 'EP001' and item_no = 'ZZT-E') then
    raise exception 'T4: EP001 was not retired from silver';
  end if;
  if not exists (select 1 from plm.item where source_id = 'EDGEHOME|EP001|ZZT-E') then
    raise exception 'T4b: the durable Item Master row for a retired EP001 item was deleted';
  end if;
  if not ((select metadata->'retired_divisions' from ingest.sync_run where id = v_run) ? 'EDGEHOME|EP001') then
    raise exception 'T4c: retirement was not recorded in sync_run metadata';
  end if;

  -- Any other missing division still refuses.
  begin
    perform * from plm.import_item_master_data(jsonb_build_object(
      'sweepId',gen_random_uuid(),'terminalReached',true,'minimumSilverRatio',0.1,
      'items',jsonb_build_array(jsonb_build_object('companyCode','EDGEHOME','divisionCode','SP001','itemNo','ZZT-S'))));
    raise exception 'T5: a sweep omitting CW001 was accepted';
  exception when raise_exception then
    if sqlerrm not like '%omitted a division%' then raise; end if;
  end;
end;
$$;
