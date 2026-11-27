-- Read-only live proof for issue #4150: the four ColdLion stamp columns exist on
-- production coldlion.order_history_line, and SO 7127837 (start 2026-07-06) carries
-- ColdLion's order-details createdTime 2026-05-05 16:25:21 read as America/New_York.
select
  (select count(*) from pg_attribute a
    where a.attrelid = 'coldlion.order_history_line'::regclass and not a.attisdropped
      and ((a.attname in ('created_time','mod_time') and a.atttypid = 'timestamptz'::regtype)
        or (a.attname in ('created_user','mod_user') and a.atttypid = 'text'::regtype))) = 4
  and exists (select 1 from coldlion.order_history_line
    where sales_order_no = 7127837
      and date_trunc('second', created_time at time zone 'America/New_York') = timestamp '2026-05-05 16:25:21')
  and not exists (select 1 from coldlion.order_history_line
    where sales_order_no = 7127837
      and (created_time is null
        or date_trunc('second', created_time at time zone 'America/New_York') <> timestamp '2026-05-05 16:25:21'))
  as passed;
