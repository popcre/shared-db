-- u2giants/popdam3#1298 stage S2 (claim: popcre/shared-db#6993).
-- PopDAM now reads DesignFlow production orders through
-- api.dam_production_orders_for_sku (popcre/shared-db#6987) and no longer
-- copies them (u2giants/popdam3#1296), so its copy tables go. The two dam
-- snapshot placeholders were created in 20260621151024 and never written by
-- anything; two functions only tidy dam.production_order_snapshot, so those
-- statements are removed from the live definitions (nothing else changes).

do $$
declare
  v_def text;
  v_fn  text;
begin
  foreach v_fn in array array['public.clear_dam_buy_sheet_import', 'public.resolve_coldlion_triage'] loop
    v_def := pg_get_functiondef(v_fn::regproc);
    v_def := regexp_replace(v_def, E'\\n[ \\t]*delete from dam\\.production_order_snapshot[^;]*;', '', 'g');
    v_def := regexp_replace(v_def, E'\\n[ \\t]*update dam\\.production_order_snapshot[^;]*;', '', 'g');
    if position('production_order_snapshot' in v_def) > 0 then
      raise exception '% still references dam.production_order_snapshot; refusing to drop it', v_fn;
    end if;
    execute v_def;
  end loop;
end
$$;

drop table if exists public.prod_order_headers_raw;
drop table if exists public.prod_order_headers_current;
drop table if exists public.prod_order_sync_runs;
drop table if exists dam.production_order_snapshot;
drop table if exists dam.erp_item_snapshot;
