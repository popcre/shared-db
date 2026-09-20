"""Regression tests for the deterministic product-type reader (issue #3290)."""

from __future__ import annotations

import csv
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from tools.product_type_reader import (  # noqa: E402
    RULES_VERSION,
    VALID_STATUSES,
    read_product_type,
    validate_reading,
)

FIXTURES = Path(__file__).with_name("fixtures") / "descriptions.csv"


def load_fixtures() -> list[dict[str, str]]:
    with FIXTURES.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


class FixtureTests(unittest.TestCase):
    """Every real description that the reader once got wrong or could not read."""

    def test_every_fixture_reads_as_reviewed(self):
        for row in load_fixtures():
            with self.subTest(description=row["description"][:60]):
                reading = read_product_type(row["description"])
                self.assertEqual(reading.product_type_status, row["expected_status"])
                self.assertEqual(reading.product_type, row["expected_product_type"])
                self.assertEqual(reading.product_construction, row["expected_product_construction"])
                self.assertEqual(reading.product_material, row["expected_product_material"])

    def test_fixtures_cover_both_failure_modes(self):
        statuses = {row["expected_status"] for row in load_fixtures()}
        self.assertTrue({"accepted", "unreadable", "placeholder"} <= statuses)

    def test_every_reading_satisfies_its_invariants(self):
        for row in load_fixtures():
            with self.subTest(description=row["description"][:60]):
                self.assertEqual(validate_reading(read_product_type(row["description"])), [])


class NeverGuessTests(unittest.TestCase):
    def test_unreadable_is_explicit_and_never_a_guess(self):
        reading = read_product_type("Marvel Thor Blue")
        self.assertEqual(reading.product_type_status, "unreadable")
        self.assertEqual(reading.product_type, "")
        self.assertEqual(reading.product_material, "")

    def test_placeholder_wording_never_becomes_a_product(self):
        for value in ("Created for Testing", "PENDING", "clearance fee", "ASSORTMENT"):
            with self.subTest(value=value):
                reading = read_product_type(value)
                self.assertEqual(reading.product_type_status, "placeholder")
                self.assertEqual(reading.product_type, "")

    def test_material_is_only_recorded_when_the_description_states_it(self):
        self.assertEqual(read_product_type("Coca-Cola Desk Mat 16x32").product_material, "")
        self.assertEqual(read_product_type("Crumb Rubber Door Mat Bows").product_material, "Crumb Rubber")

    def test_status_is_always_one_of_the_three_stored_values(self):
        for value in ("Canvas 16x20", "", "Marvel Thor Blue", "fee"):
            self.assertIn(read_product_type(value).product_type_status, VALID_STATUSES)

    def test_every_reading_carries_the_rules_version(self):
        self.assertEqual(read_product_type("Canvas 16x20").product_type_rules_version, RULES_VERSION)


