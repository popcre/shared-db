"""Tests for fail-closed idempotent apply-attempt recovery (issue #3397)."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from apply_attempt_recovery import (  # noqa: E402
    ApplyRecoveryError,
    RecoveryClaim,
    ApplyAttemptEvidence,
    evaluate_recovery,
    recover_apply_attempt,
    stable_claim_digest,
    strip_observation_metadata,
)


def _claim(**overrides):
    base = dict(
        source="shared-supabase-migrations",
        migration_hashes=("a" * 40, "b" * 40),
        target="preview",
        baseline_sha="c" * 40,
        producer="trusted-producer",
    )
    base.update(overrides)
    return RecoveryClaim(**base)


class TestStableClaim(unittest.TestCase):
    def test_observation_metadata_is_stripped(self):
        payload = {
            "source": "x",
            "observed_at": "2026-09-23T00:00:00Z",
            "run_id": 12345,
            "target": "preview",
        }
        stable = strip_observation_metadata(payload)
        self.assertEqual(stable, {"source": "x", "target": "preview"})

    def test_digest_ignores_observation_fields(self):
        a = {"source": "x", "target": "y", "observed_at": "1"}
        b = {"source": "x", "target": "y", "observed_at": "2", "run_id": 99}
        self.assertEqual(stable_claim_digest(a), stable_claim_digest(b))

    def test_digest_changes_with_stable_fields(self):
        a = {"source": "x", "target": "y"}
        b = {"source": "x", "target": "z"}
        self.assertNotEqual(stable_claim_digest(a), stable_claim_digest(b))


class TestRecoveryClaim(unittest.TestCase):
    def test_requires_exact_shas(self):
        with self.assertRaises(ApplyRecoveryError):
            _claim(baseline_sha="nope")
        with self.assertRaises(ApplyRecoveryError):
            _claim(migration_hashes=("short",))

    def test_requires_at_least_one_migration(self):
        with self.assertRaises(ApplyRecoveryError):
            _claim(migration_hashes=())

    def test_claim_digest_is_stable(self):
        c1 = _claim()
        c2 = _claim()
        self.assertEqual(c1.claim_digest, c2.claim_digest)
        self.assertEqual(len(c1.claim_digest), 64)


class TestEvaluateRecovery(unittest.TestCase):
    def _evidence(self, **overrides):
        base = dict(
            ledger_rows=({"version": "a" * 40, "hash": "d" * 64}, {"version": "b" * 40, "hash": "e" * 64}),
            catalog_result={"passed": True},
            prepared_write_status="landed",
            exclusive_lock_held=True,
        )
        base.update(overrides)
        return ApplyAttemptEvidence(**base)

    def test_refuses_without_lock(self):
        with self.assertRaises(ApplyRecoveryError) as ctx:
            evaluate_recovery(_claim(), self._evidence(exclusive_lock_held=False))
        self.assertIn("exclusive lock", str(ctx.exception))

    def test_ambiguous_prepared_write_never_authorizes(self):
        with self.assertRaises(ApplyRecoveryError) as ctx:
            evaluate_recovery(_claim(), self._evidence(prepared_write_status="ambiguous"))
        self.assertIn("ambiguous", str(ctx.exception))

    def test_unknown_prepared_write_refused(self):
        with self.assertRaises(ApplyRecoveryError):
            evaluate_recovery(_claim(), self._evidence(prepared_write_status="maybe"))

    def test_absent_is_not_applied_and_does_not_authorize_reapply(self):
        result = evaluate_recovery(_claim(), self._evidence(prepared_write_status="absent"))
        self.assertEqual(result["disposition"], "not-applied")
        self.assertFalse(result["authorizes_reapply"])

    def test_missing_ledger_content_refused(self):
        evidence = self._evidence(
            ledger_rows=({"version": "a" * 40, "hash": "d" * 64},),
        )
        with self.assertRaises(ApplyRecoveryError) as ctx:
            evaluate_recovery(_claim(), evidence)
        self.assertIn("missing claimed migration", str(ctx.exception))

    def test_catalog_failure_refused(self):
        with self.assertRaises(ApplyRecoveryError):
            evaluate_recovery(_claim(), self._evidence(catalog_result={"passed": False}))
        with self.assertRaises(ApplyRecoveryError):
            evaluate_recovery(_claim(), self._evidence(catalog_result=None))

    def test_happy_path_recovered_without_reapply(self):
        result = evaluate_recovery(_claim(), self._evidence())
        self.assertEqual(result["disposition"], "recovered")
        self.assertFalse(result["authorizes_reapply"])
        self.assertIn("verification_digest", result)

    def test_ledger_version_prefix_accepted(self):
        evidence = self._evidence(
            ledger_rows=({"version": "a" * 14 + "f" * 26, "hash": "d" * 64}, {"version": "b" * 14 + "f" * 26, "hash": "e" * 64}),
        )
        # Claim uses full 40-hex; ledger keys use 14-digit version prefixes.
        claim = _claim(migration_hashes=("a" * 14 + "f" * 26, "b" * 14 + "f" * 26))
        result = evaluate_recovery(claim, evidence)
        self.assertEqual(result["disposition"], "recovered")


class TestTrustedAdapters(unittest.TestCase):
    def test_callers_supply_adapters_not_assertions(self):
        result = recover_apply_attempt(
            source="src",
            migration_hashes=("a" * 40,),
            target="preview",
            baseline_sha="b" * 40,
            producer="p",
            read_ledger=lambda: ({"version": "a" * 40, "hash": "c" * 64},),
            read_catalog=lambda: {"passed": True},
            read_prepared_write=lambda: "landed",
            lock_is_held=lambda: True,
        )
        self.assertEqual(result["disposition"], "recovered")

    def test_rejects_non_callable_adapters(self):
        with self.assertRaises(ApplyRecoveryError):
            recover_apply_attempt(
                source="src",
                migration_hashes=("a" * 40,),
                target="preview",
                baseline_sha="b" * 40,
                producer="p",
                read_ledger=None,
                read_catalog=lambda: {"passed": True},
                read_prepared_write=lambda: "landed",
                lock_is_held=lambda: True,
            )


if __name__ == "__main__":
    unittest.main()
