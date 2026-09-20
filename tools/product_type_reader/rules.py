"""Reviewed product-type rules.

Every rule is a (product, construction, regex) triple in a fixed tuple. Ordering
inside the tuple is meaningful: it is the final, deterministic tiebreak when two
rules match wording of identical length.

Rules never read licensor, property, artwork, colour, size or historical MG
codes. Construction describes how the product is built or shaped; it must never
be used to smuggle in a material that the description does not state.
"""

from __future__ import annotations

import re

RULES_VERSION = "product-type-reader/2026-09-20"

# Tier 0 is a reviewed product rule. Tier 1 is a MATERIAL-ONLY fallback: wording
# that names a material rather than a product, and may therefore only win when no
# tier-0 rule matched at all. This replaces the old "product != Canvas" tiebreak,
# which silently let a bare "canvas" swallow canvas hampers, growth charts and
# folding frame sets.
FALLBACK_TIER = 1

# Ordered most-specific-first. Entries are (product, construction, pattern[, tier]).
_PRODUCT_PATTERNS: tuple[tuple, ...] = (
    # Lookaheads on purpose: the matched wording must stay product wording, never
    # the artwork text that sits between "canvas" and "paint".
    ("Paint-Your-Own Canvas Set", "Canvas Set", r"\b(?:diy|pbn|paint by numbers?|paint your own|colou?r your own)\b(?=.{0,55}\bcanvas\b)|\bcanvas\b(?=.{0,55}\bpaint\b)"),
    ("Growth Chart", "Hanging", r"\bgrowth chart\b"),
    ("Frame Set", "Folding", r"\bfolding\b.{0,30}\bframe set\b|\bframe set\b.{0,30}\bmarkers?\b|\bfolding canvas texture frame\b"),
    ("Framed Canvas", "Floater Frame", r"\b(?:floater|floating|float) frame(?:d)?\b.{0,35}\bcanvas\b|\bcanvas\b.{0,35}\b(?:floater|floating) frame\b"),
    ("Framed Canvas", "Frame", r"\bframed canvas\b|\bcanvas framed\b"),
    ("Canvas Tapestry", "Wood-Bar Hanging", r"\bcanvas tapestry\b.{0,20}\bwood bars?\b|\bwood bars?\b.{0,20}\bcanvas tapestry\b"),
    ("Canvas Tapestry", "Hanging", r"\b(?:printed )?canvas tapestry\b"),
    ("Color-Your-Own Kit", "DIY", r"\bcolou?r your own\b"),
    ("Framed Print", "Deep Frame", r"\bdeep frame(?:d)?\b"),
    ("Door Mat", "Outdoor", r"\boutdoor mat\b"),
    ("Floor Mat", "PVC Foam", r"\bpvc foam (?:play )?mat\b|\bprinted pvc foam mat\b"),
    ("Hard Storage Box", "Greyboard", r"\blift off\b.{0,25}\bgreyboard storage\b|\bgreyboard storage\b"),
    ("Wall Plaque", "MDF", r"\bdie cut mdf\b|\bmdf die cut\b|\bmdf box\b"),
    ("Foam Wall Decor", "Molded Foam", r"\bmolded foam\b"),
    ("Framed Print", "Under Glass", r"\bprint(?:ed)? under glass\b"),
    ("Stationery Organizer", "Multi-Section", r"\bdesktop org\b"),
    ("Canvas", "Stretched", r"\bcanvas(?:es)?\b", FALLBACK_TIER),
    # Broad structural fallbacks: a frame or frame dimension is stated but no
    # specific product noun is. They may only win when no reviewed rule matched.
    ("Framed Print", "Floater Frame", r"\b(?:floater|floating|float) frame(?:d)?\b", FALLBACK_TIER),
    ("Framed Print", "Paper", r"\bembossed paper print\b|\bpaper print\b", FALLBACK_TIER),
    ("Framed Print", "Frame", r"\bframe width\b", FALLBACK_TIER),
    ("Framed Print", "Frame", r"\bframed\b.{0,25}\b(?:print|art|poster|gloss)\b|\b(?:print|art|poster|gloss)\b.{0,25}\bframed\b", FALLBACK_TIER),
    ("Framed Glass Shadowbox", "Glass Shadowbox", r"\b(?:printed )?glass shadowbox\b|\bglass shad(?:ow)?box\b"),
    ("Framed Shadowbox", "Molded", r"\bmolded shadowbox\b|\bmold shadowbox\b"),
    ("Framed Shadowbox", "MDF", r"\bmdf (?:printed )?shadowbox\b|\bshadowbox\b.{0,25}\bmdf\b"),
    ("Framed Shadowbox", "Shadowbox", r"\bshadowbox\b"),
    ("Framed Glass Art", "Printed Glass", r"\bprinted glass\b|\bprint glass\b|\bglass under (?:die cut )?tin\b"),
    ("Framed Glass Art", "Stained Glass", r"\bstained glass art\b|\bframed stained glass\b"),
    ("Framed Glass Art", "Glass", r"\bframed glass\b|\bglass framed art\b"),
    ("Framed Lenticular Art", "3D Lenticular", r"\b3d lenticular\b|\blenticular (?:art|print|image|plaque)\b|\bframed lenticular\b"),
    ("Framed Relief Art", "Foam", r"\bmolded foam(?: wall)? art\b|\bfoam relief\b"),
    ("Framed Relief Art", "3D", r"\b(?:framed )?3d (?:wall )?art\b|\b3d in (?:a )?1 (?:inch )?frame\b|\b3d portrait\b"),
    ("Framed Print", "MDF", r"\bframed\b.{0,30}\bmdf\b|\bmdf framed\b|\bframe mdf\b|\bmdf print in (?:a )?(?:setback|floating) frame\b|\bmdf print(?:ed)?\b.{0,20}\bframed\b"),
    ("Framed Print", "Paper", r"\bframed paper (?:art|print|poster|wall art)\b"),
    ("Framed Print", "Frame", r"\bframed (?:art|print|poster|wall art)\b|\bsetback framed\b|\barch framed wall art\b|\bsquiggle framed wall art\b"),
    ("Framed Print", "Paper", r"\bframed deckle(?:d)? (?:edge )?(?:paper|print)\b|\bdeckle(?:d)? print under glass\b|\bsoft touch print framed\b"),
    ("Framed Print", "Frame", r"\bsetback frame\b"),
    ("Framed Fabric Art", "Fabric", r"\bframed\b.{0,30}\b(?:fabric|linen|burlap|embroidered)\b|\bfabric bubble frame\b"),
    ("Framed Mirror", "Mirror", r"\bframed mirror\b|\bmirror\b.{0,20}\bframe\b"),
    ("Photo Frame", "Collage", r"\b(?:multi|collage) ?(?:photo|picture|phto) frame\b|\bphoto collage frame\b"),
    ("Photo Frame", "Frame", r"\b(?:infant )?(?:photo|picture|phto) frame\b"),
    ("Wall Plaque", "Layered Die-Cut", r"\bdouble layer die cut art\b|\bdouble layer die cut\b|\blayered die cut art\b"),
    ("Wall Plaque", "MDF Floating Box", r"\bmdf floating (?:character |figure )?box\b|\bfloating (?:character |figure )?box\b.{0,20}\bmdf\b"),
    ("Wall Plaque", "Floating Box", r"\bfloating (?:character |figure )?box\b|\bfloating box\b"),
    ("Wall Plaque", "MDF", r"\bmdf (?:wall )?plaque\b|\bprinted die cut mdf wall\b|\blayered mdf laser cut plaque\b|\bmdf tabletop plaque\b"),
    ("Wall Plaque", "MDF", r"\b(?:boxed|box) mdf\b|\b[2-9] layer boxed mdf\b|\bmdf planks?\b|\bprinted mdf wood\b|\bflush mount mdf\b"),
    ("Wall Plaque", "Plank", r"\bplank palette\b"),
    ("Wall Plaque", "Natural", r"\b(?:wood|wooden|natural) (?:wall )?plaque\b"),
    ("Wall Plaque", "Plastic", r"\b(?:acrylic|plastic) (?:shaped )?(?:led )?(?:wall )?plaque\b"),
    ("Wall Plaque", "Relief", r"\b(?:relief|layered|3d molded) (?:wall )?(?:art|plaque)\b"),
    ("Tall Wall Sign", "Leaner", r"\b(?:tall|porch leaner|leaning) (?:mdf )?(?:wall )?sign\b|\bmdf porch leaner\b"),
    ("Door Hanger", "MDF", r"\bmdf door hanger\b"),
    ("Door Hanger", "Hanger", r"\bdoor hanger\b|\breversible door sign\b"),
    ("Wall Sign", "Metal", r"\b(?:tin|metal) sign\b"),
    ("Wall Sign", "Metal", r"\bprinted galvani[sz]ed steel\b|\bprinted aluminum\b|\bprinted aluminium\b"),
    ("Wall Sign", "MDF", r"\bmdf (?:door|wall) sign\b|\bmdf sign\b"),
    ("Wall Sign", "Sign", r"\b(?:door|wall) sign\b|\bhanging sign\b"),
    ("Wall Sign", "Glass", r"\bglass sign\b"),
    ("Wall Shelf", "MDF", r"\b(?:die cut )?mdf shelf\b|\bnested mdf box shelf\b"),
    ("Wall Shelf", "Shelf", r"\bwall shelf\b"),
    ("Wall Hook", "MDF", r"\bmdf (?:wall )?hooks?\b|\bmdf plaque hook\b"),
    ("Wall Hook", "Hook", r"\b(?:functional |full figure )?(?:wall )?hooks?\b|\bguitar hook\b"),
    ("Memo Board", "Dry-Erase", r"\b(?:dry erase|magnetic) (?:memo )?board\b|\bmemo board\b"),
    ("Functional Board", "Dry-Erase and Pin", r"\bdry erase\b.{0,25}\bpin ?board\b|\bpin ?board\b.{0,25}\bdry erase\b"),
    ("Functional Board", "Pinboard", r"\b(?:fabric )?pin ?board\b|\bcork ?board\b"),
    ("Functional Board", "Letterboard", r"\bletter ?board\b"),
    ("Hanging Wall Art", "Tapestry", r"\b(?:woven |fabric |canvas )?(?:hanging )?tapestry\b"),
    ("Hanging Wall Art", "Banner", r"\bhanging banner\b|\bwall banner\b|\bbunting\b|\bpennant\b"),
    ("Hanging Wall Art", "Scroll", r"\bhanging poster\b|\bwall scroll\b|\bhanging scroll\b"),
    ("Hanging Wall Art", "Fabric", r"\b(?:embroidered|fabric|plush|yarn|wool).{0,30}\b(?:hanging )?wall art\b|\bfabric bow wall art\b"),
    ("Hanging Wall Art", "Yarn", r"\byarn art\b"),
    ("Hanging Wall Art", "Button", r"\bbutton art\b"),
    ("Hanging Wall Art", "Sequin", r"\bsequin art\b"),
    ("Wall Decal", "Sticker", r"\bwall (?:stickers?|decals?)\b"),
    ("Foam Wall Decor", "Foam", r"\b(?:froomies )?(?:printed |molded )?foam (?:foam )?wall (?:decor|decoration|art)\b|\beva wall (?:decor|decoration)\b"),
    ("Wall Light", "LED", r"\b(?:neon|infinity|string) led (?:wall )?(?:light|art|mirror)\b|\bled infinity (?:art|mirror)\b"),
    ("Wall Decor", "Dimensional", r"\b(?:paper rope|natural|plastic) dimensional (?:wall )?(?:art|decor)\b"),
    ("Paper Shade", "Paper", r"\bpaper shade\b"),
    ("Tabletop Block", "Domed", r"\bdome(?:d)? block\b"),
    ("Tabletop Block", "Ceramic", r"\b(?:die cut |odd size |holiday )?ceramic (?:tabletop )?block\b"),
    ("Tabletop Block", "Glass", r"\bglass block\b"),
    ("Tabletop Block", "Acrylic", r"\bacrylic block\b"),
    ("Tabletop Block", "MDF", r"\bmdf (?:die cut |printed |shaped |solid |holiday |tabletop |laser cut )*block\b|\b(?:solid |die cut |shaped |holiday |tabletop )?mdf (?:tabletop )?block\b|\bblock mdf\b"),
    ("Tabletop Block", "Wood", r"\bwood rounded block\b|\bwood block\b"),
    ("Tabletop Monogram", "Letter", r"\b(?:wood|mdf|greyboard|fabric) (?:letter|monogram)\b"),
    ("Perpetual Calendar", "Calendar", r"\b(?:perpetual|countdown) calendar\b|\bcalendar block\b"),
    ("Tabletop Box", "Jewelry", r"\bjewelry box\b|\bnecklace storage\b"),
    ("Tabletop Box", "Music", r"\bmusic box\b"),
    ("Tabletop Box", "MDF", r"\bmdf tabletop box\b"),
    ("Tabletop Box", "Painted Art", r"\bbox painted art\b"),
    ("Mug", "Ceramic", r"\bceramic mug\b"),
    ("Mug", "Mug", r"\bmug\b"),
    ("Tabletop Box", "Glass", r"\bglass (?:storage )?box\b"),
    ("Bookend", "Object", r"\bbook ?ends?\b|\bbook rack\b"),
    ("Candle Holder", "Object", r"\bcandle holder\b"),
    ("Snow Globe", "Object", r"\bsnow globe\b"),
    ("Tabletop Planter", "Ceramic", r"\bceramic (?:mini )?planter\b"),
    ("Tabletop Planter", "Planter", r"\b(?:diy )?(?:mini )?planter\b"),
    ("Tabletop LED Art", "Acrylic", r"\btabletop led acrylic art\b|\betched acrylic (?:tabletop )?(?:art|light)\b"),
    ("Tabletop Easel", "Dry-Erase", r"\bdry erase easel\b|\btabletop easel\b"),
    ("Bank", "Tabletop", r"\b(?:mdf |ceramic )?bank\b"),
    ("Wall Clock", "Molded Plastic", r"\b(?:pp|polypropylene) ?molded wall clock\b|\bpp wall clock\b"),
    ("Wall Clock", "Molded", r"\bmolded wall clock\b"),
    ("Wall Clock", "MDF", r"\b(?:die cut |round )?mdf (?:wall )?clock\b"),
    ("Wall Clock", "Plaque", r"\bwall clock plaque\b"),
    ("Wall Clock", "Metal", r"\bmetal wall clock\b"),
    ("Wall Clock", "Clock", r"\bwall clock\b"),
    ("Desktop Clock", "Alarm", r"\b(?:metal )?(?:alarm|desktop) clock\b"),
    ("Storage Hamper", "Mesh", r"\bmesh pop up hamper\b|\bpolymesh hamper\b"),
    ("Storage Hamper", "Felt", r"\bfelt (?:oval |half moon |tapered )?hamper\b"),
    ("Storage Hamper", "Fabric", r"\b(?:fabric |canvas |oxford |nonwoven |faux leather )+(?:greyboard |rectangle |rectangular |storage )*hamper\b"),
    ("Storage Hamper", "Soft", r"\b(?:greyboard |rectangle |rectangular |storage )*hamper\b"),
    ("Storage Toy Chest", "Fabric", r"\b(?:nonwoven |fabric |canvas |oxford )+(?:collapsible |storage )*toy chest\b"),
    ("Storage Toy Chest", "Soft", r"\b(?:collapsible |storage )*toy chest\b|\btoy bin\b"),
    ("Storage Chest", "Greyboard", r"\b(?:flat top |domed |storage )*greyboard (?:flat top |domed |storage )*(?:toy )?chest\b"),
    ("Storage Chest", "Chest", r"\b(?:flat top |domed |storage )+(?:toy )?chest\b"),
    ("Storage Chest", "Plastic", r"\bplastic storage chest\b"),
    ("Storage Bin", "Fabric", r"\b(?:fabric |woven |oxford )+(?:storage |greyboard |tapered |rectangle |square |medium |large )*bin\b"),
    ("Storage Bin", "Soft", r"\b(?:storage |greyboard |tapered |rectangle |square |medium |large )+bin\b|\bstorage bin\b"),
    ("Storage Basket", "Fabric", r"\b(?:plush |woven )+(?:storage |rope |seagrass )*basket\b"),
    ("Storage Basket", "Soft", r"\b(?:storage |rope |seagrass )+basket\b|\bstorage basket\b"),
    ("Storage Tote", "Fabric", r"\b(?:fabric |canvas |woven )+(?:storage )*tote\b"),
    ("Storage Tote", "Soft", r"\bstorage tote\b"),
    ("Storage Cube", "Collapsible", r"\b(?:storage |fabric |nonwoven |collapsible )+cube\b|\bdesktop cube\b"),
    ("Storage Ottoman", "MDF", r"\bmdf storage ottoman\b"),
    ("Storage Ottoman", "Ottoman", r"\bstorage ottoman\b"),
    ("Storage Organizer", "Hanging", r"\b(?:hanging |closet |shoe |file |pocket |storage )+organi[sz]er\b"),
    ("Storage Tower", "Tower", r"\bstorage towers?\b|\bstorage stands?\b|\bdrawer tier storage\b"),
    ("Hard Storage Box", "Faux Book", r"\bfaux book storage\b|\bgreyboard book storage\b"),
    ("Hard Storage Box", "Suitcase", r"\bsuitcase (?:greyboard )?storage\b"),
    ("Hard Storage Box", "Lift-Off", r"\blift off (?:lid )?(?:storage|box)\b|\bbox lift off\b|\bbox lift off (?:greyboard )?storage\b|\blid box\b|\bglitter lid box\b"),
    ("Hard Storage Box", "Function Box", r"\b(?:storage |greyboard |plastic )+box\b|\bfunction box\b|\b7pc box set\b"),
    ("Hard Storage Box", "Flip-Top", r"\b(?:greyboard )?flip top box\b"),
    ("Tray or Dish", "Ceramic", r"\bceramic (?:trinket )?tray\b|\bceramic dish\b"),
    ("Tray or Dish", "Resin", r"\bpolyresin (?:trinket )?tray\b"),
    ("Tray or Dish", "Tray", r"\b(?:trinket )?tray\b"),
    ("Tray or Dish", "Acrylic", r"\bacrylic tray\b"),
    ("Tray or Dish", "Glass", r"\bglass tray\b"),
    ("Tray or Dish", "Wood", r"\bwood tray\b"),
    ("Pencil Case", "Zippered", r"\bpencil case\b|\bpencil pouch\b"),
    ("Pencil Cup", "Organizer", r"\bpencil cup\b|\bresin pencil\b"),
    ("Memo Holder", "Desktop", r"\bmemo holder\b|\bsticky note holder\b|\bmemo pad\b"),
    ("Stationery Organizer", "Multi-Section", r"\b(?:desk |stationery |stationary |mail |desktop )+organi[sz]er\b|\bdesktop org set\b|\bdesk set organizer\b"),
    ("Phone Stand", "Desktop", r"\b(?:desktop |mdf |plastic |pvc molded )?phone stand\b"),
    ("Tablet Stand", "Desktop", r"\b(?:desktop |mdf )?tablet stand\b"),
    ("Headphone Stand", "Desktop", r"\bheadphone stand\b"),
    ("Desk Mat", "Desk Mat", r"\bdesk ?mat\b"),
    ("Lap Desk", "Lapdesk", r"\b(?:plastic |tech |rectangle |writing |mdf )?lap ?desk\b|\blap writing desk\b"),
    ("Monitor Stand", "Desktop", r"\bmonitor stand\b"),
    ("Floor Mat", "Memory Foam", r"\bmemory foam (?:floor |bath |kitchen )?mat\b"),
    ("Door Mat", "Crumb Rubber Outdoor", r"\bcrumb rubber outdoor mat\b"),
    ("Door Mat", "Crumb Rubber Door", r"\bcrumb rubber door mat\b"),
    ("Door Mat", "Doormat", r"\bpoly doormat\b"),
    ("Door Mat", "Coir", r"\b(?:shaped |panama |debossed )?coir (?:door )?mat\b"),
    ("Door Mat", "Velvet", r"\b(?:custom )?shaped velvet mat\b"),
    ("Door Mat", "Door", r"\bdoor ?mat\b|\bdoormat\b"),
    ("Floor Mat", "Floor", r"\bfloor mat\b"),
    ("Kitchen Mat", "Anti-Fatigue", r"\banti fatigue (?:pvc )?kitchen(?: mat)?\b"),
    ("Kitchen Mat", "PVC", r"\bpvc kitchen mat\b|\bkitchen pvc mat\b"),
    ("Kitchen Mat", "Kitchen", r"\bkitchen mat\b"),
    ("Bath Mat", "Bath", r"\bbath ?mat\b"),
    ("Rug", "Floor", r"\brug\b"),
    ("Garden Sign or Flag", "Outdoor", r"\b(?:lawn sign|garden flag)\b"),
    ("Birdhouse or Feeder", "Wood", r"\b(?:wood|wooden|plywood) (?:bird ?house|bird feeder)\b"),
    ("Birdhouse or Feeder", "Outdoor", r"\b(?:bird ?house|bird feeder)\b"),
    ("Stepping Stone", "Concrete", r"\bconcrete stepping stone\b"),
    ("Stepping Stone", "Stepping", r"\bstepping stone\b"),
    ("Garden Tool", "Tool Set", r"\bgarden tool set\b"),
    ("Garden Thermometer", "Metal", r"\biron thermometer\b"),
    ("Garden Thermometer", "Outdoor", r"\bgarden thermometer\b"),
    ("Watering Can", "Metal", r"\b(?:metal|tin|iron|steel|aluminium|aluminum) watering can\b"),
    ("Watering Can", "Can", r"\bwatering can\b"),
    ("Garden Kneeler", "Kneeler", r"\bkneeler\b"),
    ("Garden Decor", "Outdoor", r"\bgarden (?:stake|decor|decoration)\b"),
    ("Keychain", "Plush", r"\bplush keychain\b"),
    ("Embroidery Kit", "DIY", r"\b(?:diy )?embroidery kit\b"),
    ("Book", "Printed Book", r"\b(?:coloring|colouring|activity|sticker|puzzle|math|problem|prompt|word find|sudoku|test prep) books?\b|\bpop up books?\b|\bboard books?\b|\bhard cover stories\b"),
    ("Display Rack", "Retail Fixture", r"\b(?:spinner|pocket|column|tier) racks?\b|\bspinner rack\b"),
)

