# Note for the session working on Mickey / Minnie / Mickey & Friends properties (2026-11-12, 12:30 PM EST)

What the MG06 work is doing, so you do not collide with it:

1. **MG06 keeps short names.** The item field MG06 (ColdLion merch group 06) is the licensed
   Property, with short display names (e.g. MICKEY MOUSE). We are not renaming MG06 values to
   match Disney's site wording.
2. **A new backend table stores the licensor-site path** for each MG06 value
   (`plan_mg06_licensor_site_path.md`), e.g. MICKEY MOUSE → Disney OPA "Mickey Mouse Family"
   > character "Mickey Mouse". The AI uses it to pick the right option when filling OPA.
   Session `mg06-site-path` builds it; it is populated only after the corrected MG06 list.
3. **Missing Disney properties are being repaired.** OPA's "Minnie", "Preschool CG Mickey
   (& Friends)" and "Standard Characters" are stuck 'unresolved' in `plm.opa_property` and never
   became `core.property` rows. Session `mg06-ilona-props` is fixing the step that should
   create them (owner rule: every scraped submission property is created). Do not hand-create
   these three rows — wait for that fix, then link to them.
4. **Which Minnie program a Minnie-only design uses** is being settled from past submissions by
   session `mg06-opa-gaps` (findings go to `docs/`).
5. **MG06 add/inactivate decisions** (Albert's 2026-11-12 sheet vs. the earlier handoff) are
   being reconciled by session `mg06-sheet-check`; Ilona confirms the open ones.

If your work changes Mickey/Minnie/Mickey & Friends `core.property` rows or their names,
comment on PR popcre/shared-db#6091 first so the site-path table maps to the right rows.
