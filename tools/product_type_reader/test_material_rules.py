"""Physical material extraction uses stated, bounded wording only."""

import pytest

from tools.product_type_reader.material_rules import extract_materials


def material(title: str, noun: str, evidence: str | None = None, boundaries=(),
             product_type: str = "", base_materials: str = "", description: str | None = None) -> str:
    start = title.index(noun)
    return extract_materials(
        text=title,
        evidence=evidence or noun,
        product_start=start,
        product_end=start + len(noun),
        size_boundaries=boundaries,
        product_type=product_type,
        base_materials=base_materials,
        description=description,
    )


@pytest.mark.parametrize("title,noun,expected", [
    ("mdf die cut block", "block", "MDF"),
    ("ceramic printed mug", "mug", "Ceramic"),
    ("silicone baking mat", "mat", "Silicone"),
    ("printed glass shadowbox", "shadowbox", "Glass"),
    ("canvas banner", "banner", "Canvas"),
    ("greyboard box", "box", "Greyboard"),
    ("pp felt organizer", "organizer", "Felt; PP"),
    ("pe rattan basket", "basket", "PE Rattan"),
    ("cotton rope basket", "basket", "Cotton Rope"),
    ("paper rope basket", "basket", "Paper Rope"),
    ("wool fabric banner", "banner", "Wool"),
    ("linen paper print", "print", "Paper"),
    ("faux wood tray", "tray", ""),
    ("tin sign", "sign", "Metal"),
    ("aluminum sign", "sign", "Aluminum"),
    ("plain mug", "mug", ""),
])
def test_explicit_prefix_and_compound_materials(title, noun, expected):
    assert material(title, noun) == expected


@pytest.mark.parametrize("title,noun,expected", [
    ("framed print under glass", "print", "Glass"),
    ("lap desk mdf", "desk", "MDF"),
    ("storage box with mdf lid", "box", "MDF"),
    ("wall art with paper and glass", "art", "Glass; Paper"),
    ("plaque with metallic artwork", "plaque", ""),
])
def test_direct_material_suffix(title, noun, expected):
    assert material(title, noun) == expected


def test_dimension_ends_trailing_material_clause():
    title = "pencil case 10x8 canvas artwork"
    assert material(title, "case", boundaries=(12,)) == ""


@pytest.mark.parametrize("title", [
    "pencil case canvas artwork",
    "pencil case canvas texture",
    "pencil case fabric pattern",
])
def test_artwork_suffix_does_not_supply_material(title):
    assert material(title, "case") == ""


def test_leading_explicit_material_survives_size_boundary():
    title = "mdf 16x20 framed print"
    assert material(title, "print", boundaries=(4,)) == "MDF"


def test_artwork_underscore_is_not_read_by_this_api():
    assert material("acrylic pencil case", "case", "acrylic pencil case") == "Acrylic"


def test_bad_span_fails_closed():
    with pytest.raises(ValueError, match="product span"):
        extract_materials(text="box", evidence="box", product_start=10, product_end=13)


def test_existing_reviewed_aliases_are_preserved():
    title = "pp molded tray"
    assert extract_materials(text=title, evidence=title, product_start=10,
                             product_end=14, base_materials="Polypropylene") == "Polypropylene"
    title = "cotton rope felt wall art"
    assert extract_materials(text=title, evidence=title, product_start=17,
                             product_end=25, base_materials="Cotton; Felt; Rope") == "Cotton; Felt; Rope"


def test_explicit_aluminum_overrides_generic_metal_label():
    title = "aluminum sign"
    assert extract_materials(text=title, evidence=title, product_start=9,
                             product_end=13, base_materials="Metal") == "Aluminum"


@pytest.mark.parametrize("title,noun,product_type", [
    ("plain canvases", "canvases", "Canvas"),
    ("diycanvas with paint pots", "diycanvas", "Paint-Your-Own Canvas Set"),
    ("canvasboard painting set", "canvasboard", "Paint-Your-Own Canvas Set"),
    ("canvas20x30 print", "print", "Canvas"),
])
def test_explicit_plural_and_joined_canvas(title, noun, product_type):
    assert material(title, noun, product_type=product_type) == "Canvas"


