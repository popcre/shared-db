#!/usr/bin/env python3
"""Synthetic tests for issue #2110 frozen-schema drop migration.

Validates the migration SQL structure without requiring a live database.
"""
import re
import sys
from pathlib import Path

MIGRATION = Path(__file__).resolve().parent.parent / "supabase" / "migrations" / "20261010033616_drop_frozen_designflow_schema.sql"

def read_migration() -> str:
    return MIGRATION.read_text(encoding="utf-8")

def test_migration_exists():
    assert MIGRATION.exists(), f"Migration not found: {MIGRATION}"

def test_single_transaction():
    sql = read_migration()
    assert sql.count("BEGIN;") == 1, "Expected exactly one BEGIN"
    assert sql.count("COMMIT;") == 1, "Expected exactly one COMMIT"

def test_no_cascade():
    sql = read_migration()
    # Check only non-comment lines for CASCADE
    for line in sql.splitlines():
        stripped = line.strip()
        if stripped.startswith("--"):
            continue
        assert "CASCADE" not in line, f"CASCADE found in SQL line: {line}"

def test_restict_drops():
    sql = read_migration()
    assert "DROP TABLE" in sql, "Expected DROP TABLE"
    assert "DROP SEQUENCE" in sql, "Expected DROP SEQUENCE"
    assert "DROP SCHEMA designflow_frozen_20260710 RESTRICT" in sql, "Expected DROP SCHEMA ... RESTRICT"
    # Check that every DROP statement ends with RESTRICT (handle multi-line)
    # Strip comments first
    lines = [l for l in sql.splitlines() if not l.strip().startswith("--")]
    clean = "\n".join(lines)
    drops = re.findall(r"DROP\s+(?:TABLE|SEQUENCE|SCHEMA)[^;]+;", clean, re.IGNORECASE | re.DOTALL)
    assert len(drops) >= 3, f"Expected at least 3 DROP statements, found {len(drops)}"
    for d in drops:
        assert "RESTRICT" in d, f"DROP without RESTRICT: {d[:80]}"

def test_all_tables_dropped():
    sql = read_migration()
    for table in ["Factory", "Roles", "art_piece", "artists", "comments", "customers", "product_category"]:
        assert f'designflow_frozen_20260710."{table}"' in sql or f"designflow_frozen_20260710.{table}" in sql, f"Missing table: {table}"

def test_all_sequences_dropped():
    sql = read_migration()
    for seq in ["Factory_id_seq", "Roles_Id_seq", "StandardizedVersionDetail_id_seq",
                "StandardizedVersion_id_seq", "art_piece_id_seq", "artists_id_seq",
                "comments_id_seq", "customers_customers_id_seq", "product_category_id_seq"]:
        assert seq in sql, f"Missing sequence: {seq}"

def test_inbound_fk_check():
    sql = read_migration()
    assert "inbound foreign key" in sql.lower() or "inbound" in sql.lower(), "Expected inbound FK precondition"

def test_postcondition():
    sql = read_migration()
    assert "to_regnamespace('designflow_frozen_20260710') IS NOT NULL" in sql, "Expected schema-absent postcondition"

def test_derived_from_header():
    sql = read_migration()
    assert "-- derived-from: none" in sql, "Expected derived-from header"

if __name__ == "__main__":
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    passed = failed = 0
    for t in tests:
        try:
            t()
            print(f"  PASS  {t.__name__}")
            passed += 1
        except AssertionError as e:
            print(f"  FAIL  {t.__name__}: {e}")
            failed += 1
    print(f"\n{passed} passed, {failed} failed")
    sys.exit(1 if failed else 0)
