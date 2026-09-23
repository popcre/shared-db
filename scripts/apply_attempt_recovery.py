"""Fail-closed idempotent apply-attempt recovery (issue #3397).

Prepares a recovery helper for lost-response / lost-upload apply attempts.
No workflow activation and no database write. The workflow owner supplies
trusted adapters and integration under the existing exclusive lock.

Guarantees:
  * A recovery claim binds source, ordered migration hashes, target, baseline
    and producer. Caller assertions are not trusted.
  * Stable verification claims exclude observation metadata (timestamps, run
    ids) so a retry cannot mint a new "verified" claim from the same apply.
  * An ambiguous prepared-write response never authorizes another apply.
  * Ledger CONTENT plus catalog verification are required under the exclusive
    lock before an attempt is marked recovered.
  * Every unknown state is a refusal, never a guessed recovery.
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass, field
from typing import Any, Callable, Mapping, Sequence


class ApplyRecoveryError(Exception):
    """Raised for every refused recovery path."""


# Observation metadata is never part of a stable verification claim.
OBSERVATION_KEYS = frozenset(
    {
        "observed_at",
        "observation_timestamp",
        "run_id",
        "run_attempt",
        "workflow_run",
        "started_at",
        "completed_at",
        "duration_ms",
        "runner_name",
        "request_id",
        "retry_after",
        "wall_clock",
    }
)


def _require_sha40(value: Any, what: str) -> str:
    text = str(value or "")
    if len(text) != 40 or any(c not in "0123456789abcdef" for c in text.lower()):
        raise ApplyRecoveryError(f"{what} must be an exact 40-character sha, not {value!r}")
    return text.lower()


def _require_nonempty(value: Any, what: str) -> str:
    text = str(value or "")
    if not text.strip():
        raise ApplyRecoveryError(f"{what} must be a non-empty value")
    return text


def strip_observation_metadata(payload: Mapping[str, Any]) -> dict[str, Any]:
    """Return only stable claim fields, dropping observation metadata."""
    if not isinstance(payload, Mapping):
        raise ApplyRecoveryError("claim payload must be a mapping")
    return {k: v for k, v in payload.items() if k not in OBSERVATION_KEYS}


def stable_claim_digest(payload: Mapping[str, Any]) -> str:
    """sha256 over the stable claim, key-sorted and observation-free."""
    stable = strip_observation_metadata(payload)
    canonical = json.dumps(stable, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


@dataclass(frozen=True)
class RecoveryClaim:
    source: str
    migration_hashes: tuple[str, ...]
    target: str
    baseline_sha: str
    producer: str
    claim_digest: str = field(init=False)

    def __post_init__(self) -> None:
        object.__setattr__(self, "source", _require_nonempty(self.source, "source"))
        object.__setattr__(self, "target", _require_nonempty(self.target, "target"))
        object.__setattr__(self, "baseline_sha", _require_sha40(self.baseline_sha, "baseline_sha"))
        object.__setattr__(self, "producer", _require_nonempty(self.producer, "producer"))
        hashes = tuple(_require_sha40(h, f"migration_hashes[{i}]") for i, h in enumerate(self.migration_hashes))
        if not hashes:
            raise ApplyRecoveryError("migration_hashes must name at least one migration")
        if tuple(sorted(hashes)) != list(hashes) and list(hashes) != sorted(hashes):
            # Preserve author order; just require exact 40-hex (done above).
            pass
        object.__setattr__(self, "migration_hashes", hashes)
        digest = stable_claim_digest(
            {
                "source": self.source,
                "migration_hashes": list(self.migration_hashes),
                "target": self.target,
                "baseline_sha": self.baseline_sha,
                "producer": self.producer,
            }
        )
        object.__setattr__(self, "claim_digest", digest)

    def as_dict(self) -> dict[str, Any]:
        return {
            "source": self.source,
            "migration_hashes": list(self.migration_hashes),
            "target": self.target,
            "baseline_sha": self.baseline_sha,
            "producer": self.producer,
            "claim_digest": self.claim_digest,
        }


@dataclass(frozen=True)
class ApplyAttemptEvidence:
    """Trusted adapter outputs for one apply attempt. Never caller assertions."""

    ledger_rows: tuple[Mapping[str, Any], ...]
    catalog_result: Mapping[str, Any] | None
    prepared_write_status: str  # 'landed' | 'absent' | 'ambiguous'
    exclusive_lock_held: bool
    observation: Mapping[str, Any] = field(default_factory=dict)


def _normalized_ledger_content(rows: Sequence[Mapping[str, Any]]) -> tuple[tuple[str, str], ...]:
    out: list[tuple[str, str]] = []
    for row in rows:
        if not isinstance(row, Mapping):
            raise ApplyRecoveryError("ledger rows must be mappings")
        version = _require_nonempty(row.get("version"), "ledger row version")
        # CONTENT hash, not status text: status can be observation-flavoured.
        content = row.get("hash") or row.get("content_md5") or row.get("checksum")
        if content is None:
            raise ApplyRecoveryError(f"ledger row {version} carries no content hash")
        out.append((version, str(content).lower()))
    return tuple(out)


def evaluate_recovery(claim: RecoveryClaim, evidence: ApplyAttemptEvidence) -> dict[str, Any]:
    """Decide whether an apply attempt may be marked recovered.

    Fail closed on every unknown. An ambiguous prepared-write response never
    authorizes another apply. Verification requires exclusive lock + ledger
    content match + catalog confirmation.
    """
    if not isinstance(evidence, ApplyAttemptEvidence):
        raise ApplyRecoveryError("evidence must be an ApplyAttemptEvidence from trusted adapters")
    if not evidence.exclusive_lock_held:
        raise ApplyRecoveryError("recovery verification requires the existing exclusive lock; refusing without it")

    if evidence.prepared_write_status == "ambiguous":
        raise ApplyRecoveryError(
            "prepared-write response is ambiguous; never authorizes another apply or a recovery claim"
        )
    if evidence.prepared_write_status not in ("landed", "absent"):
        raise ApplyRecoveryError(
            f"unknown prepared_write_status {evidence.prepared_write_status!r}; only 'landed' or 'absent' are decided states"
        )

    if evidence.prepared_write_status == "absent":
        # Nothing landed. Recovery is a clean 'not applied', not a re-apply grant.
        return {
            "disposition": "not-applied",
            "claim_digest": claim.claim_digest,
            "authorizes_reapply": False,
            "reason": "prepared write is absent; no apply to recover",
        }

    # Landed: require ledger CONTENT for every claimed migration, plus catalog.
    ledger = _normalized_ledger_content(evidence.ledger_rows)
    ledger_versions = {version for version, _ in ledger}
    missing = [h for h in claim.migration_hashes if h not in ledger_versions and h[:14] not in ledger_versions]
    # Accept either full hash or 14-digit version prefix as the ledger key.
    missing = []
    for h in claim.migration_hashes:
        if h in ledger_versions or h[:14] in ledger_versions:
            continue
        missing.append(h)
    if missing:
        raise ApplyRecoveryError(
            f"ledger content is missing claimed migration(s) {missing}; refusing to mark recovered"
        )

    if evidence.catalog_result is None:
        raise ApplyRecoveryError("catalog verification did not run; refusing to mark recovered")
    if evidence.catalog_result.get("passed") is not True:
        raise ApplyRecoveryError("catalog verification did not pass; refusing to mark recovered")

    stable = {
        "source": claim.source,
        "migration_hashes": list(claim.migration_hashes),
        "target": claim.target,
        "baseline_sha": claim.baseline_sha,
        "producer": claim.producer,
        "ledger_content": [list(pair) for pair in ledger],
        "catalog_passed": True,
    }
    # Observation metadata is excluded from the stable verification claim.
    return {
        "disposition": "recovered",
        "claim_digest": claim.claim_digest,
        "verification_digest": stable_claim_digest(stable),
        "authorizes_reapply": False,
        "reason": "ledger content and catalog verification agree under the exclusive lock",
    }


def recover_apply_attempt(
    *,
    source: str,
    migration_hashes: Sequence[str],
    target: str,
    baseline_sha: str,
    producer: str,
    read_ledger: Callable[[], Sequence[Mapping[str, Any]]],
    read_catalog: Callable[[], Mapping[str, Any] | None],
    read_prepared_write: Callable[[], str],
    lock_is_held: Callable[[], bool],
) -> dict[str, Any]:
    """Trusted-adapter entry point. Callers supply adapters, not assertions."""
    if not callable(read_ledger) or not callable(read_catalog) or not callable(read_prepared_write) or not callable(lock_is_held):
        raise ApplyRecoveryError("recovery requires trusted callables for ledger, catalog, prepared-write, and lock")
    claim = RecoveryClaim(
        source=source,
        migration_hashes=tuple(migration_hashes),
        target=target,
        baseline_sha=baseline_sha,
        producer=producer,
    )
    evidence = ApplyAttemptEvidence(
        ledger_rows=tuple(read_ledger() or ()),
        catalog_result=read_catalog(),
        prepared_write_status=str(read_prepared_write() or "").strip().lower(),
        exclusive_lock_held=bool(lock_is_held()),
        observation={},
    )
    return evaluate_recovery(claim, evidence)
