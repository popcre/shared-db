"""Small physical-wording controls, independent of historical MG codes."""

from tools.product_type_reader.construction_rules import refine_construction


def test_framed_and_deep_frame_require_a_stated_physical_phrase():
    assert refine_construction("Deep Framed wall art", "Framed Art") == "Framed"
    assert refine_construction("Art in deep frame", "Framed Art") == "Deep Frame"
    assert refine_construction("Framed print", "Framed Print") == ""
    assert refine_construction("Art_Print framed", "Framed Art") == ""
    assert refine_construction("Die-cut paper art in shadowbox frame", "Framed Shadowbox") == "Die-Cut; Framed"
    assert refine_construction("Shadowbox 16x20 die-cut paper flower in frame", "Framed Shadowbox") == ""


def test_shadowbox_frame_requires_the_physical_shadowbox_clause():
    assert refine_construction("Printed glass shadowbox frame", "Framed Glass Shadowbox") == "Framed"
    assert refine_construction("Printed glass shadowbox with black frame", "Framed Glass Shadowbox") == "Framed"
    assert refine_construction("Molded shadowbox w white frame", "Framed Shadowbox") == "Framed; Molded"
    assert refine_construction("Printed glass shadowbox w navy blue frame", "Framed Glass Shadowbox") == "Framed"
    assert refine_construction("Printed glass shadowbox winter scene black frame 11x14", "Framed Glass Shadowbox") == "Framed"
    assert refine_construction("15x20 printed glass shadowbox in oval frame", "Framed Glass Shadowbox") == "Framed"
    assert refine_construction("Photo frame with black border", "Photo Frame") == ""
    assert refine_construction("Framed print with black frame", "Framed Print") == ""
    assert refine_construction("Shadowbox 15x20 flower artwork in oval frame", "Framed Shadowbox") == ""
    assert refine_construction("Shadowbox_flower artwork in oval frame", "Framed Shadowbox") == ""
    assert refine_construction("Shadowbox winter scene frame artwork 11x14", "Framed Shadowbox") == ""
    assert refine_construction("Shadowbox w flower artwork frame 11x14", "Framed Shadowbox") == ""


def test_floating_framed_is_explicit_even_in_a_separate_physical_clause():
    assert refine_construction("Canvas_floating framed", "Framed Canvas") == "Floating Frame"
    assert refine_construction("Canvas_floating clouds", "Framed Canvas") == ""


def test_die_cut_is_a_physical_modifier_not_an_attachment_or_product_guess():
    assert refine_construction("Die-cut block", "Block") == "Die-Cut"
    assert refine_construction("Diecut MDF photo frame", "Photo Frame") == "Die-Cut"
    assert refine_construction("Die-cut MDF plaque", "Plaque") == "Die-Cut"
    assert refine_construction("Die cut icon plaque", "Plaque") == ""
    assert refine_construction("Die cut attachment photo frame", "Photo Frame") == ""
    assert refine_construction("Tablet stand with diecut artwork", "Tablet Stand") == ""
    assert refine_construction("Block_die cut art", "Block") == ""


def test_specific_families_guard_ambiguous_construction_words():
    assert refine_construction("Reversible door hanger", "Door Hanger") == "Reversible"
    assert refine_construction("Reversible MDF box", "MDF Box") == ""
    assert refine_construction("Woven file organizer", "File Organizer") == "Woven"
    assert refine_construction("Woven storage cube", "Storage Cube") == ""
    assert refine_construction("Plush wall art", "Wall Art") == "Plush"
    assert refine_construction("Plush keychain", "Keychain") == ""
    assert refine_construction("Figural pencil cup", "Pencil Cup") == "Figural"
    assert refine_construction("Figural hook", "Hook") == ""
    assert refine_construction("Straight storage cube", "Storage Cube") == "Straight"
    assert refine_construction("Straight canvas", "Canvas") == ""
    assert refine_construction("Glass art with chain", "Glass Art") == "Chain"
    assert refine_construction("Chain sign", "Sign") == ""


def test_preserves_existing_construction_in_canonical_order():
    assert refine_construction("Woven hanging wall art", "Wall Art", "Hanging") == "Hanging; Woven"
    assert refine_construction(None, "Wall Art", "Hanging") == "Hanging"


