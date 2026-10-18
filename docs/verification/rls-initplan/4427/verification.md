# Issue4427 qualification — OPEN

October18,2026 EDT. Claim4443 reserves20261018172640. The prospective generation1 contract was published before implementation. This packet is incomplete and does not authorize preview, promotion, or closure.

The candidate changes exactly46 admin policy predicates across39 tables. It guards original expressions and policy metadata, checks helper stability, and compares complete table/column ACLs, ownership, RLS flags, helper definitions/ACLs/configuration, and all overlapping policies before/after. Null WITH CHECK remains null, retaining the existing implicit check.

## Evidence actually obtained

- Fresh production read-only catalog:46 target policies,39 tables,72 complete overlapping policies. Source Node3/3 and SQL shape checks passed.
- Earlier genuine authenticated owning-client reads succeeded on assets and style_groups. These are BEFORE-only baseline reads, not post-repair acceptance; no rows, tokens or identities were retained publicly.
- No database fixture, migration apply, preview, production change, after-plan, or live write proof has occurred.

## Executable test coverage — UNEXECUTED

The local-only SQL contract requires the existing synthetic invitation-first CI seed. It compares600 original/candidate results and exact SQLSTATEs across administrator/member/missing/malformed/anonymous/repeated-administrator contexts, with a separately prepared actual policy query and helper query. Every DML probe rolls back separately; the entire suite rolls back. It changes no production grants, helpers or RLS flags and bypasses no auth provisioning trigger.

Actual positive/negative DML adapters currently cover assets INSERT/UPDATE and administrator configuration INSERT/UPDATE/DELETE, plus profile visibility/ownership union. All39 tables have bounded read/error probes. This is not all-table write qualification or performance proof.

## Remaining command adapters


