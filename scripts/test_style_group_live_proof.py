#!/usr/bin/env python3
"""Guard issue #2478's one-off production proof route without weakening others."""
import hashlib
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from shared_db_live_proof import LiveProofError, execute_bounded_probe
from style_group_live_proof import (CA_FILE, CA_SHA256, PROBE_SHA256,
                                    execute_style_group_probe)
from test_shared_db_live_proof import FakeConnection


class StyleGroupProofTests(unittest.TestCase):
    def setUp(self):
        self.sql = (ROOT / ".github/live-proofs/2478.sql").read_text(encoding="utf-8")
        self.connection = FakeConnection()
        self.connection.state = ["postgres", "postgres", "postgres", "on",
                                 "8s", "1s", False, True]

    def test_public_ca_and_exact_committed_probe_are_pinned(self):
        self.assertEqual(hashlib.sha256(self.sql.encode()).hexdigest(), PROBE_SHA256)
        self.assertEqual(hashlib.sha256(CA_FILE.read_bytes()).hexdigest(), CA_SHA256)

    def test_only_exact_probe_uses_privileged_read_only_transaction(self):
        self.assertEqual(execute_style_group_probe(self.connection, self.sql), [{"passed": True}])
        self.assertEqual(self.connection.calls[0][0], "SET TRANSACTION READ ONLY")
        self.assertEqual(self.connection.calls[1][1], ("8000ms", "1000ms"))
        self.assertEqual(self.connection.calls[-1], (self.sql, None, {"prepare": True}))
        self.assertTrue(self.connection.rolled_back)
        with self.assertRaises(LiveProofError):
            execute_style_group_probe(FakeConnection(), "select true as passed")

    def test_role_limits_result_and_server_refusal_stop(self):
        for index, value in ((0, "service_role"), (1, "service_role"), (2, "other"),
                             (3, "off"), (4, "0"), (5, "0"), (6, True), (7, False)):
            with self.subTest(index=index):
                connection = FakeConnection()
                connection.state = self.connection.state[:]
                connection.state[index] = value
                with self.assertRaises(LiveProofError):
                    execute_style_group_probe(connection, self.sql)
                self.assertFalse(any(call[2].get("prepare") for call in connection.calls))
        self.connection.rows = [(False,)]
        with self.assertRaises(LiveProofError):
            execute_style_group_probe(self.connection, self.sql)
        self.connection.error = RuntimeError("private query text")
        with self.assertRaises(LiveProofError) as caught:
            execute_style_group_probe(self.connection, self.sql)
        self.assertNotIn("private query text", str(caught.exception))

    def test_general_bypassrls_refusal_remains(self):
        with self.assertRaises(LiveProofError):
            execute_bounded_probe(self.connection, self.sql, expected_role="postgres")

    def test_workflow_limits_direct_route_to_2478(self):
        workflow = (ROOT / ".github/workflows/shared-db-live-proof.yml").read_text()
        self.assertIn("inputs.work_issue != '2478'", workflow)
        self.assertIn("inputs.work_issue == '2478'", workflow)
        self.assertIn("scripts/style_group_live_proof.py", workflow)
        self.assertIn("secrets.SUPABASE_DB_PASSWORD_PRODUCTION", workflow)
        self.assertIn("name: shared-db-live-proof-${{ inputs.work_issue }}-${{ github.sha }}", workflow)


if __name__ == "__main__":
    unittest.main()
