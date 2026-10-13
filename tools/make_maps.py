"""Crops map art from the Superstar Saga map sheets and builds a walk mask for each.

The mask is a black and white PNG the same size as the map: white = walkable,
black = blocked. It only describes the ground: water, lava, cliffs and ledges,
walls and the map edge. Trees, buildings and other tall things are "props"
(game/assets/maps/<id>_props.json): the game draws them over anyone standing
behind them and blocks only their small footprint, so the mask under a canopy
or roof stays walkable wherever the ground carries on behind it.

How a mask is built:
  1. a colour guess per pixel (grass and paths walk, water and walls block),
  2. a small median filter to remove single-pixel noise (no growing),
  3. blocked specks inside open ground are removed, and so are tiny walkable
     specks inside walls,
  4. each prop whose ground carries on above it is opened up to its base line
     (so you can walk behind it); water and lava stay blocked,
  5. hand fixes from the table below (bridges, gates...),
  6. rows of trees get the gaps between their trunks closed, and ground that
     can't be reached from the map's spawn (islands) is blocked.

After that, touch masks and props up in the game's map editor (F2 in a debug
run, see game/README.md). Re-running this script overwrites the mask, so pass
the map ids you want to rebuild.

Usage:
  python3 tools/make_maps.py "<path to Mario&LuigiMMO folder>" [map ids...]   crop art + build masks
  python3 tools/make_maps.py --mask-only [map ids...]                          rebuild masks from the art in the repo
"""
import colorsys
import json
import os
import sys
from collections import deque

from PIL import Image, ImageFilter

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "assets", "maps")


def hsv(r, g, b):
    return colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)


def town_walk(r, g, b):
    # In town, grass and the cobble paths are walkable; walls, ledges, roofs,
    # tree tops and water are not. None means "decide by the patch size".
    h, s, v = hsv(r, g, b)
    if 0.3 < h < 0.42 and s > 0.5 and v > 0.6:
        return True  # grass
    if 0.3 < h < 0.42 and 0.25 < s <= 0.5 and v > 0.7:
        return True  # light green path squares
    if 0.62 < h < 0.8 and s < 0.4 and v > 0.7:
        return True  # lavender cobbles
    if 0.585 < h < 0.62 and 0.2 < s < 0.45 and v > 0.75:
        return True  # blue-grey cobbles (water is greener)
    if 0.1 < h < 0.2 and s < 0.5 and v > 0.75:
        return None  # pale cream: a path stone if it is small, a wall if it is big
    return False


def town_water(r, g, b):
    h, s, v = hsv(r, g, b)
    return 0.5 < h < 0.585 and s > 0.15 and b > 150


def is_water(r, g, b):
    h, s, v = hsv(r, g, b)
    return 0.5 < h < 0.65 and s > 0.15 and b > 150


def field_walk(r, g, b):
    h, s, v = hsv(r, g, b)
    if is_water(r, g, b):
        return False
    if r + g + b < 120:
        return False  # outlines and shadows
    if 0.465 < h < 0.53 and s > 0.4:
        return False  # tree tops (the raised teal grass, h 0.45, is walkable)
    if 0.34 < h < 0.42 and s > 0.5 and v > 0.7:
        return False  # hedges
    if 0.1 < h < 0.135 and s > 0.65 and v < 0.9:
        return False  # cliff faces
    return True


def is_lava(r, g, b):
    h, s, v = hsv(r, g, b)
    return (h < 0.11 or h > 0.97) and s > 0.6 and r > 150


def castle_walk(r, g, b):
    h, s, v = hsv(r, g, b)
    if r + g + b < 120:
        return False
    if is_lava(r, g, b):
        return False
    if 0.11 <= h < 0.17 and s > 0.45 and r > 200:
        return False  # lava glow around the edges
    return True


