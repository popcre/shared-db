# Product-type reader — verification evidence

Phase A of [`plan_product_type_reader.md`](../../../plan_product_type_reader.md), issue
[#3290](https://github.com/popcre/shared-db/issues/3290).

## What was measured, and against what

The evaluation ran against the **live production catalog**: every non-null `item_desc` in
`coldlion.item_header`, read on 2026-09-20 through a read-only session (`set session
characteristics as transaction read only`) on project `qsllyeztdwjgirsysgai`, under the
standing read-only inspection ruling in `AGENTS.md` §0.0-A. **18,731 descriptions.** No write
of any kind was issued. The export lives in the session scratchpad; no catalog row is committed
to this public repository.

## Baseline → final

| Measure | Baseline (rules as ported, before Phase A fixes) | Final |
|---|---:|---:|
| Descriptions evaluated | 18,731 | 18,731 |
| Accepted (a product was read) | 15,879 (84.8%) | 16,468 (87.9%) |
| Unreadable (explicit no answer) | 2,190 (11.7%) | 1,601 (8.5%) |
| Placeholder (fee, test, assortment, blank) | 662 (3.5%) | 662 (3.5%) |
| Distinct matched wordings | 381 | 388 |
| Wrong against gold labels | not yet labelled | **0** |
| Accepted wording with no gold label | — | **0** |
| Accepted rows read from wording with more than one reviewed meaning | — | 6,003 (36.5%) |

The full final report is [`evaluation-2026-09-20.md`](evaluation-2026-09-20.md).

## How the gold set was built, and what it does and does not prove

Two halves, on purpose:

1. **`gold/labels.csv` — 389 rows, one per distinct (wording, product, construction) triple.**
   Every wording the reader accepts anywhere in the live catalog has a reviewed label. These labels were proposed from
   the reader's own output and then **reviewed one by one against a real example description**;
   that review produced 13 rule corrections, each of which is now a test fixture. Because the key
   is the reader's own wording, this half proves *coverage and consistency across the whole
   catalog* — it does not by itself prove independence. One wording, `canvas`, legitimately
   carries two reviewed meanings (a stretched canvas and a paint-your-own set); the rules pick
   between them by tier, and the report counts and names every such row rather than letting
   `wrong = 0` absorb it. `evaluate.py --strict` now REFUSES any shared wording whose gold rows
   do not carry an `ambiguous-by-design` note, so ambiguity nobody reviewed fails the gate.
2. **`tests/fixtures/descriptions.csv` — 48 real descriptions with expected values written out
   by hand.** This is the independent half. It carries every miss recorded on #3024 on
   2026-09-16 (7 no-answer, 4 wrong), every correction found during gold review, the
   placeholder and unreadable cases, and the determinism cases. All 48 agree with the reader.

## Corrections made during Phase A

Fixed so the reader stops inventing an answer:

- `comic book`, `storybook`, `dog on books` — artwork, not a book product (62+ rows).
- `Web-Spinner` — artwork, not a spinner rack.
- `stained glass` as an art style on a canvas — no longer a glass product (45 rows).
- `chef jersey` — artwork, not a fabric.
- bare `brush` wording (`I-Brush`, `brush stroke`) — no longer a paint-your-own set.
- a bare `canvas` no longer swallows canvas hampers, growth charts or folding frame sets: the
  bare-material rule is now an explicit fallback tier instead of a hidden tiebreak.
- `memory foam floor mat` is a floor mat, not a door mat.
- a bare `desk mat` no longer invents a rubber material.
- construction corrected wherever it smuggled in an unstated material. The first pass fixed
  instances (wood block, jute tray, silicone hook, button and sequin art, plain photo frame);
  the independent review found the class was not exhausted, so every rule was split into a
  material-stated variant and a neutral one — floating box, wall/door/hanging sign, wall shelf,
  perpetual calendar, wall clock plaque, mug, planter, hamper, bin, basket, tote, toy chest,
  ottoman, poly doormat, kitchen mat, birdhouse, stepping stone, garden thermometer, watering
  can, canvas tapestry and the framed-paper fallbacks. `ConstructionNeverStatesAnUnstatedMaterialTests`
  in `tools/product_type_reader/tests/test_reader.py` now fails the build if the class regrows.
- `MDF box` reads as boxed MDF wall art (974 rows), `MDF sign` as a wall sign.

Fixed so the reader stops refusing readable wording: `lentclr`/`lntclr`/`shbx`/`galvanzied`
abbreviations, `3-D` spacing, `molded foam`, `die cut mdf`, `greyboard storage`,
`pvc foam mat`, `outdoor mat`, `deep frame`, `floating frame`, `frame width`, `paper print`,
`print under glass`, `desktop org`, `colour your own`.

## What is still open

- The 1,601 unreadable descriptions are listed by frequency in the report. Most are
  property or artwork wording with no product noun at all (a bare property name, an artwork phrase). They are deliberately left unreadable rather than guessed.
- A handful of labels are genuinely ambiguous and are named for owner review, notably
  `Framed Print / Under Glass` versus `Framed Print / MDF` where a description states both, and
  the mixed-assortment master SKUs that name several products in one line.
- **Owner acceptance (plan step 5) remains open on #3024.** Phase B — storing the value on
  `plm.item` — must not start before it.
