-- Item -> licensor-scrape style guide links (resolver half).
--
-- Companion to 20261030040817_sku_style_guide_links_schema.sql.
--
-- Three evidence arms write into public.sku_style_guide_links:
--   1. filename_exact / filename_normalized  - an extracted "FILES USED" name matched
--      against plm.asset_file_style_guide_index, following the portal's own
--      asset -> style-guide assertion.
--   2. sheet_declared                        - the licensing sheet's own
--      "CORE/STYLE GUIDE USED:" field, kept verbatim.
--   3. sheet_label_match                     - that declared field matched by normalised
--      label against a portal style-guide label.
--
-- Quarantine model: the resolver only upserts and refreshes last_seen_at. It never
-- deletes or unlinks a row.

-- ---------------------------------------------------------------------------
-- 1. Normalised style-guide label key (declared label <-> portal label)
-- ---------------------------------------------------------------------------
create or replace function public.style_guide_label_norm(p_label text)
returns text
language sql
immutable
parallel safe
returns null on null input
as $$
  select nullif(
    btrim(
      regexp_replace(
        regexp_replace(lower(btrim(p_label)), '^\s*(the|a|an)\s+', ''),
        '[^a-z0-9]+', ' ', 'g')
    ), '')
$$;

comment on function public.style_guide_label_norm(text) is
  'Normalised style-guide label key: lowercased, leading article removed, punctuation '
  'collapsed to single spaces. Used to match a sheet-declared guide name against a '
  'portal style-guide label.';

-- ---------------------------------------------------------------------------
-- 2. Plausible source-file-name test
-- ---------------------------------------------------------------------------
-- "FILES USED" sections carry OCR noise. A real source-art name always contains at
-- least one letter, underscore, hyphen or dot; pure numbers and page furniture do not.
create or replace function public.is_plausible_source_file_name(p_name text)
returns boolean
language sql
immutable
parallel safe
returns null on null input
as $$
  select length(btrim(p_name)) between 2 and 200
     and btrim(p_name) ~ '[A-Za-z0-9._-]'
     and btrim(p_name) ~ '[A-Za-z]'
     and btrim(p_name) !~ '^[0-9]+$'
     and lower(btrim(p_name)) not in (
       'none','n/a','na','tbd','see attached','see attachment','various','multiple',
       'page','mockup','quick reference','item dimensions','licensor info'
     )
$$;

-- ---------------------------------------------------------------------------
-- 3. FILES USED parser (improved) - writes public.sku_files_used
-- ---------------------------------------------------------------------------
-- Replaces the first-cut parser. Improvements, all learned from the live corpus:
--   * header aliases widened (artwork files / source art / files used / ...);
--   * inline values split on comma, semicolon and pipe;
--   * trailing OCR punctuation stripped;
--   * entries validated by is_plausible_source_file_name instead of "not all digits".
-- Multi-line sections still stop at a blank line or a "label:" line, which is how the
-- POP licensing-sheet template is laid out.
create or replace function public.parse_pdf_files_used(p_asset_id uuid)
returns integer
language plpgsql
set search_path to 'public'
as $function$
declare
  v_sku     text;
  v_ftype   text;
  v_fname   text;
  v_text    text;
  v_lines   text[];
  v_in_sect boolean := false;
  v_line    text;
  v_trimmed text;
  v_count   int := 0;
  v_entry   text;
  v_inline  text;