```json
{
  "sql_proposal": "rls_public_admin_initplan_contracts.proposed.sql",
  "status": "UNEXECUTED PRIVATE PROPOSAL; independent root review required",
  "runtime_cases": {
    "public.assets": [
      "positive/denied INSERT",
      "positive/denied UPDATE",
      "visible SELECT"
    ],
    "public.admin_config": [
      "positive/denied INSERT UPDATE DELETE privileged SELECT"
    ],
    "public.profiles": [
      "admin all two synthetic profiles/member-own profile union"
    ]
  },
  "bounded_read_tables": 39,
  "contexts": [
    "admin",
    "member",
    "missing_subject",
    "malformed_subject",
    "anon",
    "admin_again"
  ],
  "original_candidate_expected_probe_count": 588,
  "checks": [
    "scalar candidate presence/all46 identities",
    "72 policy union role command permissive OID/deparsed-expression/null-check equality",
    "39 table rawACL/columnACL/RLS/owner preservation",
    "auth.uid/public.has_role body/ACL/OID/volatility/definer preservation",
    "public.app_role OID/owner/ACL preservation",
    "prepared-context admin/member/missing/malformed/anon equivalence",
    "next-statement admin role revocation helper control"
  ],
  "fixture_touches": {
    "writes": [
      "public.user_roles",
      "public.profiles (insert missing .invalid seed profile only)",
      "public.admin_config (two synthetic keys)",
      "public.assets (two synthetic UUIDs)"
    ],
    "reads": [
      "auth.users (exact existing CI .invalid users)",
      "all39 manifest tables",
      "pg_catalog metadata"
    ],
    "indirect_possible_writes": [
      "public.dam_search_documents (live trigger closure confirmed transactional)",
      "public.asset_effective_tags (no matching tags for fresh null-group IDs)",
      "public.render_queue (NULL thumbnail_error means no enqueue)"
    ],
    "indirect_functions": [
      "sync_asset_effective_tags",
      "stamp_style_group_asset_change",
      "set_assets_updated_at",
      "auto_queue_render",
      "compute_primary_sort_tier",
      "trg_refresh_dam_asset_search_document",
      "refresh_dam_search_asset_document",
      "infer_path_attrs",
      "trg_set_asset_path_attrs",
      "refresh_style_group_counts_on_asset_change",
      "sync_cover_description_to_style_group",
      "sync_designer_to_style_group",
      "sync_primary_asset_on_thumbnail"
    ],
    "notes": [
      "No group IDs/foreign reference IDs/real rows; no trigger disabled",
      "All operations including policy original/candidate switches inside outer ROLLBACK",
      "Each DML probe uses internal exception subtransaction rollback, preserving identical phase data",
      "No public helper changed; only pg_temp invoker function/temp grants created",
      "Source production trigger metadata does not establish current local/preview parity"
    ]
  },
  "remaining_table_adapters": [
    {
      "table": "archive.erp_items_current",
      "requires_positive_fixture_for": [
        "DELETE",
        "INSERT",
        "SELECT",
        "UPDATE"
      ],
      "bounded_read_only_currently": true,
      "policy_count": 1
    },
    {
      "table": "archive.erp_items_raw",
      "requires_positive_fixture_for": [
        "DELETE",
        "INSERT",
        "SELECT",
        "UPDATE"
      ],
      "bounded_read_only_currently": true,
      "policy_count": 1
    },
    {
      "table": "plm.legacy_erp_item_identity",
      "requires_positive_fixture_for": [
        "SELECT"
      ],
      "bounded_read_only_currently": true,
      "policy_count": 1
    },
    {
      "table": "public.agent_pairings",
      "requires_positive_fixture_for": [
        "DELETE",
        "INSERT",
        "SELECT",
        "UPDATE"
      ],
      "bounded_read_only_currently": true,
      "policy_count": 1
    },
    {
      "table": "public.agent_registrations",
      "requires_positive_fixture_for": [
        "DELETE",
        "INSERT",
        "SELECT",
        "UPDATE"
      ],
      "bounded_read_only_currently": true,
      "policy_count": 1
    },
    {
      "table": "public.ai_tag_bakeoff_results",
      "requires_positive_fixture_for": [
        "DELETE",
        "INSERT",
        "SELECT",
        "UPDATE"
      ],
      "bounded_read_only_currently": true,
      "policy_count": 2
    },
    {
      "table": "public.ai_tag_bakeoff_reviews",
      "requires_positive_fixture_for": [
        "DELETE",
        "INSERT",
        "SELECT",
        "UPDATE"
      ],
      "bounded_read_only_currently": true,
      "policy_count": 2
    },
    {
      "table": "public.ai_tag_bakeoff_runs",
      "requires_positive_fixture_for": [
        "DELETE",
        "INSERT",
        "SELECT",
        "UPDATE"
      ],
      "bounded_read_only_currently": true,
      "policy_count": 2
    },
    {
      "table": "public.app_access",
      "requires_positive_fixture_for": [
        "DELETE",
        "INSERT",
        "SELECT",
        "UPDATE"
      ],
      "bounded_read_only_currently": true,
      "policy_count": 1
    },
    {
      "table": "public.asset_characters",
      "requires_positive_fixture_for": [
        "DELETE",
        "INSERT",
        "SELECT",
        "UPDATE"
      ],
      "bounded_read_only_currently": true,
      "policy_count": 1
    },
    {
      "table": "public.asset_tags",
      "requires_positive_fixture_for": [
        "DELETE",
        "INSERT",
        "SELECT",
        "UPDATE"
      ],
      "bounded_read_only_currently": true,
      "policy_count": 1
    },
    {
      "table": "public.characters",
      "requires_positive_fixture_for": [
        "DELETE",
        "INSERT",
        "SELECT",
        "UPDATE"
      ],
      "bounded_read_only_currently": true,
      "policy_count": 1
    },
    {
      "table": "public.erp_enrichment_log",
      "requires_positive_fixture_for": [
        "DELETE",
        "INSERT",
        "SELECT",
        "UPDATE"
      ],
      "bounded_read_only_currently": true,
      "policy_count": 1
    },
    {
      "table": "public.erp_sync_runs",
      "requires_positive_fixture_for": [
        "DELETE",
        "INSERT",
        "SELECT",
        "UPDATE"
      ],
      "bounded_read_only_currently": true,
      "policy_count": 1
    },
    {
      "table": "public.hygiene_findings",
      "requires_positive_fixture_for": [
        "DELETE",
        "INSERT",
        "SELECT",
        "UPDATE"
      ],
      "bounded_read_only_currently": true,
      "policy_count": 1
    },
    {
      "table": "public.invitations",
      "requires_positive_fixture_for": [
        "DELETE",
        "INSERT",
        "SELECT",
        "UPDATE"
      ],
      "bounded_read_only_currently": true,
      "policy_count": 1
    },
    {
      "table": "public.licensors",
      "requires_positive_fixture_for": [
        "DELETE",
        "INSERT",
        "SELECT",
        "UPDATE"
      ],
      "bounded_read_only_currently": true,
      "policy_count": 1
    },
    {
      "table": "public.pdf_text_samples",
      "requires_positive_fixture_for": [
        "DELETE",
        "INSERT",
        "SELECT",
        "UPDATE"
      ],
      "bounded_read_only_currently": true,
      "policy_count": 1
    },
    {
      "table": "public.processing_queue",
      "requires_positive_fixture_for": [
        "DELETE",
        "INSERT",
        "SELECT",
        "UPDATE"
      ],
      "bounded_read_only_currently": true,
      "policy_count": 1
    },
    {
      "table": "public.prod_order_headers_current",
      "requires_positive_fixture_for": [
        "DELETE",
        "INSERT",
        "SELECT",
        "UPDATE"
      ],
      "bounded_read_only_currently": true,
      "policy_count": 1
    },
    {
      "table": "public.prod_order_headers_raw",
      "requires_positive_fixture_for": [
        "DELETE",
        "INSERT",
        "SELECT",
        "UPDATE"
      ],
      "bounded_read_only_currently": true,
      "policy_count": 1
    },
    {
      "table": "public.prod_order_sync_runs",
      "requires_positive_fixture_for": [
        "DELETE",
        "INSERT",
        "SELECT",
        "UPDATE"
      ],
      "bounded_read_only_currently": true,
      "policy_count": 1
    },
    {
      "table": "public.product_categories",
      "requires_positive_fixture_for": [
        "DELETE",
        "INSERT",
        "SELECT",
        "UPDATE"
      ],
      "bounded_read_only_currently": true,
      "policy_count": 1
    },
    {
      "table": "public.product_category_predictions",
      "requires_positive_fixture_for": [
        "DELETE",
        "INSERT",
        "SELECT",
        "UPDATE"
      ],
      "bounded_read_only_currently": true,
      "policy_count": 1
    },
    {
      "table": "public.product_subtypes",
      "requires_positive_fixture_for": [
        "DELETE",
        "INSERT",
        "SELECT",
        "UPDATE"
      ],
      "bounded_read_only_currently": true,
      "policy_count": 1
    },
    {
      "table": "public.product_types",
      "requires_positive_fixture_for": [
        "DELETE",
        "INSERT",
        "SELECT",
        "UPDATE"
      ],
      "bounded_read_only_currently": true,
      "policy_count": 1
    },
    {
      "table": "public.properties",
      "requires_positive_fixture_for": [
        "DELETE",
        "INSERT",
        "SELECT",
        "UPDATE"
      ],
      "bounded_read_only_currently": true,
      "policy_count": 1
    },
    {
      "table": "public.render_queue",
      "requires_positive_fixture_for": [
        "DELETE",
        "INSERT",
        "SELECT",
        "UPDATE"
      ],
      "bounded_read_only_currently": true,
      "policy_count": 1
    },
    {
      "table": "public.style_group_tags",
      "requires_positive_fixture_for": [
        "DELETE",
        "INSERT",
        "SELECT",
        "UPDATE"
      ],
      "bounded_read_only_currently": true,
      "policy_count": 1
    },
    {
      "table": "public.style_groups",
      "requires_positive_fixture_for": [
        "DELETE",
        "INSERT",
        "SELECT",
        "UPDATE"
      ],
      "bounded_read_only_currently": true,
      "policy_count": 1
    },
    {
      "table": "public.style_guide_crawl_runs",
      "requires_positive_fixture_for": [
        "DELETE",
        "INSERT",
        "SELECT",
        "UPDATE"
      ],
      "bounded_read_only_currently": true,
      "policy_count": 1
    },
    {
      "table": "public.style_guide_files",
      "requires_positive_fixture_for": [
        "DELETE",
        "INSERT",
        "SELECT",
        "UPDATE"
      ],
      "bounded_read_only_currently": true,
      "policy_count": 1
    },
    {
      "table": "public.style_guide_render_queue",
      "requires_positive_fixture_for": [
        "DELETE",
        "INSERT",
        "SELECT",
        "UPDATE"
      ],
      "bounded_read_only_currently": true,
      "policy_count": 1
    },
    {
      "table": "public.style_tracker_rows",
      "requires_positive_fixture_for": [
        "DELETE"
      ],
      "bounded_read_only_currently": true,
      "policy_count": 1
    },
    {
      "table": "public.tiff_optimization_queue",
      "requires_positive_fixture_for": [
        "DELETE",
        "INSERT",
        "SELECT",
        "UPDATE"
      ],
      "bounded_read_only_currently": true,
      "policy_count": 1
    },
    {
      "table": "public.user_roles",
      "requires_positive_fixture_for": [
        "DELETE",
        "INSERT",
        "SELECT",
        "UPDATE"
      ],
      "bounded_read_only_currently": true,
      "policy_count": 1
    }
  ],
  "other_uncovered": [
    "all-table positive/negative command fixture matrix",
    "all family mixed-batch/null/empty and restrictive-policy adversarial cases",
    "cardinality/timing/real plan evidence",
    "preview parity and owned lease",
    "production governed application and live acceptance",
    "browser UI proof",
    "production safe consumer write proof"
  ],
  "safety": "Production execution forbidden. This file is only for fresh isolated local CI bootstrap. Use no copied production rows."
}
```

## Required delivery gates

All applicable command fixtures,1/100/10000-row repeated measurements/raw plans, malformed and implicit-check behavior, local SQL execution, preview parity/consumer/cleanup, assigned exact-head review and CI, guarded merge, qualified production promotion, targeted advisor/catalog/ledger proof, and approved live consumer reads/writes remain open. Missing safe production write acceptance stays UNKNOWN on4427 and blocks4428. No other repair is closed by this packet.
