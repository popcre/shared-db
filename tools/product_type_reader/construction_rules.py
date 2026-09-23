"""Source-stated construction modifiers for the product-type reader.

The reader supplies its independently chosen product type.  These rules never
choose or change that type, and they do not infer a construction from it.
Artwork and licensing clauses commonly follow an underscore, so ordinary
modifiers are read only from the product title before that boundary.  The one
exception is an explicit, complete ``floating framed`` phrase, which may be
in an underscore-separated physical specification.
"""

from __future__ import annotations

import re
import unicodedata


_DIMENSION = re.compile(
    r'(?<![A-Za-z0-9])\d+(?:\.\d+)?\s*(?:in(?:ches?)?|["”″])?\s*[x×]\s*'
    r'\d+(?:\.\d+)?(?:\s*(?:in(?:ches?)?|["”″]))?'
    r'(?:\s*[x×]\s*\d+(?:\.\d+)?\s*(?:mm|cm|in(?:ches?)?|["”″])?(?:\s*[dDhH]\b)?)?', re.I)


def _words(value: object) -> str:
    text = unicodedata.normalize("NFKD", str(value or "")).encode("ascii", "ignore").decode().lower()
    text = re.sub(r"\bdie[- ]?cut\b", "die cut", text)
    text = re.sub(r"\blift[- ]off\b", "lift off", text)
    return re.sub(r"\s+", " ", text).strip()


def _literal_woven(title: str) -> bool:
    """A woven construction is not a nonwoven or woven-look appearance."""
    if not re.search(r"\bwoven\b", title):
        return False
    # The separator may be a hyphen, slash, space, or a Unicode dash erased
    # during ASCII folding.  If both claims occur, leave construction blank.
    if re.search(r"\b(?:non|not|un|faux|fake|imitation)[\s\-/]*woven\b", title):
        return False
    if re.search(r"\bwoven[\s\-/]+(?:look|effect|print|pattern|texture)\b", title):
        return False
    return True


def _shadowbox_frame(clause: str, *, before_size: bool = False) -> bool:
    """Accept a frame named as part of the physical shadowbox clause."""
    shadowbox = r"shadow\s?box"
    if re.search(r"\b" + shadowbox + r" frame\b", clause):
        return True
    if re.search(r"\b" + shadowbox +
                 r" (?:with|w/?) (?:(?!artwork\b)\w+ ){0,2}frame\b", clause):
        return True
    if re.search(r"\b" + shadowbox + r"\b(?:(?!\bartwork\b).){0,70}\bin oval frame\b", clause):
        return True
    if before_size and not re.search(r"\bartwork\b", clause):
        frame = re.search(r"\b" + shadowbox + r"\b.{0,100}?\bframe\b", clause)
        if frame and len(re.findall(r"\b\w+\b", clause[frame.end():])) <= 3:
            return True
    return False