def test_mdf_bar_is_a_stated_tapestry_component():
    title = "printed canvas tapestry with decorative mdf bar watercolor art"
    assert material(title, "tapestry", product_type="Tapestry", base_materials="Canvas") == "Canvas; MDF"


@pytest.mark.parametrize("title,noun,expected", [
    ("framed mdf print on watercolor paper", "print", "MDF; Paper"),
    ("framed mdf print with specialty paper", "print", "MDF; Paper"),
    ("framed mdf print w speciality paper", "print", "MDF; Paper"),
    ("frame with paper accessories", "frame", "Paper"),
    ("framed print on watercolor paper effect", "print", ""),
])
def test_named_paper_stock_and_accessory_clause(title, noun, expected):
    assert material(title, noun, product_type="Framed Print") == expected


def test_craft_paper_accessory_after_size_is_explicit_component():
    title = "canvas easel craft paper"
    assert material(title, "easel", boundaries=(13,), product_type="Easel",
                    base_materials="Canvas") == "Canvas; Paper"


def test_watercolor_paper_artwork_does_not_change_canvas_material():
    title = "canvas with watercolor paper artwork"
    assert material(title, "canvas", product_type="Canvas", base_materials="Canvas") == "Canvas"


def test_satin_banner_after_artwork_still_states_physical_material():
    title = "glass framed art house crest satin paper banner"
    assert material(title, "art", product_type="Framed Art", base_materials="Glass") == "Glass; Paper; Satin"


@pytest.mark.parametrize("title", ["grey board box", "greybrd box", "grey-board box", "graybrd box"])
def test_greyboard_spelling_variants(title):
    normalized = title.replace("-", " ")
    assert material(normalized, "box") == "Greyboard"


def test_canvas_frame_only_names_what_the_frame_holds():
    assert material("canvas frame", "frame", product_type="Frame", base_materials="Canvas") == ""
    assert material("canvas single canvas frame", "frame", product_type="Frame",
                    base_materials="Canvas") == "Canvas"


def test_high_gloss_abbreviation_is_not_glass():
    assert material("canvas with hgh glass", "canvas", evidence="canvas hgh glass",
                    product_type="Canvas", base_materials="Canvas; Glass") == "Canvas"


def test_depicted_glass_bottle_is_not_canvas_substrate():
    assert material("canvas with glass bottle artwork", "canvas", evidence="canvas glass",
                    product_type="Canvas", base_materials="Canvas; Glass") == "Canvas"


def test_sponge_bob_artwork_is_not_sponge_material():
    assert material("sponge bob diy canvas", "canvas", evidence="sponge bob canvas",
                    product_type="Paint-Your-Own Canvas Set") == "Canvas"


@pytest.mark.parametrize("title", [
    "metal gear solid canvas",
    "wood duck canvas",
    "glass slipper canvas",
    "paper mario canvas",
    "cotton candy canvas",
    "plastic man canvas",
])
def test_property_or_artwork_material_word_is_not_substrate(title):
    assert material(title, "canvas", evidence="canvas", product_type="Canvas") == "Canvas"


@pytest.mark.parametrize("title,expected", [
    ("metal canvas", "Canvas; Metal"),
    ("wood canvas", "Canvas; Wood"),
    ("mdf framed canvas", "Canvas; MDF"),
    ("fabric storage toy chest", "Fabric"),
])
def test_contiguous_explicit_material_prefix_remains_readable(title, expected):
    noun = "chest" if title.endswith("chest") else "canvas"
    evidence = noun
    assert material(title, noun, evidence=evidence, product_type=noun.title()) == expected


@pytest.mark.parametrize("title", [
    "canvas with wood duck artwork",
    "canvas with glass slipper artwork",
])
def test_material_looking_suffix_artwork_does_not_change_substrate(title):
    assert material(title, "canvas", evidence="canvas", product_type="Canvas") == "Canvas"


@pytest.mark.parametrize("title,noun,expected", [
    ("nonwoven storage 24 pocket hanging shoe organizer", "organizer", "Fabric"),
    ("non woven storage bin", "bin", "Fabric"),
    ("non-woven storage bin", "bin", "Fabric"),
    ("sega classic sonic die cut wood piggy bank", "bank", "Wood"),
    ("die cut wood piggy bank", "bank", "Wood"),
])
def test_bounded_textile_and_bank_physical_phrases(title, noun, expected):
    assert material(title, noun, evidence=noun, product_type=noun.title()) == expected