class ConstructionNeverStatesAnUnstatedMaterialTests(unittest.TestCase):
    """A material-named construction must be required by its own rule.

    Construction says how a product is built or shaped. When a construction names
    a material — MDF, Fabric, Greyboard, PVC — the rule that produces it must be
    unable to match a description that does not state that material, or the
    reader is inventing the material in a different column. This test enforces
    that for EVERY rule, so the class cannot regrow one rule at a time.
    """

    # A construction word maps to the wording that legitimately states it.
    MATERIAL_SYNONYMS = {
        "mdf": ("mdf",),
        "greyboard": ("greyboard",),
        "canvas": ("canvas",),
        "fabric": ("fabric", "linen", "burlap", "embroidered", "oxford", "nonwoven", "felt", "plush", "woven", "jersey", "velvet", "poly", "suede", "wool", "yarn", "canvas", "leather", "cotton"),
        "plastic": ("plastic", "pvc", "acrylic", "polypropylene", "pp ", "tpe"),
        "pvc": ("pvc",),
        "metal": ("metal", "tin", "aluminum", "aluminium", "iron", "steel", "galvanized"),
        "glass": ("glass",),
        "ceramic": ("ceramic", "dolomite", "porcelain"),
        "acrylic": ("acrylic",),
        "paper": ("paper", "print", "poster", "deckle"),
        "wood": ("wood", "plywood", "timber"),
        "foam": ("foam", "eva"),
        "coir": ("coir",),
        "velvet": ("velvet",),
        "rubber": ("rubber",),
        "felt": ("felt",),
        "mesh": ("mesh",),
        "concrete": ("concrete",),
        "lenticular": ("lenticular",),
        "mirror": ("mirror",),
        "yarn": ("yarn",),
        "plush": ("plush",),
        "poly": ("poly",),
        "stone": ("stone",),
        "resin": ("resin",),
        "suede": ("suede",),
        "linen": ("linen",),
        "burlap": ("burlap",),
        "greyboard": ("greyboard",),
    }

    @staticmethod
    def _alternatives(pattern: str) -> list[str]:
        """Split a regex on its top-level `|` (ignoring `|` inside groups)."""
        parts, depth, current = [], 0, []
        index = 0
        while index < len(pattern):
            char = pattern[index]
            if char == "\\":
                current.append(pattern[index : index + 2])
                index += 2
                continue
            if char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
            if char == "|" and depth == 0:
                parts.append("".join(current))
                current = []
            else:
                current.append(char)
            index += 1
        parts.append("".join(current))
        return parts

    @classmethod
    def _expansions(cls, alternative: str) -> list[str]:
        """Every concrete wording this alternative can match, bounded.

        A substring check over the raw pattern is not enough: a group such as
        `(?:fabric |canvas |oxford )+` passes a naive check on `fabric` even for
        the `oxford` branch. Expanding the alternation means EVERY branch has to
        carry the construction's material, which is what the invariant says.
        """
        # Optional groups require nothing at all: expand them to empty.
        text = re.sub(r"\(\?:[^()]*\)[?*]", " ", alternative)
        group = re.search(r"\(\?[:=][^()]*\)", text)
        if group is None:
            return [text]
        body = group.group(0)
        inner = body[body.index(":") + 1 if body.startswith("(?:") else body.index("=") + 1 : -1]
        branches = inner.split("|") or [""]
        out = []
        for branch in branches:
            out.extend(cls._expansions(text[: group.start()] + branch + text[group.end() :]))
        return out

    @classmethod
    def _states(cls, alternative: str, words: tuple[str, ...]) -> bool:
        """True when EVERY wording this alternative can match states one of `words`."""
        return all(
            any(word.strip() in expansion for word in words)
            for expansion in cls._expansions(alternative)
        )

    def test_every_material_named_construction_is_required_by_its_rule(self):
        from tools.product_type_reader.rules import PRODUCT_RULES

        offenders = []
        for _tier, _index, product, construction, pattern in PRODUCT_RULES:
            required = [
                words
                for token, words in self.MATERIAL_SYNONYMS.items()
                if token in construction.lower().replace("-", " ").split()
                or token == construction.lower()
            ]
            if not required:
                continue
            for alternative in self._alternatives(pattern.pattern):
                for words in required:
                    if not self._states(alternative, words):
                        offenders.append(f"{product} / {construction}: {alternative.strip()}")
        self.assertEqual(offenders, [], "construction names a material the rule does not require")


