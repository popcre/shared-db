-- Issue #3498: final plm homes for two DesignFlow tables added after the July
-- segregation map (docs PR #3497; owner request 2026-09-24).
-- derived-from: 20260901221310, 20260904143518, 20260905053422, 20260907121732
--
-- Additive only. Structure only; row movement belongs to the DesignFlow
-- migration session. Column shapes match the dflow sources (types, nullability,
-- defaults; column order differs on item_workflow_action where actor_identity_*
-- were appended last in dflow). Cross-schema foreign keys into dflow.users are
-- deliberately omitted so the plm homes do not couple to the landing schema;
-- referential integrity for those is wired when rows move. Intra-plm foreign
-- keys are included. All six source indexes are deferred because this claim
-- writes exactly the two tables (each index would add an index object key):
--   item_user_assignment_one_active (partial unique, integrity invariant)
--   item_user_assignment_active_lookup
--   item_workflow_action_item_time
--   item_workflow_action_one_return_per_source (partial unique, integrity invariant)
--   item_workflow_action_open_handoff_lookup
--   item_workflow_action_admin_review
-- The two partial-unique indexes enforce invariants and must land before any
-- rows are inserted.  Append-only enforcement (row triggers) is deferred with
-- the indexes; the COMMENTs below note it is not yet enforced.

BEGIN;

CREATE TABLE plm.item_user_assignment (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  rfq_item_id integer NOT NULL REFERENCES plm."RFQItem"("rfqItem_id") ON DELETE CASCADE,
  function_key text NOT NULL,
  user_id integer NOT NULL,
  assigned_by_user_id integer NOT NULL,
  effective_from timestamptz NOT NULL DEFAULT clock_timestamp(),
  effective_to timestamptz,
  assignment_context jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT item_user_assignment_function_key_shape_check
    CHECK (function_key = lower(btrim(function_key)) AND function_key ~ '^[a-z][a-z0-9_-]*$'),
  CONSTRAINT item_user_assignment_effective_window_check
    CHECK (effective_to IS NULL OR effective_to > effective_from),
  CONSTRAINT item_user_assignment_context_object_check
    CHECK (jsonb_typeof(assignment_context) = 'object')
);

COMMENT ON TABLE plm.item_user_assignment IS
  'Final plm item-master home for dflow.item_user_assignment (issue #3498). Item function-role assignment history. Column shapes match the dflow source; row movement is a separate DesignFlow migration. Indexes and append-only enforcement are deferred to the wiring session. Beside productUserAssignment in the item-master group.';

CREATE TABLE plm.item_workflow_action (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  rfq_item_id integer NOT NULL REFERENCES plm."RFQItem"("rfqItem_id") ON DELETE RESTRICT,
  actor_user_id integer NOT NULL,
  actor_auth_user_id uuid,
  actor_identity_source text NOT NULL DEFAULT
    (case
       when nullif(pg_catalog.current_setting('request.designflow.actor_id', true), '') is not null
         then 'designflow_jwt'
       else 'supabase_auth'
     end),
  actor_identity_email text DEFAULT
    (pg_catalog.lower(nullif(pg_catalog.btrim(
       coalesce(
         nullif(pg_catalog.current_setting('request.designflow.actor_email', true), ''),
         auth.jwt() ->> 'email'
       )
     ), ''))),
  prior_step_id integer REFERENCES plm."RFQStep"("RFQStep_id"),
  new_step_id integer NOT NULL REFERENCES plm."RFQStep"("RFQStep_id"),
  action_key text NOT NULL,
  correlation_key uuid NOT NULL,
  routing_context jsonb NOT NULL DEFAULT '{}'::jsonb,
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  source_action_id bigint,
  fallback_recipient_user_id integer,
  fallback_reason text,
  requires_admin_review boolean NOT NULL DEFAULT false,
  CONSTRAINT item_workflow_action_id_rfq_item_key UNIQUE (id, rfq_item_id),
  CONSTRAINT item_workflow_action_source_action_id_fkey
    FOREIGN KEY (source_action_id, rfq_item_id)
    REFERENCES plm.item_workflow_action(id, rfq_item_id)
    ON DELETE RESTRICT,
  CONSTRAINT item_workflow_action_correlation_key_key UNIQUE (correlation_key),
  CONSTRAINT item_workflow_action_action_key_shape_check
    CHECK (action_key = lower(btrim(action_key)) AND action_key ~ '^[a-z][a-z0-9_-]*$'),
  CONSTRAINT item_workflow_action_routing_context_object_check
    CHECK (jsonb_typeof(routing_context) = 'object'),
  CONSTRAINT item_workflow_action_source_action_not_self
    CHECK (source_action_id IS NULL OR source_action_id <> id),
  CONSTRAINT item_workflow_action_fallback_is_labeled
    CHECK (
      (fallback_recipient_user_id IS NULL AND fallback_reason IS NULL)
      OR (fallback_recipient_user_id IS NOT NULL
          AND fallback_reason IS NOT NULL
          AND btrim(fallback_reason) <> ''
          AND source_action_id IS NOT NULL)
    ),
  CONSTRAINT item_workflow_action_actor_provenance
    CHECK (
      (actor_identity_source = 'supabase_auth' AND actor_auth_user_id IS NOT NULL)
      OR (actor_identity_source = 'designflow_jwt'
          AND actor_auth_user_id IS NULL
          AND actor_identity_email IS NOT NULL)
    ),
  CONSTRAINT item_workflow_action_return_names_its_source
    CHECK (
      routing_context ->> 'return_to_original_handoff' IS DISTINCT FROM 'true'
      OR source_action_id IS NOT NULL
    )
);

COMMENT ON TABLE plm.item_workflow_action IS
  'Final plm item-master home for dflow.item_workflow_action (issue #3498). Workflow action history (append-only not yet enforced; triggers deferred to the wiring session). Column shapes match the dflow source; column order differs where actor_identity_* were appended last in dflow. Row movement is a separate DesignFlow migration. Item-master group.';

ALTER TABLE plm.item_user_assignment ENABLE ROW LEVEL SECURITY;
ALTER TABLE plm.item_workflow_action ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE plm.item_user_assignment FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE plm.item_workflow_action FROM PUBLIC, anon, authenticated, service_role;

-- Catalogue-only verification: assert the two relations landed with RLS on and
-- the deny-all revoke in place (issue #3498).
DO $verify$
DECLARE
  ok boolean;
BEGIN
  SELECT relrowsecurity INTO ok FROM pg_class WHERE oid = 'plm.item_user_assignment'::regclass;
  IF NOT ok THEN RAISE EXCEPTION 'plm.item_user_assignment: RLS not enabled'; END IF;
  SELECT relrowsecurity INTO ok FROM pg_class WHERE oid = 'plm.item_workflow_action'::regclass;
  IF NOT ok THEN RAISE EXCEPTION 'plm.item_workflow_action: RLS not enabled'; END IF;
  IF has_table_privilege('anon', 'plm.item_user_assignment', 'SELECT') THEN
    RAISE EXCEPTION 'plm.item_user_assignment: anon still has SELECT';
  END IF;
  IF has_table_privilege('anon', 'plm.item_workflow_action', 'SELECT') THEN
    RAISE EXCEPTION 'plm.item_workflow_action: anon still has SELECT';
  END IF;
END
$verify$;

COMMIT;
