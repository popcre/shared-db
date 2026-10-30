-- Item -> licensor-scrape style guide links (schema half).
--
-- WHY. PopDAM licensing-sheet / tech-pack PDFs carry a "FILES USED:" list of the
-- licensor source art a design was built from. Those names are parsed into
-- public.sku_files_used and today resolve only against the PopSG NAS crawl
-- (public.style_guide_files). This migration adds the second, licensor-authoritative
-- resolution: match each extracted file name against the licensor portal scrape
-- landings in plm.*, follow that portal's own asset -> style-guide assertion, and
-- record which style guide(s) the item drew from.
--
-- OWNERSHIP. App-owned PopDAM data, written by a governed resolver and read by the
-- PopDAM UI. It is deliberately NOT dam.asset_style_guide: that table is a canonical
-- asset-level edge, is written only by a governed migration, and requires DIRECT source
-- support (core.require_direct_support_for_canonical_edge). A filename match is DERIVED
-- evidence and the subject here is the ITEM (SKU / style group), not a single asset
-- file. Quarantine model, same as public.sku_files_used: rows are never auto-deleted.
--
-- No licensed licensor row value appears in this file.

-- ---------------------------------------------------------------------------
-- 1. Normalised file-name key
-- ---------------------------------------------------------------------------
-- Tech-pack "FILES USED" values are usually bare stems (no extension) while portal
-- asset rows carry real filenames with extensions and sometimes a folder prefix.
-- Both sides are keyed on: basename, lowercased, trailing extension stripped.
-- The extension pattern deliberately requires the first extension character to be a
-- letter so a dotted stem such as "MS_Core3.0_Extension_comp_02" is left intact.
create or replace function public.file_name_norm(p_name text)
returns text
language sql
immutable
parallel safe
returns null on null input
as $$
  select nullif(
    btrim(
      regexp_replace(
        regexp_replace(lower(btrim(p_name)), '.*[/\\]', ''),
        '\.[a-z][a-z0-9]{0,4}$', '')
    ), '')
$$;

comment on function public.file_name_norm(text) is
  'Normalised file-name matching key: basename, lowercased, trailing extension stripped. '
  'Shared by the plm.asset_file_style_guide_index view and the sku_style_guide_links resolver.';

