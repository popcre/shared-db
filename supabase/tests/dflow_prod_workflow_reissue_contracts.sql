-- Issue #2874: real replay and wrong-existing-object contracts.
-- Synthetic schema changes and all replacement DDL roll back.
begin;
set local search_path = pg_catalog;

-- Both calls must pass after the original and successor migrations have run.
\ir ../migrations/20261006235109_dflow_prod_backend_workflow_parity.sql
\ir ../migrations/20261006235109_dflow_prod_backend_workflow_parity.sql

savepoint missing_notification_fk;
alter table dflow_prod.user_notification
  drop constraint user_notification_workflow_action_id_fkey;
\set ON_ERROR_STOP off
\ir ../migrations/20261006235109_dflow_prod_backend_workflow_parity.sql
\set missing_fk_state :SQLSTATE
\set missing_fk_message :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint missing_notification_fk;
select :'missing_fk_state' = 'P0001'
  and :'missing_fk_message' = 'issue-2874 reissue refused: existing or resulting catalog differs from the exact canonical contract'
  as missing_fk_refused \gset
\if :missing_fk_refused
\else
  \echo 'Missing notification FK did not produce the exact reissue refusal.'
  \quit 1
\endif

savepoint wrong_assignment_shape;
alter table dflow_prod.item_user_assignment
  add constraint issue_2874_wrong_assignment_shape check (user_id > 0);
\set ON_ERROR_STOP off
\ir ../migrations/20261006235109_dflow_prod_backend_workflow_parity.sql
\set wrong_shape_state :SQLSTATE
\set wrong_shape_message :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint wrong_assignment_shape;
select :'wrong_shape_state' = 'P0001'
  and :'wrong_shape_message' = 'issue-2874 reissue refused: existing or resulting catalog differs from the exact canonical contract'
  as wrong_shape_refused \gset
\if :wrong_shape_refused
\else
  \echo 'Wrong assignment constraint did not produce the exact reissue refusal.'
  \quit 1
\endif

-- Each rejected attempt left the valid catalog intact.
\ir ../migrations/20261006235109_dflow_prod_backend_workflow_parity.sql
rollback;
