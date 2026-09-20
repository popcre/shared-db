"""Deterministic, locale-independent normalisation for item descriptions.

Every transformation here is pure ASCII and fixed-order. Nothing depends on the
process locale, the hash seed, dictionary iteration order, or the wall clock.
"""

from __future__ import annotations

import re
import unicodedata

# Ordered on purpose: replacements are applied in this exact sequence so the
# result never depends on mapping iteration order.
ABBREVIATIONS: tuple[tuple[str, str], ...] = (
    ("shadow box", "shadowbox"),
    ("shadow bx", "shadowbox"),
    ("shdwbx", "shadowbox"),
    ("shdbx", "shadowbox"),
    ("shbx", "shadowbox"),
    ("galvanzied", "galvanized"),
    ("galvanised", "galvanized"),
    ("die-cut", "die cut"),
    ("diecut", "die cut"),
    ("fatique", "fatigue"),
    ("cnvs", "canvas"),
    ("cnvas", "canvas"),
    ("cvs", "canvas"),
    ("frmd", "framed"),
    ("frmed", "framed"),
    ("frme", "frame"),
    ("lnticulr", "lenticular"),
    ("lentclr", "lenticular"),
    ("lntclr", "lenticular"),
    ("lenticlr", "lenticular"),
    ("prntd", "printed"),
    ("prnt", "print"),
    ("grybrd", "greyboard"),
    ("strge", "storage"),
    ("dcor", "decor"),
    ("deocr", "decor"),
    ("stggerd", "staggered"),
    ("mtallic", "metallic"),
    ("glss", "glass"),
    ("ml ded", "molded"),
    ("doublelayer", "double layer"),
    ("dbl layer", "double layer"),
    ("lift-off", "lift off"),
    ("liftoff", "lift off"),
)

# Size wording is never part of the product type. Stripped before matching.
DIMENSION = re.compile(
    r"\b\d+(?:\.\d+)?\s*(?:\"|in|inch|inches|cm|mm|ft)?\s*[xX×]\s*"
    r"\d+(?:\.\d+)?(?:\s*(?:\"|in|inch|inches|cm|mm|ft))?"
    r"(?:\s*[xX×]\s*\d+(?:\.\d+)?(?:\s*(?:\"|in|inch|inches|cm|mm|ft))?)?"
)

_NON_ALNUM = re.compile(r"[^a-z0-9]+")

# "3-D" and "3 D" mean "3d"; collapse them before any rule sees the text.
_SPACED_3D = re.compile(r"\b3 d\b")


def _to_ascii_lower(value: object) -> str:
    """ASCII-fold and lowercase without touching the process locale."""
    if value is None:
        return ""
    text = str(value)
    # str.lower() is locale-independent in Python; the ASCII fold below makes the
    # result byte-identical regardless of the input's Unicode form.
    text = unicodedata.normalize("NFKD", text)
    text = text.encode("ascii", "ignore").decode("ascii")
    return text.lower()


def normalize(value: object) -> str:
    """Canonical lowercase ASCII token string used for all rule matching."""
    text = _to_ascii_lower(value)
    for old, new in ABBREVIATIONS:
        text = text.replace(old, new)
    collapsed = " ".join(_NON_ALNUM.sub(" ", text).split())
    return _SPACED_3D.sub("3d", collapsed)


def strip_size(text: str) -> str:
    """Remove dimension wording from an already-normalised string."""
    return " ".join(DIMENSION.sub(" ", text).split())


def candidate_wording(description: object) -> str:
    """Stable observed wording used as the exact dictionary lookup key."""
    if description is None:
        return ""
    return str(description).split("_", 1)[0].strip()[:240]
