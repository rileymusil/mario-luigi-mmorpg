"""Cuts the Superstar Saga item pictures into game/assets/items/.

Source (in the Mario&LuigiMMO art drop):
  MISC UI AND MORE/... Miscellaneous - Items    - MLSS items (A.J. Nitro)

Outputs one transparent PNG per item id in Game.ITEMS (game/scripts/game.gd),
named <id>.png, about 14x16 each. The menus and the battle's item list show
them beside the item's name.

Super Syrup has no picture of its own on the sheet: it is the Syrup jar
tinted red, the way Superstar Saga tells the two apart.

Usage: python3 tools/slice_items.py "<path to Mario&LuigiMMO folder>"
"""
import colorsys
import os
import sys

from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "game", "assets", "items")
SHEET = "MISC UI AND MORE/Game Boy Advance - Mario & Luigi_ Superstar Saga - Miscellaneous - Items.png"

# id -> (left, top, right, bottom) on the sheet: the still, upright frame of
# each item's spin.
BOXES = {
    "mushroom": (123, 24, 137, 40),        # red
    "super_mushroom": (123, 141, 137, 157),  # orange
    "ultra_mushroom": (123, 101, 137, 117),  # green with red spots
    "one_up": (123, 62, 137, 78),          # green 1-Up
    "syrup": (128, 213, 140, 229),         # honey jar
    "refreshing_herb": (65, 235, 76, 251),  # leafy herb
    "red_pepper": (315, 160, 331, 175),
    "green_pepper": (336, 160, 352, 175),
}


def cut(sheet, box):
    img = sheet.crop(box)
    bg = sheet.getpixel((0, 0))[:3]
    px = img.load()
    for y in range(img.size[1]):
        for x in range(img.size[0]):
            if px[x, y][:3] == bg:
                px[x, y] = (0, 0, 0, 0)
    return img.crop(img.getbbox())


def tint(img, hue_shift):
    """Turns the picture's hue round by hue_shift (0-1), keeping dark outlines."""
    out = img.copy()
    px = out.load()
    for y in range(out.size[1]):
        for x in range(out.size[0]):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            if s < 0.15:
                continue  # white shine and black outline stay as they are
            r2, g2, b2 = colorsys.hsv_to_rgb((h + hue_shift) % 1.0, s, v)
            px[x, y] = (round(r2 * 255), round(g2 * 255), round(b2 * 255), a)
    return out


def save(img, name):
    img.save(os.path.join(OUT, name + ".png"))
    print(name, img.size)


def main(root):
    os.makedirs(OUT, exist_ok=True)
    sheet = Image.open(os.path.join(root, SHEET)).convert("RGBA")
    for name, box in BOXES.items():
        save(cut(sheet, box), name)
    save(tint(cut(sheet, BOXES["syrup"]), -0.09), "super_syrup")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
