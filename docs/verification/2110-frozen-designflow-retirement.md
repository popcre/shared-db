# Frozen DesignFlow retirement — issue 2110

Albert's September 6 retirement decision, preserved in issue 2110, explicitly
authorizes removing the frozen schema and repointing its two inbound foreign
keys to live `dflow` parents. No child or live-parent row is changed.

## Admission evidence

Read-only production admission was reverified September 20 using
`supabase_read_only_user` with `transaction_read_only=on`. The target was
independently identified using the Supabase connection URL. The seven table
and nine sequence names, old constraint properties and archived row inventory
are enforced in the migration, rather than trusted from this document.

All frozen art identities agree with the live parents except historical
`art_source_id`, `updated_at` and `updated_by`. Source dictionary codes and
descriptions also differ: these are real historical metadata differences, not
an assertion that all fields are identical. The migration never copies those
values into live parents. Referenced roles agree on every frozen column; live
roles additionally have `app_role_id`. The child counts are compared within
the locked transaction. The committed live proof checks the resulting validated
parent relationships and absence of orphan children.

The original rejected Grok review
`.ai/reviews/grok-orphan-designflow-repoint-20260827T152007Z-1390799.md`
could not be recovered from the available machine. Its absence is not approval.
Fresh independent reviews must assess semantic repointing and recovery before
preview/merge. Current consumer searches and the actual production Item Master
deployment found no frozen-schema use; they are not an exhaustive guarantee
about every dynamic or external consumer.

## Protected recovery material

The original backup is the 1Password Document `zepc66j5xajdg4novzttmmrtg4`
in `vibe_coding`. Its byte-level SHA-256 is
`916be84f738eee32ec2d70020c80dbe1f75fa788fc3f96007410b9d81f50eb72`.
The in-memory retrieval verified all COPY sections and the completed dump
marker. Never commit the backup or print its rows.

A prior isolated PostgreSQL 18 rehearsal restored the archive after redacting
contact values before insertion and omitting eighteen external foreign keys.
It verified data and internal constraints, **not full-system recovery**. The
protected local rehearsal is stopped; its files remain preserved because
automatic cleanup was refused. Do not retry or bypass that cleanup refusal.

Recovery after a committed retirement requires a separately reviewed forward
migration. Retrieve the protected document directly into a protected process;
verify its fingerprint; redact artist emails and every prohibited contact field
before insertion; recreate its external dependencies and revalidate the eighteen
external foreign keys; restore definitions under the frozen schema rather than
overwriting live `dflow`; verify archived identities and internal constraints;
then, only if recovery explicitly calls for it, repoint the two inbound keys
under locks and validate. Never replay the raw dump or restore contact values.
The vault copy intentionally retains the historical original, outside the
application database. Missing external dependencies stop recovery for engineering.

## Delivery gates

Local validation on September 20: the isolated synthetic PostgreSQL regression
passed ten tests with zero failures or skips. It exercises successful retirement
with unchanged child counts, unknown tables/sequences/dependencies, external
routine text references, changed
parent identity, missing live parents, changed foreign-key actions, archived
row-count drift and transactional rollback after a late RESTRICT refusal.
The cluster was stopped. SQL static checks and live-proof shape validation also
passed. Static checks did not read a live migration ledger; the preview lane
must independently perform that live check.

The current preview target was resolved independently from the repository
variable and protected configuration. A September 20 read-only transaction
confirmed that its archived table and child row inventories match production,
so no backup import or contact restoration is needed for preview rehearsal.

Preview application, fresh independent review, generated types from the existing
preview-only `Generate database types` workflow, guarded merge and production
promotion remain separate gates. This document does not claim any ran.
The destructive promotion gate may require independent engineering approval;
no manual production dispatch is authorized by authoring this migration.