def test_box_and_frame_assembly_words_require_source_wording():
    assert refine_construction("Hard storage box with lift off lid", "Hard Storage Box") == "Lift-Off"
    assert refine_construction("Hard storage box with lift-off lid", "Hard Storage Box") == "Lift-Off"
    assert refine_construction("Hard storage box", "Hard Storage Box") == ""
    assert refine_construction("Setback framed art", "Framed Art") == "Framed; Setback"
    assert refine_construction("Faux book desktop organizer", "Desktop Organizer") == "Faux Book"
    assert refine_construction("MDF box with hooks", "MDF Box") == "Hooks"
    assert refine_construction("Wall hook", "Wall Hook") == ""


def test_explicit_block_perpetual_calendar_word_orders():
    assert refine_construction("Block MDF Perpetual Calendar", "Perpetual Calendar") == "Block"
    assert refine_construction("MDF Block Perpetual Calendar", "Perpetual Calendar") == "Block"
    assert refine_construction("Block MDF Perpetual Calendar", "Perpetual Calendar", "Domed") == "Block; Domed"


def test_block_does_not_transfer_to_compound_or_generic_products():
    assert refine_construction(
        "MDF Block Perpetual Calendar with Pencil Cup", "Perpetual Calendar"
    ) == ""
    assert refine_construction(
        "MDF Block Perpetual Calendar with Pencil Cup", "Perpetual Calendar with Pencil Cup"
    ) == ""
    assert refine_construction("MDF block", "Block") == ""
    assert refine_construction("Block calendar", "Perpetual Calendar") == ""
    assert refine_construction("MDF block desk calendar", "Perpetual Calendar") == ""
    assert refine_construction("Calendar_Block MDF Perpetual Calendar", "Perpetual Calendar") == ""


def test_woven_construction_excludes_nonwoven_and_appearance_forms():
    for wording in (
        "non-woven storage bin", "non woven storage bin", "nonwoven storage bin",
        "non–woven storage bin", "non/woven storage bin", "not woven storage bin",
        "un-woven storage bin", "unwoven storage bin", "faux-woven storage bin",
        "fake woven storage bin", "imitation woven storage bin",
        "woven-look storage bin", "woven texture storage bin",
        "non-woven and woven storage bin",
    ):
        assert refine_construction(wording, "Storage Bin") == "", wording


def test_literal_woven_hyphenated_construction_remains_positive():
    for wording in ("woven storage bin", "hand-woven storage bin", "machine-woven storage bin"):
        assert refine_construction(wording, "Storage Bin") == "Woven", wording


def test_size_ends_construction_evidence_before_artwork():
    assert refine_construction("Canvas 16x20 die cut flower artwork", "Canvas") == ""
    assert refine_construction("Die-cut canvas 16x20 flower artwork", "Canvas") == "Die-Cut"
    assert refine_construction("Canvas 16\" x 20\" floating framed flowers", "Framed Canvas") == ""
    assert refine_construction("Floating framed canvas 16\" x 20\" flowers", "Framed Canvas") == "Floating Frame"
    assert refine_construction("Storage bin 12x12 non-woven floral artwork", "Storage Bin") == ""
    assert refine_construction("Woven storage bin 12x12 floral artwork", "Storage Bin") == "Woven"


def test_artwork_clauses_do_not_supply_other_constructions():
    assert refine_construction("Canvas_die cut flower artwork", "Canvas") == ""
    assert refine_construction("Framed art_woven flowers", "Framed Art") == "Framed"
    assert refine_construction("Canvas_floating framed artwork", "Framed Canvas") == ""
    assert refine_construction("Canvas_floating framed", "Framed Canvas") == "Floating Frame"


def test_complete_product_phrase_after_size_is_physical_evidence():
    assert refine_construction("Gallery 16x20 framed art", "Framed Art") == "Framed"
    assert refine_construction("Gallery 16x20 plush wall art", "Wall Art") == "Plush"
    assert refine_construction("Gallery 16x20 MDF die cut", "Sign") == "Die-Cut"
    assert refine_construction("Gallery 16x20 diecut MDF art", "Art") == "Die-Cut"
    assert refine_construction("Canvas 16x20 die cut flower artwork", "Canvas") == ""
    assert refine_construction("Sign 16x20 die cut flower artwork", "Sign") == ""


