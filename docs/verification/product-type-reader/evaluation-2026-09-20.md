# Product-type reader — full-catalog evaluation

- Rules version: `product-type-reader/2026-09-20`
- Catalog source: live production `coldlion.item_header`, read-only, 2026-09-20 (18,731 descriptions)
- Descriptions evaluated: **18731**

## Counts

| Outcome | Rows | Share |
|---|---:|---:|
| Accepted (a product was read) | 16468 | 87.9% |
| Unreadable (explicitly no answer) | 1601 | 8.5% |
| Placeholder (fee, test, assortment, blank) | 662 | 3.5% |
| Correct against gold labels | 16468 | 100.0% of accepted |
| **Wrong against gold labels** | **0** | 0.0% of accepted |
| Accepted wording with no gold label | 0 | 0.0% of accepted |
| Read from wording that carries more than one reviewed meaning | 6003 | 36.5% of accepted |

Distinct product types read: 73.

## Products read (top 25 by rows)

| Product type | Rows |
|---|---:|
| Canvas | 5920 |
| Wall Plaque | 1604 |
| Framed Print | 1224 |
| Framed Lenticular Art | 815 |
| Framed Glass Art | 547 |
| Framed Canvas | 427 |
| Door Mat | 425 |
| Framed Glass Shadowbox | 415 |
| Framed Shadowbox | 406 |
| Tabletop Monogram | 329 |
| Tabletop Block | 296 |
| Paint-Your-Own Canvas Set | 277 |
| Hanging Wall Art | 254 |
| Wall Sign | 251 |
| Wall Clock | 235 |
| Hard Storage Box | 231 |
| Storage Hamper | 203 |
| Storage Chest | 202 |
| Foam Wall Decor | 167 |
| Photo Frame | 155 |
| Storage Toy Chest | 155 |
| Lap Desk | 126 |
| Pencil Cup | 120 |
| Wall Hook | 111 |
| Storage Bin | 110 |

## Wording that carries more than one reviewed meaning

These wordings are produced by more than one rule, so the wording alone does not settle the product. The rules still choose one deterministically, and a row counts as correct only against a reviewed pair — but `wrong = 0` must be read together with this table, not instead of it.

| Matched wording | Rows | Reviewed meanings |
|---|---:|---|
| canvas | 6003 | Canvas / Stretched; Paint-Your-Own Canvas Set / Canvas Set |

## Independent per-description gold fixtures

The wording labels above are keyed on the reader's own matched wording, so they prove consistency across the catalog rather than independence. The fixture set `tools/product_type_reader/tests/fixtures/descriptions.csv` is the independent half: each row is a real description with its expected product written out by hand before the reader was asked, covering every miss recorded on #3024 and every correction made during gold review.

- Fixture descriptions checked: **48**; disagreeing with the reader: **0**.

## Wrong answers

None. Every accepted reading matches its reviewed gold label.

## Accepted wording with no gold label

None. Every accepted wording carries a reviewed gold label.

## Unreadable descriptions (for owner review)

1601 descriptions carry no reviewed product wording and are marked `unreadable` rather than guessed. No catalog row is reproduced here: the table counts the two-word phrases that appear in those descriptions, which is what a reviewer needs in order to judge whether a rule is missing. Phrases are kept only when every word is in the rules' own product vocabulary, so licensor, property and artwork names cannot appear.

| Two-word phrase in an unreadable description | Descriptions |
|---|---:|
| high gloss | 54 |
| wall art | 53 |
| die cut | 37 |
| stained glass | 32 |
| gloss art | 30 |
| color your | 24 |
| mini stained | 17 |
| 1 25 | 16 |
| domed storage | 16 |
| mdf writing | 16 |
| tabletop decor | 16 |
| writing desk | 16 |
| natural wood | 15 |
| printed natural | 15 |
| ceramic cube | 13 |
| collage framed | 13 |
| dry erase | 13 |
| fabric storage | 13 |
| bow frame | 12 |
| mdf art | 11 |
| mdf frame | 11 |
| mdf word | 11 |
| nonwoven fabric | 11 |
| book cover | 10 |
| custom shaped | 10 |
| framed 3d | 10 |
| leather art | 10 |
| shaped mat | 10 |
| box art | 9 |
| erase calendar | 9 |
| mdf wood | 9 |
| mirror wall | 9 |
| painted mdf | 9 |
| art print | 8 |
| block tabletop | 8 |
| faux books | 8 |
| flat domed | 8 |
| foam art | 8 |
| mdf print | 8 |
| collage glass | 7 |
| glass plaque | 7 |
| led mirror | 7 |
| letter a | 7 |
| linen framed | 7 |
| mdf wall | 7 |
| metal art | 7 |
| mini markers | 7 |
| print in | 7 |
| under glass | 7 |
| wall decor | 7 |

