"""Cuts the Superstar Saga menu art into game/assets/ui/ and builds the bitmap font.

Sources (in the "MISC UI AND MORE" folder of the art drop):
  Speech Boxes      - MLSS alphabet, speech balloons, cursor arrows (MajinPiccolo)
  Save Menu         - green notebook, place-name strip, gold digits, coin (Starpower)
  Equipment Menu    - red / green stat cards, navy bar, HP/BP/POW/DEF icons (Mirax96)
  Emotion Bubbles   - "!" and "..." bubbles (A.J. Nitro)
  Introduction & File Select - title sky and logo (A.J. Nitro)

Outputs transparent PNGs plus two BMFont (.fnt) fonts that Godot imports as
FontFile: mlss_font (plain glyphs, coloured by the theme) and
mlss_font_outline (white glyphs with a dark 1px border, for text drawn
straight over the map or a battle).

Usage: python3 tools/slice_ui.py "<path to Mario&LuigiMMO folder>"
"""
import os
import sys

from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "game", "assets", "ui")
PREFIX = "MISC UI AND MORE/Game Boy Advance - Mario & Luigi_ Superstar Saga - Miscellaneous - "

SKY_BLUE = (140, 198, 255)  # background of the Equipment Menu and Emotion Bubbles sheets
WHITE = (255, 255, 255)