class PublicVenueTests(unittest.TestCase):
    """This is a public repository: no licensed catalog wording may land in it.

    `scripts/public-data-venue.test.mjs` allows these two CSVs by name on the
    strength of this test. If it is removed or weakened, that allowance is void.
    """

    LICENSED_TOKENS = (
        "disney", "marvel", "batman", "superman", "spider", "stitch", "peanuts", "snoopy",
        "pooh", "sonic", "coca", "cola", "nbc", "nbcu", "warner", "star wars", "care bears",
        "hulk", "thor", "joker", "shrek", "dora", "elmo", "wicked", "gotham", "avengers",
        "princess", "mickey", "minnie", "aristocats", "paw patrol", "sega", "viacom",
        "harry potter", "potter", "nickelodeon", "spongebob", "strawberry shortcake", "kobe",
        "jordan", "paramount", "universal", "dreamworks", "illumination", "pokemon", "barbie",
        "lego", "hello kitty", "kitty", "sega", "peppa", "bluey", "garfield", "smurf",
        "transformers", "jurassic", "sesame", "care bear", "coca-cola", "pepsi",
    )

    PATHS = (
        Path(__file__).resolve().parents[1] / "gold" / "labels.csv",
        FIXTURES,
    )

    def test_no_licensor_or_property_name_is_published(self):
        for path in self.PATHS:
            text = path.read_text(encoding="utf-8").lower()
            for token in self.LICENSED_TOKENS:
                with self.subTest(path=path.name, token=token):
                    self.assertNotIn(token, text)

    def test_every_gold_wording_is_itself_readable_product_wording(self):
        """The strongest backstop: an allowlist, not a list of names to avoid.

        Every gold wording, read on its own, must come back as an accepted product
        whose meaning the gold set already reviewed. A licensor, property or
        artwork phrase cannot do that — it reads `unreadable` — so a licensed name
        cannot reach this file without failing here, whether or not anyone
        remembered to add it to a blocklist.
        """
        with Path(self.PATHS[0]).open(newline="", encoding="utf-8") as handle:
            rows = list(csv.DictReader(handle))
        reviewed: dict[str, set[tuple[str, str]]] = {}
        for row in rows:
            reviewed.setdefault(row["matched_wording"], set()).add(
                (row["expected_product_type"], row["expected_product_construction"])
            )
        from tools.product_type_reader.evaluate import VOCABULARY

        for wording, pairs in sorted(reviewed.items()):
            with self.subTest(wording=wording):
                reading = read_product_type(wording)
                if (
                    reading.product_type_status == "accepted"
                    and (reading.product_type, reading.product_construction) in pairs
                ):
                    continue
                # A few wordings only carry their catalog meaning in context: "diy"
                # names a paint-your-own set when "canvas" follows it, and reads as a
                # colour-your-own kit on its own. Those must still be built only from
                # words the rules themselves contain, which no licensor name is.
                outside = [
                    token
                    for token in wording.split()
                    if not token.isdigit() and token not in VOCABULARY
                ]
                self.assertEqual(outside, [], "gold wording contains words no rule can match")

    def test_gold_labels_carry_no_item_number(self):
        """An item number is a catalog identifier, in any case or shape."""
        with Path(self.PATHS[0]).open(newline="", encoding="utf-8") as handle:
            wordings = [row["matched_wording"] for row in csv.DictReader(handle)]
        for wording in wordings:
            with self.subTest(wording=wording):
                # Product wording is words; a bare code or a long digit run is not.
                self.assertNotRegex(wording, r"(?i)\b[a-z]{1,4}[-_]?\d{3,}\b")
                self.assertNotRegex(wording, r"\b\d{4,}\b")


class NoiseIsIgnoredTests(unittest.TestCase):
    """Licensor, property, artwork, colour and size never change the product."""

    def test_licensor_and_property_do_not_change_the_product(self):
        base = read_product_type("Printed Glass Shadowbox 12x12")
        for noise in ("Disney ", "Marvel Spider-Man ", "WB Lord of the Rings "):
            with self.subTest(noise=noise):
                reading = read_product_type(noise + "Printed Glass Shadowbox 12x12")
                self.assertEqual(reading.product_type, base.product_type)
                self.assertEqual(reading.product_construction, base.product_construction)

    def test_size_order_and_units_do_not_change_the_product(self):
        readings = [
            read_product_type('Disney MDF Plaque Stitch 16x20"'),
            read_product_type('Disney MDF Plaque Stitch 20x16"'),
            read_product_type("Disney MDF Plaque Stitch 16 x 20 inches"),
            read_product_type("Disney MDF Plaque Stitch"),
        ]
        first = readings[0].as_dict()
        for reading in readings[1:]:
            self.assertEqual(reading.as_dict(), first)

    def test_accented_and_unicode_wording_reads_the_same(self):
        plain = read_product_type("Marvel Color Your Hero Foam Wall Decor Captain America")
        accented = read_product_type("Marvel Color Your Hero Foam Wall Décor Captain América")
        self.assertEqual(accented.as_dict(), plain.as_dict())


if __name__ == "__main__":  # pragma: no cover
    unittest.main()
