-- #5758 Step 1 (claim #5777): ColdLion merch-group descriptions are not item data.
--
-- Baseline (docs/verification/db-anti-bloat-5758/20261105T2318Z/baseline.md, read
-- 2026-11-05 6:18 PM EST): of the newest 3,000 item_merch_group 'updated' change_log
-- rows, 2,994 changed only mg_desc (+hash/id); of 3,000 item_header 'updated' rows,
-- 2,981 changed only merchGroupNNDesc (+hash). The vendor's /items and /itemDetails
-- full snapshots intermittently omit the merchGroupNNDesc family while returning the
-- same merchGroupNN code, so hashing or storing those descriptions recorded the
-- omission as a nightly "change" (~10k rows/night, ~90% of coldlion.change_log).
--
-- Plan decision D4 (plan_db-anti-bloat-safeguards.md, 2026-11-05): item-slot rows and
-- their hashes carry merch-group CODES only; labels resolve by joining
-- coldlion.merch_group_detail on (company_code, division_code, mg_type_code, mg_code).
-- The loader change (tools/coldlion-landing) ships in the same merge; its change_log
-- suppression ignores exactly the fields dropped here, so this migration and the new
-- loader are safe in either apply order.
--
-- Readers checked before the drop (2026-11-05): none. plm.coldlion_item_merch_group
-- (20261005025111) exposes company/division/item/slot/mg_code/last_seen_at only;
-- grep of this repository, u2giants/popdam3 and popcre/designflow-backend finds no
-- reader of item_merch_group.mg_desc (popdam3 scripts/sync-coldlion-prepacks.mjs is a
-- WRITER and is aligned in the same landing window). The 2026-09-03 ingest ruling for
-- merchGroupNNDesc (issue #2081 comment 5526450180) is superseded for the item-slot
-- grain by this change; merch_group_detail.mg_desc (the master's own description) is
-- untouched.

-- 1. The slot row is (company, division, item, item_pkey, slot_no) + mg_code.
--    Dropping mg_desc also drops its column comment from 20260905014719.
alter table coldlion.item_merch_group
  drop column if exists mg_desc;

-- 2. One-time recompute of every slot hash to the codes-only canonical form, so the
--    first loader run after this change finds identical hashes and writes nothing
--    instead of re-hashing ~250k rows. The loader hashes
--    sha256(canonical JSON of {"mgCode":<code>,"slotNo":<n>}); canonical JSON is
--    sorted-key, no-space, standard string escaping, which is exactly what
--    to_jsonb(mg_code)::text and slot_no::text produce below. mg_code cannot be
--    blank (item_merch_group_mg_code_not_blank), so no quoting edge exists.
update coldlion.item_merch_group
   set source_hash = encode(
         extensions.digest(
           '{"mgCode":' || to_jsonb(mg_code)::text || ',"slotNo":' || slot_no::text || '}',
           'sha256'),
         'hex');

-- 3. Prove the recompute landed: every slot row's hash must equal the freshly
--    derived codes-only hash. A failure here aborts the migration (fail closed)
--    rather than leaving half-rehashed rows the loader would then flood-log.
do $$
begin
  if exists (
    select 1
      from coldlion.item_merch_group g
     where g.source_hash is distinct from
           encode(extensions.digest(
             '{"mgCode":' || to_jsonb(g.mg_code)::text || ',"slotNo":' || g.slot_no::text || '}',
             'sha256'), 'hex')
  ) then
    raise exception 'item_merch_group hash recompute incomplete: at least one slot row is not in the codes-only canonical form';
  end if;
end;
$$;

comment on table coldlion.item_merch_group is
  'ColdLion merchandise-group slots as ROWS, for both grains. item_pkey IS NULL is the '
  'item-header slot; item_pkey NOT NULL is that SKU''s own slot. All fourteen slots are '
  'representable at each grain. A CLEARED SLOT IS DELETED by the current-state loader in '
  'the same transaction as its parent upsert - upsert-only would preserve stale taxonomy, '
  'and mg_code may not be blank, so a cleared slot cannot be faked as an empty string. '
  'Owner ruling D16: licensor (slot 05) and property (slot 06) describe the COMPONENT '
  'style, never the Master assortment. A detail slot is NEVER defaulted, copied or fallen '
  'back from the item-header slot, in either direction. THIS IS A LOADER RULE, NOT A '
  'SCHEMA GUARANTEE: this table only makes a compliant loader possible by giving each '
  'grain its own row. No constraint here can detect a loader that copies the parent '
  'value onto a SKU, because a SKU may legitimately share its parent licensor (D14 '
  'measured that in a substantial minority of prepack groups), so value-equality '
  'enforcement would reject real data. D16 is enforced by the Step 7 loader and the '
  'Step 8 promotion contract. '
  'CHANGE 2026-11-05 (#5758 D4): descriptions are no longer item data. The slot row and '
  'its source_hash carry (slot_no, mg_code) only - the mg_desc column is dropped and the '
  'hash above is codes-only - because the vendor''s /items and /itemDetails snapshots '
  'intermittently omit merchGroupNNDesc for the same merchGroupNN code, which hashed the '
  'omission as a nightly change for ~90% of coldlion.change_log. The label for a code '
  'lives on coldlion.merch_group_detail; when a reader wants one, join on '
  '(company_code, division_code, mg_type_code, mg_code) - mg_code collides across types '
  'inside one division, so the type code is mandatory. Measured 2026-11-05 (baseline '
  'above): with mg_type_code = the zero-padded slot number, 68,289 of 252,269 slot rows '
  'have no merch_group_detail match and 181 (company, division, mg_type_code, mg_code) '
  'groups span more than one mg_category row - that join is incomplete and can return '
  'more than one label row (prefer active = ''Y''), so re-derive the mapping for a '
  'specific slot before relying on it.';
