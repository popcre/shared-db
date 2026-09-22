SELECT to_regnamespace('designflow_frozen_20260710') IS NULL
  AND (SELECT count(*) FROM pg_constraint WHERE contype='f' AND convalidated AND (
    (conrelid='app."RolePermissions"'::regclass AND conname='RolePermissions_RoleId_fkey' AND confrelid='dflow."Roles"'::regclass) OR
    (conrelid='plm.art_piece_attachment'::regclass AND conname='art_piece_attachment_art_piece_id_fkey' AND confrelid='dflow.art_piece'::regclass)))=2
  AND NOT EXISTS (SELECT FROM plm.art_piece_attachment c LEFT JOIN dflow.art_piece p ON p.id=c.art_piece_id WHERE p.id IS NULL)
  AND NOT EXISTS (SELECT FROM app."RolePermissions" c LEFT JOIN dflow."Roles" p ON p."Id"=c."RoleId" WHERE p."Id" IS NULL)
  as passed;
