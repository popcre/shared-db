-- shared-db#4373, claim #4374: per-order Linesheet choice for Stage Catalog.
-- derived-from: none
-- Additive server-owned state. Existing orders read false when no row exists.
-- No foreign key to the sync-owned ProdOrderHeader; identifiers match its int key.
-- Rollback: drop table plm.prod_stage_option after its application reader is retired.
create table plm.prod_stage_option (
  prod_order_header_id integer primary key,
  needs_linesheet boolean not null default false,
  updated_by integer null,
  updated_at timestamptz not null default now()
);
alter table plm.prod_stage_option enable row level security;
revoke all on plm.prod_stage_option from anon, authenticated;
grant select, insert, update, delete on plm.prod_stage_option to service_role;
comment on table plm.prod_stage_option is 'DesignFlow Stage Catalog per-order choices. Linesheet eligibility still comes from licensor_stage_option; this flag records whether this order needs it. Internal production permissions enforced by tracking API. shared-db#4373.';