def test_rope_construction_requires_a_supported_storage_product_phrase():
    assert refine_construction("Cotton rope storage bin", "Storage Bin") == "Rope"
    assert refine_construction("Paper rope storage bin", "Storage Bin") == "Rope"
    assert refine_construction("Cotton rope basket", "Storage Basket") == "Rope"
    assert refine_construction("Cotton rope bin with artwork", "Storage Bin") == ""
    assert refine_construction("Canvas with cotton rope", "Canvas") == ""


def test_explicit_assembly_words_are_bounded_to_physical_families():
    assert refine_construction("Pendulum clock", "Clock") == "Pendulum"
    assert refine_construction("Clock 12x12 pendulum artwork", "Clock") == ""
    assert refine_construction("Framed deckle edge paper art", "Framed Art") == "Deckled Edge; Framed"
    assert refine_construction("Framed print with deckled edge artwork", "Framed Print") == ""
    assert refine_construction("Layered MDF plaque", "Plaque") == "Layered"
    assert refine_construction("Printed glass layered artwork", "Glass Art") == ""
    assert refine_construction("MDF plaque 12x12 layered flower artwork", "Plaque") == ""
    assert refine_construction("Folding shelf", "Shelf") == "Folding"
    assert refine_construction("Shelf 12x12 folding flower artwork", "Shelf") == ""
    assert refine_construction("Non-collapsible storage ottoman", "Storage Ottoman", "Collapsible") == "Non-Collapsible"
    assert refine_construction("Not collapsible storage ottoman", "Storage Ottoman") == "Non-Collapsible"
    assert refine_construction("Collapsible storage ottoman", "Storage Ottoman", "Collapsible") == "Collapsible"
    assert refine_construction("Frayed fabric framed art", "Framed Fabric Art") == "Framed; Frayed"
    assert refine_construction("Framed fabric art 12x12 frayed flower artwork", "Framed Fabric Art") == "Framed"
    assert refine_construction("Writing desk with legs", "Writing Desk") == "With Legs"
    assert refine_construction("Writing desk 12x12 with legs artwork", "Writing Desk") == ""
    assert refine_construction("DIY ceramic planter", "Planter") == "DIY"
    assert refine_construction("DIY trinket tray with paint", "Trinket Tray") == "DIY"
    assert refine_construction("DIY artwork with paint", "Planter") == ""
    assert refine_construction("Molded photo frame", "Photo Frame") == "Molded"
    assert refine_construction("Photo frame 12x12 molded flower artwork", "Photo Frame") == ""
    assert refine_construction("Canvas in floating frame", "Framed Canvas") == "Floating Frame"
    assert refine_construction("Framed print in floater frame", "Framed Print") == "Floating Frame"
    assert refine_construction("Framed print 12x12 floating frame artwork", "Framed Print") == ""


def test_frame_and_edge_specifications_need_a_physical_product_phrase():
    assert refine_construction("Blank artist canvas_CANVAS FRAME_8x10", "Canvas") == "Frame"
    assert refine_construction("Blank artist canvas_2PK_CANVAS FRAME_8x10", "Canvas") == "Frame"
    assert refine_construction('Blank artist canvas_21x31 Single Canvas Frame x 0.75"', "Canvas") == "Frame"
    assert refine_construction("Blank artist canvas_FRAME BLACK CANVAS_8x10", "Canvas") == "Frame"
    assert refine_construction("Canvas_CANVAS FRAME_8x10", "Canvas") == ""
    assert refine_construction("Blank artist canvas_flower frame artwork_8x10", "Canvas") == ""
    assert refine_construction("Printed MDF in deep frame", "Framed Print", "Framed") == "Deep Frame; Framed"
    assert refine_construction("Deep frame flower artwork print", "Print") == ""
    assert refine_construction("Framed deckled print under glass", "Framed Print", "Framed") == "Deckled Edge; Framed"
    assert refine_construction("Framed print with deckled edge artwork", "Framed Print", "Framed") == "Framed"
    assert refine_construction("Shadowbox 11x14 frame width 1 inch", "Framed Shadowbox") == "Framed"
    assert refine_construction("Shadowbox 11x14 flower artwork in frame", "Framed Shadowbox") == ""