# crop: (left, top, right, bottom) on the source sheet.
# walk: colour guess (True walk, False block, None decide by patch size).
# hard: colours a prop never opens up (water, lava), even when it hides them.
# smooth: median filter size. islands: specks smaller than this many pixels are removed.
# seeds: points on the main walkable area (spawns); walkable ground that can't be
#   reached from them (islands in water or lava) is blocked, to keep the mask tidy.
# fixes: list of ("block"|"walk", (left, top, right, bottom)) in map pixels, applied last.
MAPS = {
    "castle_town": {
        "sheet": "Maps/Game Boy Advance - Mario & Luigi_ Superstar Saga - Maps - Beanbean Castle Town (Exterior).png",
        "crop": (0, 646, 1452, 1290), "walk": town_walk, "hard": town_water, "smooth": 7, "islands": 900,
        "seeds": [(320, 560)],
        "fixes": [
            ("walk", (686, 356, 764, 400)),  # bridge over the river
            ("walk", (0, 398, 60, 452)), ("walk", (1392, 398, 1452, 452)),  # west and east gates
            ("block", (578, 0, 676, 136)), ("block", (776, 0, 872, 150)),  # stairs up to the castle
            ("block", (208, 0, 482, 118)),  # palace windows
        ],
    },
    "outskirts": {
        "sheet": "Maps/Game Boy Advance - Mario & Luigi_ Superstar Saga - Maps - Beanbean Outskirts.png",
        "crop": (1447, 1923, 2912, 2560), "walk": field_walk, "hard": is_water, "smooth": 5, "islands": 200,
        "seeds": [(800, 615)],
        "fixes": [
            # Tops of the giant trees, the raised platforms and the rock pillar.
            ("block", (324, 0, 436, 88)), ("block", (197, 108, 313, 200)), ("block", (419, 108, 501, 200)),
            ("block", (499, 92, 580, 202)), ("block", (850, 60, 1060, 120)), ("block", (1094, 44, 1140, 102)),
            ("block", (1172, 28, 1258, 86)), ("block", (1284, 28, 1380, 86)), ("block", (1028, 381, 1158, 478)),
            ("block", (50, 412, 148, 506)), ("block", (786, 60, 850, 171)), ("block", (350, 85, 410, 114)),
            # East bridge to Bowser's Castle, and a way down from it to the meadow.
            ("walk", (1380, 46, 1465, 80)), ("walk", (1381, 46, 1405, 112)),
        ],
    },
    "bowser_castle": {
        "sheet": "Maps/Game Boy Advance - Mario & Luigi_ Superstar Saga - Maps - Bowser's Castle.png",
        "crop": (40, 415, 436, 1030), "walk": castle_walk, "hard": is_lava, "smooth": 5, "islands": 120,
        "seeds": [(205, 250)],
        "fixes": [
            ("block", (0, 0, 156, 150)), ("block", (250, 0, 396, 150)), ("block", (156, 0, 250, 92)),  # castle walls
            ("block", (84, 355, 112, 425)), ("block", (296, 355, 324, 425)),  # spiked pillars by the platform
            ("block", (160, 404, 182, 615)), ("block", (226, 404, 250, 615)),  # bridge chains
            ("walk", (182, 380, 226, 615)),  # rail bridge
        ],
    },
}


def components(mask, value):
    """Yields (area, touches_edge, pixels) for each 4-connected region of `value`."""
    w, h = mask.size
    px = mask.load()
    seen = bytearray(w * h)
    for sy in range(h):
        for sx in range(w):
            if seen[sy * w + sx] or px[sx, sy] != value:
                continue
            q = deque([(sx, sy)])
            seen[sy * w + sx] = 1
            pixels = []
            edge = False
            while q:
                x, y = q.popleft()
                pixels.append((x, y))
                if x == 0 or y == 0 or x == w - 1 or y == h - 1:
                    edge = True
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] and px[nx, ny] == value:
                        seen[ny * w + nx] = 1
                        q.append((nx, ny))
            yield len(pixels), edge, pixels


def remove_specks(mask, limit):
    px = mask.load()
    for value, fill in ((0, 255), (255, 0)):
        for area, edge, pixels in list(components(mask, value)):
            if area < limit and not edge:
                for x, y in pixels:
                    px[x, y] = fill


def load_props(map_id):
    path = os.path.join(OUT, map_id + "_props.json")
    if not os.path.exists(path):
        return []
    with open(path) as f:
        return json.load(f).get("props", [])