-- ---------------------------------------------------------------------------
-- 2. Cross-portal filename -> style guide index
-- ---------------------------------------------------------------------------
-- One row per (portal, normalised file name, style guide the portal asserts that
-- file belongs to). Every arm below is a DIRECT portal assertion: an asset -> guide
-- relationship the source system publishes. No arm infers a guide from co-occurrence.
--
-- Portals WITHOUT a published style-guide relationship are deliberately absent:
--   * Paramount Creative Library publishes Collections, not Style Guides. A Collection
--     is not a Style Guide and must never be stored as one (level-mismatch trap).
--   * Coca-Cola publishes assets with no guide relationship.
--   * Disney OPA publishes properties/characters only - it has no file or guide arm.
--   * Sega guide candidates and Wildbrain keyword guides are pipeline inferences,
--     not portal-declared style guides.
-- Adding a portal means adding one UNION ALL arm here, after confirming the portal
-- itself asserts asset -> style guide.
create or replace view plm.asset_file_style_guide_index
with (security_invoker = true) as
  -- Disney DCP Vault: dcp_asset.style_guide_id is a direct FK.
  select
    'disney_dcpvault'::text          as source_system,
    public.file_name_norm(a.file_name) as file_name_norm,
    coalesce(nullif(g.source_guide_id, ''), g.id::text) as source_style_guide_key,
    g.folder_name                    as style_guide_label,
    g.core_style_guide_id            as core_style_guide_id,
    a.file_name                      as matched_file_name
  from plm.dcp_asset a
  join plm.dcp_style_guide g on g.id = a.style_guide_id

  union all
  -- Lucasfilm / Star Wars DCP Vault: same shape, separate namespace.
  select
    'lucasfilm_dcpvault',
    public.file_name_norm(a.file_name),
    coalesce(nullif(g.source_guide_id, ''), g.id::text),
    g.folder_name,
    g.core_style_guide_id,
    a.file_name
  from plm.lucasfilm_dcp_asset a
  join plm.lucasfilm_dcp_style_guide g on g.id = a.style_guide_id

  union all
  -- Marvel DCP Vault.
  select
    'marvel_dcpvault',
    public.file_name_norm(a.file_name),
    coalesce(nullif(g.source_guide_id, ''), g.id::text),
    g.folder_name,
    g.core_style_guide_id,
    a.file_name
  from plm.marvel_dcp_asset a
  join plm.marvel_dcp_style_guide g on g.id = a.style_guide_id

  union all
  -- Marvel ASGARD: filename lives on the node asset observation; the guide is
  -- reached through guide_node -> style_guide. Observation carries the exact
  -- visible filename, which is the more faithful match key.
  select
    'marvel_asgard',
    public.file_name_norm(o.exact_filename),
    coalesce(nullif(g.source_guide_key, ''), g.source_identity_key),
    g.exact_label,
    null::uuid,
    o.exact_filename
  from plm.marvel_asgard_node_asset_observation o
  join plm.marvel_asgard_guide_node n on n.id = o.guide_node_id
  join plm.marvel_asgard_style_guide g on g.id = n.style_guide_id
  where btrim(o.exact_filename) <> ''

  union all
  -- NBCU Creative Asset Factory: junction table is the direct assertion.
  select
    'nbcu',
    public.file_name_norm(a.file_name),
    g.style_guide_key,
    g.style_guide_label,
    g.core_style_guide_id,
    a.file_name
  from plm.nbcu_asset a
  join plm.nbcu_asset_style_guide l
    on l.capture_id = a.capture_id and l.asset_source_key = a.asset_source_key
  join plm.nbcu_style_guide g
    on g.capture_id = l.capture_id and g.style_guide_key = l.style_guide_key

  union all
  -- Warner STARLABS: normalised arm. source_id is '' for every Warner guide
  -- (the portal publishes no guide id), so identity falls back to fallback_key.
  select
    'warner_starlabs',
    public.file_name_norm(a.file_name),
    coalesce(nullif(g.source_id, ''), g.fallback_key),
    g.label,
    null::uuid,
    a.file_name
  from plm.wb_asset_normalized a
  join plm.wb_asset_style_guide_normalized l on l.asset_id = a.id
  join plm.wb_style_guide_normalized g on g.id = l.style_guide_id

  union all
  -- Peanuts (Tenovos): the asset row itself carries the style guide key.
  select
    'peanuts_tenovos',
    public.file_name_norm(a.file_name),
    g.value_key,
    g.value_label,
    null::uuid,
    a.file_name
  from plm.peanuts_asset a
  join plm.peanuts_style_guide g
    on g.capture_id = a.capture_id and g.value_key = a.style_guide_key

  union all
  -- Sesame Workshop (NetX): junction asset -> style guide.
  select
    'sesame_netx',
    public.file_name_norm(a.original_file_name),
    g.value_key,
    g.value_label,
    null::uuid,
    a.original_file_name
  from plm.sesame_asset a
  join plm.sesame_asset_style_guide l
    on l.capture_id = a.capture_id and l.asset_source_id = a.asset_source_id
  join plm.sesame_style_guide g
    on g.capture_id = l.capture_id and g.value_key = l.value_key
  where btrim(a.original_file_name) <> '';

comment on view plm.asset_file_style_guide_index is
  'Cross-portal index: one row per (portal, normalised file name, style guide the portal '
  'asserts that file belongs to). Every arm is a DIRECT source assertion; no arm infers a '
  'guide from co-occurrence. Paramount Collections and Coca-Cola assets are deliberately '
  'absent - neither portal publishes a style-guide relationship. Sega and Wildbrain '
  'are excluded because their guide relationships are inferred.';

alter view plm.asset_file_style_guide_index owner to postgres;

-- Internal resolver index: ASGARD landing tables are service-role-only.
-- UI readers use the authenticated-readable sku_style_guide_links result instead.
revoke all on plm.asset_file_style_guide_index from public, anon, authenticated;
grant select on plm.asset_file_style_guide_index to service_role;

