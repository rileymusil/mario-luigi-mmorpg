"""Cuts the pants and badge pictures for equipment into game/assets/items/.

Source (in the Mario&LuigiMMO art drop):
  MISC UI AND MORE/... Miscellaneous - Equipment Menu  - MLSS equipment menu (Mirax96)

The sheet has one pair of pants and one badge. Each piece of gear in
Game.GEAR (game/scripts/game.gd) is one of them recoloured: `hue` turns the
colours round the colour wheel (0..1), `sat` scales how strong they are, the
way Superstar Saga tells its pants and badges apart.

Usage: python3 tools/slice_gear.py "<path to Mario&LuigiMMO folder>"
"""
import colorsys
import os
import sys

from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "game", "assets", "items")
SHEET = "MISC UI AND MORE/Game Boy Advance - Mario & Luigi_ Superstar Saga - Miscellaneous - Equipment Menu.png"
BOXES = {"pants": (46, 107, 62, 127), "badge": (72, 109, 87, 123)}

# id -> (picture, hue shift, saturation scale). Pants start blue, badges pink.
GEAR = {
    "thin_pants": ("pants", 0.0, 1.0),
    "work_pants": ("pants", 0.48, 0.55),   # brown
    "heart_jeans": ("pants", 0.35, 1.0),   # pink
    "koopa_pants": ("pants", 0.72, 1.0),   # green
    "mountain_pants": ("pants", 0.12, 1.0),  # purple
    "heart_badge": ("badge", 0.0, 1.0),
    "power_badge": ("badge", 0.05, 1.2),   # red
    "sp_badge": ("badge", 0.4, 1.0),       # green
    "guard_badge": ("badge", 0.68, 1.0),   # blue
    "spiny_badge": ("badge", 0.12, 1.2),   # orange
    "great_badge": ("badge", 0.2, 1.3),    # gold
}


def cut(sheet, box):
    img = sheet.crop(box).convert("RGBA")
    bg = sheet.getpixel((5, 100))[:3]
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            if px[x, y][:3] == bg:
                px[x, y] = (0, 0, 0, 0)
    return img


def recolour(img, hue, sat, keep_gold):
    out = img.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
            if s < 0.2 or l < 0.2 or l > 0.9 or (keep_gold and 0.08 < h < 0.18):
                continue  # outlines, highlights and the pants' gold buttons keep their colour
            r2, g2, b2 = colorsys.hls_to_rgb((h + hue) % 1.0, l, min(1.0, s * sat))
            px[x, y] = (round(r2 * 255), round(g2 * 255), round(b2 * 255), a)
    return out


def main(root):
    sheet = Image.open(os.path.join(root, SHEET)).convert("RGB")
    base = {k: cut(sheet, box) for k, box in BOXES.items()}
    os.makedirs(OUT, exist_ok=True)
    for gid, (kind, hue, sat) in GEAR.items():
        recolour(base[kind], hue, sat, kind == "pants").save(os.path.join(OUT, gid + ".png"))
        print("wrote", gid)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
