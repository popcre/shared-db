# Private historical customs benchmark

Owner: DesignFlow HTS evaluation; shared-db issue #5447, application issue
[designflow-backend#279](https://github.com/popcre/designflow-backend/issues/279).
Albert explicitly requested lossless preservation in development and production
and designation as the authoritative software-comparison benchmark.

`plm.customs_benchmark_dataset` holds the complete original intelligence object,
source-file manifest, content-addressed dataset identity, authority context and
expected counts. `plm.customs_benchmark_artifact` preserves every original file
byte, relative filename, media type, byte count and SHA-256, including all customs
PDFs, extracts, earlier catalogs and load evidence, report, reproducibility
scripts, previews and the original item-master workbook.
`plm.customs_benchmark_observation` makes every source section queryable without
losing any unrecognized source fields in `original_record`. These are private
archive records, outside the sanitized shared `hts_rag` learning tables. Do not
copy commercial source documents or identifiers into that shared-learning path.

## Authority and evaluation

The archive is authoritative for the preserved historical customs evidence.
Compare software outputs against its linked styles and physical product facts,
retaining the packet, entry, page, source hash and original status on every
comparison. A direct historical candidate is eligible for historical agreement
measurement; it still requires source association checking before becoming a
frozen answer. Historical filings are not binding CBP rulings or automatically
valid current-law labels. Code mapping must retain original codes and supported
successors separately. Do not silently rewrite the item-master HTS field.

Packet inference, product-family research leads, clock-component exclusions,
unmatched styles, coverage and anomalies remain available, but must never become
confirmed item answers by inheritance. Report their coverage separately. Keep
benchmark answers out of model prompts and memory for the evaluated items and
families; an archive used for development is not an untouched evaluation set.

## Import and verification

The generic [loader](../tools/load-customs-benchmark.py) contains no private data
and issues no DDL. Its inputs are the private source directory, original workbook,
exact target ref and a local `project-ref` file. The Supabase Management API token
comes only from the environment through 1Password. Full imports use
`CUSTOMS_DB_DIRECT=1` with `psycopg` and the canonical database password and
pooler host in environment variables: the Management API rejects large PDF
queries. The loader verifies TLS using the repository CA and compares the direct
database cluster identity with the proved project through the Management API
before every statement. This uses the supported database connection for large
content; no schema or access control is bypassed. The default mode only verifies;
`--apply` inserts immutable rows with conflict preservation. Run against the
actual DesignFlow non-production and shared production targets independently;
shared preview is rehearsal, not the requested development delivery.

Before every request the loader checks the local target file and the Management
API project identity. It re-reads every artifact's bytes and verifies database
SHA-256 plus size, compares every observation and the entire original intelligence
object, then re-inventories the source files. A partial import is **not usable or
complete** until full verification succeeds. Re-running safely finishes missing
rows; a conflicting existing row stops verification without replacing evidence.
The tables grant only SELECT/INSERT to `service_role`, with RLS enabled and no
browser policies. Backend evaluation uses a trusted server-side identity; this
change adds no public endpoint, browser access or classifier behavior.

Schema goes through canonical automatic production promotion and the existing
sandbox migration workflow. Source data stays out of GitHub, Actions and public
logs. The same issue retains target-specific load receipts and live proof.