def refine_construction(description: object, product_type: str, current: str = "") -> str:
    """Add only explicit, family-bound physical construction evidence.

    ``description`` is source wording, not a reader prediction.  The return
    value uses the reader's canonical sorted, semicolon-separated convention.
    Existing values are preserved; the caller must separately decide whether
    those existing values are supported.
    """
    parts = set(filter(None, (part.strip() for part in current.split(";"))))
    if not isinstance(description, str) or not product_type:
        return "; ".join(sorted(parts))

    title_source = description.split("_", 1)[0]
    dimension = _DIMENSION.search(title_source)
    after_size = _words(title_source[dimension.end():]) if dimension else ""
    # Dimensions divide the product phrase from frequently artistic wording.
    # A physical adjective after a size is not enough to modify the product.
    if dimension:
        title_source = title_source[:dimension.start()]
    title = _words(title_source)
    # A whole underscore clause may independently name this one assembly.
    # Searching the complete description would also read artwork clauses.
    clauses = [_words(clause) for clause in description.split("_")[1:]]

    def stated(pattern: str) -> bool:
        return re.search(pattern, title) is not None

    # A quantity set or a noun already carried by the product type is not a
    # physical construction.  These narrow cases correct upstream extras.
    if product_type == "Paint-Your-Own Canvas Set" and stated(r"\bcanvas panel\b"):
        parts.discard("Panel")
    if product_type == "Hard Storage Box" and stated(r"\bfaux book storage set\b"):
        parts.discard("Set")
    if product_type == "Box Shelf" and re.search(r"\bnested mdf box shelf set\b", title + " " + after_size):
        parts.discard("Set")
    if product_type == "Storage Cube":
        parts.discard("Set")
    if product_type in {"Porch Leaner", "Leaner Sign"}:
        parts.discard("Leaner")
    if product_type == "Framed Canvas" and stated(r"\b(?:floater framed|matted framed floated) canvas\b"):
        parts.discard("Framed")

    if stated(r"\bframed\b") and product_type in {
        "Framed Art", "Framed Fabric Art", "Framed Glass Art"
    }:
        parts.add("Framed")
    if product_type in {"Framed Shadowbox", "Framed Glass Shadowbox"} \
            and stated(r"\bdie cut paper\b.{0,35}\bin shadowbox frame\b"):
        parts.add("Framed")
    if product_type in {"Framed Shadowbox", "Framed Glass Shadowbox"} \
            and (_shadowbox_frame(title, before_size=True) or _shadowbox_frame(after_size)):
        parts.add("Framed")
    if product_type == "Framed Shadowbox" and re.search(r"\bframe width\b", after_size):
        parts.add("Framed")
    if stated(r"\bdeep frame\b") and product_type == "Framed Art":
        parts.add("Deep Frame")
    if stated(r"\bdeep frame\b") and product_type == "Framed Print":
        parts.add("Deep Frame")
    if stated(r"\b(?:floating|floater|float) framed\b") or any(
            re.fullmatch(r"(?:floating|floater|float) framed", clause) for clause in clauses):
        parts.add("Floating Frame")
    if product_type != "Tablet Stand" and stated(r"\bdie cut\b") \
            and not stated(r"\bdie cut (?:icon|attachment)\b"):
        parts.add("Die-Cut")
    if stated(r"\brevers(?:e|ible)\b") and product_type in {
        "Tall Sign", "Door Hanger", "Door Sign"
    }:
        parts.add("Reversible")
    if _literal_woven(title) and product_type in {
        "File Organizer", "Tapestry", "Storage Bin", "Wall Art",
        "Decorative Object", "Hanging Organizer"
    }:
        parts.add("Woven")
    if stated(r"\bplush\b") and product_type in {
        "Plush Cube Art", "Storage Basket", "Wall Art"
    }:
        parts.add("Plush")
    if stated(r"\bfigural\b") and product_type in {"Pencil Cup", "Planter"}:
        parts.add("Figural")
    if stated(r"\bstraight\b") and product_type == "Storage Cube":
        parts.add("Straight")
    if stated(r"\bchain\b") and product_type in {"Glass Art", "Framed Glass Art"}:
        parts.add("Chain")
    if product_type == "Clock" and stated(r"\bpendulum\b"):
        parts.add("Pendulum")
    if product_type == "Framed Art" and stated(r"\bdeckled? edge\b"):
        parts.add("Deckled Edge")
    if product_type == "Framed Print" and stated(r"\bframed\s+deckled?\s+print\b"):
        parts.add("Deckled Edge")
    if product_type == "Plaque" and stated(r"\blayered\s+mdf\b"):
        parts.add("Layered")
    if product_type == "Plaque" and stated(r"\b(?:2|two)[- ]layer\s+mdf\b"):
        parts.discard("Double-Layer")
        parts.add("Layered")
    if product_type == "Plaque" and stated(r"\bplaque\s+(?:with|w/)\s*\d*\s*hooks?\b"):
        parts.add("With Hooks")
    if product_type == "MDF Box" and stated(r"\bmdf box\b.{0,20}\b(?:slits|slots)\b"):
        parts.add("Slotted")
    if product_type == "Framed Art" and stated(r"\b(?:white|black) mat\b"):
        parts.add("Matted")
    if product_type in {"Framed Art", "Framed Canvas"} and stated(
            r"\b(?:art|canvas)\s+(?:with|w/?)\s*(?:(?:glass|handpaint|glitter|fillet|red foil)\s*(?:and|&|,)\s*)*mat\b"):
        parts.add("Matted")
    if product_type == "Block" and stated(r"\b(?:wood|mdf) block rounded edge\b"):
        parts.add("Rounded")
    if product_type == "Storage Chest" and stated(
            r"\b(?:domed\s+(?:grey[- ]?board\s+)?storage chest|dmd\s+(?:grybrd|grey[- ]?board)\s+strg chst)\b") \
            and not stated(r"\bflat[- ]domed\b"):
        parts.add("Domed")
    if product_type == "Tabletop Block" and stated(r"\bdome block tabletop\b"):
        parts.discard("Dome")
        parts.add("Domed")
    if product_type == "Lap Desk" and stated(r"\blap\s+(?:(?:writing|dry erase)\s+)?desk\b.{0,25}\b(?:with|w/?)\s+cushion\b"):
        parts.add("Cushioned")
    if product_type == "Foam Wall Decor" and stated(r"\bhand cut foam wall decor\b"):
        parts.add("Hand-Cut")
    if product_type == "MDF Box" and stated(r"\b(?:floating mdf box|floating character in mdf box)\b"):
        parts.add("Floating")
    if product_type == "Storage Hamper" and stated(r"\bround poly[- ]cotton greyboard laundry\b"):
        parts.add("Round")
    if product_type == "Block" and stated(r"\bwood rounded block\b"):
        parts.add("Rounded")
    if product_type == "Hard Storage Box" and stated(r"\bflip[- ]top box\b"):
        parts.add("Flip-Top")
    if product_type == "Door Hanger" and stated(r"\blenticular reversible door hanger\b"):
        parts.add("Lenticular")
    if product_type == "Framed Art" and stated(r"\bwrapped linen in floating frame\b"):
        parts.add("Wrapped")
        parts.add("Floating Frame")
    if product_type == "Magazine Holder" and stated(r"\bmagazine holder with drawer\b"):
        parts.add("Drawer")
    if product_type == "Storage Chest" and stated(r"\bflat[- ]domed\b.{0,30}\b(?:storage chest|chest)\b"):
        parts.add("Flat-Domed")
    if product_type == "Photo Frame" and stated(r"\bdie cut mdf phto frme hrt shpe\b"):
        parts.add("Shaped")
    if product_type == "Clock" and stated(r"\b(?:with|w/?) step movement\b"):
        parts.add("Step Movement")
    if product_type == "Shelf" and stated(r"\bfolding\b"):
        parts.add("Folding")
    if product_type == "Storage Ottoman" and stated(r"\b(?:non[- ]?|not )collapsible\b"):
        parts.discard("Collapsible")
        parts.add("Non-Collapsible")
    if product_type in {"Framed Glass Shadowbox", "Framed Fabric Art"} and stated(r"\bfrayed\b"):
        parts.add("Frayed")
    if product_type == "Writing Desk" and stated(r"\b(?:with|w) legs\b"):
        parts.add("With Legs")
    diy_noun = {"Planter": "planter", "Trinket Tray": "trinket tray", "Stepping Stone": "stepping stone"}.get(product_type)
    if diy_noun and stated(r"\bdiy\b(?:\s+\w+){0,5}\s+" + diy_noun + r"\b"):
        parts.add("DIY")
    if product_type in {"Wall Clock", "Clock", "Photo Frame", "Framed Shadowbox", "Art"} \
            and stated(r"\bmolded\b"):
        parts.add("Molded")
    molded_noun = {
        "Foam Art": r"foam art",
        "Wall Art": r"(?:felt )?wall art",
        "Wall Figure": r"wall figures?",
        "Phone Stand": r"phone stand",
        "Canvas": r"canvas",
        "Frame": r"(?:mdf )?frame",
        "Framed Art": r"frame art",
        "Framed Glass Shadowbox": r"(?:glass )?shadowbox",
        "Mask": r"(?:polyresin )?mask",
        "Wall Mask": r"(?:3d )?wall mask",
    }.get(product_type)
    if molded_noun and stated(r"\bmolded\s+" + molded_noun + r"\b"):
        parts.add("Molded")
    if product_type in {"Clock", "Wall Clock"} and stated(r"\bmldd wll clck\b"):
        parts.add("Molded")
    if product_type == "Framed Shadowbox" and stated(r"\b(?:mldd|mold)\s+(?:shdwbx|shadowbox)\b"):
        parts.add("Molded")
    if product_type in {"Framed Canvas", "Frame", "Framed Print"} \
            and stated(r"\b(?:float|floating|floater) framed?\b"):
        parts.add("Floating Frame")
    if product_type == "Framed Canvas" and stated(r"\bframed floated canvas\b"):
        parts.add("Floating Frame")
    if product_type == "Frame" and stated(r"\b(?:float|floate) frames?\b"):
        parts.add("Floating Frame")
    if product_type == "Framed Canvas" and stated(r"\bfloatr frm cnvs\b"):
        parts.add("Floating Frame")
    if product_type == "Framed Print" and stated(r"\bfloat frm embossd ppr prnt\b"):
        parts.add("Floating Frame")
    if product_type in {"Canvas", "Framed Canvas"} and stated(
            r"\b(?:canvas floating frame|floating\b.{0,20}\bframe canvas)\b"):
        parts.add("Floating Frame")
    if product_type == "Frame" and stated(r"\bsetback frame\b"):
        parts.add("Framed")
    if product_type in {"Photo Frame", "Block"} and stated(
            r"\bdie cut\b.{0,35}\b(?:egg|heart)[- ]+shap(?:e|ed)\b"):
        parts.add("Shaped")
    if product_type == "Storage Bin" and stated(r"\b(?:cotton|paper) rope storage bin\b"):
        parts.add("Rope")
    if product_type == "Storage Basket" and stated(r"\bcotton rope basket\b"):
        parts.add("Rope")
    if stated(r"\blift off\b") and product_type in {"Hard Storage Box", "Storage Box"}:
        parts.add("Lift-Off")
    if stated(r"\bsetback\b") and product_type == "Framed Art":
        parts.add("Setback")
    if stated(r"\bfaux book\b") and product_type in {"Desktop Organizer", "Storage Box"}:
        parts.add("Faux Book")
    if stated(r"\bhooks?\b") and product_type == "MDF Box":
        parts.add("Hooks")
    # Only a complete physical product phrase can re-open the evidence after
    # a dimension.  A bare adjective there may describe the depicted artwork.
    if product_type == "Framed Art" and re.search(r"\bframed art\b", after_size):
        parts.add("Framed")
    if product_type == "Wall Art" and re.search(r"\bplush wall art\b", after_size):
        parts.add("Plush")
    if product_type == "Sign" and re.search(r"\bmdf die cut\b", after_size):
        parts.add("Die-Cut")
    if product_type == "Art" and re.search(r"\bdie cut\b.{0,25}\bmdf\b.{0,15}\bart\b", after_size):
        parts.add("Die-Cut")
    if product_type in {"Framed Canvas", "Canvas"} and re.search(
            r"\b(?:canvas in floating frame|floating frame canvas|flt frame\b.{0,25}\bcnv)\b", after_size):
        parts.add("Floating Frame")
    if product_type == "Framed Shadowbox" and re.search(r"\bmolded shadowbox\b", after_size):
        parts.add("Molded")
    if product_type == "Box Shelf" and re.search(r"\bnested mdf box shelf\b", after_size):
        parts.add("Nested")
    if product_type == "File Organizer" and re.search(r"\b(?:\d+[- ]tier\s+)?mesh file organizer\b", after_size):
        parts.add("Mesh")
    if product_type == "File Organizer" and re.search(r"\bvertical file organizer\b", after_size):
        parts.add("Vertical")
    if product_type == "Storage Chest" and re.search(r"\bflat[- ]domed\b.{0,30}\b(?:storage chest|chest)\b", after_size):
        parts.add("Flat-Domed")
    if product_type == "Plaque" and re.search(r"\bmdf plaque\s+(?:with|w/)\s*\d*\s*hooks?\b", after_size):
        parts.add("With Hooks")
    if product_type == "Canvas" and stated(r"\bblank artist canvas\b") and any(
            not re.search(r"\b(?:artwork|graphic|pattern|print)\b", clause)
            and re.search(r"\b(?:canvas frame|frame black canvas)\b", clause)
            for clause in clauses):
        parts.add("Frame")
    # Both reviewed word orders identify the calendar's physical block form.
    # A bundled pencil cup is a different, compound product and needs its own
    # classification instead of inheriting the plain-calendar construction.
    if product_type == "Perpetual Calendar" \
            and stated(r"\b(?:block mdf|mdf block) perpetual calendar\b") \
            and not stated(r"\bpencil\s+cup\b"):
        parts.add("Block")
    return "; ".join(sorted(parts))
