-- Issue #3498: final plm homes for two DesignFlow tables added after the July
-- segregation map (docs PR #3497; owner request 2026-09-24).
-- derived-from: dflow.item_user_assignment, dflow.item_workflow_action (live shapes)
--
-- Additive only. Structure only; row movement belongs to the DesignFlow
-- migration session. Column shapes match the dflow sources. Cross-schema
-- foreign keys into dflow.* are deliberately omitted so the plm homes do not
-- couple to the landing schema; referential integrity is wired when rows move.
-- Partial unique indexes from the dflow sources are also deferred: this claim
-- writes exactly the two tables.

BEGIN;

CREATE TABLE plm.item_user_assignment (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  rfq_item_id integer NOT NULL,
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
  'Final plm item-master home for dflow.item_user_assignment (issue #3498). Item function-role assignment history. Shape matches the dflow source; row movement is a separate DesignFlow migration. Beside productUserAssignment in the item-master group.';

CREATE TABLE plm.item_workflow_action (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  rfq_item_id integer NOT NULL,
  actor_user_id integer NOT NULL,
  actor_auth_user_id uuid,
  actor_identity_source text NOT NULL DEFAULT 'supabase_auth',
  actor_identity_email text,
  prior_step_id integer,
  new_step_id integer NOT NULL,
  action_key text NOT NULL,
  correlation_key uuid NOT NULL,
  routing_context jsonb NOT NULL DEFAULT '{}'::jsonb,
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  source_action_id bigint,
  fallback_recipient_user_id integer,
  fallback_reason text,
  requires_admin_review boolean NOT NULL DEFAULT false,
  CONSTRAINT item_workflow_action_id_rfq_item_key UNIQUE (id, rfq_item_id),
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
    )
);

COMMENT ON TABLE plm.item_workflow_action IS
  'Final plm item-master home for dflow.item_workflow_action (issue #3498). Append-only workflow action history. Shape matches the dflow source; row movement is a separate DesignFlow migration. Item-master group.';

ALTER TABLE plm.item_user_assignment ENABLE ROW LEVEL SECURITY;
ALTER TABLE plm.item_workflow_action ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE plm.item_user_assignment FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE plm.item_workflow_action FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
