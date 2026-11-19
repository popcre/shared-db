-- Drop the pre-batch 15-argument api.crm_update_contact overload, freeing
-- the name for the approved 18-argument shape from 20261225010404 (same
-- batch). Marker-free by design: this file is applied after 20261225010404
-- re-created the name, so no retired-object restoration declaration is needed
-- on any database (popcrm-web #39; claim popcre/shared-db#6820). Version
-- 20261225010405 reserved atomically (refs/db-claims).
--
-- Preview: no-op (the overload was already dropped there). Production:
-- removes the pre-batch overload in the same transaction that added the
-- clear-field shape, so the two overloads never coexist and no named call is
-- ever ambiguous.
--
-- derived-from: none

drop function if exists api.crm_update_contact(
  uuid, text, text, text, text, text, text, uuid, uuid, text, text,
  boolean, boolean, boolean, boolean
);
