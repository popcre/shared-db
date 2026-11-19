-- Live proof for #4064 (migration 20261008004417). Read-only.
-- Proves on production: the migration is in the ledger, the function exists as SECURITY
-- INVOKER with an empty search_path, and only service_role (not anon/authenticated) may
-- execute it. Out of scope for this read-only probe: atomicity under concurrency (shown by
-- the contract design and the app-side prover in u2giants/popdam3 scripts/shared-db-live-proof.mjs)
-- and the popdam3 caller.
select (
  exists (select 1 from supabase_migrations.schema_migrations where version = '20261008004417')
  and to_regprocedure('public.admin_config_apply_counters(text,jsonb,jsonb)') is not null
  and exists (select 1 from pg_proc p
              where p.oid = to_regprocedure('public.admin_config_apply_counters(text,jsonb,jsonb)')
                and not p.prosecdef
                and coalesce(p.proconfig @> array['search_path=""']::text[], false))
  and has_function_privilege('service_role', 'public.admin_config_apply_counters(text,jsonb,jsonb)', 'execute')
  and not has_function_privilege('anon', 'public.admin_config_apply_counters(text,jsonb,jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'public.admin_config_apply_counters(text,jsonb,jsonb)', 'execute')
) as passed;
