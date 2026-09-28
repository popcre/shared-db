-- Issue #3400: stored HTS product phrase for CBP CROSS ruling search.
-- Additive only: nullable columns, no default, no backfill, no index.
-- Targets: plm (dev/staging) and dflow_prod (Supabase production cutover).
-- The application (popcre/designflow-backend#107) fills these values.
-- One column per statement so the production business-risk gate classifies
-- each as a catalog-only nullable add.
-- derived-from: none

alter table plm."itemHeader" add column if not exists hts_product_phrase text;
alter table plm."itemHeader" add column if not exists hts_product_phrase_source text;
alter table plm."itemHeader" add column if not exists hts_product_phrase_at timestamptz;

alter table plm."RFQItem" add column if not exists hts_product_phrase text;
alter table plm."RFQItem" add column if not exists hts_product_phrase_source text;
alter table plm."RFQItem" add column if not exists hts_product_phrase_at timestamptz;

alter table dflow_prod."itemHeader" add column if not exists hts_product_phrase text;
alter table dflow_prod."itemHeader" add column if not exists hts_product_phrase_source text;
alter table dflow_prod."itemHeader" add column if not exists hts_product_phrase_at timestamptz;

alter table dflow_prod."RFQItem" add column if not exists hts_product_phrase text;
alter table dflow_prod."RFQItem" add column if not exists hts_product_phrase_source text;
alter table dflow_prod."RFQItem" add column if not exists hts_product_phrase_at timestamptz;
