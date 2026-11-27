-- Issue https://github.com/popcre/shared-db/issues/7200: approval numbers read from licensor submission confirmation PDFs.
--
-- Owner request, Albert Hazan, 2026-11-27. Every licensor portal prints its own
-- approval/submission number under a different name (or none), so the value and the
-- name printed beside it are stored separately. Additive and nullable: earlier
-- captures keep nulls; rows stay immutable and a new capture carries the values.
-- NO LICENSED VALUES ARE IN THIS FILE; rows are application data.
alter table plm.licensor_submission_pdf
  add column approval_number text,
  add column approval_number_label text,
  add column approval_stage text,
  add column approval_status text,
  add column contract_number text;

comment on column plm.licensor_submission_pdf.approval_number is
  'The licensor''s own approval/submission number for this style, as printed (Disney Ref, Brand Assurance #, Project Number, Component #, Submission #, Item, Article SKU, or an unlabeled number).';
comment on column plm.licensor_submission_pdf.approval_number_label is
  'What the licensor calls the approval number on this page; "(unlabeled box)" or "(unlabeled, before SKU)" when the page gives it no name.';
comment on column plm.licensor_submission_pdf.approval_stage is
  'Approval stage printed on the page (for example Concept, Pre-Production, Sculpt), when the portal shows one.';
comment on column plm.licensor_submission_pdf.approval_status is
  'Approval status printed on the page (for example Proceed to Production, Final Approval), when the portal shows one.';
comment on column plm.licensor_submission_pdf.contract_number is
  'Licence contract number printed on the page, when shown.';

create index licensor_submission_pdf_approval_number_idx
  on plm.licensor_submission_pdf (approval_number) where approval_number is not null;
