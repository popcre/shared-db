-- Live acceptance canary for #3027 Step 1 (popcre/ai-devops#401): one fully
-- machine-qualified automatic production promotion. Work issue #3043, claim #3044.
-- Catalog-only: replaces the descriptive comment on the no-op lane canary table
-- from #660. No data, grant, RLS, or application behaviour changes.
comment on table plm.production_lane_canary is 'No-op canary for the bounded production migration apply lane (issue #660). No application reads or writes this table. Do not extend it and do not build on it. Comment rewritten by migration 20260916120643 as the acceptance canary #3027 step 1 automatic production promotion.';