begin
  select sku, file_type::text, filename into v_sku, v_ftype, v_fname
  from assets where id = p_asset_id;
  if v_sku is null or btrim(v_sku) = '' then return 0; end if;

  -- Style Guide Sources are parsed ONLY from licensing-sheet / tech-pack PDFs.
  if not public.is_style_guide_source_pdf(v_ftype, v_fname) then return 0; end if;

  select extracted_text into v_text
  from pdf_text_samples
  where asset_id = p_asset_id and extracted_text is not null
  order by sampled_at desc limit 1;
  if v_text is null then return 0; end if;

  v_lines := string_to_array(v_text, E'\n');
  foreach v_line in array v_lines loop
    v_trimmed := btrim(v_line);

    if v_trimmed ~* '^(files?\s+used|source\s+files?|art\s+files?|artwork\s+files?|design\s+files?|source\s+art(work)?)\s*:' then
      v_in_sect := true;
      v_inline := btrim(regexp_replace(v_trimmed,
        '(?i)^(files?\s+used|source\s+files?|art\s+files?|artwork\s+files?|design\s+files?|source\s+art(work)?)\s*:\s*', ''));
      v_inline := btrim(v_inline, E' \t.,;:');
      if v_inline <> '' then
        foreach v_entry in array regexp_split_to_array(v_inline, '[,;|]') loop
          v_entry := btrim(btrim(v_entry), E' \t.,;:');
          if public.is_plausible_source_file_name(v_entry) then
            insert into sku_files_used (sku, file_name, source)
            values (v_sku, v_entry, 'pdf_text')
            on conflict (sku, file_name) do nothing;
            v_count := v_count + 1;
          end if;
        end loop;
        v_in_sect := false;
      end if;
      continue;
    end if;

    if v_in_sect then
      if v_trimmed = '' or v_trimmed ~ '^\S[^:]*:\s*$' then
        v_in_sect := false;
        continue;
      end if;
      v_entry := btrim(v_trimmed, E' \t.,;:');
      if public.is_plausible_source_file_name(v_entry) then
        insert into sku_files_used (sku, file_name, source)
        values (v_sku, v_entry, 'pdf_text')
        on conflict (sku, file_name) do nothing;
        v_count := v_count + 1;
      end if;
    end if;
  end loop;
  return v_count;
end;
$function$;

comment on function public.parse_pdf_files_used(uuid) is
  'Parse the "FILES USED" section of a licensing-sheet / tech-pack PDF text sample into '
  'public.sku_files_used. Gated by is_style_guide_source_pdf; entries are validated by '
  'is_plausible_source_file_name.';

-- ---------------------------------------------------------------------------
-- 4. Declared style-guide parser - writes public.sku_style_guide_links
-- ---------------------------------------------------------------------------
-- The POP licensing-sheet template carries its own "CORE/STYLE GUIDE USED:" field.
-- That is the designer's declaration, captured verbatim. It is stored as evidence
-- (source_system = 'sheet_declared') and is never presented as a portal identity.
create or replace function public.parse_pdf_declared_style_guide(p_asset_id uuid)
returns integer
language plpgsql
set search_path to 'public'
as $function$
declare
  v_sku   text;
  v_ftype text;
  v_fname text;
  v_text  text;
  v_label text;
  v_key   text;
begin
  select sku, file_type::text, filename into v_sku, v_ftype, v_fname
  from assets where id = p_asset_id;
  if v_sku is null or btrim(v_sku) = '' then return 0; end if;
  if not public.is_style_guide_source_pdf(v_ftype, v_fname) then return 0; end if;

  select extracted_text into v_text
  from pdf_text_samples
  where asset_id = p_asset_id and extracted_text is not null
  order by sampled_at desc limit 1;
  if v_text is null then return 0; end if;

  v_label := btrim((regexp_match(v_text,
    '(?im)^\s*(?:core\s*/\s*)?style\s+guide\s+used\s*:\s*([^\r\n]{1,200})'))[1]);
  if v_label is null then return 0; end if;
  v_label := btrim(v_label, E' \t.,;:');
  if not public.is_plausible_source_file_name(v_label) then
    return 0;
  end if;

  v_key := public.style_guide_label_norm(v_label);
  if v_key is null or v_key = '' then return 0; end if;

  insert into sku_style_guide_links
    (sku, file_name, source_system, source_style_guide_key, style_guide_label,
     match_method, match_confidence, matched_asset_count)
  values
    (v_sku, null, 'sheet_declared', v_key, v_label, 'sheet_declared', 1.0, 1)
  on conflict on constraint sku_style_guide_links_identity_key
  do update set last_seen_at = now(), style_guide_label = excluded.style_guide_label;
  return 1;
end;
$function$;

comment on function public.parse_pdf_declared_style_guide(uuid) is
  'Capture the licensing sheet''s own "CORE/STYLE GUIDE USED:" value for an item as '
  'sheet_declared evidence in public.sku_style_guide_links. Verbatim; no portal claim.';

