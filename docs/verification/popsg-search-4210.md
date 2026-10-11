# PopSG matching search repair evidence — issue 4210

Owner: Codex chat 01a12c68-44b8-7bb3-b1d4-98cb375b6859 on hetz.

## Executed synthetic behavior checks

Disposable PostgreSQL 15, invented fixture rows only, completed October 11,
2026 before 6:30 PM EDT. Existing nine search contracts passed. The canonical
baseline function was installed under a fixture-only name; the replacement
was applied under the actual serving name. All 224 complete JSON equality
comparisons passed: Files and Guides; null, matching, unmatched, negated,
quoted, null-identity and tag queries; four sorts; limits 1/200; offsets 0/1.
The equality covered entire results, totals, facets, order, rank, live preview
selection and null/empty guide identity. Existing contracts separately test
role denial, service access and an authorized authenticated user.

Terminal evidence retained locally:

```
NOTICE: issue #2506 PopSG v2 search contracts: all 9 checks passed
NOTICE: Full old/new JSON equality: 224 synthetic cases passed
```

## Bounded read-only query-body checks

Production-sized corpus: 220,218 active documents, 94,497 matching a common
six-character term. Every diagnostic transaction was READ ONLY; statement
ceiling stayed eight seconds and work_mem stayed 64MB. Files single-row
materialization: 4,113 ms. Guides constant SQL planned for bound call values
and separate page metadata/tag aggregation: 4,621 ms. No production function,
row, index, cron or setting was changed for these tests. These measurements
are diagnosis, not signed-in acceptance. The first two-hint prototype still
timed out in Guides; it is superseded by the final branch.

Runtime EXECUTE interpolates no user text. Fifteen USING values bind the
normalized mode and the original arguments in signature order. Planning cost
was 17 ms for the final Guides probe. Function settings remain precisely
search_path and work_mem; no plan-cache or timeout setting is added.

## Actual index usage and whole-set reads

The final common-query Guides plan reported these actual index nodes:

- Index Only Scan: `idx_sgf_live_missing_clean_ids`, rows 0, loops 1.
- Index Only Scan: `idx_sgf_live_missing_error_ids`, rows 2220, loops 1.
- Index Only Scan: `idx_sgf_live_preview_ids`, rows 108999, loops 2.
- Index Scan: `style_guide_files_pkey`, rows 1, loops 31665.

The bounded render-rollup reads the queue once. Broad common queries can
legitimately use sequential or parallel scans: nearly half the corpus matches,
and exact totals/facets require the whole matched set. No claim is made that
every optional predicate uses an index. The repair adds no index and does not
hide these reads. The query plan, not index existence alone, is the evidence.

Schema-only index inventory captured read-only:

