-- #6657 read-only acceptance: the PopSG worker can still execute, while
-- signed-in PopDAM and CRM callers retain their existing access.
with worker_routines(signature) as (
  values
    ('public.get_style_guide_deterministic_tag_batch(uuid,integer,boolean)'),
    ('public.replace_style_guide_deterministic_tags(uuid,jsonb,text,text)'),
    ('public.replace_style_guide_folder_consensus_tags(uuid,jsonb,text)')
),
caller_routines(signature) as (
  values
    ('public.resolve_coldlion_triage(uuid,text,uuid)'),
    ('api.crm_overview_counts()'),
    ('api.crm_overview_email_counts()'),
    ('api.crm_overview_email_volume(integer)'),
    ('api.crm_overview_pending_approvals(integer)'),
    ('api.crm_overview_pipeline_stages()'),
    ('api.crm_overview_recent_meetings(integer)'),
    ('api.crm_overview_recent_unrouted(integer)')
)
select (
  select bool_and(
    coalesce(has_function_privilege('service_role', to_regprocedure(signature), 'execute'), false)
    and has_function_privilege('authenticated', to_regprocedure(signature), 'execute') is false
    and has_function_privilege('anon', to_regprocedure(signature), 'execute') is false
    and has_function_privilege('public', to_regprocedure(signature), 'execute') is false
  )
  from worker_routines
) and (
  select bool_and(
    coalesce(has_function_privilege('authenticated', to_regprocedure(signature), 'execute'), false)
    and has_function_privilege('anon', to_regprocedure(signature), 'execute') is false
  )
  from caller_routines
) as passed;
