-- Issue #4428 installed-catalog proof, READ ONLY.
-- Proves 17 ownership policies wrap auth.uid() as a scalar InitPlan.
WITH wrapped AS (
  select count(*) as n from pg_policies
  where schemaname = 'public'
    and tablename in (
      'app_access','asset_checkouts','helper_devices','helper_tokens',
      'order_list_user_views','profiles','style_tracker_user_views'
    )
    and (qual like '%( SELECT auth.uid() AS uid)%' or with_check like '%( SELECT auth.uid() AS uid)%')
), total AS (
  select count(*) as n from pg_policies
  where schemaname = 'public'
    and tablename in (
      'app_access','asset_checkouts','helper_devices','helper_tokens',
      'order_list_user_views','profiles','style_tracker_user_views'
    )
)
select (w.n >= 17) as passed
from wrapped w, total t;