-- ---------------------------------------------------------------------------
-- 5. Backfill both parsers across every existing text sample
-- ---------------------------------------------------------------------------
create or replace function public.backfill_pdf_files_used()
returns integer
language plpgsql
set search_path to 'public'
as $function$
declare
  v_id    uuid;
  v_total int := 0;
begin
  for v_id in (
    select distinct asset_id
    from pdf_text_samples
    where asset_id is not null
      and extracted_text is not null
      and char_count > 100
  ) loop
    v_total := v_total + public.parse_pdf_files_used(v_id);
    perform public.parse_pdf_declared_style_guide(v_id);
  end loop;
  return v_total;
end;
$function$;

comment on function public.backfill_pdf_files_used() is
  'Re-run the FILES USED and declared-style-guide parsers over every existing '
  'pdf_text_samples row. Needed because bulk_insert_pdf_text_samples skips the per-row '
  'trigger and only parses the rows in that batch; samples written before the parsers '
  'existed are otherwise never parsed.';

-- ---------------------------------------------------------------------------
-- 6. Cross-reference resolver
-- ---------------------------------------------------------------------------
create or replace function public.resolve_sku_style_guide_links()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
set statement_timeout to '120s'
as $function$
declare
  v_filename_rows int := 0;
  v_declared_rows int := 0;
  v_label_rows    int := 0;
begin
  -- ARM 1 - extracted file name -> portal style guide.
  with src as (
    select distinct u.sku, u.file_name, public.file_name_norm(u.file_name) as fn
    from public.sku_files_used u
    where u.file_name is not null and btrim(u.file_name) <> ''
  ),
  hits as (
    select s.sku, s.file_name, i.source_system, i.source_style_guide_key,
           i.style_guide_label, i.core_style_guide_id,
           min(lower(btrim(i.matched_file_name))) as sample_file_name,
           count(distinct i.matched_file_name)    as matched_asset_count
    from src s
    join plm.asset_file_style_guide_index i on i.file_name_norm = s.fn
    group by s.sku, s.file_name, i.source_system, i.source_style_guide_key,
             i.style_guide_label, i.core_style_guide_id
  ),
  scored as (
    -- How many distinct portal guides this one (sku, file_name) lands on. More than
    -- one means the file name is not decisive, so confidence is divided accordingly.
    select h.*, count(*) over (partition by h.sku, h.file_name) as guide_count
    from hits h
  ),
  ins as (
    insert into public.sku_style_guide_links
      (sku, file_name, source_system, source_style_guide_key, style_guide_label,
       match_method, match_confidence, matched_asset_count, core_style_guide_id)
    select s.sku, s.file_name, s.source_system, s.source_style_guide_key,
           s.style_guide_label,
           case when lower(btrim(s.file_name)) = s.sample_file_name
                then 'filename_exact' else 'filename_normalized' end,
           1.0 / greatest(s.guide_count, 1)::real,
           s.matched_asset_count,
           s.core_style_guide_id
    from scored s
    on conflict on constraint sku_style_guide_links_identity_key
    do update
      set last_seen_at = now(),
          style_guide_label   = excluded.style_guide_label,
          match_confidence    = excluded.match_confidence,
          matched_asset_count = excluded.matched_asset_count,
          core_style_guide_id = coalesce(excluded.core_style_guide_id,
                                        public.sku_style_guide_links.core_style_guide_id)
    returning 1
  )
  select count(*) into v_filename_rows from ins;

  -- ARM 2 - the sheet's own declared style guide, verbatim.
  with decl as (
    select a.sku,
           btrim(btrim((regexp_match(p.extracted_text,
             '(?im)^\s*(?:core\s*/\s*)?style\s+guide\s+used\s*:\s*([^\r\n]{1,200})'))[1]),
             E' \t.,;:') as label
    from public.pdf_text_samples p
    join public.assets a on a.id = p.asset_id
    where p.extracted_text is not null
      and p.extracted_text ~* 'style\s+guide\s+used\s*:'
      and a.sku is not null and btrim(a.sku) <> ''
      and public.is_style_guide_source_pdf(a.file_type::text, a.filename)
  ),
  ins as (
    insert into public.sku_style_guide_links
      (sku, file_name, source_system, source_style_guide_key, style_guide_label,
       match_method, match_confidence, matched_asset_count)
    select d.sku, null, 'sheet_declared', public.style_guide_label_norm(d.label),
           d.label, 'sheet_declared', 1.0, 1
    from decl d
    where d.label <> ''
      and public.style_guide_label_norm(d.label) is not null
      and public.is_plausible_source_file_name(d.label)
    on conflict on constraint sku_style_guide_links_identity_key
    do update set last_seen_at = now(), style_guide_label = excluded.style_guide_label
    returning 1
  )
  select count(*) into v_declared_rows from ins;

  -- ARM 3 - declared label matched against a portal style-guide label.
  with decl as (
    select a.sku,
           btrim(btrim((regexp_match(p.extracted_text,
             '(?im)^\s*(?:core\s*/\s*)?style\s+guide\s+used\s*:\s*([^\r\n]{1,200})'))[1]),
             E' \t.,;:') as label
    from public.pdf_text_samples p
    join public.assets a on a.id = p.asset_id
    where p.extracted_text is not null
      and p.extracted_text ~* 'style\s+guide\s+used\s*:'
      and a.sku is not null and btrim(a.sku) <> ''
      and public.is_style_guide_source_pdf(a.file_type::text, a.filename)
  ),
  guides as (
    select distinct i.source_system, i.source_style_guide_key, i.style_guide_label,
           i.core_style_guide_id,
           public.style_guide_label_norm(i.style_guide_label) as ln
    from plm.asset_file_style_guide_index i
    where btrim(i.style_guide_label) <> ''
  ),
  hits as (
    select d.sku, d.label, g.source_system, g.source_style_guide_key,
           g.style_guide_label, g.core_style_guide_id
    from decl d
    join guides g on g.ln = public.style_guide_label_norm(d.label)
    where public.style_guide_label_norm(d.label) is not null
  ),
  ins as (
    insert into public.sku_style_guide_links
      (sku, file_name, source_system, source_style_guide_key, style_guide_label,
       match_method, match_confidence, matched_asset_count)
    select h.sku, null, h.source_system, h.source_style_guide_key,
           h.style_guide_label, 'sheet_label_match', 1.0, 1
    from hits h
    on conflict on constraint sku_style_guide_links_identity_key
    do update set last_seen_at = now(),
                  style_guide_label   = excluded.style_guide_label,
                  core_style_guide_id = coalesce(excluded.core_style_guide_id,
                                                public.sku_style_guide_links.core_style_guide_id)
    returning 1
  )
  select count(*) into v_label_rows from ins;

  return jsonb_build_object(
    'filename_rows', v_filename_rows,
    'declared_rows', v_declared_rows,
    'label_match_rows', v_label_rows
  );
