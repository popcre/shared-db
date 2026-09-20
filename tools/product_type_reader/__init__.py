"""Permanent, deterministic product-type reader (issue #3290, Phase A of #3024).

Public surface:

    from tools.product_type_reader import read_product_type
    reading = read_product_type('Disney Cars Nonwoven storage closet toy chest')

It returns the `plm.item` product columns requested in orchestrator issue #3036.
This package performs no database access and holds no catalog data.
"""

from .normalization import candidate_wording, normalize, strip_size
from .reader import (
    FIELDS,
    ProductTypeReading,
    read_product_type,
    unusable_reason,
    validate_reading,
)
from .rules import (
    RULES_VERSION,
    STATUS_ACCEPTED,
    STATUS_PLACEHOLDER,
    STATUS_UNREADABLE,
    VALID_STATUSES,
)

__all__ = [
    "FIELDS",
    "ProductTypeReading",
    "RULES_VERSION",
    "STATUS_ACCEPTED",
    "STATUS_PLACEHOLDER",
    "STATUS_UNREADABLE",
    "VALID_STATUSES",
    "candidate_wording",
    "normalize",
    "read_product_type",
    "strip_size",
    "unusable_reason",
    "validate_reading",
]
