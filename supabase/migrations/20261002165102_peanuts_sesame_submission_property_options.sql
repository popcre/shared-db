-- #3897: Peanuts and Sesame Workshop Submissions Property options (owner decisions
-- 2026-10-02, Albert Hazan, recorded in u2giants/licensor-source-data PRs #100 and #105).
--
-- reserved-version: 20261002165102 (claim #3898)
-- derived-from: 20260917144950 (plm.sesame_submission_property_option),
--               20260930202719 (plm.wildbrain_submission_property_option shape, grants, policies)
--
-- Owner report (chat 2026-10-02): "when i go to data.designflow.app, both peanuts and
-- sesame submissions sections have 0 properties in them".
--
-- Changes:
--   1. Seed the one owner-authorized Sesame Workshop Submissions option into the
--      existing plm.sesame_submission_property_option (MediaBox option for Sesame
--      Street). The other four captured options are not ingested (owner: "drop the
--      other four"). No structural change to that table.
--   2. New table plm.peanuts_submission_property_option, same shape as its Sesame and
--      WildBrain siblings, check-pinned to the two owner-entered Peanuts Properties.
--      These were entered manually by the owner, not scraped, so their keys are
--      owner-manual keys, never presented as portal source ids.
--   3. Not in this migration: the peanuts-submissions arm of
--      api.db_data_admin_scraped_source_inventory (step 2 of #3897; that function is
--      still held by claim #3842).

-- 1. Sesame Workshop: the one owner-authorized option.
insert into plm.sesame_submission_property_option
  (option_key, exact_label, ordinal, source_field, source_captured_at, raw)
values
  ('6f101119-6043-45b2-be4c-f4d42e65022c',
   'Sesame street',
   0,
   'property_source_id',
   '2026-08-21T11:21:21Z'::timestamptz,
   '{"source":"Sesame Workshop MediaBox Product Approvals","captured":"2026-08-21","captured_label":" Sesame Street","authority":"Albert Hazan owner decision 2026-10-02","source_repo":"u2giants/licensor-source-data#105"}'::jsonb)
on conflict (option_key) do nothing;

-- 2. Peanuts: new option table and its two owner-entered rows.
create table if not exists plm.peanuts_submission_property_option (
  option_key         text        not null,
  exact_label        text        not null,
  ordinal            integer     not null,
  source_field       text        not null,
  source_captured_at timestamptz not null,
  raw                jsonb       not null default '{}'::jsonb,
  loaded_at          timestamptz not null default now(),
  constraint peanuts_submission_property_option_pkey primary key (option_key),
  constraint peanuts_submission_property_option_label_nonblank_chk check (btrim(exact_label) <> ''),
  constraint peanuts_submission_property_option_ordinal_chk check (ordinal >= 0),
  constraint peanuts_submission_property_option_field_nonblank_chk check (btrim(source_field) <> ''),
  constraint peanuts_submission_property_option_raw_obj_chk check (jsonb_typeof(raw) = 'object'),
  -- Owner decision 2026-10-02: exactly these two Peanuts Submissions Properties.
  -- Widening this is a business decision and needs a reviewed migration.
  constraint peanuts_submission_property_option_owner_scope_chk
    check (option_key in ('owner-manual:peanuts-classic', 'owner-manual:charlie-brown-tv-special'))
);

comment on table plm.peanuts_submission_property_option is
  'PEANUTS SUBMISSIONS PROPERTY OPTIONS, NOT CANONICAL MASTER DATA. The POP Peanuts '
  'Submissions Properties entered manually by the owner on 2026-10-02 (#3897; '
  'u2giants/licensor-source-data#100). Not scraped: option_key is an owner-manual key, '
  'never a portal source id. Resolves nothing to core.*.';

alter table plm.peanuts_submission_property_option enable row level security;
revoke all on table plm.peanuts_submission_property_option from public, anon, authenticated, service_role;
grant select, insert on table plm.peanuts_submission_property_option to service_role;
grant select on table plm.peanuts_submission_property_option to authenticated;

drop policy if exists peanuts_submission_property_option_service_read on plm.peanuts_submission_property_option;
create policy peanuts_submission_property_option_service_read on plm.peanuts_submission_property_option
  for select to service_role using (true);
drop policy if exists peanuts_submission_property_option_plm_read on plm.peanuts_submission_property_option;
create policy peanuts_submission_property_option_plm_read on plm.peanuts_submission_property_option
  for select to authenticated using (app.has_app_access('plm') or app.has_role('administrator') or app.has_any_role(array['sales', 'licensing']::app.app_role[]));

insert into plm.peanuts_submission_property_option
  (option_key, exact_label, ordinal, source_field, source_captured_at, raw)
values
  ('owner-manual:peanuts-classic', 'Peanuts Classic', 0, 'owner_manual_entry',
   '2026-10-02T00:00:00Z'::timestamptz,
   '{"source":"manual owner entry","authority":"Albert Hazan owner decision 2026-10-02","source_repo":"u2giants/licensor-source-data#100"}'::jsonb),
  ('owner-manual:charlie-brown-tv-special', 'Charlie Brown TV Special', 1, 'owner_manual_entry',
   '2026-10-02T00:00:00Z'::timestamptz,
   '{"source":"manual owner entry","authority":"Albert Hazan owner decision 2026-10-02","source_repo":"u2giants/licensor-source-data#100"}'::jsonb)
on conflict (option_key) do nothing;

-- Self-check: exact counts and the sibling read grant.
do $$
begin
  if (select count(*) from plm.sesame_submission_property_option) <> 1
     or not exists (select 1 from plm.sesame_submission_property_option
                    where option_key = '6f101119-6043-45b2-be4c-f4d42e65022c'
                      and exact_label = 'Sesame street') then
    raise exception '#3897 self-check: Sesame must hold exactly the one owner-authorized option';
  end if;
  if (select count(*) from plm.peanuts_submission_property_option) <> 2 then
    raise exception '#3897 self-check: Peanuts must hold exactly the two owner-entered options';
  end if;
  if not (select c.relrowsecurity from pg_class c
          where c.oid = 'plm.peanuts_submission_property_option'::regclass) then
    raise exception '#3897 self-check: RLS is not enabled on plm.peanuts_submission_property_option';
  end if;
  if has_table_privilege('anon', 'plm.peanuts_submission_property_option', 'select')
     or has_table_privilege('authenticated', 'plm.peanuts_submission_property_option', 'insert')
     or not has_table_privilege('authenticated', 'plm.peanuts_submission_property_option', 'select')
     or has_table_privilege('service_role', 'plm.peanuts_submission_property_option', 'update') then
    raise exception '#3897 self-check: client roles hold more than the sibling read grant';
  end if;
  if (select count(*) from pg_policies where schemaname = 'plm'
        and tablename = 'peanuts_submission_property_option' and cmd = 'SELECT') <> 2 then
    raise exception '#3897 self-check: read policies are missing';
  end if;
end $$;
