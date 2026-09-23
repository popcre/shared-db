"""Small, owner-approved real descriptions with independently reviewed facts."""
import csv
from pathlib import Path

import pytest

from tools.product_type_reader import read_product_type
from tools.product_type_reader.evaluate import FIELDS, canonical_fields


FIXTURE = Path(__file__).parent / 'tests' / 'fixtures' / 'descriptions.csv'
with FIXTURE.open(encoding='utf-8', newline='') as stream:
    CASES = list(csv.DictReader(stream))


@pytest.mark.parametrize('case', CASES, ids=lambda case: case['description'][:45])
def test_reviewed_real_description(case):
    expected = {field: case[field] for field in FIELDS}
    actual = read_product_type(case['description'])
    assert canonical_fields(actual) == canonical_fields(expected)