def _rule(index: int, entry: tuple) -> tuple[int, int, str, str, "re.Pattern[str]"]:
    product, construction, pattern = entry[0], entry[1], entry[2]
    tier = entry[3] if len(entry) > 3 else 0
    return (tier, index, product, construction, re.compile(pattern))


PRODUCT_RULES: tuple[tuple[int, int, str, str, "re.Pattern[str]"], ...] = tuple(
    _rule(index, entry) for index, entry in enumerate(_PRODUCT_PATTERNS)
)

# Wording that describes no physical product on its own.
UNUSABLE_PATTERNS: tuple[str, ...] = (
    r"^(?:pending|assortment|assorted|asst|desc|sample|samples|test|testing|tes)$",
    r"\b(?:testing|created for testing|test item|test style|test creation)\b",
    r"\b(?:fee|fees|refund|clearance fee|handling charge|handing charge|mddp)\b",
    r"\b(?:discount|rework charges?|additional cost|contractual samples?|samples for)\b",
    r"^(?:assort(?:ed|ment)?|asst|assr?ortment)(?: [a-z0-9]+){0,6}$",
    r"^(?:lacey and isf|foil corners|contractual samples?|assorted contractuals?)$",
)

UNUSABLE_RULES: tuple["re.Pattern[str]", ...] = tuple(re.compile(p) for p in UNUSABLE_PATTERNS)

