# Product-type reader — full-catalog evaluation

- Rules version: `product-type-reader/2026-09-20`
- Catalog source: live production `coldlion.item_header`, read-only, 2026-09-20 (18,731 descriptions)
- Descriptions evaluated: **18731**

## Counts

| Outcome | Rows | Share |
|---|---:|---:|
| Accepted (a product was read) | 16457 | 87.9% |
| Unreadable (explicitly no answer) | 1612 | 8.6% |
| Placeholder (fee, test, assortment, blank) | 662 | 3.5% |
| Correct against gold labels | 16457 | 100.0% of accepted |
| **Wrong against gold labels** | **0** | 0.0% of accepted |
| Accepted wording with no gold label | 0 | 0.0% of accepted |

Distinct product types read: 73.

## Products read (top 25 by rows)

| Product type | Rows |
|---|---:|
| Canvas | 5920 |
| Wall Plaque | 1604 |
| Framed Print | 1224 |
| Framed Lenticular Art | 815 |
| Framed Glass Art | 547 |
| Door Mat | 425 |
| Framed Canvas | 416 |
| Framed Glass Shadowbox | 415 |
| Framed Shadowbox | 406 |
| Tabletop Monogram | 329 |
| Tabletop Block | 296 |
| Paint-Your-Own Canvas Set | 288 |
| Hanging Wall Art | 254 |
| Wall Sign | 251 |
| Wall Clock | 235 |
| Hard Storage Box | 231 |
| Storage Hamper | 203 |
| Storage Toy Chest | 174 |
| Storage Chest | 172 |
| Foam Wall Decor | 167 |
| Photo Frame | 155 |
| Lap Desk | 126 |
| Pencil Cup | 120 |
| Wall Hook | 111 |
| Storage Bin | 110 |

## Independent per-description gold fixtures

The wording labels above are keyed on the reader's own matched wording, so they prove consistency across the catalog rather than independence. The fixture set `tools/product_type_reader/tests/fixtures/descriptions.csv` is the independent half: each row is a real description with its expected product written out by hand before the reader was asked, covering every miss recorded on #3024 and every correction made during gold review.

- Fixture descriptions checked: **48**; disagreeing with the reader: **0**.

## Wrong answers

None. Every accepted reading matches its reviewed gold label.

## Accepted wording with no gold label

None. Every accepted wording carries a reviewed gold label.

## Unreadable descriptions (for owner review)

1612 descriptions carry no reviewed product wording and are marked `unreadable` rather than guessed. The most frequent wordings follow; each is licensed source wording quoted only as far as its product-bearing head.

| Description head | Rows |
|---|---:|
| MARVEL WALL ART | 7 |
| Ceramic | 6 |
| 11X14" MIXED LICENSE ASSORTMENT | 4 |
| AVENGERS PORTRAIT | 4 |
| HIGH GLOSS THOR | 4 |
| LEONARDO | 4 |
| MARVEL STICKERS | 4 |
| SW MOVIE POSTER | 4 |
| DOG COLLAGE | 3 |
| MARVEL | 3 |
| MDF w LED Rope | 3 |
| MICHELANGELO | 3 |
| PAW PATROL DREAM | 3 |
| Textured PU with Screenprint | 3 |
| AIRPLANE COLLAGE | 2 |
| AVENGERS 12X24X1.5 INSPIRATIONAL MDF | 2 |
| AVENGERS GALLERY PORTRAIT | 2 |
| Batman Logo Painted MDF Wood 18x16 x 1.5 | 2 |
| Captain America Retro 24" x 24" framed comic collage | 2 |
| Care Bears Coir Mart Fall Holiday Bear 'I love fall' 5 color 18x28" x.59" | 2 |
| Ceramic Cube with Decal | 2 |
| Ceramic Tabletop | 2 |
| DC- Disney Greyboard Letters | 2 |
| DONATELLO | 2 |
| DONATELLO PORTRAIT | 2 |
| DSNY, XL, L, M, S, LFTOFF GRYBRD STRG W FOIL, 15X14" X7.5," 13X11" X7," 11X9" X6," 9.5X7.5" X5.5" | 2 |
| Disney MDF DIY pcture frm die-cut attachment, 12 paint pots and brush Pooh and Piglet scene 8.6 | 2 |
| Disney The Aristocats Medium Domed Storage w/ Foil Mary with bows on pink 12.28x8.03" x8.03" | 2 |
| Disney color-your-hero white MDF with 3 mini markers Mickey 4.7x7.5" | 2 |
| Disney color-your-hero white MDF with rope Minnie 4.4x7.4" | 2 |
| Framed Holographic Printed Faux Leather | 2 |
| GOLD FOIL FLAMINGO | 2 |
| GOLD FOIL MOOSE | 2 |
| HIGH GLOSS CAPTAIN AMERICA | 2 |
| High Gloss Art 14x20.5 x 1.5" Marvel Assorted | 2 |
| IRONMAN COLLAGE GLASS | 2 |
| LEONARDO PORTRAIT | 2 |
| MARVEL 11X17 3D | 2 |
| MARVEL LETTER K | 2 |
| MARVEL RETRO COMICS LETTER S | 2 |
| MARVEL RETRO TILES | 2 |
| MDF Rounded Plaque | 2 |
| MOOSE COLLAGE | 2 |
| MOTORCYCLE COLLAGE | 2 |
| MRVL, DSNY, 3 DRWR TIER STRGE, 11.5X34" X11.5" | 2 |
| MV ASSORTED PORTRAITS | 2 |
| MV BLACK PANTHER SAMPLES | 2 |
| MV MARVEL RETRO SAMPLES | 2 |
| MV SPIDERMAN SAMPLES | 2 |
| Marvel 'Stronger' Inspirational MDF Avengers 12x24" x 1.5" | 2 |

