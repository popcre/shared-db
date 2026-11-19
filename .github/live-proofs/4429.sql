-- Issue #4429 installed-catalog proof, READ ONLY.
WITH wrapped AS (
  select count(*) as n from pg_policies
  where schemaname = 'public'
    and (schemaname, tablename, policyname) in (
      ('public','style_guide_file_tags','style_guide_file_tags_read'),
      ('public','style_guide_tag_aliases','style_guide_tag_aliases_read'),
      ('public','style_guide_tagging_state','style_guide_tagging_state_read'),
      ('public','style_guide_tags','style_guide_tags_read')
    )
    and qual like '%( SELECT has_app_access(%'
)
select (w.n = 4) as passed from wrapped w;