# Treatment (embellishment) checks, ordered; first match wins.
TREATMENT_RULES: tuple[tuple[str, "re.Pattern[str]"], ...] = tuple(
    (name, re.compile(pattern))
    for name, pattern in (
        ("DIY", r"\b(?:diy|pbn|paint by numbers?|paint your own)\b"),
        ("LED", r"\b(?:led|light up|lightup|backlit|neon)\b"),
        ("Foil", r"\b(?:foil|holofoil|holographic|gold leaf)\b"),
        ("Embroidery", r"\b(?:embroidered|embroidery|cross stitch|chenille|applique)\b"),
        ("High Gloss", r"\b(?:high|hi) gloss\b"),
        ("Glitter", r"\b(?:glitter|sequin|rhinestone|diamond dust|crystal gravel)\b"),
        ("Handpaint", r"\bhand ?paint(?:ed)?\b"),
        ("Gel Coat", r"\b(?:gel|gel coat|allover gel|spot gel|varnish)\b"),
        ("Metallic", r"\b(?:metallic|metal plate|metallic pu)\b"),
        ("Staggered", r"\bstaggered\b|\b[2-9] ?(?:piece|pc) (?:multi )?(?:panel )?canvas\b"),
        ("Shaped", r"\b(?:shaped|die cut|arched|round|hexagon|custom shape)\b"),
        ("Attachment", r"\b(?:attachment|raised|layered|fabric bow|grommet|shoelace)\b"),
        ("Debossed or Embossed", r"\b(?:debossed|embossed|raised embossed)\b"),
    )
)

