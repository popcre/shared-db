"""Regression tests for the deterministic product-type reader (issue #3290)."""

from __future__ import annotations

import csv
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
        "harry potter", "nickelodeon", "spongebob", "strawberry shortcake", "kobe", "jordan",
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

    def test_gold_labels_carry_no_item_number(self):
        text = Path(self.PATHS[0]).read_text(encoding="utf-8")
        self.assertNotRegex(text, r"\b[A-Z]{2,}\d{4,}\b")


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