-- ---------------------------------------------------------------------------
-- 3. Item -> style guide link table
-- ---------------------------------------------------------------------------
create table if not exists public.sku_style_guide_links (
  id                     uuid primary key default gen_random_uuid(),
  sku                    text not null,
  -- The extracted source file that produced the match. NULL when the row came from
  -- the sheet's own declared "CORE/STYLE GUIDE USED" field rather than a file match.
  file_name              text,
  source_system          text not null,
  source_style_guide_key text not null,
  style_guide_label      text not null,
  match_method           text not null,
  match_confidence       real not null default 1.0,
  -- How many distinct portal asset file names collapse onto this normalised key.
  -- >1 means the file name is not unique in the portal and the guide is one of
  -- several candidates - read the row as "possible", not "certain".
  matched_asset_count    integer not null default 1,
  -- Reserved for promotion to the canonical catalogue. core.style_guide is seeded
  -- empty today (fix_characters_style_guides.md Phase 3), so this stays NULL until
  -- that backfill lands. Never invented here.
  core_style_guide_id    uuid references core.style_guide (id) on delete set null,
  first_seen_at          timestamptz not null default now(),
  last_seen_at           timestamptz not null default now(),
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),

  constraint sku_style_guide_links_sku_chk            check (btrim(sku) <> ''),
  constraint sku_style_guide_links_source_system_chk  check (btrim(source_system) <> ''),
  constraint sku_style_guide_links_source_key_chk     check (btrim(source_style_guide_key) <> ''),
  constraint sku_style_guide_links_label_chk          check (btrim(style_guide_label) <> ''),
  constraint sku_style_guide_links_match_method_chk   check (
    match_method in ('filename_exact', 'filename_normalized', 'sheet_declared', 'sheet_label_match')
  ),
  constraint sku_style_guide_links_confidence_chk     check (match_confidence >= 0 and match_confidence <= 1),
  constraint sku_style_guide_links_asset_count_chk    check (matched_asset_count >= 1),
  constraint sku_style_guide_links_file_name_chk      check (file_name is null or btrim(file_name) <> ''),
  -- file_name is NULLable, so the identity key uses NULLS NOT DISTINCT the same way
  -- dam.sku_style_guide_source does. Named so the resolver can target it explicitly.
  constraint sku_style_guide_links_identity_key unique nulls not distinct
    (sku, source_system, source_style_guide_key, file_name)
);

create index if not exists sku_style_guide_links_sku_idx
  on public.sku_style_guide_links (sku);

create index if not exists sku_style_guide_links_guide_idx
  on public.sku_style_guide_links (source_system, source_style_guide_key);

create index if not exists sku_style_guide_links_core_guide_idx
  on public.sku_style_guide_links (core_style_guide_id)
  where core_style_guide_id is not null;

create trigger set_updated_at before update on public.sku_style_guide_links
  for each row execute function app.set_updated_at();

comment on table public.sku_style_guide_links is
  'Which licensor style guide(s) a PopDAM item (SKU / style group) drew its source art '
  'from. Derived by matching the item''s extracted "FILES USED" file names against '
  'plm.asset_file_style_guide_index, and by the sheet''s own "CORE/STYLE GUIDE USED" '
  'field. Evidence, not canonical: quarantine model, never auto-deleted. '
  'core_style_guide_id is a reserved promotion slot to core.style_guide (currently empty).';

comment on column public.sku_style_guide_links.file_name is
  'Extracted source file that produced the match. NULL for rows taken from the sheet''s '
  'declared "CORE/STYLE GUIDE USED" field.';

comment on column public.sku_style_guide_links.matched_asset_count is
  'Number of distinct portal asset file names that collapse onto this normalised key. '
  'Greater than 1 means the file name is ambiguous in the portal.';

alter table public.sku_style_guide_links enable row level security;

drop policy if exists "service role all" on public.sku_style_guide_links;
create policy "service role all" on public.sku_style_guide_links
  for all to service_role using (true) with check (true);

drop policy if exists "authenticated read" on public.sku_style_guide_links;
create policy "authenticated read" on public.sku_style_guide_links
  for select to authenticated using (true);

revoke all on public.sku_style_guide_links from public, anon;
grant select on public.sku_style_guide_links to authenticated;
grant select, insert, update, delete, truncate on public.sku_style_guide_links to service_role, postgres;