def test_layers_hooks_slits_mat_and_rounded_edge_are_source_stated():
    assert refine_construction("Two-layer MDF die-cut plaque", "Plaque", "Double-Layer") == "Die-Cut; Layered"
    assert refine_construction("2-layer MDF plaque", "Plaque", "Double-Layer") == "Layered"
    assert refine_construction("Two-layer flower artwork plaque", "Plaque") == ""
    assert refine_construction("MDF plaque with 4 hooks", "Plaque") == "With Hooks"
    assert refine_construction('9x12" MDF plaque with 4 hooks', "Plaque") == "With Hooks"
    assert refine_construction('MDF plaque 9x12" flower art with 4 hooks', "Plaque") == ""
    assert refine_construction("MDF box art w/ slits", "MDF Box") == "Slotted"
    assert refine_construction("MDF box_slits in flower artwork", "MDF Box") == ""
    assert refine_construction("Framed art with white mat", "Framed Art") == "Framed; Matted"
    assert refine_construction("Framed art_white mat flower artwork", "Framed Art") == "Framed"
    assert refine_construction("Wood block rounded edge", "Block") == "Rounded"
    assert refine_construction("Wood block_round edge flower artwork", "Block") == ""


def test_explicit_shape_mounting_and_abbreviated_physical_specs():
    assert refine_construction("Framed floated canvas with foil", "Framed Canvas") == "Floating Frame"
    assert refine_construction("Framed canvas_floated flower artwork", "Framed Canvas") == ""
    assert refine_construction("Setback frame with linen paper", "Frame", "Setback") == "Framed; Setback"
    assert refine_construction("Setback frame with raised lasercut icon", "Frame", "Raised; Setback") == "Laser-Cut; Raised; Setback"
    assert refine_construction("Frame with setback flower artwork", "Frame") == ""
    assert refine_construction("Mldd Shdwbx", "Framed Shadowbox") == "Molded"
    assert refine_construction("Mold Shadowbox", "Framed Shadowbox") == "Molded"
    assert refine_construction("Mold flower artwork shadowbox", "Framed Shadowbox") == ""
    assert refine_construction("Die-cut MDF photo frame egg-shaped", "Photo Frame") == "Die-Cut; Shaped"
    assert refine_construction("Die-cut MDF block egg shaped", "Block") == "Die-Cut; Shaped"
    assert refine_construction("Die-cut photo frame_egg-shaped artwork", "Photo Frame") == "Die-Cut"
    assert refine_construction("Framed art w glass & mat", "Framed Art") == "Framed; Matted"
    assert refine_construction("Framed canvas w handpaint, fillet and mat", "Framed Canvas") == "Matted"
    assert refine_construction("Framed art_mat design artwork", "Framed Art") == "Framed"


def test_domed_shape_requires_a_storage_chest_or_tabletop_block_phrase():
    assert refine_construction("Domed greyboard storage chest", "Storage Chest") == "Domed"
    assert refine_construction("DMD GRYBRD STRG CHST W FOIL", "Storage Chest") == "Domed"
    assert refine_construction("Dome block tabletop decor", "Tabletop Block", "Dome") == "Domed"
    assert refine_construction("Storage chest_domed flower artwork", "Storage Chest") == ""
    assert refine_construction("Flat-domed chest", "Storage Chest") == "Flat-Domed"
    assert refine_construction("Flat-Domed Greyboard Storage Chest", "Storage Chest", "Flat-Domed") == "Flat-Domed"
    assert refine_construction("Dome block", "Block") == ""


def test_floating_frame_abbreviations_still_name_a_physical_frame():
    assert refine_construction("Float Frames w Highgloss", "Frame") == "Floating Frame"
    assert refine_construction("Floate Frame w Highgloss", "Frame") == "Floating Frame"
    assert refine_construction("floatr frm cnvs w hgh glss", "Framed Canvas") == "Floating Frame"
    assert refine_construction("float frm embossd ppr prnt", "Framed Print") == "Floating Frame"
    assert refine_construction("Canvas floating frame", "Framed Canvas") == "Floating Frame"
    assert refine_construction('Floating red .25" frame canvas', "Canvas") == "Floating Frame"
    assert refine_construction("Floating character in MDF box", "MDF Box") == "Floating"
    assert refine_construction("Canvas_floating frame flower artwork", "Canvas") == ""
    assert refine_construction("Canvas 16x20 floating flower frame artwork", "Canvas") == ""


