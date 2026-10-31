# The typed database contract

`database.types.ts` is the **canonical, generated** TypeScript description of the
shared Supabase database. It is the one place an application should learn the
shape of a table, view, function, or enum.

It is generated, never hand-edited. If it is wrong, the fix is a migration and a
regeneration, not a patch to this file.

## What applications should consume

`sync.yml` mirrors this repository's root into the `shared-db/` subfolder of every
consumer repo on each push to `main`. So from inside a consumer application the
file is already present at:

```
shared-db/types/database.types.ts
```

Import it directly from there. Do not copy it elsewhere in the application, and
do not re-declare these types by hand — a second copy is a second source of
truth, and it will drift.

```ts
import type { Database } from '../shared-db/types/database.types'

// Supabase client, fully typed:
const supabase = createClient<Database>(url, key)

// A single row type, by schema and table:
type SampleWorkflow = Database['dflow']['Tables']['sample_workflow']['Row']

// Insert and Update shapes are separate, and differ from Row:
type NewSampleWorkflow = Database['dflow']['Tables']['sample_workflow']['Insert']
```

`Row`, `Insert`, and `Update` are deliberately distinct. `Insert` omits columns
the database fills in (identities, defaults, generated columns); `Update` makes
everything optional. Using `Row` for a write is the usual cause of a spurious
"missing property" error.

## Which schemas are covered

`public`, `dflow`, `plm`, `core`, `app`, `hts_rag`.

If an application needs a schema not in that list, regenerate with it added
rather than hand-writing the missing piece.

## How to refresh it

1. Land the migration and apply it to **preview** through
   `shared-supabase-migrations.yml`.
2. Run the **Generate database types** workflow.
3. Download its `database-types` artifact.
4. Replace this file and open a normal reviewed pull request.

Step 4 is not automated on purpose. This file feeds nine applications, and a
generated file that changes without review is how a schema change reaches all of
them unnoticed.

## What it is generated from, and why that matters

The **Generate database types** workflow (`generate-database-types.yml`) has two
read-only paths. With `work_issue` blank, it reads the live **preview** project
selected by the repository variable `PREVIEW_PROJECT_REF` and produces the
`database-types` download described above. With `work_issue` supplied, it reads
**production** and produces an issue-bound artifact containing the generated
TypeScript and `db-generated-types-proof.json`. The production proof requires
exactly `public,dflow,plm,core,app,hts_rag`.

Neither path replays migration files. A merged migration is not evidence that
it has been applied to the source database. Before presenting a production
snapshot as current, compare its generation time and the production migration
ledger with the migrations whose objects consumers need. Record the source,
generation run, and any unapplied migrations in the regeneration PR. If ledger
verification is unavailable, mark production freshness unverified; do not infer
that missing objects are intentionally unapplied or hand-edit generated types.
