"""The deterministic product-type reader.

`read_product_type(description)` returns exactly the #3036 `plm.item` columns
(minus `product_type_read_at`, which the writer sets) plus `matched_wording`,
which exists for evaluation and is never stored.

Determinism contract
--------------------
For a given rules version, the returned values depend only on the description
string. The reader never consults the clock, the locale, the hash seed, random
numbers, the environment or any I/O. Rule selection is a total order, so two
rules matching the same wording length can never swap places between runs.
"""

from __future__ import annotations

from dataclasses import dataclass
import re

from .normalization import candidate_wording, normalize, strip_size
from .rules import (
    MATERIAL_RULES,
    NO_TREATMENT,
    PRODUCT_RULES,
    RULES_VERSION,
    STATUS_ACCEPTED,
    STATUS_PLACEHOLDER,
    STATUS_UNREADABLE,
    TREATMENT_RULES,
    UNUSABLE_RULES,
    VALID_STATUSES,
)

FIELDS = (
    "product_type",
    "product_construction",
    "product_material",
    "product_treatment",
    "product_type_status",
    "product_type_rules_version",
    "matched_wording",
)


@dataclass(frozen=True)
class ProductTypeReading:
    product_type: str = ""
    product_construction: str = ""
    product_material: str = ""
    product_treatment: str = ""
    product_type_status: str = STATUS_UNREADABLE
    product_type_rules_version: str = RULES_VERSION
    matched_wording: str = ""
    reason: str = "No reviewed product rule matched this description"

    def as_dict(self) -> dict[str, str]:
        return {field: getattr(self, field) for field in FIELDS}


def unusable_reason(description: object) -> str:
    """Why a description carries no physical product at all ("" when it does)."""
    text = normalize(description)
    if not text:
        return "blank description"
    if _is_identifier_only(text):
        return "identifier only"
    for pattern in UNUSABLE_RULES:
        if pattern.search(text):
            return "test, fee, placeholder, or non-product wording"
    return ""


_IDENTIFIER_ONLY = re.compile(r"[a-z]*\d+[a-z0-9]*")


def _is_identifier_only(text: str) -> bool:
    return _IDENTIFIER_ONLY.fullmatch(text) is not None


def _material_from_text(text: str) -> str:
    for material, pattern in MATERIAL_RULES:
        if pattern.search(text):
            return material
    return ""


def _treatment_from_text(text: str) -> str:
    for treatment, pattern in TREATMENT_RULES:
        if pattern.search(text):
            return treatment
    if NO_TREATMENT.search(text):
        return "None"
    return ""


def _select_rule(text: str):
    """Pick the single winning rule under a total, deterministic order.

    Key: reviewed product rules before material-only fallbacks, then more words,
    then more characters, then the rule's own position in the ordered rule table
    (earlier = more specific). No dictionary or set iteration takes part in the
    decision, so the winner cannot change between runs.
    """
    best = None
    best_key = None
    for tier, index, product, construction, pattern in PRODUCT_RULES:
        match = pattern.search(text)
        if match is None:
            continue
        wording = " ".join(match.group(0).split())
        key = (tier, -len(wording.split()), -len(wording), index)
        if best_key is None or key < best_key:
            best_key = key
            best = (product, construction, wording)
    return best


def read_product_type(description: object) -> ProductTypeReading:
    """Read the physical product out of one item description."""
    reason = unusable_reason(description)
    if reason:
        return ProductTypeReading(
            product_type_status=STATUS_PLACEHOLDER,
            product_type_rules_version=RULES_VERSION,
            reason=reason,
        )

    text = strip_size(normalize(description))
    selected = _select_rule(text)
    if selected is None:
        return ProductTypeReading(
            product_type_status=STATUS_UNREADABLE,
            product_type_rules_version=RULES_VERSION,
            reason="No reviewed product rule matched this description",
        )

    product, construction, wording = selected
    return ProductTypeReading(
        product_type=product,
        product_construction=construction,
        product_material=_material_from_text(text),
        product_treatment=_treatment_from_text(text),
        product_type_status=STATUS_ACCEPTED,
        product_type_rules_version=RULES_VERSION,
        matched_wording=wording,
        reason="Reviewed product rule matched the full description",
    )


def validate_reading(reading: ProductTypeReading) -> list[str]:
    """Invariants every stored reading must satisfy."""
    errors: list[str] = []
    if reading.product_type_status not in VALID_STATUSES:
        errors.append("invalid status")
    if reading.product_type_status == STATUS_ACCEPTED and not reading.product_type:
        errors.append("accepted reading lacks a physical product")
    if reading.product_type_status != STATUS_ACCEPTED and reading.product_type:
        errors.append("non-accepted reading cannot carry a physical product")
    if reading.product_type_rules_version != RULES_VERSION:
        errors.append("reading carries a foreign rules version")
    return errors


__all__ = [
    "FIELDS",
    "ProductTypeReading",
    "RULES_VERSION",
    "candidate_wording",
    "normalize",
    "read_product_type",
    "unusable_reason",
    "validate_reading",
]
