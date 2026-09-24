-- Live proof for #3043 (migration 20260916120643, #3027 Step 1 canary). Read-only.
-- Proves: the migration is in production's ledger; column
-- plm.production_lane_canary.step1_acceptance_note exists as nullable text;
-- the canary table still holds exactly 1 row.
select (
  exists (select 1 from supabase_migrations.schema_migrations where version = '20260916120643')
  and exists (
    select 1 from information_schema.columns
    where table_schema = 'plm' and table_name = 'production_lane_canary'
      and column_name = 'step1_acceptance_note' and data_type = 'text' and is_nullable = 'YES'
  )
  and (select count(*) from plm.production_lane_canary) = 1
) as passed
