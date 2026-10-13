"""Cuts the Superstar Saga battle art into game/assets/battle/.

Sources (in the Mario&LuigiMMO art drop):
  MISC UI AND MORE/... Battle Backgrounds        - battle backgrounds (Ryan914)
  Maps/Custom ... Backgrounds - Wart Throne       - Wart's throne room (Frario; veggie machine by Starpower)
  Maps/Custom ... Backgrounds - Sand Bird         - Sand Bird stage (Joshr_691)
  MISC UI AND MORE/... Action Icons               - action command icons (SpaceSandwich)
  MISC UI AND MORE/Custom ... Blocks (M&L_ Superstar Saga-Battle Style) - blocks (Ridge Troopa)
  MISC UI AND MORE/Custom ... Mushrooms           - the Mushroom (Spencer EX, Ridge Troopa)
  MISC UI AND MORE/... Battle Ratings & Status Effects - word art and status icons
                                                    (Mario Maker 69420, English by Johnnie Electronic)
  MISC UI AND MORE/... Battle Start               - battle start star swipe (Sblaka)

Outputs (transparent PNGs unless noted):
  backgrounds/<id>.png    one GBA screen (240x160, opaque) per background; the
                          battle scales it to cover the 384x216 viewport.
  block_yellow.png        command block for you (the "?" wiped off, widened to
  block_blue.png          fit an icon) and for partners.
  icon_<action>.png       pictures for the blocks: jump, hammer, hand, burst,
                          mushroom, run, x (the "can't use" mark).
  prompt_<icon>_<red|green>.png  A-button badges shown during timed presses
                          (red over you, green over partners).
  rating_<word>.png       ok, good, great, miss, lucky, critical, advance.
  status_burn.png, status_stun.png
  battle_start.png        the star swipe: 23 frames on a 6x4 grid of 240x160 cells.

Usage: python3 tools/slice_battle.py "<path to Mario&LuigiMMO folder>"
"""
import os
import sys

from PIL import Image

from slice_ui import flood_clear

OUT = os.path.join(os.path.dirname(__file__), "..", "game", "assets", "battle")
MISC = "MISC UI AND MORE/Game Boy Advance - Mario & Luigi_ Superstar Saga - Miscellaneous - "
CUSTOM = "MISC UI AND MORE/Custom _ Edited - Mario Customs - "
MAPS = "Maps/Custom _ Edited - Mario Customs - Backgrounds - "

# --- Backgrounds -----------------------------------------------------------------
# id -> (sheet, top-left of the 240x160 screen). Names are the area each one
# fits; battle.gd picks one per map from Game.MAPS[map]["battle_bg"].
SHEET = MISC + "Battle Backgrounds.png"
BACKGROUNDS = {
    "castle_town": (SHEET, (2, 815)),          # Beanbean Castle gate and bridge
    "outskirts": (SHEET, (246, 165)),          # grass, trees and bean plants
    "bowser_castle": (SHEET, (489, 977)),      # stone walls, pink tiles
    "bowser_castle_lava": (SHEET, (731, 977)),
    "bean_fields": (SHEET, (731, 815)),
    "chucklehuck_woods": (SHEET, (246, 327)),
    "chateau_cellar": (SHEET, (2, 327)),
    "hoohoo_mountain": (SHEET, (731, 2)),
    "stardust_fields": (SHEET, (488, 2)),
    "koopa_cruiser": (SHEET, (245, 2)),
    "peach_castle": (SHEET, (2, 2)),
    "oho_oasis": (SHEET, (245, 653)),
    "guffawha_ruins": (SHEET, (2, 653)),
    "gwarhar_lagoon": (SHEET, (489, 653)),
    "jokes_end": (SHEET, (245, 977)),
    "woohoo_hooniversity": (SHEET, (489, 490)),
    "little_fungitown": (SHEET, (731, 327)),
    "wart_throne": (MAPS + "Wart Throne (Mario & Luigi_ Superstar Saga-Style).png", (10, 172)),
    "sand_bird": (MAPS + "Sand Bird (Mario & Luigi_ Superstar Saga-Style).png", (5, 409)),
}

# --- Command blocks and icons ---------------------------------------------------
BLOCKS = CUSTOM + "Objects - Blocks (M&L_ Superstar Saga-Battle Style).png"
BLOCK_SIZE = (30, 32)
ICONS = MISC + "Action Icons.png"
ICON_BOXES = {
    "jump": (17, 262, 30, 282), "hammer": (46, 260, 68, 282), "hand": (81, 260, 100, 281),
    "burst": (43, 298, 69, 324), "x": (114, 306, 126, 318),
}
PROMPT_BOXES = {
    "jump_red": (8, 12, 36, 40), "hammer_red": (72, 12, 100, 40), "hand_red": (104, 12, 132, 40),
    "burst_red": (296, 10, 325, 40),
    "jump_green": (8, 108, 36, 136), "hammer_green": (72, 108, 100, 136), "hand_green": (104, 108, 132, 136),
    "burst_green": (296, 106, 325, 136),
}
MUSHROOMS = CUSTOM + "Power-Ups & Items - Mushrooms (Mario & Luigi_ Superstar Saga-Style).png"

