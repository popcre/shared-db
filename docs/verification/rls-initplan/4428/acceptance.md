# #4428 acceptance (close-out)

## Verdict: ACCEPTED — structural delivery already live; this record is the close-out proof

Migration `supabase/migrations/20261023122936_owner_uid_initplans.sql` (17 owner-uid
policies wrapped, claim #4624) was authored in [PR #4674](https://github.com/popcre/shared-db/pull/4674)
(content commit `7685878ceb50ccb8c6afa8918332d90822ce7721`, merge `7b333686f`) and applied
to production by Actions run [39960456276](https://github.com/popcre/shared-db/actions/runs/39960456276)
on 2026-10-23. This document records the independent read-only re-proof taken
2026-11-05 (approx. 7:30–7:52 PM EST) by the closing session, per the
2026-11-04 close-out plan on the issue. No production write was performed at any
point in this close-out.

## Target proof

Management API project probe for the production ref quoted in the runbook:

```
{"id":"qsllyeztdwjgirsysgai","name":"popdam","region":"us-east-1","status":"ACTIVE_HEALTHY","created_at":"2026-06-20T19:28:33.600876Z"}
```

All queries below ran read-only against this exact project via the Management API
query endpoint (Supabase CLI access token from 1Password vault `vibe_coding`).

## Step 1 — installed-catalog live re-proof

`.github/live-proofs/4428.sql` (unmodified, from `origin/main`) executed read-only:

```
[{"passed":true}]
```

Migration ledger:

```
select version from supabase_migrations.schema_migrations where version='20261023122936'
-> [{"version":"20261023122936"}]    (exactly 1 row)
```

## Step 2 — policy text spot-check (production catalog)

All 17 owner-uid policies exist on the 7 family tables and every one evaluates
`auth.uid()` through a scalar InitPlan subquery with the owner column left as a
bare, row-dependent reference. No policy DDL on any of the 7 tables exists in any
migration with a version later than `20261023122936` (no drift).

| Table | Policy | cmd | wrapped |
|---|---|---|---|
| app_access | Users read own app_access | SELECT | yes |
| asset_checkouts | users insert own checkouts | INSERT | yes |
| asset_checkouts | users update own checkouts | UPDATE | yes |
| helper_devices | users insert own devices | INSERT | yes |
| helper_devices | users see own devices | SELECT | yes |
| helper_devices | users update own devices | UPDATE | yes |
| helper_tokens | users insert own tokens | INSERT | yes |
| helper_tokens | users see own tokens | SELECT | yes |
| order_list_user_views | order_list_user_views_owner_delete | DELETE | yes |
| order_list_user_views | order_list_user_views_owner_insert | INSERT | yes |
| order_list_user_views | order_list_user_views_owner_select | SELECT | yes |
| order_list_user_views | order_list_user_views_owner_update | UPDATE | yes |
| profiles | Users read own profile | SELECT | yes |
| profiles | Users update own profile | UPDATE | yes |
| style_tracker_user_views | Users insert their own style tracker views | INSERT | yes |
| style_tracker_user_views | Users read their own style tracker views | SELECT | yes |
| style_tracker_user_views | Users update their own style tracker views | UPDATE | yes |

Canonical wrapped form (identical shape in all 17): `user_id = ( SELECT auth.uid() AS uid)`.

Non-owner policies present on the same tables (unchanged by this family):

| Table | Policy | note |
|---|---|---|
| app_access | Admins manage app_access | #4427 admin-family wrap `( SELECT has_role(auth.uid(), ...) AS has_role)` — its own scope, in production since 2026-10-21 |
| asset_checkouts | authenticated users see all checkouts | `qual = true`; post-baseline addition already known to the #4428 work contract |
| profiles | Admins read all profiles | #4427 admin-family wrap — its own scope |

Total live policies on the 7 tables: 20 = 17 owner + 3 above. No extras appeared.
`has_role(...)` was not wrapped by this family's migration.

Performance advisor (`advisors/performance`, observed 2026-11-05): 53
`auth_rls_initplan` warnings remain project-wide; **none names any of the 17
policies above**. The only two touching family tables name `Admins manage
app_access` and `Admins read all profiles` — both #4427-family policies whose
retained static flags are recorded in the
[4427 acceptance](../4427/acceptance.md).

## Step 3 — actual-plan measurement (read-only, ROLLBACK-bounded)

Three most-populated family tables by estimated live rows: `helper_tokens`
(~194), `app_access` (~50), `profiles` (~48). Five runs each; every run inside
`begin; set local statement_timeout='8s'; set local role authenticated; select
set_config('request.jwt.claims', '<real user uuid, redacted>', true); explain
(analyze, buffers) select * from public.<table>; rollback;`. No INSERT/UPDATE/DDL
executed; every transaction rolled back. A real production user context was used;
no user ids, emails or row contents are retained here.

Observed plan shapes (identical across all 15 runs):

```
helper_tokens: Filter: (user_id = (InitPlan 1).col1)  +  InitPlan 1 (Result: auth.uid())
app_access:    Filter: ((user_id = (InitPlan 1).col1) OR (InitPlan 2).col1)
               InitPlan 1 -> auth.uid() (owner policy); InitPlan 2 -> #4427 has_role wrap (OR'd permissive admin policy)
profiles:      same two-InitPlan shape as app_access
```

RLS visibly enforced under the authenticated role: `helper_tokens` returned 94
owner rows and removed 100 non-owner rows per scan; `app_access` returned 1 of
50; `profiles` returned 1 of 48 (allow and deny paths both exercised).

| Table | run ms (5 runs) | median ms | InitPlan | per-row auth.uid() |
|---|---|---:|---|---|
| helper_tokens | 0.271 / 0.287 / 0.222 / 0.260 / 0.267 | 0.260 | 1 | none |
| app_access | 2.002 / 5.061 / 6.563 / 3.161 / 4.037 | 4.037 | 1 (owner) | none |
| profiles | 3.193 / 4.558 / 4.767 / 2.079 / 3.834 | 3.834 | 1 (owner) | none |

Comparison basis, stated honestly: the
[2026-10-18 baseline](../2026-10-18-baseline.md) Timings section contains
controlled measurements of the **admin `has_role` expression** (medians: original
132.956 ms, uid-only wrap 123.219 ms, whole-check wrap 3.788 ms over 10,000
generated rows); it holds **no per-table before timings for the owner-uid
family**. The retained before/after evidence for this family is therefore the
plan shape itself — pre-migration policies called bare `auth.uid()` per row;
every live plan now evaluates it exactly once via `InitPlan 1` and references the
result as `(InitPlan 1).col1` in the row filter — plus the 2026-10-23 catalog
apply. No repeatable regression is possible from removing per-row evaluations;
none was observed.

## Consumer write acceptance

**Consumer write acceptance through application paths remains UNKNOWN** (no
approved app test route), exactly as recorded on the issue since 2026-10-23.
This close-out does not invent one; permissions and row visibility are unchanged
by design and by the catalog/plan evidence above.

## Boundaries

- No migration, `ALTER POLICY`, grant, role, or RLS-flag change was made by this
  close-out; no `has_role` helper body was touched.
- Later families #4429 and #4430 were closed 2026-11-04 on the same
  already-live basis; nothing in this record changes their scope.
- This record closes #4428 only; the parent #4421 matrix row and checkbox for
  #4428 are updated alongside it. It does not close #4421 or the wider #2326
  programme.
