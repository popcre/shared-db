# OPA product lines, Minnie program, Style Guide field — findings 2026-11-12

Supports `plan_mg06_licensor_site_path.md`.

## (a) Property list per "Create New Product" line — PARTIAL (live check blocked)
On 2026-11-12 12:35 PM EST Albert's Chrome OPA session had expired (MyID sign-in
page). Credentials are never entered by AI, so lines were not re-opened live.
Captured evidence already in the database (`plm.opa_capture_scope`, 2026-09-10):
| Scope | Line of business | Type | Template | Properties |
|---|---|---|---|---|
| disney_home_standard | 200 (Home) | Standard | 21 | 1451 |
| lucas_home_standard | 200 (Home) | Standard | 462 | 74 |
So Disney and Lucas are separate brands with separate templates and property lists.
Range, Packaging and Line Sheet lines were never captured. TODO once OPA is signed in:
open each line, record template id and property list, load as new capture scopes.

## (b) Minnie program for a Minnie-only design — DECIDED from history
`plm.licensor_submission_pdf`, OPA property "Minnie": 406 of 406 character picks are
"Minnie & Me" (2022–2026). No split; no owner question needed.
Rule: MG06 Minnie Mouse → OPA property "Minnie" → "Minnie & Me".
Preschool designs use a different property, "Preschool CG Minnie (& Friends)" (26 subs) —
not this MG06 value.

## (c) Style Guide field — PARTIAL
Past PDFs record a Style Guide on only ~38 Disney-family submissions, nearly all Marvel
(e.g. "Marvel Universe", "Spider-Man", "Avengers"); 18 say "Character". Classic Disney
(Mickey/Minnie) submissions leave it blank. Working rule for the AI:
1. Leave blank unless the chosen OPA property offers style-guide options.
2. If offered, pick the guide whose name matches the art source on the design file;
   else the guide matching the property name; else "Character".
3. Never guess between two plausible guides — flag the style for a person.
Live check of how the dropdown is populated is pending OPA sign-in.