def test_explicit_cushion_cutting_nesting_roundness_and_floating_box():
    assert refine_construction("Rectangular lap desk with cushion", "Lap Desk") == "Cushioned"
    assert refine_construction("Lap writing desk w cushion", "Lap Desk") == "Cushioned"
    assert refine_construction("Lap desk_cushion flower artwork", "Lap Desk") == ""
    assert refine_construction("Hand Cut Foam Wall Decor", "Foam Wall Decor") == "Hand-Cut"
    assert refine_construction("Foam Wall Decor_hand cut paper art", "Foam Wall Decor") == ""
    assert refine_construction("Floating Character in MDF Box", "MDF Box") == "Floating"
    assert refine_construction("Floating MDF Box Art", "MDF Box") == "Floating"
    assert refine_construction("MDF Box_floating character artwork", "MDF Box") == ""
    assert refine_construction("Round poly-cotton greyboard laundry hamper", "Storage Hamper") == "Round"
    assert refine_construction("Storage hamper_round character artwork", "Storage Hamper") == ""
    assert refine_construction('10x10" nested MDF box shelf set', "Box Shelf") == "Nested"
    assert refine_construction('10x10" nested box artwork', "Box Shelf") == ""


def test_complete_physical_phrase_after_a_leading_size():
    assert refine_construction('10"x14.75" Canvas in Floating Frame', "Framed Canvas") == "Floating Frame"
    assert refine_construction('16x20 FLT FRAME METALLIC CNV', "Framed Canvas") == "Floating Frame"
    assert refine_construction('12.5x15.25 Molded shadowbox', "Framed Shadowbox") == "Molded"
    assert refine_construction('12.5x15.25 molded flower artwork', "Framed Shadowbox") == ""
    assert refine_construction('10x14.75 floating frame floral artwork', "Canvas") == ""


def test_molded_requires_the_stated_product_assembly():
    assert refine_construction("Molded foam art", "Foam Art") == "Molded"
    assert refine_construction("Molded felt wall art", "Wall Art") == "Molded"
    assert refine_construction("Molded wall figure", "Wall Figure") == "Molded"
    assert refine_construction("Molded phone stand", "Phone Stand") == "Molded"
    assert refine_construction("Molded canvas", "Canvas") == "Molded"
    assert refine_construction("Molded MDF frame", "Frame") == "Molded"
    assert refine_construction("Molded frame art", "Framed Art") == "Molded"
    assert refine_construction("Molded glass shadowbox", "Framed Glass Shadowbox") == "Molded"
    assert refine_construction("Molded polyresin mask", "Mask") == "Molded"
    assert refine_construction("Molded 3D wall mask", "Wall Mask") == "Molded"
    assert refine_construction("Mldd Wll Clck", "Wall Clock") == "Molded"
    assert refine_construction("Foam art_molded flower artwork", "Foam Art") == ""
    assert refine_construction("Foam art 15x15 molded flower artwork", "Foam Art") == ""


def test_named_lid_mounting_shape_and_movement_remain_physical():
    assert refine_construction("Greyboard flip-top box with die-cut lid", "Hard Storage Box") == "Die-Cut; Flip-Top"
    assert refine_construction("Hard storage box_flip-top artwork", "Hard Storage Box") == ""
    assert refine_construction("Lenticular reversible door hanger", "Door Hanger") == "Lenticular; Reversible"
    assert refine_construction("Door hanger_lenticular character art", "Door Hanger") == ""
    assert refine_construction("Wood Rounded Block", "Block") == "Rounded"
    assert refine_construction("Block_rounded flower artwork", "Block") == ""
    assert refine_construction("Wrapped Linen in Floating Frame", "Framed Art") == "Floating Frame; Wrapped"
    assert refine_construction("Framed art_wrapped flower artwork", "Framed Art") == "Framed"
    assert refine_construction("Magazine holder with drawer", "Magazine Holder") == "Drawer"
    assert refine_construction("Magazine holder_drawer illustration", "Magazine Holder") == ""
    assert refine_construction("Flat-Domed Greyboard Storage Chest", "Storage Chest") == "Flat-Domed"
    assert refine_construction("Storage chest_flat-domed arch artwork", "Storage Chest") == ""
    assert refine_construction("Die-Cut MDF PHTO FRME HRT SHPE", "Photo Frame") == "Die-Cut; Shaped"
    assert refine_construction("Photo frame_heart shape artwork", "Photo Frame") == ""
    assert refine_construction("Die-cut clock w step movement", "Clock") == "Die-Cut; Step Movement"
    assert refine_construction("Clock_step movement graphic", "Clock") == ""


