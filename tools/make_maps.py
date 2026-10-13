"""Crops map art from the Superstar Saga map sheets and builds a walk mask for each.

The mask is a black and white PNG the same size as the map: white = walkable,
black = blocked. It starts from a colour guess and can be touched up by hand
in any paint program (game/assets/maps/<id>_mask.png). Re-running this script
overwrites hand edits, so pass the map ids you want to rebuild.

Usage: python3 tools/make_maps.py "<path to Mario&LuigiMMO folder>" [map ids...]
"""
import colorsys
import os
import sys

from PIL import Image, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "game", "assets", "maps")


def is_water(r, g, b):
    h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    return 0.5 < h < 0.65 and s > 0.15 and b > 150


def is_dark(r, g, b):
    return r + g + b < 120


def town_blocked(r, g, b):
    # In town only grass and the lavender cobble paths are walkable.
    h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    grass = 0.22 < h < 0.42 and s > 0.35 and v > 0.6
    path = 0.58 < h < 0.85 and s < 0.4 and v > 0.55  # water is h 0.53-0.56
    return not (grass or path)


def field_blocked(r, g, b):
    h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    if is_water(r, g, b) or is_dark(r, g, b):
        return True
    if 0.36 < h < 0.5 and s > 0.45:  # tree canopies and trunks
        return True
    return False


def castle_blocked(r, g, b):
    h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    if is_dark(r, g, b):
        return True
    if (h < 0.11 or h > 0.97) and s > 0.6 and r > 150:  # lava
        return True
    return False


# crop: (left, top, right, bottom) on the source sheet.
# fixes: list of ("block"|"walk", (left, top, right, bottom)) in map pixels.
MAPS = {
    "castle_town": {
        "sheet": "Maps/Game Boy Advance - Mario & Luigi_ Superstar Saga - Maps - Beanbean Castle Town (Exterior).png",
        "crop": (0, 646, 1452, 1290), "blocked": town_blocked, "smooth": 13, "grow": 9,
        "fixes": [("walk", (640, 372, 775, 412)),  # bridge between the two halves
                  ("walk", (0, 386, 60, 432)), ("walk", (1392, 386, 1452, 432))],  # west and east gates
    },
    "outskirts": {
        "sheet": "Maps/Game Boy Advance - Mario & Luigi_ Superstar Saga - Maps - Beanbean Outskirts.png",
        "crop": (1447, 1923, 2912, 2560), "blocked": field_blocked,
        "fixes": [("walk", (1375, 48, 1465, 82)), ("walk", (1375, 48, 1405, 115))],  # east bridge
    },
    "bowser_castle": {
        "sheet": "Maps/Game Boy Advance - Mario & Luigi_ Superstar Saga - Maps - Bowser's Castle.png",
        "crop": (40, 415, 436, 1030), "blocked": castle_blocked,
        "fixes": [("block", (0, 0, 160, 120)), ("block", (282, 0, 396, 120)), ("block", (160, 0, 282, 92)),  # back walls
                  ("walk", (180, 380, 228, 615))],  # rail bridge
    },
}


def build(map_id, cfg, root):
    src = Image.open(os.path.join(root, cfg["sheet"])).convert("RGB")
    art = src.crop(cfg["crop"])
    w, h = art.size
    px = art.load()
    mask = Image.new("L", (w, h), 0)
    mp = mask.load()
    for y in range(h):
        for x in range(w):
            mp[x, y] = 0 if cfg["blocked"](*px[x, y]) else 255
    # Smooth out single-pixel noise: majority vote over 7x7 neighbourhoods.
    mask = mask.filter(ImageFilter.MedianFilter(cfg.get("smooth", 7)))
    if cfg.get("grow"):
        mask = mask.filter(ImageFilter.MaxFilter(cfg["grow"]))  # close thin outlines
    for kind, box in cfg["fixes"]:
        mask.paste(255 if kind == "walk" else 0, box)
    os.makedirs(OUT, exist_ok=True)
    art.save(os.path.join(OUT, map_id + ".png"))
    mask.save(os.path.join(OUT, map_id + "_mask.png"))
    print(map_id, art.size)


if __name__ == "__main__":
    root = sys.argv[1]
    for map_id, cfg in MAPS.items():
        if len(sys.argv) > 2 and map_id not in sys.argv[2:]:
            continue
        build(map_id, cfg, root)
