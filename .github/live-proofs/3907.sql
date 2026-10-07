-- Read-only proof of the last three mapped DesignFlow user relationships.
SELECT (
  EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '20261007002113')
  AND (SELECT count(*) FROM (VALUES
    ('app."RolePermissions"', 'RolePermissions_UserId_fkey', 'UserId'),
    ('plm.art_piece_attachment', 'art_piece_attachment_created_by_fkey', 'created_by'),
    ('plm.art_piece_attachment', 'art_piece_attachment_updated_by_fkey', 'updated_by')
  ) v(t,n,col)
  JOIN pg_constraint c ON c.conrelid = to_regclass(v.t) AND c.conname = v.n
    AND c.contype = 'f' AND c.confrelid = to_regclass('dflow.users')
    AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred
    AND c.confmatchtype = 's' AND c.confupdtype = 'a' AND c.confdeltype = 'a'
  JOIN pg_attribute child ON child.attrelid = c.conrelid AND child.attname = v.col
    AND c.conkey = ARRAY[child.attnum]
  JOIN pg_attribute parent ON parent.attrelid = c.confrelid AND parent.attname = 'id'
    AND c.confkey = ARRAY[parent.attnum]
  ) = 3
) as passed;