def test_complete_file_organizer_phrase_after_leading_size():
    assert refine_construction('10x13x7 3-tier mesh file organizer', "File Organizer") == "Mesh"
    assert refine_construction('12x6x7 Vertical file organizer', "File Organizer") == "Vertical"
    assert refine_construction('10x13x7 mesh flower artwork', "File Organizer") == ""


def test_product_nouns_and_quantity_sets_do_not_become_construction():
    assert refine_construction("DIY canvas panel 2pc set with brush", "Paint-Your-Own Canvas Set", "Panel") == ""
    assert refine_construction("Canvas panel", "Canvas", "Panel") == ""
    assert refine_construction("Greyboard faux book storage set", "Hard Storage Box", "Faux Book; Set") == "Faux Book"
    assert refine_construction('10x10 nested MDF box shelf set of 2', "Box Shelf", "Nested; Set") == "Nested"
    assert refine_construction("Three-piece storage cubes", "Storage Cube", "Set") == ""
    assert refine_construction("Porch leaner with LED", "Porch Leaner", "Leaner") == ""
    assert refine_construction("Leaner sign", "Leaner Sign", "Leaner") == ""
    assert refine_construction("MDF porch leaner hanging sign", "Sign", "Hanging; Leaner") == "Hanging; Leaner"
    assert refine_construction("Floater Framed Canvas", "Framed Canvas", "Floating Frame; Framed") == "Floating Frame"
    assert refine_construction("Framed canvas", "Framed Canvas", "Framed") == "Framed"


def test_nested_physical_words_do_not_promote_art_or_quantity_to_construction():
    assert refine_construction("Floater Framed High Gloss Canvas", "Framed Canvas", "Floating Frame; Framed") == "Floating Frame"
    assert refine_construction("Molded MDF Plaque emblem graphic", "Plaque", "Molded") == ""
    assert refine_construction("Molded Foam Art", "Foam Art", "Molded") == "Molded"
    assert refine_construction("Rectangle lap desk with cushion", "Lap Desk", "Cushioned; Rectangular") == "Cushioned"
    assert refine_construction("7pc storage trunk set", "Storage Trunk", "Set") == ""
    assert refine_construction("7pc storage toy chest set", "Storage Toy Chest", "Set") == ""
    assert refine_construction("2 piece set tapered storage bin", "Storage Bin", "Set; Tapered") == "Tapered"
    assert refine_construction("Framed art_2 piece set_abstract artwork", "Framed Art", "Framed; Set") == "Framed"
    assert refine_construction("Raised embossed floral pattern door mat", "Door Mat", "Raised") == ""
    assert refine_construction("Raised door mat", "Door Mat", "Raised") == "Raised"


def test_fifth_pass_complete_physical_phrases_stay_bounded():
    assert refine_construction("Fabric letter with weighted bottom", "Decorative Letter") == "Weighted"
    assert refine_construction("Decorative letter_weighted flower artwork", "Decorative Letter") == ""
    assert refine_construction("Framed art w glitter mat", "Framed Art") == "Framed; Matted"
    assert refine_construction("Framed deckle paper w mat and foil", "Framed Art") == "Framed; Matted"
    assert refine_construction("Framed art_glitter mat design", "Framed Art") == "Framed"
    assert refine_construction("Flush mount framed art", "Framed Art") == "Flush Mount; Framed"
    assert refine_construction("Arch framed wall art", "Framed Art") == "Arch; Framed"
    assert refine_construction("Rug_runner artwork", "Rug") == ""
    assert refine_construction("Runner rug", "Rug") == "Runner"
    assert refine_construction("Spinning desktop organizer", "Desktop Organizer") == "Spinning"
    assert refine_construction("Rounded corner lift off greyboard storage", "Storage Container") == "Rounded Corner"
    assert refine_construction("Pencil cup with clock", "Pencil Cup") == "With Clock"
    assert refine_construction("Rope Wrapped Round Canvas", "Canvas") == "Rope-Wrapped"
    assert refine_construction("Shaped small box", "Storage Box") == "Shaped"
    assert refine_construction("DIY pcture frm die-cut attachment", "Photo Frame", "Die-Cut") == "DIY; Die-Cut Attachment"
    assert refine_construction("Photo frame_die-cut attachment artwork", "Photo Frame") == ""
    assert refine_construction('24x18 Stretch Canvas with glue coat', "Canvas") == "Stretched"
    assert refine_construction('24x18 stretch flower artwork', "Canvas") == ""
    assert refine_construction("Set coir door mat and woven underlay", "Door Mat", "Set") == ""


