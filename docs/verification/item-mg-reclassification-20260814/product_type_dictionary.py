"""Governed semantic item-type dictionary support (compatibility layer).

The rules themselves now live in the permanent package `tools/product_type_reader`
(issue #3290, Phase A of #3024). There is only ONE implementation of the rules;
this module keeps the historical MG-reclassification analysis scripts working by
re-exporting that package behind the older names and the older `needs_review`
status.

The rule set identifies physical products and independently records construction/shape
and treatment. It never reads MG codes. MG codes are learned later, only from accepted
post-change rows carrying the resulting semantic signature.
"""

from __future__ import annotations

import sys
from dataclasses import dataclass
from pathlib import Path

import pandas as pd

_REPO_ROOT = Path(__file__).resolve().parents[3]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from tools.product_type_reader.normalization import candidate_wording, normalize  # noqa: E402
from tools.product_type_reader.reader import (  # noqa: E402
    read_product_type,
    unusable_reason as _unusable_reason,
)
from tools.product_type_reader.rules import (  # noqa: E402
    MATERIAL_RULES,
    NO_TREATMENT,
    PRODUCT_RULES,
    TREATMENT_RULES,
    UNUSABLE_PATTERNS,
)

__all__ = [
    "PRODUCT_PATTERNS",
    "SemanticSignature",
    "UNUSABLE_PATTERNS",
    "candidate_wording",
    "classify_semantic_signature",
    "embellishment_from_text",
    "form_for_product",
    "material_from_text",
    "normalize",
    "subtype_for_product",
    "unusable_reason",
    "validate_signature",
]

# Historical shape: (product, construction, compiled pattern).
PRODUCT_PATTERNS = tuple(
    (product, construction, pattern)
    for _tier, _index, product, construction, pattern in PRODUCT_RULES
)


def unusable_reason(value: object) -> str:
    return _unusable_reason(None if pd.isna(value) else value)


@dataclass(frozen=True)
class SemanticSignature:
    physical_product: str = ""
    construction_shape: str = ""
    treatment: str = ""
    matched_wording: str = ""
    status: str = "needs_review"
    decision: str = "No reviewed physical-product rule matched"
    form: str = ""
    subtype: str = ""
    material: str = ""
    embellishment: str = ""
    embellishment_state: str = "unreadable"
    default_rule_applied: str = ""

    @property
    def full_key(self) -> str:
        return "|".join(normalize(v) for v in (self.physical_product, self.construction_shape, self.treatment))

    @property
    def product_key(self) -> str:
        return normalize(self.physical_product)

    @property
    def product_construction_key(self) -> str:
        return "|".join(normalize(v) for v in (self.physical_product, self.construction_shape))


def embellishment_from_text(text: str) -> tuple[str, str]:
    for treatment, pattern in TREATMENT_RULES:
        if pattern.search(text):
            return treatment, "stated"
    if NO_TREATMENT.search(text):
        return "None", "none"
    return "", "unreadable"


def material_from_text(text: str) -> str:
    for material, pattern in MATERIAL_RULES:
        if pattern.search(text):
            return material
    return ""


def form_for_product(product: str) -> str:
    if product in {"Canvas", "Paint-Your-Own Canvas Set"}:
        return "Stretched or Box"
    if product.startswith("Framed ") or product in {"Photo Frame"}:
        return "Framed" if product != "Photo Frame" else "Photo Frames"
    if product in {"Wall Plaque", "Wall Sign", "Tall Wall Sign", "Door Hanger"}:
        return "Plaque"
    if product in {"Wall Shelf", "Wall Hook", "Memo Board", "Functional Board"}:
        return "Functional Wall"
    if product in {"Hanging Wall Art", "Wall Decal", "Foam Wall Decor", "Wall Light", "Wall Decor", "Paper Shade"}:
        return "Other Wall"
    if product in {"Tabletop Block", "Tabletop Monogram", "Perpetual Calendar"}:
        return "Block"
    if product == "Tabletop Box":
        return "Box"
    if product in {"Mug", "Bookend", "Candle Holder", "Snow Globe", "Tabletop Planter", "Bank", "Tray or Dish"}:
        return "Object" if product != "Bank" else "Other Tabletop"
    if product in {"Tabletop LED Art", "Tabletop Easel"}:
        return "Other Tabletop"
    if "Clock" in product:
        return "Clocks"
    if product in {"Storage Hamper", "Storage Toy Chest", "Storage Chest", "Storage Bin", "Storage Basket", "Storage Tote", "Storage Cube", "Storage Ottoman"}:
        return "Soft Storage"
    if product == "Hard Storage Box":
        return "Hard Storage"
    if product in {"Storage Organizer", "Storage Tower"}:
        return "Other Storage"
    if product in {"Stationery Organizer", "Pencil Cup", "Memo Holder", "Phone Stand", "Headphone Stand"}:
        return "Stationery Organization"
    if product in {"Tablet Stand", "Lap Desk", "Desk Mat"}:
        return "Desk Accessories"
    if product in {"Monitor Stand", "Embroidery Kit", "Display Rack", "Book", "Pencil Case"}:
        return "Other Workspace"
    if product in {"Color-Your-Own Kit", "Keychain", "Frame Set", "Growth Chart"}:
        return "Other"
    if product in {"Door Mat", "Floor Mat", "Kitchen Mat", "Bath Mat", "Rug"}:
        return "Floor Coverings"
    if product in {"Garden Sign or Flag", "Birdhouse or Feeder", "Stepping Stone", "Garden Tool", "Garden Thermometer", "Watering Can", "Garden Kneeler", "Garden Decor"}:
        return "Garden"
    return ""


