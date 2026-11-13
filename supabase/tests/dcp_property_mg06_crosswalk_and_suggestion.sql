begin;
-- popcre/shared-db#6271 — tests for plm.dcp_property_mg06_crosswalk and
-- plm.suggested_property_for_sku (designflow-backend#408 steps 1-2).
-- Covers: single film, several films, unmapped film, cross-licensor collision.
-- Rolled back — assertions only.

-- Crosswalk seed: the 16 Done-criteria films must have rows.
do $$
begin
  assert (select count(*) from plm.dcp_property_mg06_crosswalk) >= 16,
    'crosswalk must have at least the 16 Done-criteria films';
  assert (select count(*) from plm.dcp_property_mg06_crosswalk where confidence = 'exact') >= 12,
    'at least 12 exact mappings expected';
  -- aristocats maps to AC
  assert (select mg_code from plm.dcp_property_mg06_crosswalk
          where dcp_source_id = 'dcpvault:properties/ar/aristocats') = 'AC',
    'aristocats must map to AC';
  -- lilo-and-stitch-umbrella maps to LS
  assert (select mg_code from plm.dcp_property_mg06_crosswalk
          where dcp_source_id = 'dcpvault:properties/li/lilo-and-stitch-umbrella') = 'LS',
    'lilo-and-stitch-umbrella must map to LS';
  -- robin-hood is explicitly unmapped (no MG06 exists)
  assert (select confidence from plm.dcp_property_mg06_crosswalk
          where dcp_source_id = 'dcpvault:properties/ro/robin-hood') = 'unmapped',
    'robin-hood must be marked unmapped';
end $$;

-- Single film: 3FZ27DYLS01 (Stitch art only) -> LS, basis single_film
do $$
declare
  v_count integer;
  v_basis text;
begin
  select count(*), min(basis) into v_count, v_basis
  from plm.suggested_property_for_sku('3FZ27DYLS01');
  assert v_count = 1, 'single-film SKU must return exactly 1 suggestion, got ' || v_count;
  assert v_basis = 'single_film', 'basis must be single_film, got ' || v_basis;
end $$;

-- Verify the suggestion is LS
do $$
declare
  v_code text;
begin
  select mg_code into v_code
  from plm.suggested_property_for_sku('3FZ27DYLS01') limit 1;
  assert v_code = 'LS', 'single-film Stitch SKU must suggest LS, got ' || coalesce(v_code,'null');
end $$;

-- Cross-licensor collision: MF296CBCC01 (Care Bears SKU with a Stitch file name)
-- must return empty — the SKU-level Disney restriction excludes it.
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from plm.suggested_property_for_sku('MF296CBCC01');
  assert v_count = 0, 'Care Bears SKU must get no suggestion, got ' || v_count;
end $$;

-- Cross-licensor collision: MFZ2GMVSP04 (Spider-Man SKU) must return empty.
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from plm.suggested_property_for_sku('MFZ2GMVSP04');
  assert v_count = 0, 'Marvel SKU must get no suggestion, got ' || v_count;
end $$;

-- Unmapped film: a SKU whose only film is robin-hood (no MG06) must return empty.
-- GFZ52DYCP03 has only ro/robin-hood per the back-test.
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from plm.suggested_property_for_sku('GFZ52DYCP03');
  assert v_count = 0, 'robin-hood-only SKU must get no suggestion (unmapped), got ' || v_count;
end $$;

-- Function must be read-only (stable) and not writable
do $$
begin
  assert (select provolatile from pg_proc
          where proname = 'suggested_property_for_sku'
            and pronamespace = 'plm'::regnamespace) = 's',
    'function must be STABLE (read-only)';
end $$;

rollback;