def test_explicit_variant_and_shape_phrases_do_not_read_artwork():
    assert refine_construction("Floater Framed Printed Canvas", "Framed Canvas", "Floating Frame; Framed") == "Floating Frame"
    assert refine_construction("Double-sided-print MDF plaque", "Plaque") == "Reversible"
    assert refine_construction("Plaque_double-sided-print flower art", "Plaque") == ""
    assert refine_construction("Square woven bin", "Storage Bin") == "Square; Woven"
    assert refine_construction("Flat-domd grybrd strge chst", "Storage Chest") == "Flat-Domed"
    assert refine_construction("Double Layer Diecut Abstract Art", "Art") == "Die-Cut; Layered"
    assert refine_construction("Glass shadowbox w canvas backer raised", "Framed Glass Shadowbox") == "Raised"
    assert refine_construction("Glass shadowbox_raised portrait artwork", "Framed Glass Shadowbox") == ""
    assert refine_construction("Anti-fatique PVC household mat", "Mat") == "Anti-Fatigue"
    assert refine_construction("Boxed MDF with paper print", "Print") == "Boxed"
    assert refine_construction("Tapared storage bin", "Storage Bin") == "Tapered"
    assert refine_construction("Die-cut MDF SHPD PHTO FRME", "Photo Frame") == "Die-Cut; Shaped"
    assert refine_construction("Paper rope shaped large bin", "Storage Bin") == "Rope"
    assert refine_construction("Shaped 2-Sided MDF Block", "Block") == "Shaped; Two-Sided"
    assert refine_construction("3-Layer Glass Shadowbox", "Framed Glass Shadowbox") == "Layered"
    assert refine_construction("PYO Ceramic trinket tray", "Trinket Tray") == "DIY"
    assert refine_construction("Stagger canvas", "Canvas") == "Staggered"
    assert refine_construction("Canvas_stagger flower artwork", "Canvas") == ""
    assert refine_construction("MDF Photo Frame_Routed Edge_Violet_4x6", "Photo Frame") == "Routed Edge"
    assert refine_construction("MDF Photo Frame_routed edge graphic artwork", "Photo Frame") == ""


def test_framed_wall_assembly_requires_the_wall_art_or_shadowbox_phrase():
    assert refine_construction("Framed geometric wall art", "Wall Art") == "Framed"
    assert refine_construction('12x15 MDF Framed steel-wire wall art', "Wall Art") == "Framed"
    assert refine_construction("Dual color frame shadowbox", "Framed Shadowbox") == "Framed"
    assert refine_construction("MDF Framed botanical study w pink frame", "Frame") == "Framed"
    assert refine_construction("MDF Frame botanical study", "Frame") == ""
    assert refine_construction("Wall art_framed garden artwork", "Wall Art") == ""
    assert refine_construction('12x15 MDF framed character artwork on wall art', "Wall Art") == ""
    assert refine_construction("Dual color frame artwork shadowbox", "Framed Shadowbox") == ""
    assert refine_construction("MDF Photo Frame_Diecut Lion Attachment", "Photo Frame") == ""
    assert refine_construction("Wall Pegs 13x18 Spider-Man Die-Cut", "Wall Pegs") == ""


def test_same_type_physical_specs_do_not_promote_art_or_quantity():
    assert refine_construction("Rectangle lap desk floral quote with yellow cushion", "Lap Desk") == "Cushioned"
    assert refine_construction("Lap desk_floral quote with yellow cushion", "Lap Desk") == ""
    assert refine_construction("Canvas Floater Framed", "Framed Canvas", "Floating Frame; Framed") == "Floating Frame"
    assert refine_construction("Mld wall colcks", "Clock") == "Molded"
    assert refine_construction("Wall clock_molded flower artwork", "Clock") == ""
    assert refine_construction("Framed MDF printed scalloped paper under glass", "Framed Print") == "Scalloped"
    assert refine_construction("Freeform ceramic block", "Block") == "Freeform"
    assert refine_construction("Mesh pop-up polyester hamper", "Storage Hamper") == "Pop-Up"
    assert refine_construction("MDF box with photo insert", "MDF Box") == "Photo Insert"
    assert refine_construction('8x11 Floating Character in MDF Box', "MDF Box") == "Floating"
    assert refine_construction("Dome chests", "Storage Chest", "Dome") == "Domed"
    assert refine_construction("2 piece set 3D lenticular plaque", "Plaque", "Set") == ""
    assert refine_construction("3-piece die-cut MDF sign", "Sign", "Die-Cut; Set") == "Die-Cut"
    assert refine_construction("5-Pc set cotton rope storage bins", "Storage Bin", "Set") == ""
    assert refine_construction("Four-pack canvas panel", "Canvas", "Panel") == ""
    assert refine_construction("Shaped MDF pencil cup", "Pencil Cup", "Shaped") == ""
    assert refine_construction("Pencil cup_shaped fruit artwork", "Pencil Cup", "Shaped") == "Shaped"


