"""Gold-set coverage check.

Every distinct wording the reader accepts in the live catalog must carry a
reviewed label in `labels.csv`. Prints `uncovered: N` and exits non-zero when
any wording is unlabelled.

    python tools/product_type_reader/gold/coverage.py --catalog <path>
"""

from __future__ import annotations

import argparse
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from tools.product_type_reader.evaluate import load_catalog, load_gold  # noqa: E402
from tools.product_type_reader.reader import read_product_type  # noqa: E402


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", required=True, type=Path)
    parser.add_argument("--labels", type=Path, default=Path(__file__).with_name("labels.csv"))
    args = parser.parse_args(argv)

    if not args.catalog.exists():
        print(f"catalog not found: {args.catalog}", file=sys.stderr)
        return 2

    labels = load_gold(args.labels)
    uncovered = Counter()
    wordings = set()
    for row in load_catalog(args.catalog):
        reading = read_product_type(row["description"])
        if reading.product_type_status != "accepted":
            continue
        wordings.add(reading.matched_wording)
        if reading.matched_wording not in labels:
            uncovered[reading.matched_wording] += 1

    print(f"labels: {len(labels)}")
    print(f"distinct accepted wordings in catalog: {len(wordings)}")
    print(f"uncovered: {len(uncovered)}")
    for wording, count in sorted(uncovered.items(), key=lambda pair: (-pair[1], pair[0]))[:25]:
        print(f"  {count:5} {wording}")
    return 1 if uncovered else 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
