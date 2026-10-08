-- Fixed #4060 metadata only. User values are never returned by this query.
SELECT json_build_object(
  'table_kind', c.relkind,
  'table_oid', c.oid::bigint,
  'index', (SELECT json_build_object('unique', i.indisunique, 'valid', i.indisvalid,
    'ready', i.indisready, 'table_oid', i.indrelid::bigint, 'method', am.amname,
    'keys', i.indnkeyatts, 'attributes', i.indnatts,
    'expression', pg_get_expr(i.indexprs, i.indrelid),
    'predicate', pg_get_expr(i.indpred, i.indrelid))
    FROM pg_index i JOIN pg_class ic ON ic.oid = i.indexrelid
    JOIN pg_am am ON am.oid = ic.relam
    WHERE i.indexrelid = to_regclass('dflow.users_email_lower_uidx')),
  'columns', (SELECT json_agg(json_build_object('name', a.attname,
    'type', format_type(a.atttypid, a.atttypmod), 'not_null', a.attnotnull,
    'identity', a.attidentity, 'generated', a.attgenerated,
    'default', pg_get_expr(d.adbin, d.adrelid)) ORDER BY a.attnum)
    FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
    WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped),
  'insert_triggers', (SELECT coalesce(json_agg(json_build_object('internal', t.tgisinternal,
    'type', t.tgtype, 'function_schema', n.nspname, 'function', p.proname,
    'constraint_type', fk.contype, 'constraint_table', fk.conrelid::bigint,
    'referenced_table', fk.confrelid::bigint,
    'key_columns', (SELECT array_agg(a.attname ORDER BY k.ord)
      FROM unnest(fk.conkey) WITH ORDINALITY k(num,ord)
      JOIN pg_attribute a ON a.attrelid = fk.conrelid AND a.attnum = k.num))
    ORDER BY t.oid), '[]'::json)
    FROM pg_trigger t JOIN pg_proc p ON p.oid = t.tgfoid
    JOIN pg_namespace n ON n.oid = p.pronamespace
    LEFT JOIN pg_constraint fk ON fk.oid = t.tgconstraint
    WHERE t.tgrelid = c.oid AND t.tgenabled <> 'D' AND (t.tgtype & 4) <> 0),
  'profile_oid', to_regclass('app.profile')::oid::bigint,
  'checks', (SELECT count(*) FROM pg_constraint WHERE conrelid = c.oid AND contype = 'c'),
  'unsafe_indexes', (SELECT count(*) FROM pg_index other JOIN pg_class ic ON ic.oid = other.indexrelid
    JOIN pg_am am ON am.oid = ic.relam
    WHERE other.indrelid = c.oid AND (
      am.amname <> 'btree' OR other.indisexclusion OR
      (other.indexrelid <> to_regclass('dflow.users_email_lower_uidx')
        AND (other.indexprs IS NOT NULL OR other.indpred IS NOT NULL)) OR
      EXISTS(SELECT 1 FROM unnest(other.indclass::oid[]) op(oid)
        JOIN pg_opclass oc ON oc.oid = op.oid JOIN pg_namespace ns ON ns.oid = oc.opcnamespace
        WHERE ns.nspname <> 'pg_catalog'))),
  'rules', (SELECT count(*) FROM pg_rewrite WHERE ev_class = c.oid),
  'ledger_present', (SELECT count(*) = 1 FROM supabase_migrations.schema_migrations
    WHERE version = '20261008160444'),
  'duplicate_groups', (SELECT count(*) FROM (SELECT lower(btrim(email))
    FROM dflow.users WHERE nullif(btrim(email), '') IS NOT NULL
    GROUP BY lower(btrim(email)) HAVING count(*) > 1) duplicates)
) FROM pg_class c WHERE c.oid = to_regclass('dflow.users');
