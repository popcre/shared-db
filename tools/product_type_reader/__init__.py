"""Deterministic description reader; no database or historical MG dependency."""

from .reader import RULES_VERSION, read_product_type

__all__ = ["RULES_VERSION", "read_product_type"]