@pytest.mark.parametrize("title,noun,product_type,expected", [
    ("mdf icon hook", "hook", "Hook", "MDF"),
    ("nonwoven storage closet toy chest", "chest", "Storage Toy Chest", "Fabric"),
    ("nonwoven storage in closet pop up hamper", "hamper", "Storage Hamper", "Fabric"),
    ("fabric bow wall art", "art", "Wall Art", "Fabric"),
    ("poly cotton greyboard laundry hamper", "hamper", "Storage Hamper", "Greyboard; Poly-Cotton"),
    ("greyboard recipe box", "box", "Recipe Box", "Greyboard"),
])
def test_material_in_bounded_product_clause_after_size(title, noun, product_type, expected):
    assert material(title, noun, evidence=noun, product_type=product_type,
                    boundaries=(0,)) == expected


def test_size_separates_preceding_artwork_from_material_clause():
    title = "wood duck mdf icon hook"
    assert material(title, "hook", evidence="hook", boundaries=(10,),
                    product_type="Hook") == "MDF"


@pytest.mark.parametrize("title,noun,product_type,expected", [
    ("lenticular art in 1 mdf frame", "art", "Lenticular Art", "MDF"),
    ("boxed mdf with decoupaged paper print", "print", "Print", "MDF; Paper"),
    ("greyboard lift off lid pink glitter lid box", "box", "Hard Storage Box", "Greyboard"),
    ("die cut paper butterfly in shadowbox frame", "frame", "Framed Shadowbox", "Paper"),
    ("framed newspaper under glass", "newspaper", "Frame", "Glass; Paper"),
    ("paper card art print", "print", "Art Print", "Paper"),
    ("mdf photo frame with ink pad and paper", "frame", "Photo Frame", "MDF; Paper"),
    ("setback frame with printed linen paper", "frame", "Framed Art", "Paper"),
])
def test_named_physical_components(title, noun, product_type, expected):
    assert material(title, noun, evidence=noun, product_type=product_type) == expected


@pytest.mark.parametrize("title,noun,product_type,expected", [
    ("mdf yellow friends frame wall art", "art", "Wall Art", "MDF"),
    ("mdf spot varnish print", "print", "Print", "MDF"),
    ("chalkboard art mdf box", "art", "Chalkboard Box", "MDF"),
    ("nonwoven fabric desktop storage cubby", "cubby", "Desktop Organizer", "Fabric"),
    ("fabric covered magnetic memo board", "board", "Memo Board", "Fabric"),
    ("canvas layered fabric", "canvas", "Canvas", "Canvas; Fabric"),
    ("greyboard faux vhs box storage set", "set", "Storage Box", "Greyboard"),
    ("greyboard flat top storage chest", "chest", "Storage Chest", "Greyboard"),
    ("framed glass fringed paper shadowbox", "shadowbox", "Framed Glass Shadowbox", "Paper"),
    ("floating frame embossed ppr prnt", "frame", "Framed Print", "Paper"),
    ("frame embossed pper prnt", "frame", "Framed Print", "Paper"),
    ("canvas easel craft paper", "easel", "Canvas", "Canvas; Paper"),
])
def test_reviewed_material_residual_phrases(title, noun, product_type, expected):
    assert material(title, noun, evidence=noun, product_type=product_type) == expected


def test_mdf_artwork_word_does_not_become_substrate():
    assert material("canvas with mdf logo art", "canvas", evidence="canvas",
                    product_type="Canvas") == "Canvas"


@pytest.mark.parametrize("title,noun,product_type,expected", [
    ("mdf framed character wall art", "art", "Wall Art", "MDF"),
    ("mdf 7 high phone stands", "stands", "Phone Stand", "MDF"),
    ("guitar hook led and mdf", "hook", "Guitar Hook", "MDF"),
    ("die cut pieced mdf logo art", "art", "Art", "MDF"),
    ("circle mdf collectible shelf", "shelf", "Shelf", "MDF"),
    ("greyboard float top storage chest", "chest", "Storage Chest", "Greyboard"),
    ("greyboard float tp storage chest", "chest", "Storage Chest", "Greyboard"),
])
def test_remaining_reviewed_explicit_components(title, noun, product_type, expected):
    assert material(title, noun, evidence=noun, product_type=product_type) == expected