# --- Ratings, status, battle start ---------------------------------------------------
RATINGS = MISC + "Battle Ratings & Status Effects.png"
RATING_BOXES = {
    "ok": (2, 3, 34, 35), "good": (42, 3, 106, 35), "great": (114, 3, 178, 35), "miss": (186, 3, 250, 35),
    "lucky": (258, 3, 322, 35), "critical": (330, 3, 394, 35), "advance": (402, 3, 466, 35),
}
START = MISC + "Battle Start.gif"
START_BG = (255, 248, 255)
STAR_COLORS = {(240, 240, 0), (128, 128, 0)}
# Frames of the star swipe in play order (sheet rows, left to right).
START_FRAMES = [
    (30, 83, 45, 97), (57, 69, 101, 114), (116, 62, 175, 123), (188, 54, 259, 129),
    (29, 170, 115, 259), (127, 157, 236, 270), (252, 148, 393, 273), (413, 144, 588, 268), (614, 150, 810, 248),
    (16, 325, 236, 390), (297, 297, 529, 423), (563, 286, 803, 446),
    (12, 453, 252, 613), (292, 451, 532, 611), (574, 458, 814, 618),
    (9, 637, 249, 797), (286, 637, 526, 797), (565, 636, 805, 796),
    (13, 814, 253, 974), (284, 811, 524, 971), (575, 807, 815, 967),
    (7, 986, 247, 1146), (279, 986, 519, 1146),
]
SCREEN = (240, 160)


def load(root, name):
    return Image.open(os.path.join(root, name)).convert("RGBA")


def save(img, name):
    path = os.path.join(OUT, name + ".png")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print(name, img.size)


def cut(sheet, box):
    """Crops a sprite and clears the sheet background around it."""
    piece = sheet.crop(box)
    piece = flood_clear(piece, {piece.getpixel((0, 0))[:3]})
    return piece.crop(piece.getbbox())


def stretch(img, size, col, row):
    """Grows a block to `size` by repeating one plain column and one plain row."""
    w, h = img.size
    xs = list(range(col)) + [col] * (size[0] - w + 1) + list(range(col + 1, w))
    ys = list(range(row)) + [row] * (size[1] - h + 1) + list(range(row + 1, h))
    out = Image.new("RGBA", size)
    for y, sy in enumerate(ys):
        for x, sx in enumerate(xs):
            out.putpixel((x, y), img.getpixel((sx, sy)))
    return out


def build_backgrounds(root):
    for name, (sheet, (x, y)) in BACKGROUNDS.items():
        img = Image.open(os.path.join(root, sheet)).convert("RGB")
        save(img.crop((x, y, x + SCREEN[0], y + SCREEN[1])), "backgrounds/" + name)


def build_blocks(root):
    sheet = load(root, BLOCKS)
    sky = sheet.getpixel((0, 0))[:3]
    # Yellow "?" block with the "?" painted over in the face colour.
    yellow = sheet.crop((68, 4, 88, 30))
    face = yellow.getpixel((2, 15))
    for y in range(11, 24):
        for x in range(3, 17):
            yellow.putpixel((x, y), face)
    blue = sheet.crop((112, 62, 132, 88))                       # plain blue block
    for name, block in (("block_yellow", yellow), ("block_blue", blue)):
        block = stretch(block, BLOCK_SIZE, 10, 15)
        px = block.load()
        for y in range(block.size[1]):
            for x in range(block.size[0]):
                if px[x, y][:3] == sky:
                    px[x, y] = (0, 0, 0, 0)
        save(block, name)

    icons = load(root, ICONS)
    for name, box in ICON_BOXES.items():
        save(cut(icons, box), "icon_" + name)
    save(cut(icons, ICON_BOXES["jump"]).transpose(Image.ROTATE_90), "icon_run")   # arrow pointing away
    save(cut(load(root, MUSHROOMS), (57, 18, 73, 35)), "icon_mushroom")
    for name, box in PROMPT_BOXES.items():
        save(cut(icons, box), "prompt_" + name)


def build_ratings(root):
    sheet = load(root, RATINGS)
    for name, box in RATING_BOXES.items():
        save(cut(sheet, box), "rating_" + name)
    save(cut(sheet, (575, 74, 586, 84)), "status_burn")        # the flame from the stat icons
    start = load(root, START)
    save(cut(start, START_FRAMES[0]), "status_stun")          # a little star circles stunned enemies


def build_battle_start(root):
    sheet = load(root, START)
    cols, rows = 6, 4
    grid = Image.new("RGBA", (SCREEN[0] * cols, SCREEN[1] * rows), (0, 0, 0, 0))
    for i, box in enumerate(START_FRAMES):
        frame = sheet.crop(box)
        px = frame.load()
        for y in range(frame.size[1]):
            for x in range(frame.size[0]):
                if px[x, y][:3] not in STAR_COLORS:
                    px[x, y] = (0, 0, 0, 0)
        # Smaller frames are the star still growing in the middle of the screen.
        ox = (SCREEN[0] - frame.size[0]) // 2 + (i % cols) * SCREEN[0]
        oy = (SCREEN[1] - frame.size[1]) // 2 + (i // cols) * SCREEN[1]
        grid.alpha_composite(frame, (ox, oy))
    save(grid, "battle_start")


if __name__ == "__main__":
    root = sys.argv[1]
    build_backgrounds(root)
    build_blocks(root)
    build_ratings(root)
    build_battle_start(root)