# --- Font ---------------------------------------------------------------------
# Rows on the Speech Boxes sheet. `base` is the first row under the letters.
UPPER = {"chars": "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "rows": (85, 96), "base": 94, "x": (0, 200)}
LOWER = {"chars": "abcdefghijklmnopqrstuvwxyz", "rows": (132, 145), "base": 142, "x": (0, 200)}
SYMBOLS = {"chars": "!?,'.", "base": 190,
           "boxes": [(21, 182, 23, 190), (24, 182, 30, 190), (31, 186, 34, 190), (35, 182, 38, 186), (39, 188, 42, 190)]}

# Glyphs the sheet doesn't have, drawn in the same style: '#' ink, 'o' soft edge.
# Row 0 is the top of a capital letter; rows 8-9 are below the baseline.
EXTRA = {
    "0": [".o##o.", "o#..#o", "#....#", "#....#", "#....#", "#....#", "o#..#o", ".o##o."],
    "1": [".o#.", "o##.", "..#.", "..#.", "..#.", "..#.", "..#.", ".###"],
    "2": [".o##o.", "o#..#o", "....o#", "...o#o", "..o#o.", ".o#o..", "o#o...", "######"],
    "3": [".o##o.", "o#..#o", "....o#", "..##o.", "....o#", "#....#", "o#..#o", ".o##o."],
    "4": ["...o#.", "..o##.", ".o#.#.", "o#..#.", "#...#.", "######", "....#.", "....#."],
    "5": ["######", "#.....", "#o##o.", "#o..#o", ".....#", "#....#", "o#..#o", ".o##o."],
    "6": [".o##o.", "o#..#o", "#.....", "#o##o.", "#o..#o", "#....#", "o#..#o", ".o##o."],
    "7": ["######", "#...o#", "....#o", "...o#.", "...#o.", "..o#..", "..#o..", "..#..."],
    "8": [".o##o.", "o#..#o", "#o..o#", ".o##o.", "o#..#o", "#....#", "o#..#o", ".o##o."],
    "9": [".o##o.", "o#..#o", "#....#", "o#..##", ".o##.#", ".....#", "o#..#o", ".o##o."],
    ":": ["..", "..", "##", "##", "..", "..", "##", "##"],
    ";": ["..", "..", "##", "##", "..", "..", "##", "##", ".#", "#."],
    "-": ["....", "....", "....", "....", "####", "....", "....", "...."],
    "+": [".....", ".....", "..#..", "..#..", "#####", "..#..", "..#..", "....."],
    "=": [".....", ".....", ".....", "#####", ".....", "#####", ".....", "....."],
    "/": ["....#", "...o#", "...#o", "..o#.", ".o#..", "o#o..", "#o...", "#...."],
    "(": [".o#", "o#.", "#o.", "#..", "#..", "#o.", "o#.", ".o#"],
    ")": ["#o.", ".#o", ".o#", "..#", "..#", ".o#", ".#o", "#o."],
    "[": ["###", "#..", "#..", "#..", "#..", "#..", "#..", "###"],
    "]": ["###", "..#", "..#", "..#", "..#", "..#", "..#", "###"],
    "<": ["....", "...#", "..#o", ".#o.", "#o..", ".#o.", "..#o", "...#"],
    ">": ["....", "#...", "o#..", ".o#.", "..o#", ".o#.", "o#..", "#..."],
    "\"": ["#.#", "#.#", "#.#", "...", "...", "...", "...", "..."],
    "*": [".....", "..#..", "#.#.#", ".###.", "#.#.#", "..#..", ".....", "....."],
    "_": ["......", "......", "......", "......", "......", "......", "......", "......", "######"],
    "%": ["##...#", "##..#o", "...o#.", "..o#..", "..#o..", ".#o...", "o#..##", "#...##"],
    "#": ["..#.#..", "..#.#..", "#######", "..#.#..", "..#.#..", "#######", "..#.#..", "..#.#.."],
    "&": [".o##o..", "o#..#o.", "o#..#o.", ".o##o..", "o#o#o.#", "#..o#o#", "o#..o#o", ".o##o.#"],
    "~": [".......", ".......", ".......", ".o#o..#", "#o.o#o.", ".......", ".......", "......."],
}
SPACE_ADVANCE = 4
LINE_HEIGHT = 12
BASE = 9          # baseline, counted from the top of a line
CELL_TOP = BASE - 8  # capital letters start one row below the top of the line
INK = 48          # darkness of the sheet's letters, used to turn soft edges into alpha


def load(root, name, mode="RGBA"):
    return Image.open(os.path.join(root, PREFIX + name + ".png")).convert(mode)


def bands(mask):
    out, start = [], None
    for i, v in enumerate(mask + [False]):
        if v and start is None:
            start = i
        if not v and start is not None:
            out.append((start, i))
            start = None
    return out


def glyph_alpha(c):
    """Sheet pixel -> alpha of a white glyph pixel (dark ink = solid)."""
    if c[3] == 0:
        return 0
    lum = (c[0] + c[1] + c[2]) / 3
    return max(0, min(255, int(round((255 - lum) / (255 - INK) * 255))))


def cut_glyph(sheet, box, base):
    """Returns (white glyph image, top row relative to the capital top)."""
    x0, y0, x1, y1 = box
    g = Image.new("RGBA", (x1 - x0, y1 - y0), (0, 0, 0, 0))
    for y in range(y0, y1):
        for x in range(x0, x1):
            a = glyph_alpha(sheet.getpixel((x, y)))
            if a > 20:
                g.putpixel((x - x0, y - y0), (255, 255, 255, a))
    return g, y0 - (base - 8)


def draw_glyph(rows):
    w = max(len(r) for r in rows)
    g = Image.new("RGBA", (w, len(rows)), (0, 0, 0, 0))
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch == "#":
                g.putpixel((x, y), (255, 255, 255, 255))
            elif ch == "o":
                g.putpixel((x, y), (255, 255, 255, 70))
    return g, 0


def collect_glyphs(speech):
    glyphs = {}  # char -> (image, top, advance)
    for spec in (UPPER, LOWER):
        y0, y1 = spec["rows"]
        dark = lambda x, y: speech.getpixel((x, y))[3] > 0 and sum(speech.getpixel((x, y))[:3]) < 300
        cols = bands([any(dark(x, y) for y in range(y0, y1)) for x in range(*spec["x"])])
        assert len(cols) == len(spec["chars"]), (spec["chars"][:3], len(cols))
        for ch, (a, b) in zip(spec["chars"], cols):
            img, top = cut_glyph(speech, (a, y0, b, y1), spec["base"])
            glyphs[ch] = (img, top, b - a + 1)
    for ch, box in zip(SYMBOLS["chars"], SYMBOLS["boxes"]):
        img, top = cut_glyph(speech, box, SYMBOLS["base"])
        glyphs[ch] = (img, top, box[2] - box[0] + 1)
    for ch, rows in EXTRA.items():
        img, top = draw_glyph(rows)
        glyphs[ch] = (img, top, img.size[0] + 1)
    # Trim empty rows so the atlas stays small; remember where the ink starts.
    out = {}
    for ch, (img, top, adv) in glyphs.items():
        bb = img.getbbox()
        if bb is None:
            continue
        out[ch] = (img.crop((0, bb[1], img.size[0], bb[3])), top + bb[1], adv)
    return out


def outlined(img):
    """White glyph -> white glyph with a dark 1px border (soft edges dropped)."""
    w, h = img.size
    o = Image.new("RGBA", (w + 2, h + 2), (0, 0, 0, 0))
    ink = {(x + 1, y + 1) for y in range(h) for x in range(w) if img.getpixel((x, y))[3] >= 128}
    for (x, y) in ink:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                if (x + dx, y + dy) not in ink:
                    o.putpixel((x + dx, y + dy), (24, 20, 40, 255))
    for p in ink:
        o.putpixel(p, (255, 255, 255, 255))
    return o


def write_font(name, glyphs, outline=False):
    items = []
    for ch, (img, top, adv) in sorted(glyphs.items()):
        if outline:
            items.append((ch, outlined(img), top - 1, -1, adv + 1))
        else:
            items.append((ch, img, top, 0, adv))
    # Shelf-pack into a 256 wide atlas.
    x = y = shelf = 0
    places = []
    for ch, img, top, xoff, adv in items:
        w, h = img.size
        if x + w > 256:
            x, y, shelf = 0, y + shelf + 1, 0
        places.append((ch, img, x, y, top, xoff, adv))
        x += w + 1
        shelf = max(shelf, h)
    height = 1
    while height < y + shelf + 1:
        height *= 2
    atlas = Image.new("RGBA", (256, height), (0, 0, 0, 0))
    lines = [
        'info face="MLSS%s" size=%d bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=0 aa=1 padding=0,0,0,0 spacing=1,1 outline=0'
        % (" Outline" if outline else "", LINE_HEIGHT),
        "common lineHeight=%d base=%d scaleW=256 scaleH=%d pages=1 packed=0 alphaChnl=0 redChnl=4 greenChnl=4 blueChnl=4"
        % (LINE_HEIGHT + (2 if outline else 0), BASE + (1 if outline else 0), height),
        'page id=0 file="%s.png"' % name,
        "chars count=%d" % (len(places) + 1),
        "char id=32 x=0 y=0 width=0 height=0 xoffset=0 yoffset=0 xadvance=%d page=0 chnl=15" % (SPACE_ADVANCE + (1 if outline else 0)),
    ]
    for ch, img, px, py, top, xoff, adv in places:
        atlas.paste(img, (px, py))
        lines.append("char id=%d x=%d y=%d width=%d height=%d xoffset=%d yoffset=%d xadvance=%d page=0 chnl=15"
                     % (ord(ch), px, py, img.size[0], img.size[1], xoff, CELL_TOP + top + (1 if outline else 0), adv))
    atlas.save(os.path.join(OUT, name + ".png"))
    with open(os.path.join(OUT, name + ".fnt"), "w") as f:
        f.write("\n".join(lines) + "\n")
    print(name, len(places) + 1, "glyphs")


# --- Pictures -----------------------------------------------------------------

def clear_color(img, colors):
    img = img.copy()
    px = img.load()
    for y in range(img.size[1]):
        for x in range(img.size[0]):
            if px[x, y][:3] in colors:
                px[x, y] = (0, 0, 0, 0)
    return img


def flood_clear(img, colors):
    """Clears background colours connected to the edge of the picture."""
    img = img.copy()
    px = img.load()
    w, h = img.size
    todo = [(x, y) for x in range(w) for y in (0, h - 1)] + [(x, y) for y in range(h) for x in (0, w - 1)]
    while todo:
        x, y = todo.pop()
        if 0 <= x < w and 0 <= y < h and px[x, y][3] > 0 and px[x, y][:3] in colors:
            px[x, y] = (0, 0, 0, 0)
            todo += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    return img


def largest_part(img):
    """Keeps only the biggest connected blob (drops stray marks like a TM)."""
    px = img.load()
    w, h = img.size
    seen, best = set(), set()
    for y in range(h):
        for x in range(w):
            if (x, y) in seen or px[x, y][3] == 0:
                continue
            part, todo = set(), [(x, y)]
            seen.add((x, y))
            while todo:
                a, b = todo.pop()
                part.add((a, b))
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        c = (a + dx, b + dy)
                        if 0 <= c[0] < w and 0 <= c[1] < h and c not in seen and px[c][3] > 0:
                            seen.add(c)
                            todo.append(c)
            if len(part) > len(best):
                best = part
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    for p in best:
        out.putpixel(p, px[p])
    return out.crop(out.getbbox())


def fill(img, box, color):
    x0, y0, x1, y1 = box
    for y in range(y0, y1):
        for x in range(x0, x1):
            img.putpixel((x, y), color + (255,))


def save(img, name):
    img.save(os.path.join(OUT, name + ".png"))
    print(name, img.size)


def build_pictures(root):
    speech = load(root, "Speech Boxes")
    save(speech.crop((356, 121, 516, 145)), "balloon")          # 9-slice, 6px corners
    save(speech.crop((232, 82, 252, 112)), "balloon_tail")      # row 0 lines up with the balloon's blue edge
    save(speech.crop((43, 182, 50, 190)), "next_arrow")         # blue "more text" triangle
    save(speech.crop((52, 180, 67, 191)), "cursor")             # yellow menu pointer

    notes = load(root, "Save Menu")
    book = notes.crop((8, 1, 248, 161))
    green = (168, 200, 176)
    fill(book, (34 - 8, 35 - 1, 126 - 8, 119 - 1), green)       # left page: drop the emblem
    fill(book, (130 - 8, 35 - 1, 222 - 8, 119 - 1), green)      # right page: drop the portrait frames
    # A sheet of paper overlaps the top right corner and the bottom edge in the
    # rip: mirror the clean top left corner over it and repeat a clean column.
    for x in range(192, 240):
        for y in range(0, 23):
            book.putpixel((x, y), book.getpixel((239 - x, y)))
    for x in range(30, 232):
        for y in range(151, 160):
            book.putpixel((x, y), book.getpixel((32, y)))
    strip = flood_clear(notes.crop((24, 119, 232, 147)), {green, (152, 184, 160), (192, 216, 200)})
    bbox = strip.getbbox()
    strip = strip.crop(bbox)
    # Wipe the little "FILE" labels off the ruled lines by repeating the middle column.
    w, h = strip.size
    for x in range(12, w - 12):
        for y in range(1, h - 1):
            strip.putpixel((x, y), strip.getpixel((w // 2, y)))
    book.alpha_composite(strip, (24 - 8 + bbox[0], 119 - 1 + bbox[1]))
    save(book, "notebook")
    save(strip, "place_strip")
    digits = Image.new("RGBA", (80, 13), (0, 0, 0, 0))
    for i, (a, b) in enumerate([(616, 624), (626, 633), (635, 643), (645, 653), (655, 663), (666, 674),
                                (677, 685), (687, 695), (697, 705), (707, 715)]):
        d = flood_clear(notes.crop((a, 104, b, 117)), {WHITE})
        digits.paste(d, (i * 8 + (8 - (b - a)) // 2, 0))
    save(digits, "gold_digits")                                  # 10 cells of 8x13, 0-9
    save(flood_clear(notes.crop((617, 95, 629, 100)), {WHITE}), "lv")
    save(flood_clear(notes.crop((225, 549, 236, 565)), {WHITE}).crop((1, 1, 10, 15)), "coin")

    equip = load(root, "Equipment Menu")
    for name, dy in (("card_red", 0), ("card_green", 155)):
        card = equip.crop((204, 214 + dy, 442, 262 + dy))
        header = card.getpixel((10, 6))[:3]
        for y in range(2, 9):                                    # erase the "MARIO" / "LUIGI" name
            for x in range(20, 70):
                if card.getpixel((x, y))[:3] == (248, 248, 248):
                    card.putpixel((x, y), header + (255,))
        paper = (232, 232, 224)
        fill(card, (10, 12, 225, 40), paper)                     # erase the stat slots
        fill(card, (18, 40, 225, 45), paper)
        save(clear_color(card, {SKY_BLUE}), name)
    save(clear_color(equip.crop((205, 263, 441, 284)), {SKY_BLUE}), "navy_bar")
    for name, box in (("icon_hp", (125, 98, 136, 113)), ("icon_bp", (146, 98, 157, 113)),
                      ("icon_def", (121, 115, 137, 129)), ("icon_pow", (142, 114, 159, 129))):
        save(clear_color(equip.crop(box), {SKY_BLUE}), name)
    # Just the heart and the bean (no "HP" / "BP" captions) for the HUD.
    for name, box in (("icon_heart", (125, 98, 136, 106)), ("icon_bean", (146, 98, 157, 106))):
        icon = clear_color(equip.crop(box), {SKY_BLUE})
        save(icon.crop(icon.getbbox()), name)

    emotion = load(root, "Emotion Bubbles")
    save(clear_color(emotion.crop((150, 38, 174, 60)), {SKY_BLUE}), "emote_exclaim")
    save(clear_color(emotion.crop((64, 7, 88, 29)), {SKY_BLUE}), "emote_dots")

    intro = load(root, "Introduction & File Select")
    sky = intro.crop((125, 531, 365, 691))                       # one GBA screen of sky and clouds
    wide = Image.new("RGBA", (384, 216))
    top = sky.getpixel((0, 0))
    fill(wide, (0, 0, 384, 56), top[:3])
    wide.paste(sky, (0, 56))
    wide.paste(sky.transpose(Image.FLIP_LEFT_RIGHT), (240, 56))  # mirrored so the seam matches
    save(wide.convert("RGB"), "title_sky")
    save(largest_part(flood_clear(intro.crop((144, 380, 362, 424)), {WHITE})), "logo")


if __name__ == "__main__":
    root = sys.argv[1]
    os.makedirs(OUT, exist_ok=True)
    glyphs = collect_glyphs(load(root, "Speech Boxes"))
    write_font("mlss_font", glyphs)
    write_font("mlss_font_outline", glyphs, outline=True)
    build_pictures(root)