def test_separate_closed_physical_clause_after_underscore():
    assert material("functional guitar hook", "hook", evidence="hook", product_type="Guitar Hook",
                    description='Functional Guitar Hook_LED and MDF 11.4x5.07" x3.73"') == "MDF"
    assert material("canvas", "canvas", product_type="Canvas",
                    description="Canvas_LED and MDF artwork") == "Canvas"
    assert material("canvas", "canvas", product_type="Canvas",
                    description="Canvas_Wood Duck artwork") == "Canvas"


@pytest.mark.parametrize("title,noun,product_type,base,expected", [
    ("plush cubeart", "cubeart", "Plush Cube Art", "Fabric", ""),
    ("cotton rope storage bin with felt applique", "bin", "Storage Bin",
     "Cotton; Felt; Rope", "Cotton; Felt"),
    ("cotton rope storage bin", "bin", "Storage Bin", "Cotton; Rope", "Cotton"),
    ("half canvas half cotton rope storage bin", "bin", "Storage Bin",
     "Canvas; Cotton; Rope", "Canvas; Cotton"),
    ("half canvas half cotton rope storage bin", "bin", "Storage Bin",
     "Cotton; Rope", "Canvas; Cotton"),
    ("set of cotton rope storage bins with canvas inside", "bins", "Storage Bin",
     "Canvas; Cotton; Rope", "Canvas; Cotton Rope"),
    ("5 pc set cotton rope storage bins w canvas inside", "bins", "Storage Bin",
     "Cotton; Rope", "Canvas; Cotton Rope"),
    ("cotton rope storage with embroidery", "storage", "Storage Container",
     "Cotton; Rope", "Cotton Rope"),
    ("paper rope storage bin", "bin", "Storage Bin", "Paper; Rope", "Paper"),
    ("satin canvas", "canvas", "Canvas", "Canvas; Satin", "Canvas"),
    ("mdf door sign with hanging rope", "sign", "Door Sign", "MDF; Rope", "MDF"),
])
def test_reviewed_material_vs_component_or_style(title,noun,product_type,base,expected):
    assert material(title,noun,evidence=noun,product_type=product_type,base_materials=base) == expected


@pytest.mark.parametrize("title,noun,product_type,expected", [
    ("canvas with chenille embroidery", "canvas", "Canvas", "Canvas; Chenille"),
    ("canvas w chenille artwork", "canvas", "Canvas", "Canvas; Chenille"),
    ("metal plate emb canvas", "canvas", "Canvas", "Canvas; Metal"),
    ("canvas character art with metal logo", "canvas", "Canvas", "Canvas; Metal"),
])
def test_explicit_canvas_components(title,noun,product_type,expected):
    assert material(title,noun,evidence=noun,product_type=product_type) == expected


def test_property_names_still_do_not_supply_material():
    assert material("metal gear solid canvas", "canvas", evidence="canvas",
                    product_type="Canvas") == "Canvas"
    assert material("wood duck canvas", "canvas", evidence="canvas",
                    product_type="Canvas") == "Canvas"


@pytest.mark.parametrize("title,expected", [
    ("floating frame canvas w faux leather", "Canvas; Faux Leather"),
    ("stretched canvas with textured faux leather patch", "Canvas; Faux Leather"),
    ("canvas w handpaint and faux leather paint splatter", "Canvas; Faux Leather"),
    ("canvas w chenille and faux leather", "Canvas; Chenille; Faux Leather"),
    ("printed canvas multipack set of 4 w faux leather patch", "Canvas; Faux Leather"),
])
def test_explicit_canvas_faux_leather_is_physical_material(title, expected):
    assert material(title,"canvas",evidence="canvas",product_type="Canvas") == expected


@pytest.mark.parametrize("title", [
    "canvas with faux leather texture",
    "canvas with faux leather look",
    "canvas with faux leather pattern",
])
def test_faux_leather_appearance_does_not_state_material(title):
    assert material(title,"canvas",evidence="canvas",product_type="Canvas") == "Canvas"