NO_TREATMENT = re.compile(r"\b(?:plain|unembellished|no embellishment)\b")

# Material is recorded ONLY when the description states it. Ordered; first wins.
MATERIAL_RULES: tuple[tuple[str, "re.Pattern[str]"], ...] = tuple(
    (name, re.compile(pattern))
    for name, pattern in (
        ("Crumb Rubber", r"\bcrumb rubber\b"),
        ("Memory Foam", r"\bmemory foam\b"),
        ("MDF", r"\bmdf\b"),
        ("Greyboard", r"\bgreyboard\b"),
        ("Canvas", r"\bcanvas(?:es)?\b"),
        ("Lenticular", r"\blenticular\b"),
        ("Acrylic", r"\bacrylic\b"),
        ("Polyresin", r"\bpolyresin\b"),
        ("Ceramic", r"\bceramic\b"),
        ("Glass", r"\bglass\b"),
        ("Mirror", r"\bmirror\b"),
        ("Metal", r"\b(?:metal|tin|aluminium|aluminum|iron|steel)\b"),
        ("Plastic", r"\b(?:plastic|pvc|polypropylene|pp molded|poly|polyester)\b"),
        ("Fabric", r"\b(?:fabric|nonwoven|non woven|oxford|felt|plush|linen|burlap|velvet)\b"),
        ("Paper", r"\b(?:paper|paperboard|print|poster)\b"),
        ("Wood", r"\b(?:wood|wooden)\b"),
        ("Coir", r"\bcoir\b"),
        ("Foam", r"\bfoam\b"),
        ("Concrete", r"\bconcrete\b"),
        ("Natural Fiber", r"\b(?:rope|seagrass|rattan)\b"),
    )
)

STATUS_ACCEPTED = "accepted"
STATUS_UNREADABLE = "unreadable"
STATUS_PLACEHOLDER = "placeholder"
VALID_STATUSES = (STATUS_ACCEPTED, STATUS_UNREADABLE, STATUS_PLACEHOLDER)
