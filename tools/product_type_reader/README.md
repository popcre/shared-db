# `tools/product_type_reader` — the deterministic product-type reader

Phase A of the product-type reader plan ([`plan_product_type_reader.md`](../../plan_product_type_reader.md),
issues [#3290](https://github.com/popcre/shared-db/issues/3290) and
[#3024](https://github.com/popcre/shared-db/issues/3024)).

It answers one question about an item description: **what physical product is this?**

```python
from tools.product_type_reader import read_product_type

reading = read_product_type('Disney Cars Nonwoven storage closet toy chest with playmat 10x15"')
reading.product_type              # 'Storage Toy Chest'
reading.product_construction      # 'Fabric'
reading.product_material          # 'Fabric'  (stated in the description only)
reading.product_treatment         # ''
reading.product_type_status       # 'accepted' | 'unreadable' | 'placeholder'
reading.product_type_rules_version
reading.matched_wording           # evaluation only; never stored
```

The returned fields are exactly the `plm.item` columns landed by orchestrator issue #3036,
except `product_type_read_at`, which the writer sets. **Nothing here touches the database.**

## The four rules this code exists to keep

1. **A wrong answer is worse than no answer.** A description the rules cannot read is marked
   `unreadable`; it is never guessed. This value feeds HTS (customs) classification.
2. **Material is recorded only when the description states it.** No default material is invented.
3. **Licensor, property, artwork, colour, size and historical MG codes never influence the
   product.** Sizes are stripped before matching, so `16x20` and `20x16` read identically.
4. **Deterministic.** For a given rules version the output depends on the description alone —
   no clock, locale, hash seed, randomness, environment or I/O, and no dictionary or set
   iteration takes part in choosing a rule. `tests/test_determinism.py` proves it, including
   across `PYTHONHASHSEED` values in separate processes and under a changed locale.

## Layout

| Path | What it is |
|---|---|
| `normalization.py` | ASCII fold, abbreviation expansion, size stripping |
| `rules.py` | the reviewed rule tables, in fixed order; tier 1 rules are fallbacks |
| `reader.py` | `read_product_type`, the total-order rule selection, invariants |
| `evaluate.py` | full-catalog evaluation and report writer |
| `gold/labels.csv` | one reviewed label per distinct matched wording |
| `gold/coverage.py` | proves every accepted wording in the catalog carries a label |
| `tests/fixtures/descriptions.csv` | hand-written per-description expectations |
| `tests/` | regression and determinism tests |

`docs/verification/item-mg-reclassification-20260814/product_type_dictionary.py` is now a thin
compatibility layer over this package, so the historical MG analysis scripts keep working. There
is only one implementation of the rules.

## Running it

```
python -m pytest -q tools/product_type_reader/tests docs/verification/item-mg-reclassification-20260814
python tools/product_type_reader/gold/coverage.py --catalog <export outside this repo>
python tools/product_type_reader/evaluate.py --catalog <export> --strict --report docs/verification/product-type-reader/<name>.md
```

The catalog export is licensed source data. Keep it outside this public repository — the reports
carry counts, product labels and reader wording only.
