"""Offline regression checks for the batch-4 catch-up migration (#6375).

These source-contract checks run without a database. Runtime SQL contracts
remain in supabase/tests/production_po_no_reuse.sql and the item-history tests.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20261115160800_sandbox_catchup_item_po_pdf_tables.sql"
SQL = re.sub(r"--[^\n]*", "", MIGRATION.read_text()).lower()
SQL = re.sub(r"\s+", " ", SQL).strip()


class CatchupContracts(unittest.TestCase):
    def privileges(self, table, role):
        # Start with the inherited plm service-role defaults from 20260810180000.
        privileges = {"select", "insert", "update", "delete"} if role == "service_role" else set()
        for action, rights, tables, roles in re.findall(
            r"\b(grant|revoke) (all|[a-z, ]+) on (plm\.[a-z_, .]+?) (?:to|from) ([a-z_, ]+);",
            SQL,
        ):
            if table not in tables.split(", ") or role not in roles.split(", "):
                continue
            rights = set(rights.split(", ")) if rights != "all" else {
                "select", "insert", "update", "delete", "truncate", "references", "trigger"
            }
            if action == "revoke":
                privileges -= rights
            else:
                privileges |= rights
        return privileges

    def test_po_guard_is_attached_to_every_insert_and_update(self):
        self.assertIn(
            "create trigger production_po_no_reuse before insert or update on "
            "plm.production_order for each row execute function plm.guard_production_po_number();",
            SQL,
        )

    def test_ledger_and_history_are_closed_to_application_roles(self):
        for table in (
            "plm.production_po_reservation", "plm.production_po_legacy_admission",
            "plm.item_user_assignment", "plm.item_workflow_action",
        ):
            for role in ("public", "anon", "authenticated", "service_role"):
                with self.subTest(table=table, role=role):
                    self.assertEqual(self.privileges(table, role), set())
        for table in ("plm.licensor_submission_pdf", "plm.licensor_submission_pdf_capture"):
            self.assertEqual(self.privileges(table, "service_role"), {"select", "insert"})
        self.assertIn(
            "grant update (loaded_file_count, status, completed_at, notes) "
            "on plm.licensor_submission_pdf_capture to service_role;", SQL,
        )
        self.assertEqual(
            self.privileges("plm.coldlion_property_sync_run", "service_role"),
            {"select", "insert", "update", "delete"},
        )

    def test_read_policies_have_table_grants(self):
        tables = re.findall(r"create policy .*? on (plm\.\w+) .*? for select to authenticated", SQL)
        self.assertEqual(len(tables), 3)
        for table in tables:
            self.assertEqual(self.privileges(table, "authenticated"), {"select"})

    def test_cutover_locks_validates_and_reserves_before_enforcement(self):
        steps = (
            "begin; lock table plm.production_order in share row exclusive mode;",
            "do $cutover$",
            "insert into plm.production_po_reservation(normalized_po) select distinct",
            "create trigger production_po_no_reuse",
            "commit;",
        )
        positions = [SQL.index(step) for step in steps]
        self.assertEqual(positions, sorted(positions))
        cutover = SQL.split("do $cutover$", 1)[1].split("$cutover$;", 1)[0]
        self.assertIn("plm.normalize_production_po_number(production_order_number) is null", cutover)
        self.assertIn("plm.normalize_production_po_number(production_order_number) = ''", cutover)
        self.assertIn("raise exception", cutover)
        self.assertIn("from plm.production_order on conflict (normalized_po) do nothing;", SQL)
        self.assertTrue(SQL.endswith("commit;"))

    def test_constraints_triggers_and_policies_can_replay(self):
        constraints = re.findall(r'alter table (plm\.\w+) add constraint "([^"]+)"', SQL)
        self.assertEqual(len(constraints), 39)
        for table, name in constraints:
            self.assertIn(
                "if not exists (select 1 from pg_catalog.pg_constraint "
                f"where conrelid = '{table}'::regclass and conname = '{name}') then "
                f'alter table {table} add constraint "{name}"', SQL,
            )
        for name, table in re.findall(r"create trigger (\w+) .*? on (plm\.\w+)", SQL):
            self.assertLess(SQL.index(f"drop trigger if exists {name} on {table};"),
                            SQL.index(f"create trigger {name} "))
        for name, table in re.findall(r'create policy "([^"]+)" on (plm\.\w+)', SQL):
            self.assertLess(SQL.index(f'drop policy if exists "{name}" on {table};'),
                            SQL.index(f'create policy "{name}" '))


if __name__ == "__main__":
    unittest.main()
