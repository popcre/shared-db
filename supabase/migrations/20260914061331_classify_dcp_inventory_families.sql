-- Issue #2879: classify the Lucasfilm and 20th Century DCP landing families in
-- both source-inventory contracts. This changes catalog definitions only.
-- No source rows or DB Data Admin listing behavior are changed.
-- derived-from: 20260910155753

do $migration$
declare
  v_function text;
  v_view text;
  v_anchor text := 'when c.relname like ''marvel\_%'' then ''marvel''';
  v_replacement text := 'when c.relname like ''lucasfilm\_dcp\_%'' then ''lucasfilm_dcpvault''
      when c.relname like ''twentieth_century\_dcp\_%'' then ''twentieth_century_dcpvault''
      when c.relname like ''marvel\_%'' then ''marvel''';
begin
  v_function := pg_get_functiondef(
    'api.source_capture_inventory_exact(text)'::regprocedure);
  v_view := pg_get_viewdef('api.source_capture_inventory'::regclass, true);

  if (length(v_function)-length(replace(v_function,v_anchor,''))) / length(v_anchor) <> 1
     or (length(v_view)-length(replace(v_view,v_anchor,''))) / length(v_anchor) <> 1 then
    raise exception using errcode='55000',
      message='#2879: source-inventory predecessor classification differs';
  end if;

  v_function := replace(v_function, v_anchor, v_replacement);
  v_view := replace(v_view, v_anchor, v_replacement);

  if position('when c.relname like ''lucasfilm\_dcp\_%'' then ''lucasfilm_dcpvault''' in v_function)=0
     or position('when c.relname like ''twentieth_century\_dcp\_%'' then ''twentieth_century_dcpvault''' in v_function)=0
     or position('when c.relname like ''lucasfilm\_dcp\_%'' then ''lucasfilm_dcpvault''' in v_view)=0
     or position('when c.relname like ''twentieth_century\_dcp\_%'' then ''twentieth_century_dcpvault''' in v_view)=0 then
    raise exception using errcode='55000',
      message='#2879: source-inventory classification postconditions failed';
  end if;

  execute v_function;
  execute 'create or replace view api.source_capture_inventory as ' || v_view;
end
$migration$;

do $verify$
declare
  v_function text;
  v_view text;
begin
  v_function := pg_get_functiondef(
    'api.source_capture_inventory_exact(text)'::regprocedure);
  v_view := pg_get_viewdef('api.source_capture_inventory'::regclass, true);
  if position('lucasfilm_dcpvault' in v_function)=0
     or position('twentieth_century_dcpvault' in v_function)=0
     or position('lucasfilm_dcpvault' in v_view)=0
     or position('twentieth_century_dcpvault' in v_view)=0 then
    raise exception '#2879: both inventory definitions must retain both DCP family mappings';
  end if;
end
$verify$;
