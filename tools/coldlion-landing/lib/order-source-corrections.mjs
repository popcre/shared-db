/** Source-specific OrderList corrections travel with the immutable source ref.
 * No SKU-wide alias is inferred. Changed source cells invalidate the decision.
 */
export function correctionExpressions({ metadata = "r.metadata", sourceId = "r.source_id", sku, po }) {
  const c = `(${metadata} -> 'orderlist_source_correction')`;
  const valid = `(${c}->>'version' = '1'
    and ${c}->>'source_id' = ${sourceId}
    and ${c}->>'original_sku' = ${sku}
    and ${c}->>'original_customer_po' is not distinct from ${po}
    and nullif(btrim(${c}->>'canonical_sku'), '') is not null
    and nullif(btrim(${c}->>'canonical_customer_po'), '') is not null
    and nullif(btrim(${c}->>'evidence_ref'), '') is not null)`;
  return {
    valid,
    sku: `case when ${valid} then ${c}->>'canonical_sku' else ${sku} end`,
    po: `case when ${valid} then ${c}->>'canonical_customer_po' else ${po} end`,
  };
}

/** Read-only refusal before any writer work. Source observations stay untouched. */
export function buildSourceCorrectionPreflightSql() {
  const correction = correctionExpressions({ sku: "s.sku", po: "s.po_number" });
  return `do $source_corrections$
begin
  if exists (
    with corrected as materialized (
      select r.* from plm.production_order_line_source_ref r
      where r.source_system = 'coldlion' and r.metadata ? 'orderlist_source_correction'
    ), versions as (
      select l.*, rank() over (partition by l.sales_order_no,l.sales_order_line_no
        order by run.started_at desc nulls last,l.last_seen_run desc) observation_rank
      from coldlion.intake_order_line l
      left join coldlion.sync_run run on run.id=l.last_seen_run
      where exists (select 1 from corrected r
        where r.source_id ~ '^coldlion:so:[0-9]+:line:[0-9]+:component:[0-9]+$'
          and l.sales_order_no=split_part(r.source_id,':',3)::bigint
          and l.sales_order_line_no=split_part(r.source_id,':',5)::integer)
    ), staged as (
      select distinct l.sales_order_no,l.sales_order_line_no,l.master_item_no,l.po_number,
        nullif(c.sub_item_no,'') sub_item_no,nullif(c.sub_label_code,'') sub_label_code,
        coalesce(nullif(btrim(c.sub_item_no),''),l.master_item_no) sku
      from versions l join coldlion.intake_order_component c on c.line_id=l.id
      where l.observation_rank=1 and l.division_code is distinct from 'EP001'
    )
    select 1 from corrected r left join staged s
      on s.sales_order_no=split_part(r.source_id,':',3)::bigint
      and s.sales_order_line_no=split_part(r.source_id,':',5)::integer
      and s.master_item_no=r.metadata->>'master_item_no'
      and s.sub_item_no is not distinct from nullif(r.metadata->>'sub_item_no','')
      and s.sub_label_code is not distinct from nullif(r.metadata->>'sub_label_code','')
    where ${correction.valid} is not true
  ) then
    raise exception 'OrderList source correction no longer matches the latest source; held without changes. Review its source ID and original SKU/customer PO.';
  end if;
end;
$source_corrections$;`;
}
