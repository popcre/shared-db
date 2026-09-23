"""Reviewed real descriptions with independently reviewed facts.

The fixture holds live catalog wording, so it lives only in the private evidence
package (`reviewed-description-fixture.csv`), never in this public repository.
Point PRODUCT_TYPE_READER_PRIVATE_FIXTURE at it to run these checks; the public
synthetic tests cover every rule without it.
"""
import csv
import os
from pathlib import Path

import pytest



_FIXTURE_PATH = os.environ.get('PRODUCT_TYPE_READER_PRIVATE_FIXTURE', '')
if not _FIXTURE_PATH:
    pytest.skip('private reviewed-description fixture not configured '
                '(set PRODUCT_TYPE_READER_PRIVATE_FIXTURE)', allow_module_level=True)
from tools.product_type_reader import read_product_type
from tools.product_type_reader.evaluate import FIELDS, canonical_fields
with Path(_FIXTURE_PATH).open(encoding='utf-8', newline='') as stream:
    CASES = list(csv.DictReader(stream))
if not CASES:
    raise RuntimeError(f'private fixture {_FIXTURE_PATH} is empty')


@pytest.mark.parametrize('case', CASES, ids=lambda case: case['description'][:45])
def test_reviewed_real_description(case):
    expected = {field: case[field] for field in FIELDS}
    actual = read_product_type(case['description'])
    assert canonical_fields(actual) == canonical_fields(expected)
