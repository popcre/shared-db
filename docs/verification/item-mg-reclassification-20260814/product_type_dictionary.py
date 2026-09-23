"""Compatibility imports for historical MG analysis; implementation lives in tools."""
from pathlib import Path
import sys

_ROOT = str(Path(__file__).resolve().parents[3])
if _ROOT not in sys.path:
    sys.path.insert(0, _ROOT)
from tools.product_type_reader.legacy import *  # noqa: F401,F403