- `style_guide_files_pkey`: `CREATE UNIQUE INDEX style_guide_files_pkey ON public.style_guide_files USING btree (id)`.
- `style_guide_files_root_path_unique`: `CREATE UNIQUE INDEX style_guide_files_root_path_unique ON public.style_guide_files USING btree (root_label, relative_path)`.
- `idx_sgf_root_label`: `CREATE INDEX idx_sgf_root_label ON public.style_guide_files USING btree (root_label)`.
- `idx_sgf_directory_path`: `CREATE INDEX idx_sgf_directory_path ON public.style_guide_files USING btree (directory_path)`.
- `idx_sgf_normalized_name`: `CREATE INDEX idx_sgf_normalized_name ON public.style_guide_files USING btree (normalized_name)`.
- `idx_sgf_is_active`: `CREATE INDEX idx_sgf_is_active ON public.style_guide_files USING btree (is_active)`.
- `idx_sgf_crawl_run_id`: `CREATE INDEX idx_sgf_crawl_run_id ON public.style_guide_files USING btree (crawl_run_id)`.
- `idx_sgf_style_guide_folder`: `CREATE INDEX idx_sgf_style_guide_folder ON public.style_guide_files USING btree (style_guide_folder)`.
- `idx_sgf_property_folder`: `CREATE INDEX idx_sgf_property_folder ON public.style_guide_files USING btree (property_folder)`.
- `idx_sgf_licensor_name`: `CREATE INDEX idx_sgf_licensor_name ON public.style_guide_files USING btree (licensor_name)`.
- `idx_sgf_render_errored`: `CREATE INDEX idx_sgf_render_errored ON public.style_guide_files USING btree (id) WHERE (is_active AND (thumbnail_url IS NULL) AND (thumbnail_error IS NOT NULL))`.
- `idx_style_guide_files_filename_trgm`: `CREATE INDEX idx_style_guide_files_filename_trgm ON public.style_guide_files USING gin (lower(filename) gin_trgm_ops)`.
- `idx_style_guide_files_active_modified`: `CREATE INDEX idx_style_guide_files_active_modified ON public.style_guide_files USING btree (modified_at DESC NULLS LAST, filename) WHERE is_active`.
- `idx_sgf_reconcile_root_active_run_id`: `CREATE INDEX idx_sgf_reconcile_root_active_run_id ON public.style_guide_files USING btree (root_label, crawl_run_id, id) WHERE is_active`.
- `idx_style_guide_files_tag_names`: `CREATE INDEX idx_style_guide_files_tag_names ON public.style_guide_files USING gin (tag_names)`.
- `idx_style_guide_files_tag_search_trgm`: `CREATE INDEX idx_style_guide_files_tag_search_trgm ON public.style_guide_files USING gin (tag_search_text gin_trgm_ops)`.
- `idx_sgf_directory_path_trgm`: `CREATE INDEX idx_sgf_directory_path_trgm ON public.style_guide_files USING gin (directory_path gin_trgm_ops)`.
- `idx_sgf_relative_path_trgm`: `CREATE INDEX idx_sgf_relative_path_trgm ON public.style_guide_files USING gin (relative_path gin_trgm_ops)`.
- `idx_sgf_live_preview_ids`: `CREATE INDEX idx_sgf_live_preview_ids ON public.style_guide_files USING btree (id) WHERE (is_active AND (thumbnail_url IS NOT NULL))`.
- `idx_sgf_live_missing_clean_ids`: `CREATE INDEX idx_sgf_live_missing_clean_ids ON public.style_guide_files USING btree (id) WHERE (is_active AND (thumbnail_url IS NULL) AND (thumbnail_error IS NULL))`.
- `idx_sgf_live_missing_error_ids`: `CREATE INDEX idx_sgf_live_missing_error_ids ON public.style_guide_files USING btree (id) WHERE (is_active AND (thumbnail_url IS NULL) AND (thumbnail_error IS NOT NULL))`.
- `idx_sgf_active_preview_category`: `CREATE INDEX idx_sgf_active_preview_category ON public.style_guide_files USING btree ((
CASE
    WHEN (thumbnail_url IS NOT NULL) THEN 'has_preview'::text
    WHEN (lower(file_extension) <> ALL (ARRAY['pdf'::text, 'ai'::text, 'psd'::text, 'eps'::text, 'jpg'::text, 'jpeg'::text, 'png'::text, 'tif'::text, 'tiff'::text])) THEN 'unsupported'::text
    WHEN ((thumbnail_error IS NULL) AND (lower(file_extension) = ANY (ARRAY['pdf'::text, 'ai'::text, 'psd'::text, 'eps'::text, 'jpg'::text, 'jpeg'::text, 'png'::text, 'tif'::text, 'tiff'::text]))) THEN 'renderable_no_preview'::text
    WHEN ((thumbnail_error IS NOT NULL) AND (lower(file_extension) = ANY (ARRAY['pdf'::text, 'ai'::text, 'psd'::text, 'eps'::text, 'jpg'::text, 'jpeg'::text, 'png'::text, 'tif'::text, 'tiff'::text])) AND ((lower(thumbnail_error) = ANY (ARRAY['no_pdf_compat'::text, 'no_preview_or_render_failed'::text, 'blank_render'::text])) OR (lower(thumbnail_error) ~~ '%enoent%'::text) OR (lower(thumbnail_error) ~~ '%not found%'::text) OR (lower(thumbnail_error) ~~ '%missing%'::text) OR (lower(thumbnail_error) ~~ '%unsupported%'::text) OR (lower(thumbnail_error) ~~ '%corrupt%'::text))) THEN 'renderable_terminal'::text
    WHEN ((thumbnail_error IS NOT NULL) AND (lower(file_extension) = ANY (ARRAY['pdf'::text, 'ai'::text, 'psd'::text, 'eps'::text, 'jpg'::text, 'jpeg'::text, 'png'::text, 'tif'::text, 'tiff'::text]))) THEN 'renderable_recoverable'::text
    WHEN ((thumbnail_error IS NOT NULL) AND ((lower(thumbnail_error) = ANY (ARRAY['no_pdf_compat'::text, 'no_preview_or_render_failed'::text, 'blank_render'::text])) OR (lower(thumbnail_error) ~~ '%enoent%'::text) OR (lower(thumbnail_error) ~~ '%not found%'::text) OR (lower(thumbnail_error) ~~ '%missing%'::text) OR (lower(thumbnail_error) ~~ '%unsupported%'::text) OR (lower(thumbnail_error) ~~ '%corrupt%'::text))) THEN 'other_terminal'::text
    WHEN (thumbnail_error IS NOT NULL) THEN 'other_recoverable'::text
    ELSE 'other_unexplained'::text
END)) WHERE is_active`.
- `style_guide_render_queue_pkey`: `CREATE UNIQUE INDEX style_guide_render_queue_pkey ON public.style_guide_render_queue USING btree (id)`.
- `idx_sgrq_status`: `CREATE INDEX idx_sgrq_status ON public.style_guide_render_queue USING btree (status)`.
- `idx_sgrq_file_id`: `CREATE INDEX idx_sgrq_file_id ON public.style_guide_render_queue USING btree (style_guide_file_id)`.
- `idx_sgrq_created_at`: `CREATE INDEX idx_sgrq_created_at ON public.style_guide_render_queue USING btree (created_at DESC)`.
- `idx_sgrq_status_created_at`: `CREATE INDEX idx_sgrq_status_created_at ON public.style_guide_render_queue USING btree (status, created_at DESC)`.
- `idx_sgrq_file_status`: `CREATE INDEX idx_sgrq_file_status ON public.style_guide_render_queue USING btree (style_guide_file_id, status)`.
- `style_guide_search_documents_pkey`: `CREATE UNIQUE INDEX style_guide_search_documents_pkey ON public.style_guide_search_documents USING btree (style_guide_file_id)`.
- `idx_sg_search_documents_search_vector`: `CREATE INDEX idx_sg_search_documents_search_vector ON public.style_guide_search_documents USING gin (search_vector) WHERE is_active`.
- `idx_sg_search_documents_filters`: `CREATE INDEX idx_sg_search_documents_filters ON public.style_guide_search_documents USING btree (licensor_name, property_folder, file_extension, modified_at DESC) WHERE is_active`.
- `idx_sg_search_documents_stable_page`: `CREATE INDEX idx_sg_search_documents_stable_page ON public.style_guide_search_documents USING btree (modified_at DESC NULLS LAST, style_guide_file_id) WHERE is_active`.

## Review response

The first DeepSeek run returned BLOCKED, with no confirmed correctness defect,
because index use/equivalence evidence was not attached and owner/dependency
checks were incomplete. That finding is retained, not replaced by an approval.
This artifact supplies executed aggregate evidence and real plan/index facts;
the baseline, contract and live proof now assert PostgreSQL ownership and
exact dependency kinds/key column types as well as body/settings/grants.

The dynamic marker sidecar is hash-bound. Its runtime constant SELECT creates
no extra durable object when this migration applies; ordinary catalog
verification still covers the static CREATE OR REPLACE FUNCTION. CI’s missing
sidecar refusal is addressed explicitly, without weakening its checker.

Production acceptance remains unchecked until the guarded merge, merged-main
rehearsal, automatic promotion and request-correlated live checks succeed.
