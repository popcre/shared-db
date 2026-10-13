-- Rolled-back structural contracts for issue #4150: the four ColdLion /orderHistory
-- stamps on coldlion.order_history_line, nullable, typed, and read as New York time.
begin;

do $$
declare
  v_count integer;
  v_comment text;
begin
  select count(*) into v_count
  from pg_attribute a
  where a.attrelid = 'coldlion.order_history_line'::regclass
    and a.attnum > 0 and not a.attisdropped and not a.attnotnull and not a.atthasdef
    and ((a.attname in ('created_time','mod_time') and a.atttypid = 'timestamptz'::regtype)
      or (a.attname in ('created_user','mod_user') and a.atttypid = 'text'::regtype));
  if v_count <> 4 then
    raise exception 'order_history_line carries % of 4 nullable, default-free stamp columns', v_count;
  end if;

  v_comment := col_description('coldlion.order_history_line'::regclass,
    (select attnum from pg_attribute where attrelid = 'coldlion.order_history_line'::regclass and attname = 'created_time'));
  if v_comment is null or v_comment not like '%America/New_York%' or v_comment like '%landed as UTC%' then
    raise exception 'created_time comment does not state the New York reading';
  end if;

  -- The acceptance example: 2026-05-05 16:25:21.159 New York (EDT) is 20:25:21.159 UTC.
  if ('2026-05-05 16:25:21.159'::timestamp at time zone 'America/New_York')
     <> '2026-05-05 20:25:21.159+00'::timestamptz then
    raise exception 'America/New_York reading of the acceptance example is wrong';
  end if;
end $$;

rollback;