def test_canvas_faux_leather_rope_attachment_is_not_substrate():
    assert material("floating frame canvas w faux leather and rope", "canvas",
                    evidence="canvas", product_type="Framed Canvas",
                    base_materials="Canvas; Faux Leather; Rope") == "Canvas; Faux Leather"
    assert material("rope canvas", "canvas", evidence="canvas", product_type="Canvas",
                    base_materials="Canvas; Rope") == "Canvas; Rope"


@pytest.mark.parametrize("title,noun,product_type,expected", [
    ("ceramic mini planter", "planter", "Planter", "Ceramic"),
    ("ceramic planter with photo frame", "planter", "Planter with Photo Frame", "Ceramic"),
    ("ceramic figure block", "block", "Block", "Ceramic"),
    ("ceramic three chain links tabletop decor", "tabletop", "Tabletop Decor", "Ceramic"),
    ("shaped ceramic tabletop", "tabletop", "Tabletop Decor", "Ceramic"),
    ("cermaic piggy bank", "bank", "Bank", "Ceramic"),
    ("diy crmic min plntr", "plntr", "Planter", "Ceramic"),
    ("mdf photo frame with plaster print", "photo frame", "Photo Frame", "MDF; Plaster"),
    ("canvas w eva bin", "bin", "Storage Bin", "Canvas; EVA"),
    ("wire emb canvas", "canvas", "Canvas", "Canvas; Wire"),
    ("stretched pu w screen print", "print", "Print", "PU"),
    ("faux pu hamper", "hamper", "Storage Hamper", "PU"),
    ("setback framed metallic pu", "framed", "Framed Art", "PU"),
])
def test_reviewed_explicit_material_components(title,noun,product_type,expected):
    assert material(title,noun,evidence=noun,product_type=product_type) == expected


def test_underscore_ceramic_substrate_is_before_physical_noun():
    assert material("clay knot tabletop decor", "knot", evidence="knot",
                    product_type="Decorative Knot", description="Ceramic_Clay Knot Tabletop Decor") == "Ceramic"
    assert material("clay knot tabletop decor", "knot", evidence="knot",
                    product_type="Decorative Knot", description="Ceramic artwork_Clay Knot Tabletop Decor") == ""


def test_material_words_in_artwork_do_not_supply_substrate():
    assert material("canvas", "canvas", evidence="canvas", product_type="Canvas",
                    description="Canvas_Ceramic vase artwork") == "Canvas"
    assert material("photo frame", "frame", evidence="frame", product_type="Photo Frame",
                    description="Photo Frame_Plaster statue artwork") == ""


@pytest.mark.parametrize("title,noun,product_type,base,expected", [
    ("plush basket with felt embroidery", "basket", "Storage Basket", "Fabric; Felt", "Felt"),
    ("gold love on black wood veneer", "love", "Decorative Word", "MDF; Wire", "MDF; Wire; Wood"),
    ("pvc household mat", "mat", "Mat", "", "PVC"),
    ("pvc frame", "frame", "Photo Frame", "", "PVC"),
    ("polyester mesh pop up hamper", "hamper", "Storage Hamper", "", "Polyester"),
    ("polyester mesh hamper", "hamper", "Storage Hamper", "", "Polyester"),
    ("polyester throw rug", "rug", "Rug", "", "Polyester"),
    ("pe rattan wall shelf", "shelf", "Wall Shelf", "", "PE Rattan"),
    ("burlap canvas", "canvas", "Canvas", "Canvas; Fabric", "Burlap; Canvas"),
    ("canvas with chiffon applique", "canvas", "Canvas", "Canvas", "Canvas; Chiffon"),
    ("metal bow frame mdf print", "print", "Print", "MDF", "MDF; Metal"),
    ("printed glass shadowbox nat wood frame", "shadowbox", "Framed Glass Shadowbox", "Glass", "Glass; Wood"),
    ("framed art under glass w dark wood frame", "art", "Framed Art", "Glass", "Glass; Wood"),
    ("printed glass under die cut tin", "glass", "Glass Art", "Glass; Metal", "Glass; Tin"),
])
def test_more_reviewed_material_substrates(title,noun,product_type,base,expected):
    assert material(title,noun,evidence=noun,product_type=product_type,
                    base_materials=base) == expected


