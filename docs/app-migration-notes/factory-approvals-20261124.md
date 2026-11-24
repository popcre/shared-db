# Factory customer approvals (issue #7070)

Shared-db objects: `core.factory_approval` (one row per factory × program:
disney, dollar_general, nbcu, walmart), `core.factory_approval_form` (full
history of Disney FAMA / NBCU LMS PDFs), bucket `factory-approval-forms`,
view `core.factory_approval_renewal_due`, role `production`.

Application work still needed:

- **Vendor screen (PLM/DesignFlow):** Yes/No per program, approved name,
  facility/LMS number and expiry; manual edits write `core.factory_approval`
  (licensing, production, administrator). Upload: put the PDF in the bucket,
  then insert `core.factory_approval_form (factory_id, program, storage_path, file_name)`.
  Show the form history list.
- **Indra OCR worker (PopDAM agent-api):** service role calls
  `core.claim_factory_approval_form_ocr(limit)`, downloads each PDF, OCRs with
  Indra, extracts name, number (NBCU usually `L` + 4 digits) and expiry, then
  calls `core.record_factory_approval_form_ocr(form_id, text, name, number, expires_on, error)`.
  The newest processed form updates the approval automatically.
- **Reminders:** daily cron `factory-approval-renewal-reminders` writes
  `app.notification` rows (app `plm`) to every licensing and production user,
  once per expiry date, 42 days before expiry. Email delivery, if wanted, reads
  those rows.
- Assign the new `production` role to the production team members.