def test_exact_physical_specs_preserve_artwork_and_quantity_boundaries():
    assert refine_construction("Setback frame with raised lasercut icon", "Frame", "Raised; Setback") == "Laser-Cut; Raised; Setback"
    assert refine_construction("Setback frame_lasercut icon artwork", "Frame", "Setback") == "Setback"
    assert refine_construction("Rectangle lap desk with cusion", "Lap Desk") == "Cushioned"
    assert refine_construction("Oval lap writing desk with cushion", "Lap Desk", "Cushioned; Oval") == "Cushioned"
    assert refine_construction("2 tier wall shelf", "Wall Shelf") == "Two-Tier"
    assert refine_construction("Sculpted memo pad holder", "Memo Holder") == "Sculpted"
    assert refine_construction("Memo holder_sculpted flower artwork", "Memo Holder") == ""
    assert refine_construction("Tech lapdesk with USB ports", "Lap Desk") == "USB Ports"
    assert refine_construction("Wall monogram letter with weighted bottom", "Wall Monogram") == "Weighted Bottom"
    assert refine_construction("Wall monogram_weighted artwork", "Wall Monogram") == ""
    assert refine_construction("Block MDF perpetual calendar w dome", "Perpetual Calendar", "Block; Dome") == "Block; Domed"
    assert refine_construction("Die-cut MDF block w moving needle", "Block") == "Die-Cut; Moving Needle"
    assert refine_construction("Faux VHS box storage set", "Storage Box", "Set") == "Faux VHS"
    assert refine_construction("Fltr frm cnvs w hgh glss", "Framed Canvas", "Framed") == "Floating Frame"


def test_exact_type_subassemblies_do_not_become_artwork_construction():
    assert refine_construction("floatr frm cnvs w hgh glss", "Framed Canvas", "Floating Frame; Framed") == "Floating Frame"
    assert refine_construction("Framed floated canvas w mat", "Framed Canvas", "Floating Frame; Framed; Matted") == "Floating Frame; Matted"
    assert refine_construction("Framed glass fringed paper shadowbox", "Framed Glass Shadowbox") == "Framed; Fringed"
    assert refine_construction("Double-sided door sign", "Door Sign") == "Reversible"
    assert refine_construction("Door sign_double-sided character artwork", "Door Sign") == ""
    assert refine_construction("Stretched PU w screen-print", "Print") == "Stretched"
    assert refine_construction("Hexagon geometric canvas art", "Canvas") == "Hexagonal"
    assert refine_construction("Canvas_hexagon flower artwork", "Canvas") == ""
    assert refine_construction("Framed art w deckle foil edge paper", "Framed Art") == "Deckled Edge; Framed"
    assert refine_construction("Lasercut MDF layered frame", "Frame") == "Laser-Cut"
    assert refine_construction("2-piece faux book desktop storage set", "Hard Storage Box", "Faux Book; Set") == "Faux Book"
    assert refine_construction("MDF box with floating character", "MDF Box") == "Floating"
    assert refine_construction("MDF box_floating character artwork", "MDF Box") == ""
    assert refine_construction("MDF photo frame_die cut attachment", "Photo Frame", "Die-Cut") == ""
    assert refine_construction("Die-cut MDF photo frame", "Photo Frame", "Die-Cut") == "Die-Cut"
    assert refine_construction("Framed art with 4-panel portrait", "Framed Art", "Framed; Panel") == "Framed"
    assert refine_construction('13x19 2 piece set lenticular plaque', "Plaque", "Set") == ""
