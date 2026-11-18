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
    p.oid is not null
    and p.prosecdef is true
    and position('auth.role() <> ''service_role''' in lower(p.prosrc)) > 0
    and has_function_privilege('service_role', p.oid, 'execute') is true
    and has_function_privilege('postgres', p.oid, 'execute') is true
    and has_function_privilege('supabase_admin', p.oid, 'execute') is true
    and has_function_privilege('authenticated', p.oid, 'execute') is false
    and has_function_privilege('anon', p.oid, 'execute') is false
    and has_function_privilege('public', p.oid, 'execute') is false
  )
  from worker_routines r
  left join pg_catalog.pg_proc p on p.oid = to_regprocedure(r.signature)
) and (
  select bool_and(
    to_regprocedure(signature) is not null
    and has_function_privilege('authenticated', to_regprocedure(signature), 'execute') is true
    and has_function_privilege('anon', to_regprocedure(signature), 'execute') is false
  )
  from caller_routines
) as passed;