def subtype_for_product(product: str, construction: str) -> str:
    fixed = {
        "Canvas": "Canvas", "Paint-Your-Own Canvas Set": "Canvas",
        "Wall Clock": "Wall Clock", "Desktop Clock": "Desktop Clock",
        "Storage Hamper": "Hamper", "Storage Bin": "Bin", "Storage Basket": "Basket", "Storage Tote": "Basket",
        "Storage Toy Chest": "Chest", "Storage Chest": "Chest", "Storage Tower": "Tower or Stand",
        "Storage Cube": "Cube", "Storage Ottoman": "Ottoman", "Storage Organizer": "Organizer",
        "Door Mat": "Door", "Floor Mat": "Floor", "Bath Mat": "Bath", "Kitchen Mat": "Kitchen", "Rug": "Rug",
        "Pencil Cup": "Pencil Cup", "Pencil Case": "Pencil Case",
        "Phone Stand": "Phone Stand", "Headphone Stand": "Headphone Stand",
        "Desk Mat": "Desk Mat", "Monitor Stand": "Monitor Stand", "Lap Desk": "Lap Desk",
    }
    return fixed.get(product, construction or product)


def classify_semantic_signature(value: object) -> SemanticSignature:
    original = None if pd.isna(value) else value
    reading = read_product_type(original)
    if reading.product_type_status == "placeholder":
        return SemanticSignature(status="placeholder", decision=reading.reason)
    if reading.product_type_status == "unreadable":
        return SemanticSignature()

    text = normalize(original)
    embellishment, state = embellishment_from_text(text)
    product = reading.product_type
    return SemanticSignature(
        physical_product=product,
        construction_shape=reading.product_construction,
        treatment=embellishment,
        matched_wording=reading.matched_wording,
        status="accepted",
        decision="Reviewed three-axis product rule matched the full description",
        form=form_for_product(product),
        subtype=subtype_for_product(product, reading.product_construction),
        material=material_from_text(text),
        embellishment=embellishment,
        embellishment_state=state,
        # Historical label, kept so older analysis output stays comparable. The
        # reader no longer applies a hidden default: a bare "canvas" now wins only
        # through the explicit fallback tier in rules.py (issue #3290).
        default_rule_applied="bare_canvas_means_stretched_wall_art" if product == "Canvas" else "",
    )


GENERIC_ONLY = {"mat", "box", "set", "art", "board", "bin", "storage", "decor", "wall art"}


def validate_signature(signature: SemanticSignature) -> list[str]:
    errors: list[str] = []
    if signature.status == "accepted" and not signature.physical_product:
        errors.append("accepted signature lacks physical product")
    if signature.status not in {"accepted", "alias", "rejected", "placeholder", "needs_review"}:
        errors.append("invalid status")
    if normalize(signature.matched_wording) in GENERIC_ONLY and signature.status in {"accepted", "alias"}:
        errors.append("generic noun wording cannot be accepted or aliased")
    if signature.status in {"rejected", "placeholder", "needs_review"} and signature.physical_product:
        errors.append("non-accepted signature cannot carry a physical product")
    return errors