def open_behind_props(mask, hard, props):
    """Opens the ground hidden behind each prop where the ground just above
    the prop is walkable (decided on the mask before any prop is opened, so a
    prop never opens a path through another prop). Water and lava (`hard`)
    stay blocked."""
    w, h = mask.size
    before = mask.copy().load()
    hard = hard.load()
    px = mask.load()
    for p in props:
        if p.get("fill") == "none":
            continue
        x0, y0, rw, rh = p["rect"]
        base = int(p["base"])
        cols = range(max(0, x0), min(w, x0 + rw))
        if p.get("fill") != "all":
            # Open the whole prop when most of the ground along its top edge is walkable.
            open_cols = sum(1 for x in cols if y0 >= 4 and all(before[x, y] == 255 for y in range(y0 - 4, y0 - 1)))
            if open_cols < 0.5 * len(cols):
                continue
        for x in cols:
            for y in range(max(0, y0), min(h, base)):
                if not hard[x, y]:
                    px[x, y] = 255


def close_tree_rows(mask, props):
    """Trees standing side by side (same base line, trunks under 56px apart)
    form a fence: block the ground between their trunks so you can walk
    behind a row of trees but not straight through it."""
    trees = [p for p in props if p.get("shape") == "tree" and p.get("foot")]
    for a in trees:
        for b in trees:
            fa, fb = a["foot"], b["foot"]
            if a is b or abs(a["base"] - b["base"]) > 6 or not 0 < fb[0] - fa[0] <= 56:
                continue
            top = max(fa[1], fb[1])
            bottom = min(fa[1] + fa[3], fb[1] + fb[3])
            mask.paste(0, (fa[0] + fa[2], top, fb[0], bottom))


def keep_reachable(mask, seeds):
    """Blocks walkable ground that can't be reached from any seed point."""
    px = mask.load()
    for area, edge, pixels in list(components(mask, 255)):
        inside = set(pixels)
        if not any(tuple(s) in inside for s in seeds):
            for x, y in pixels:
                px[x, y] = 0


def build_mask(map_id, cfg, art):
    w, h = art.size
    src = art.convert("RGB").load()
    mask = Image.new("L", (w, h), 0)
    mp = mask.load()
    cache = {}
    for y in range(h):
        for x in range(w):
            c = src[x, y]
            if c not in cache:
                ok = cfg["walk"](*c)
                cache[c] = 128 if ok is None else (255 if ok else 0)
            mp[x, y] = cache[c]
    # Unsure colours: small patches (path stones) walk, big ones (walls) block.
    for area, edge, pixels in list(components(mask, 128)):
        for x, y in pixels:
            mp[x, y] = 255 if area < cfg.get("stones", 400) else 0
    mask = mask.filter(ImageFilter.MedianFilter(cfg.get("smooth", 5)))
    remove_specks(mask, cfg.get("islands", 150))
    hard = Image.new("L", (w, h), 0)
    hp = hard.load()
    for y in range(h):
        for x in range(w):
            if cfg["hard"](*src[x, y]):
                hp[x, y] = 255
    hard = hard.filter(ImageFilter.MedianFilter(5))
    props = load_props(map_id)
    open_behind_props(mask, hard, props)
    remove_specks(mask, cfg.get("islands", 150))  # bits of roof pattern left behind
    for kind, box in cfg["fixes"]:
        mask.paste(255 if kind == "walk" else 0, box)
    close_tree_rows(mask, props)
    if cfg.get("seeds"):
        keep_reachable(mask, cfg["seeds"])
    mask.save(os.path.join(OUT, map_id + "_mask.png"))
    print(map_id, "mask", mask.size)


def build(map_id, cfg, root):
    if root:
        src = Image.open(os.path.join(root, cfg["sheet"])).convert("RGB")
        art = src.crop(cfg["crop"])
        os.makedirs(OUT, exist_ok=True)
        art.save(os.path.join(OUT, map_id + ".png"))
    else:
        art = Image.open(os.path.join(OUT, map_id + ".png")).convert("RGB")
    build_mask(map_id, cfg, art)


if __name__ == "__main__":
    args = sys.argv[1:]
    root = None if args and args[0] == "--mask-only" else (args[0] if args else None)
    if not args:
        sys.exit(__doc__)
    ids = args[1:]
    for map_id, cfg in MAPS.items():
        if ids and map_id not in ids:
            continue
        build(map_id, cfg, root)
