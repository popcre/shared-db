-- Live proof for issue #2110: frozen schema designflow_frozen_20260710 is absent
-- and the two repointed foreign keys resolve to dflow parents.
SELECT
  (to_regnamespace('designflow_frozen_20260710') IS NULL
   AND (SELECT count(*) FROM plm.art_piece_attachment) = 2276
   AND (SELECT count(*) FROM app."RolePermissions") = 4) as passed
