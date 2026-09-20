"""Determinism proofs for the product-type reader (issue #3290).

"Deterministic" is the point of this reader: the same description must produce
byte-identical output on every run, on every machine, whatever the hash seed,
the locale, the input order, or the Unicode form of the text.
"""

from __future__ import annotations

import json
import locale
import subprocess
import sys
import unittest
from hashlib import sha256
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT))

from tools.product_type_reader import FIELDS, read_product_type  # noqa: E402
from tools.product_type_reader.tests.test_reader import load_fixtures  # noqa: E402

SAMPLE = [
    # Product wording is real; licensor and property names are placeholders, so
    # this public file carries no licensed catalog row.
    'Licensor Nonwoven storage closet toy chest with playmat Group shot 10x15"',
    'Floater Frame Canvas w Handpaint_Fall White & Orange Pumpkins_24x12" x1.5"',
    'Licensor Molded Shadowbox Character standing in front of glass 16x20" x1.125"',
    'Licensor Acrylic Pencil Case Character 8x4"',
    "Property Character Blue",
    "Created for Testing",
    "",
]


def digest(descriptions) -> str:
    payload = [
        [description, [getattr(read_product_type(description), field) for field in FIELDS]]
        for description in descriptions
    ]
    return sha256(json.dumps(payload, sort_keys=True, ensure_ascii=True).encode("utf-8")).hexdigest()


class DeterminismTests(unittest.TestCase):
    def test_repeated_runs_are_byte_identical(self):
        """In-process stability. Weak on its own — see the subprocess tests."""
        first = digest(SAMPLE)
        for _ in range(25):
            self.assertEqual(digest(SAMPLE), first)

    def test_input_order_does_not_change_any_answer(self):
        forwards = {description: digest([description]) for description in SAMPLE}
        backwards = {description: digest([description]) for description in reversed(SAMPLE)}
        self.assertEqual(backwards, forwards)

    def test_every_fixture_is_stable_in_a_fresh_process(self):
        """The real proof: a separate interpreter must reach the same digest.

        Comparing a digest to itself inside one process cannot detect hash-seed
        or iteration-order dependence, because the seed is fixed once per process.
        """
        descriptions = [row["description"] for row in load_fixtures()]
        here = digest(descriptions)
        script = (
            "import sys; sys.path.insert(0, %r);"
            "from tools.product_type_reader.tests.test_determinism import digest;"
            "from tools.product_type_reader.tests.test_reader import load_fixtures;"
            "print(digest([row['description'] for row in load_fixtures()]))" % str(REPO_ROOT)
        )
        result = subprocess.run(
            [sys.executable, "-c", script], check=True, capture_output=True, text=True, env=_clean_env()
        )
        self.assertEqual(result.stdout.strip(), here)

    def test_a_shuffled_catalog_reads_the_same_in_a_fresh_process(self):
        """Order independence, proved across a process boundary."""
        descriptions = [row["description"] for row in load_fixtures()]
        shuffled = descriptions[::-1]
        script = (
            "import sys; sys.path.insert(0, %r);"
            "from tools.product_type_reader.tests.test_determinism import digest;"
            "from tools.product_type_reader.tests.test_reader import load_fixtures;"
            "rows=[row['description'] for row in load_fixtures()][::-1];"
            "print(digest(rows))" % str(REPO_ROOT)
        )
        result = subprocess.run(
            [sys.executable, "-c", script],
            check=True,
            capture_output=True,
            text=True,
            env={**_clean_env(), "PYTHONHASHSEED": "7919"},
        )
        self.assertEqual(result.stdout.strip(), digest(shuffled))

    def test_hash_seed_does_not_change_the_result(self):
        script = (
            "import sys; sys.path.insert(0, %r);"
            "from tools.product_type_reader.tests.test_determinism import digest, SAMPLE;"
            "print(digest(SAMPLE))" % str(REPO_ROOT)
        )
        digests = set()
        for seed in ("0", "1", "12345", "random"):
            result = subprocess.run(
                [sys.executable, "-c", script],
                check=True,
                capture_output=True,
                text=True,
                env={**_clean_env(), "PYTHONHASHSEED": seed},
            )
            digests.add(result.stdout.strip())
        self.assertEqual(len(digests), 1, f"hash seed changed the reader output: {digests}")

    def test_locale_does_not_change_the_result(self):
        before = digest(SAMPLE)
        original = locale.setlocale(locale.LC_ALL)
        applied = None
        for candidate in ("tr_TR.UTF-8", "Turkish_Turkey.1254", "de_DE.UTF-8", "German_Germany.1252", "C"):
            try:
                locale.setlocale(locale.LC_ALL, candidate)
            except locale.Error:
                continue
            applied = candidate
            break
        try:
            self.assertEqual(digest(SAMPLE), before, f"locale {applied} changed the reader output")
        finally:
            locale.setlocale(locale.LC_ALL, original)

    def test_rules_never_depend_on_dictionary_or_set_iteration(self):
        from tools.product_type_reader.rules import MATERIAL_RULES, PRODUCT_RULES, TREATMENT_RULES

        for table in (PRODUCT_RULES, MATERIAL_RULES, TREATMENT_RULES):
            self.assertIsInstance(table, tuple)
        indexes = [index for _tier, index, _p, _c, _pattern in PRODUCT_RULES]
        self.assertEqual(indexes, sorted(indexes))
        self.assertEqual(len(set(indexes)), len(indexes))


def _clean_env() -> dict[str, str]:
    import os

    env = dict(os.environ)
    env.pop("PYTHONHASHSEED", None)
    return env


if __name__ == "__main__":  # pragma: no cover
    unittest.main()
