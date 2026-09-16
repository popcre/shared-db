-- Issue #3091: Production Tracking step 4 - persisted milestone schedule.
-- derived-from: none
--
-- designflow-tracking computes a needed-by date per production-order milestone
-- and currently discards it. Overdue alerts need a durable, de-duplicable copy.
-- Additive only; rows are application data written by designflow-tracking.
--
-- plm."ProdOrderHeader" is keyed by "prodOrderNo"; its identity column id has no
-- unique constraint, so a foreign key to id first needs a unique index on id.

BEGIN;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM plm."ProdOrderHeader" GROUP BY id HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION 'plm."ProdOrderHeader".id holds duplicate values; cannot add a unique index (#3091)';
  END IF;
END $$;

CREATE UNIQUE INDEX prod_order_header_id_key ON plm."ProdOrderHeader" (id);

CREATE TABLE plm.prod_order_milestone_schedule (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  prod_order_header_id integer NOT NULL
    REFERENCES plm."ProdOrderHeader"(id) ON DELETE CASCADE,
  sku text NOT NULL DEFAULT '',
  stage_name text NOT NULL,
  needed_date date,
  estimated_date date,
  actual_date date,
  status text NOT NULL,
  anchor_type text,
  anchor_date date,
  factory_time_id integer
    REFERENCES plm."FactoryTime"(id) ON DELETE SET NULL,
  sampling_days integer,
  mass_production_days integer,
  template_source text,
  computed_at timestamptz NOT NULL DEFAULT now(),
  first_past_due_at timestamptz,
  CONSTRAINT prod_order_milestone_schedule_stage_name_not_blank_check
    CHECK (btrim(stage_name) <> ''),
  CONSTRAINT prod_order_milestone_schedule_status_not_blank_check
    CHECK (btrim(status) <> ''),
  CONSTRAINT prod_order_milestone_schedule_days_nonnegative_check
    CHECK (
      (sampling_days IS NULL OR sampling_days >= 0)
      AND (mass_production_days IS NULL OR mass_production_days >= 0)
    )
);

CREATE UNIQUE INDEX prod_order_milestone_schedule_upsert_key
  ON plm.prod_order_milestone_schedule (prod_order_header_id, stage_name, sku);

CREATE INDEX prod_order_milestone_schedule_status_needed_idx
  ON plm.prod_order_milestone_schedule (status, needed_date);

COMMENT ON TABLE plm.prod_order_milestone_schedule IS
  'Persisted Production Tracking milestone schedule: one row per production order, stage and SKU (empty SKU for order-level stages). Written by designflow-tracking (#3091).';
COMMENT ON COLUMN plm.prod_order_milestone_schedule.sku IS
  'SKU for licensing stages; empty string for order-level stages so the upsert key is plain columns.';
COMMENT ON COLUMN plm.prod_order_milestone_schedule.factory_time_id IS
  'Lead-time template used; null means no template applied.';
COMMENT ON COLUMN plm.prod_order_milestone_schedule.template_source IS
  'Human-readable template source text, or "no template".';
COMMENT ON COLUMN plm.prod_order_milestone_schedule.computed_at IS
  'Set on every upsert by the writer.';
COMMENT ON COLUMN plm.prod_order_milestone_schedule.first_past_due_at IS
  'Set once when the milestone first becomes past due; the writer never overwrites it.';

-- Same access model as sibling plm tracking tables: the DesignFlow API connects
-- as the table owner. No browser or service-role access.
ALTER TABLE plm.prod_order_milestone_schedule ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE plm.prod_order_milestone_schedule FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