def test_pe_rattan_first_clause_is_physical_on_reviewed_decor():
    assert material("dimensional bow", "bow", evidence="bow", product_type="Dimensional Decor",
                    description="PE Rattan_Dimensional Bow") == "PE Rattan"
    assert material("dimensional bow", "bow", evidence="bow", product_type="Dimensional Decor",
                    description="PE Rattan style_Dimensional Bow") == ""


def test_artwork_and_appearance_words_stay_outside_material():
    assert material("canvas", "canvas", evidence="canvas", product_type="Canvas",
                    description="Canvas_Burlap texture artwork") == "Canvas"
    assert material("mat", "mat", evidence="mat", product_type="Mat",
                    description="Mat_PVC logo artwork") == ""
    assert material("glass art", "glass", evidence="glass", product_type="Glass Art",
                    description="Glass Art_Tin Man artwork") == "Glass"


def test_wood_veneer_after_leading_size_is_still_physical():
    title = "gold love on black wood veneer"
    assert material(title, "love", evidence="love", product_type="Decorative Word",
                    base_materials="MDF; Wire", boundaries=(0,)) == "MDF; Wire; Wood"


@pytest.mark.parametrize("title,noun,product_type,base,expected", [
    ("canvas with mdf effect", "canvas", "Canvas", "Canvas; MDF", "Canvas"),
    ("canvas with wood texture", "canvas", "Canvas", "Canvas; Wood", "Canvas"),
    ("canvas with metal look", "canvas", "Canvas", "Canvas; Metal", "Canvas"),
    ("canvas with glass pattern", "canvas", "Canvas", "Canvas; Glass", "Canvas"),
    ("canvas with faux wood", "canvas", "Canvas", "Canvas; Wood", "Canvas"),
    ("canvas with mdf frame and mdf effect", "canvas", "Canvas", "Canvas; MDF", "Canvas; MDF"),
    ("faux pu hamper", "hamper", "Storage Hamper", "", "PU"),
])
def test_visual_effect_never_supplies_physical_material(title,noun,product_type,base,expected):
    assert material(title,noun,evidence=noun,product_type=product_type,
                    base_materials=base) == expected


@pytest.mark.parametrize("prefix", ["nonwoven", "non woven", "non-woven"])
def test_nonwoven_separator_variants_are_explicit_fabric(prefix):
    title = f"{prefix} storage bin"
    assert material(title,"storage bin",evidence="woven storage bin" if prefix != "nonwoven" else title,
                    product_type="Storage Bin") == "Fabric"


@pytest.mark.parametrize("title,noun,product_type,base,expected", [
    ("mdf die cut destination signs", "signs", "Sign", "", "MDF"),
    ("mdf w lenticular reversible door hanger", "hanger", "Door Hanger", "", "MDF"),
    ("framed glass shadowbox w frayed linen", "shadowbox", "Framed Glass Shadowbox", "Glass", "Glass; Linen"),
    ("figural ceramic pencil cup wooden barrel", "cup", "Pencil Cup", "Ceramic; Wood", "Ceramic"),
    ("plush wall art", "art", "Wall Art", "Fabric", ""),
    ("plush keychain", "keychain", "Keychain", "Fabric", "Plush"),
    ("printed glass retro 15x20 shadowbox frame", "shadowbox", "Framed Glass Shadowbox", "", "Glass"),
    ("frmd art undr glss", "art", "Framed Art", "", "Glass"),
])
def test_latest_reviewed_material_phrases(title,noun,product_type,base,expected):
    assert material(title,noun,evidence=noun,product_type=product_type,
                    base_materials=base) == expected


def test_barrel_artwork_and_plush_name_do_not_create_other_materials():
    assert material("ceramic pencil cup with wood frame", "cup", evidence="cup",
                    product_type="Pencil Cup", base_materials="Ceramic; Wood") == "Ceramic; Wood"
    assert material("wall art", "art", evidence="art", product_type="Wall Art",
                    description="Wall Art_Plush character artwork") == ""
