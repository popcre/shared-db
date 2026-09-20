"""Full-catalog evaluation of the deterministic product-type reader.

Reads a catalog export (JSON or CSV with `item_number` and `description`), runs
the reader over every row, compares the result against the reviewed gold labels
in `gold/labels.csv`, and prints an aggregate report.

The catalog itself is licensed source data: it is read from a path outside this
repository (a scratchpad export or the private evidence repository) and is never
written into the report. Only counts, product labels and reader wording appear
in the output.

    python -m tools.product_type_reader.evaluate --catalog <path> [--strict]
        [--report docs/verification/product-type-reader/<name>.md]
        [--unreadable-sample 50]

Exit codes: 0 clean, 1 strict gate failed, 2 could not evaluate.
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

if __package__ in (None, ""):  # direct execution
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from tools.product_type_reader.normalization import normalize  # noqa: E402
from tools.product_type_reader.reader import read_product_type  # noqa: E402
from tools.product_type_reader.rules import (  # noqa: E402
    RULES_VERSION,
    STATUS_ACCEPTED,
    STATUS_PLACEHOLDER,
    STATUS_UNREADABLE,
)

GOLD_LABELS = Path(__file__).with_name("gold") / "labels.csv"
LABEL_FIELDS = (
    "matched_wording",
    "expected_product_type",
    "expected_product_construction",
    "expected_status",
    "note",
)


@dataclass(frozen=True)
class Outcome:
    total: int = 0
    accepted: int = 0
    unreadable: int = 0
    placeholder: int = 0
    correct: int = 0
    wrong: int = 0
    uncovered: int = 0
    ambiguous: int = 0


def load_gold(path: Path = GOLD_LABELS) -> dict[str, list[dict[str, str]]]:
    """Reviewed labels, keyed on matched wording.

    One wording may legitimately be produced by more than one rule (a paint-your-own
    set and a bare canvas both match the wording "canvas"), so each wording carries a
    LIST of reviewed product/construction pairs. A reading whose wording is known but
    whose pair is not reviewed counts as wrong, never as silently correct.
    """
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    labels: dict[str, list[dict[str, str]]] = {}
    for row in rows:
        wording = (row.get("matched_wording") or "").strip()
        if not wording:
            continue
        labels.setdefault(wording, []).append(
            {field: (row.get(field) or "").strip() for field in LABEL_FIELDS}
        )
    return labels


def load_catalog(path: Path) -> list[dict[str, str]]:
    text = path.read_text(encoding="utf-8")
    if path.suffix.lower() == ".json":
        rows = json.loads(text)
    else:
        rows = list(csv.DictReader(text.splitlines()))
    return [
        {"item_number": str(row.get("item_number") or ""), "description": row.get("description") or ""}
        for row in rows
    ]


def evaluate(catalog: list[dict[str, str]], labels: dict[str, list[dict[str, str]]]):
    counts = Counter()
    wrong_examples: list[tuple[str, str, str]] = []
    uncovered_wording = Counter()
    unreadable_wording = Counter()
    product_counts = Counter()
    ambiguous_wording = Counter()

    for row in catalog:
        counts["total"] += 1
        reading = read_product_type(row["description"])
        status = reading.product_type_status
        counts[status] += 1

        if status == STATUS_UNREADABLE:
            unreadable_wording.update(_wording_pairs(row["description"]))
            continue
        if status == STATUS_PLACEHOLDER:
            continue

        product_counts[reading.product_type] += 1
        gold = labels.get(reading.matched_wording)
        if gold is None:
            counts["uncovered"] += 1
            uncovered_wording[reading.matched_wording] += 1
            continue
        if len(gold) > 1:
            # The wording alone admits more than one reviewed meaning. The rules
            # still pick one deterministically, but "0 wrong" must not be read as
            # "no ambiguity", so every such row is counted and reported.
            counts["ambiguous"] += 1
            ambiguous_wording[reading.matched_wording] += 1
        if any(
            entry["expected_status"] == STATUS_ACCEPTED
            and entry["expected_product_type"] == reading.product_type
            and entry["expected_product_construction"] == reading.product_construction
            for entry in gold
        ):
            counts["correct"] += 1
        else:
            counts["wrong"] += 1
            if len(wrong_examples) < 50:
                reviewed = "; ".join(
                    f"{entry['expected_product_type']} / {entry['expected_product_construction']}"
                    f" ({entry['expected_status']})"
                    for entry in gold
                )
                wrong_examples.append(
                    (
                        reading.matched_wording,
                        f"{reading.product_type} / {reading.product_construction}",
                        reviewed,
                    )
                )

    outcome = Outcome(
        total=counts["total"],
        accepted=counts[STATUS_ACCEPTED],
        unreadable=counts[STATUS_UNREADABLE],
        placeholder=counts[STATUS_PLACEHOLDER],
        correct=counts["correct"],
        wrong=counts["wrong"],
        uncovered=counts["uncovered"],
        ambiguous=counts["ambiguous"],
    )
    return outcome, wrong_examples, uncovered_wording, unreadable_wording, product_counts, ambiguous_wording


def _vocabulary() -> frozenset[str]:
    """Every literal word the rule tables can match.

    The unreadable table is filtered to phrases that touch this vocabulary, so it
    reports missing product wording rather than licensor, property or artwork names.
    """
    import re as _re

    from tools.product_type_reader.rules import MATERIAL_RULES, PRODUCT_RULES, TREATMENT_RULES

    words: set[str] = set()
    patterns = [pattern.pattern for _t, _i, _p, _c, pattern in PRODUCT_RULES]
    patterns += [pattern.pattern for _name, pattern in MATERIAL_RULES]
    patterns += [pattern.pattern for _name, pattern in TREATMENT_RULES]
    for pattern in patterns:
        words.update(_re.findall(r"[a-z]{3,}", pattern))
    words.difference_update({"cut"})
    return frozenset(words)


VOCABULARY = _vocabulary()


def _wording_pairs(description: str) -> set[str]:
    """Two-word phrases from one unreadable description.

    The report must never carry a catalog row. Counting word pairs says what
    wording the reader cannot read — which is the actionable part — without
    copying any licensed description into this public repository.
    """
    tokens = normalize(description).split()
    pairs = {" ".join(tokens[index : index + 2]) for index in range(len(tokens) - 1)}
    return {pair for pair in pairs if all(word in VOCABULARY for word in pair.split())}


FIXTURES = Path(__file__).with_name("tests") / "fixtures" / "descriptions.csv"

# Set by main() so the report can name each ambiguous wording's reviewed meanings.
_AMBIGUOUS_LABELS: dict[str, list[dict[str, str]]] = {}


def _check_fixtures() -> tuple[int, int]:
    """Compare the reader against the hand-written per-description gold fixtures."""
    if not FIXTURES.exists():
        return (0, 0)
    with FIXTURES.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    wrong = 0
    for row in rows:
        reading = read_product_type(row["description"])
        if (
            reading.product_type_status != row["expected_status"]
            or reading.product_type != row["expected_product_type"]
            or reading.product_construction != row["expected_product_construction"]
            or reading.product_material != row["expected_product_material"]
        ):
            wrong += 1
    return (len(rows), wrong)


def _percent(part: int, whole: int) -> str:
    return "0.0%" if not whole else f"{100.0 * part / whole:.1f}%"


def render_report(
    outcome: Outcome,
    wrong_examples,
    uncovered_wording: Counter,
    unreadable_wording: Counter,
    product_counts: Counter,
    ambiguous_wording: Counter,
    source: str,
    unreadable_sample: int,
) -> str:
    lines = [
        "# Product-type reader — full-catalog evaluation",
        "",
        f"- Rules version: `{RULES_VERSION}`",
        f"- Catalog source: {source}",
        f"- Descriptions evaluated: **{outcome.total}**",
        "",
        "## Counts",
        "",
        "| Outcome | Rows | Share |",
        "|---|---:|---:|",
        f"| Accepted (a product was read) | {outcome.accepted} | {_percent(outcome.accepted, outcome.total)} |",
        f"| Unreadable (explicitly no answer) | {outcome.unreadable} | {_percent(outcome.unreadable, outcome.total)} |",
        f"| Placeholder (fee, test, assortment, blank) | {outcome.placeholder} | {_percent(outcome.placeholder, outcome.total)} |",
        f"| Correct against gold labels | {outcome.correct} | {_percent(outcome.correct, outcome.accepted)} of accepted |",
        f"| **Wrong against gold labels** | **{outcome.wrong}** | {_percent(outcome.wrong, outcome.accepted)} of accepted |",
        f"| Accepted wording with no gold label | {outcome.uncovered} | {_percent(outcome.uncovered, outcome.accepted)} of accepted |",
        f"| Read from wording that carries more than one reviewed meaning | {outcome.ambiguous} | {_percent(outcome.ambiguous, outcome.accepted)} of accepted |",
        "",
        f"Distinct product types read: {len(product_counts)}.",
        "",
        "## Products read (top 25 by rows)",
        "",
        "| Product type | Rows |",
        "|---|---:|",
    ]
    for product, count in sorted(product_counts.items(), key=lambda pair: (-pair[1], pair[0]))[:25]:
        lines.append(f"| {product} | {count} |")

    lines += [
        "",
        "## Wording that carries more than one reviewed meaning",
        "",
        "These wordings are produced by more than one rule, so the wording alone does not settle "
        "the product. The rules still choose one deterministically, and a row counts as correct "
        "only against a reviewed pair — but `wrong = 0` must be read together with this table, "
        "not instead of it.",
        "",
    ]
    if not ambiguous_wording:
        lines.append("None. Every accepted wording carries exactly one reviewed meaning.")
    else:
        lines.append("| Matched wording | Rows | Reviewed meanings |")
        lines.append("|---|---:|---|")
        for wording, count in sorted(ambiguous_wording.items(), key=lambda pair: (-pair[1], pair[0]))[:25]:
            meanings = "; ".join(
                f"{entry['expected_product_type']} / {entry['expected_product_construction']}"
                for entry in _AMBIGUOUS_LABELS.get(wording, [])
            )
            lines.append(f"| {wording} | {count} | {meanings} |")

    lines += [
        "",
        "## Independent per-description gold fixtures",
        "",
        "The wording labels above are keyed on the reader's own matched wording, so they prove "
        "consistency across the catalog rather than independence. The fixture set "
        "`tools/product_type_reader/tests/fixtures/descriptions.csv` is the independent half: each "
        "row is a real description with its expected product written out by hand before the reader "
        "was asked, covering every miss recorded on #3024 and every correction made during gold "
        "review.",
        "",
    ]
    fixture_total, fixture_wrong = _check_fixtures()
    lines.append(
        f"- Fixture descriptions checked: **{fixture_total}**; disagreeing with the reader: **{fixture_wrong}**."
    )

    lines += ["", "## Wrong answers", ""]
    if not wrong_examples:
        lines.append("None. Every accepted reading matches its reviewed gold label.")
    else:
        lines.append("| Matched wording | Reader said | Gold label says |")
        lines.append("|---|---|---|")
        for wording, got, expected in wrong_examples:
            lines.append(f"| {wording} | {got} | {expected} |")

    lines += ["", "## Accepted wording with no gold label", ""]
    if not uncovered_wording:
        lines.append("None. Every accepted wording carries a reviewed gold label.")
    else:
        lines.append("| Matched wording | Rows |")
        lines.append("|---|---:|")
        for wording, count in sorted(uncovered_wording.items(), key=lambda pair: (-pair[1], pair[0]))[:50]:
            lines.append(f"| {wording} | {count} |")

    lines += [
        "",
        "## Unreadable descriptions (for owner review)",
        "",
        f"{outcome.unreadable} descriptions carry no reviewed product wording and are marked "
        "`unreadable` rather than guessed. No catalog row is reproduced here: the table counts the "
        "two-word phrases that appear in those descriptions, which is what a reviewer needs in "
        "order to judge whether a rule is missing. Phrases are kept only when every word is in the "
        "rules' own product vocabulary, so licensor, property and artwork names cannot "
        "appear.",
        "",
        "| Two-word phrase in an unreadable description | Descriptions |",
        "|---|---:|",
    ]
    for wording, count in sorted(unreadable_wording.items(), key=lambda pair: (-pair[1], pair[0]))[:unreadable_sample]:
        lines.append(f"| {wording} | {count} |")
    lines.append("")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", required=True, type=Path, help="JSON or CSV catalog export (outside this repo)")
    parser.add_argument("--labels", type=Path, default=GOLD_LABELS)
    parser.add_argument("--report", type=Path, default=None)
    parser.add_argument("--source", default=None, help="human description of the catalog source")
    parser.add_argument("--unreadable-sample", type=int, default=50)
    parser.add_argument("--strict", action="store_true", help="fail when any answer is wrong or unlabelled")
    args = parser.parse_args(argv)

    if not args.catalog.exists():
        print(f"catalog not found: {args.catalog}", file=sys.stderr)
        return 2
    if not args.labels.exists():
        print(f"gold labels not found: {args.labels}", file=sys.stderr)
        return 2

    catalog = load_catalog(args.catalog)
    labels = load_gold(args.labels)
    outcome, wrong, uncovered, unreadable, products, ambiguous = evaluate(catalog, labels)
    _AMBIGUOUS_LABELS.clear()
    _AMBIGUOUS_LABELS.update({wording: labels[wording] for wording in ambiguous})

    source = args.source or f"{args.catalog.name} ({len(catalog)} rows)"
    report = render_report(
        outcome, wrong, uncovered, unreadable, products, ambiguous, source, args.unreadable_sample
    )
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(report + "\n", encoding="utf-8")
        print(f"report written: {args.report}")

    print(
        f"total={outcome.total} accepted={outcome.accepted} unreadable={outcome.unreadable} "
        f"placeholder={outcome.placeholder} correct={outcome.correct} wrong={outcome.wrong} "
        f"uncovered={outcome.uncovered} ambiguous={outcome.ambiguous}"
    )
    if args.strict and (outcome.wrong or outcome.uncovered):
        print("strict gate failed: wrong or unlabelled answers remain", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