end;
$function$;

comment on function public.resolve_sku_style_guide_links() is
  'Derive public.sku_style_guide_links from (a) extracted FILES USED file names matched '
  'against plm.asset_file_style_guide_index, (b) the sheet''s declared CORE/STYLE GUIDE '
  'USED field, and (c) that declared field matched to a portal guide label. Upsert only; '
  'never deletes. SECURITY DEFINER because plm.* is not PostgREST-exposed.';

revoke all on function public.resolve_sku_style_guide_links() from public, anon, authenticated;
grant execute on function public.resolve_sku_style_guide_links() to service_role, postgres;
grant execute on function public.backfill_pdf_files_used() to service_role, postgres;
grant execute on function public.parse_pdf_files_used(uuid) to service_role, postgres;
grant execute on function public.parse_pdf_declared_style_guide(uuid) to service_role, postgres;
grant execute on function public.style_guide_label_norm(text) to service_role, postgres, authenticated;
grant execute on function public.is_plausible_source_file_name(text) to service_role, postgres, authenticated;
grant execute on function public.file_name_norm(text) to service_role, postgres, authenticated;

-- ---------------------------------------------------------------------------
-- 7. Nightly refresh
-- ---------------------------------------------------------------------------
-- Runs after the 02:00 UTC PopSG crawl and the 04:00 UTC sku_files_used resolver, so
-- newly captured portal rows and newly linked files-used rows are picked up the same
-- night.
select cron.schedule(
  'resolve-sku-style-guide-links-nightly',
  '30 4 * * *',
  $$select public.resolve_sku_style_guide_links()$$
);
