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
  add --heights to also rebuild <map>_height.png (otherwise an existing one is kept, see "Height layer")
  python3 tools/make_maps.py --outlines [map ids...]                           trace prop outlines (see "Prop outlines")
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


def town_wall(r, g, b):
    # Cream bricks of the terrace walls (and their darker mortar).
    h, s, v = hsv(r, g, b)
    return 0.1 < h < 0.2 and s < 0.45 and v > 0.75


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


def never(r, g, b):
    return False  # the mask comes only from the hand fixes (rooms drawn as rectangles)


def house_walk(r, g, b):
    # Castle Town houses and shops: orange planks and the pale yellow rug.
    h, s, v = hsv(r, g, b)
    if 0.07 < h < 0.15 and s > 0.6 and v > 0.8:
        return True
    return 0.11 < h < 0.18 and 0.3 < s <= 0.6 and v > 0.9


def palace_walk(r, g, b):
    # Beanbean Castle: green checker floor and the red carpet; teal ledges and walls block.
    h, s, v = hsv(r, g, b)
    if 0.2 < h < 0.25 and s > 0.5 and v > 0.65:
        return True
    return (h < 0.02 or h > 0.98) and s > 0.5 and v > 0.65  # carpet


def stardust_walk(r, g, b):
    # Stardust Fields: the violet ground and the pink plateaus walk; dark cliffs and the sky block.
    h, s, v = hsv(r, g, b)
    if 0.74 <= h < 0.81 and s > 0.4 and v > 0.75:
        return True
    return 0.79 <= h < 0.9 and 0.2 <= s < 0.42 and v > 0.86


def stardust_plateau(r, g, b):
    h, s, v = hsv(r, g, b)
    return 0.82 <= h < 0.9 and s < 0.42 and v > 0.86


def stardust_cliff(r, g, b):
    h, s, v = hsv(r, g, b)
    return 0.8 <= h < 0.9 and s > 0.35 and v < 0.65


def sky(r, g, b):
    return False  # nothing to keep blocked under props


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
        # The rip shows the town as two screens with a 4px divider down the
        # river, and the river's head drawn differently on each side: mirror
        # the west bank's head of the river onto the east side and close the gap.
        # The sheet's teal frame also shows along the map's edges.
        "patch": [((727, 0, 745, 310), (705, 0, 723, 310), True),
                  ((723, 0, 725, 644), (721, 0, 723, 644), False), ((725, 0, 727, 644), (727, 0, 729, 644), False),
                  ((0, 0, 1452, 1), (0, 1, 1452, 2), False), ((0, 641, 1452, 642), (0, 640, 1452, 641), False),
                  ((0, 642, 1452, 643), (0, 640, 1452, 641), False), ((0, 643, 1452, 644), (0, 640, 1452, 641), False),
                  ((0, 0, 1, 644), (3, 0, 4, 644), False), ((1, 0, 2, 644), (3, 0, 4, 644), False),
                  ((2, 0, 3, 644), (3, 0, 4, 644), False)] + [((x, 0, x + 1, 644), (1446, 0, 1447, 644), False)
                                                              for x in range(1447, 1452)],
        "seeds": [(320, 560)],
        "fixes": [
            ("walk", (686, 356, 764, 400)),  # bridge over the river
            ("walk", (0, 398, 60, 452)), ("walk", (1392, 398, 1452, 452)),  # west and east gates
            ("block", (578, 0, 676, 136)), ("block", (776, 0, 872, 150)),  # stairs up to the castle
            ("block", (208, 0, 482, 118)),  # palace windows
        ],
        # The cream brick walls under the grass terraces are ledge faces: the
        # low ones can be jumped up, any of them dropped down.
        "height": {"faces": [("auto", town_wall, (6, 48), None)]},
    },
    "outskirts": {
        "sheet": "Maps/Game Boy Advance - Mario & Luigi_ Superstar Saga - Maps - Beanbean Outskirts.png",
        "crop": (1447, 1923, 2912, 2560), "walk": field_walk, "hard": is_water, "smooth": 5, "islands": 200,
        "fill_black": [((0, 0, 1465, 637), (460, 330, 492, 362))],  # gaps of the rip at the west and east edges: water
        "seeds": [(800, 615), (100, 450), (520, 110), (460, 150), (260, 175)],  # + raised ground reached by jumping
        "fixes": [
            # Tops of the giant trees, the raised platforms and the rock pillar.
            ("block", (324, 0, 436, 88)), ("block", (850, 60, 1060, 120)), ("block", (1094, 44, 1140, 102)),
            ("block", (1172, 28, 1258, 86)), ("block", (1284, 28, 1380, 86)), ("block", (1028, 381, 1158, 478)),
            ("block", (50, 412, 148, 506)), ("block", (786, 60, 850, 171)), ("block", (350, 85, 410, 114)),
            # East bridge to Bowser's Castle, and a way down from it to the meadow.
            ("walk", (1380, 46, 1465, 80)), ("walk", (1381, 46, 1405, 112)),
            # Raised ground you jump onto (see "height"): the L-shaped hedge and
            # the two flat tree tops west of it, the way to the west islands.
            ("walk", (500, 98, 578, 125)), ("walk", (500, 98, 544, 172)),
            ("walk", (420, 112, 500, 192)), ("walk", (198, 112, 340, 192)),
            ("block", (197, 190, 312, 200)), ("block", (450, 190, 500, 200)),  # leafy fringe over the water
            ("walk", (54, 414, 146, 491)),  # hedge on the south-west island
        ],
        "height": {
            "levels": [(1, "box", (500, 94, 544, 172)), (1, "box", (500, 94, 579, 125)),
                       (1, "box", (420, 108, 500, 193)), (1, "box", (196, 108, 340, 193)),
                       (1, "box", (53, 412, 147, 491))],
            "faces": [("box", (544, 125, 579, 149)), ("box", (500, 172, 546, 200)), ("box", (53, 491, 147, 508))],
        },
    },
    "bowser_castle": {
        "sheet": "Maps/Game Boy Advance - Mario & Luigi_ Superstar Saga - Maps - Bowser's Castle.png",
        "crop": (40, 415, 436, 1030), "walk": castle_walk, "hard": is_lava, "smooth": 5, "islands": 120,
        # The rip's black void round the lava (and a cut-off corner of a block
        # at the bottom left) becomes more lava.
        "patch": [((78, 578, 112, 615), (274, 522, 308, 559), False)],
        "fill_black": [((0, 0, 396, 615), (274, 522, 322, 570))],  # a lava tile with whole bubbles
        "seeds": [(205, 250)],
        "fixes": [
            ("block", (0, 0, 156, 150)), ("block", (250, 0, 396, 150)), ("block", (156, 0, 250, 92)),  # castle walls
            ("block", (84, 355, 112, 425)), ("block", (296, 355, 324, 425)),  # spiked pillars by the platform
            ("block", (160, 404, 182, 615)), ("block", (226, 404, 250, 615)),  # bridge chains
            ("walk", (182, 380, 226, 615)),  # rail bridge
        ],
    },
}

# Phase 4: more of the kingdom. Extra keys:
# fill_white: [(box, tile)] pure white pixels in box (a hole in the rip) are filled
#   from the tile box, repeated; [(box, [source boxes], period)] fills each
#   pixel from the same row of the first source box with a column in phase. fill_black: [(box, tile)] the same for black
#   gaps between the pieces of a rip (patches of 300+ black pixels).
# patch: [(box, source box, mirror)] copies a piece of the crop over another
#   (mirrored left-right if mirror is true), to mend seams between pieces. white: colour for the sheet's leftover white
#   background (patches of pure white). paint: [(box, colour)] art fixes.
# Interiors are small rooms: a door mat at the bottom leads back outside.
_INTERIOR = "Maps/Game Boy Advance - Mario & Luigi_ Superstar Saga - Maps - Beanbean Castle Town (Interior).png"
_SHOP = "Maps/Game Boy Advance - Mario & Luigi_ Superstar Saga - Maps - Beanbean Castle Town Shop (Interior).png"
_PALACE = "Maps/Game Boy Advance - Mario & Luigi_ Superstar Saga - Maps - Beanbean Castle.gif"
_HOOHOO_IN = "Maps/Game Boy Advance - Mario & Luigi_ Superstar Saga - Maps - Hoohoo Village (Interior).png"


def _house(crop, floor, mats, seed):
    """A Castle Town house: planks by colour, the open floor in front of the
    furniture (rug included) and the door mats walk."""
    return {"sheet": _INTERIOR, "crop": crop, "walk": house_walk, "hard": sky, "smooth": 5, "islands": 400,
            "seeds": [seed], "fixes": [("walk", floor)] + [("walk", m) for m in mats]}


MAPS.update({
    # Castle Town houses (Mitchcom's sheet): one room per house, the big
    # double house has two doors.
    "house_nw": _house((15, 60, 227, 314), (26, 142, 186, 219), [(94, 208, 118, 241)], (106, 205)),
    "house_sw": _house((265, 60, 477, 314), (26, 142, 186, 220), [(94, 208, 118, 242)], (106, 205)),
    "house_s": _house((494, 60, 706, 314), (26, 142, 193, 221), [(94, 208, 118, 243)], (106, 205)),
    "house_se": _house((727, 60, 939, 317), (26, 142, 186, 223), [(94, 210, 118, 245)], (106, 207)),
    "house_ne": _house((5, 349, 425, 599), (26, 131, 399, 216), [(94, 205, 118, 238), (302, 205, 326, 238)], (106, 200)),
    # Shops (Mario Gamer's sheet): counter at the back, two display tables.
    "shop_mushroom": {"sheet": _SHOP, "crop": (6, 392, 246, 649), "walk": house_walk, "hard": sky, "smooth": 5,
                      "islands": 300, "seeds": [(56, 200)],
                      "fixes": [("walk", (41, 205, 71, 249)), ("block", (16, 0, 224, 130))]},
    "shop_badge": {"sheet": _SHOP, "crop": (6, 656, 246, 913), "walk": house_walk, "hard": sky, "smooth": 5,
                   "islands": 300, "seeds": [(56, 200)],
                   "fixes": [("walk", (42, 205, 72, 250)), ("block", (16, 0, 224, 130))]},
    "starbeans_cafe": {
        "sheet": "Maps/Game Boy Advance - Mario & Luigi_ Superstar Saga - Maps - Starbeans Cafe (Interior).png",
        "crop": (0, 0, 480, 269), "walk": never, "hard": sky, "smooth": 1, "islands": 1, "seeds": [(248, 220)],
        "fixes": [
            ("walk", (58, 99, 422, 240)), ("walk", (228, 230, 268, 262)),  # floor, door mat
            ("block", (188, 0, 308, 147)),  # the bar
            ("block", (54, 106, 84, 146)), ("block", (396, 140, 426, 180)),  # wall shelves
        ],
    },
    # Beanbean Castle (Bacon's sheet): the entrance hall and the throne room.
    "castle_hall": {"sheet": _PALACE, "crop": (390, 815, 822, 1128), "walk": palace_walk, "hard": sky, "smooth": 3,
                    "islands": 200, "seeds": [(224, 280)],
                    "fixes": [("walk", (50, 185, 98, 266)), ("walk", (370, 185, 418, 266)),  # floor emblems
                              ("walk", (192, 285, 257, 313))]},  # corridor out to town
    "throne_room": {"sheet": _PALACE, "crop": (508, 4, 722, 472), "walk": palace_walk, "hard": sky, "smooth": 3,
                    "islands": 200, "seeds": [(107, 430)],
                    "fixes": [("walk", (85, 199, 139, 278)), ("walk", (82, 440, 132, 468))]},  # carpet emblem, corridor
    # Outdoors.
    "stardust_fields": {
        "sheet": "Maps/Game Boy Advance - Mario & Luigi_ Superstar Saga - Maps - Stardust Fields.png",
        "crop": (720, 830, 1250, 1500), "walk": stardust_walk, "hard": sky, "smooth": 5, "islands": 300,
        "seeds": [(40, 590)], "white": (123, 130, 222),
        "fixes": [("walk", (0, 404, 44, 432)), ("walk", (0, 572, 34, 600)),  # west bridges
                  ("block", (84, 340, 120, 378))],  # top of the little pillar under the plateau
        # The pink plateaus stand one level above the violet ground: jump up
        # onto them from the violet. Their tall south cliffs can only be
        # dropped down.
        "height": {
            "levels": [(1, "flood", [(200, 230), (360, 270), (222, 150)], stardust_plateau, (95, 100, 410, 340)),
                       (1, "flood", [(505, 130)], stardust_plateau, (470, 95, 530, 160))],
            "faces": [("auto", stardust_cliff, (20, 80), (95, 230, 410, 380))],
            "flat": [(84, 340, 122, 420)],  # the little pillar under the plateau stays a wall
        },
    },
    "hoohoo_village": {
        "sheet": "Maps/Game Boy Advance - Mario & Luigi_ Superstar Saga - Maps - Hoohoo Village (Exterior).png",
        "crop": (14, 8, 734, 452), "walk": never, "hard": sky, "smooth": 5, "islands": 200,
        "seeds": [(60, 110)], "fill_white": [((240, 231, 480, 284), [(480, 231, 506, 284), (190, 231, 222, 284)], 32)], "white": (16, 0, 0),
        "fixes": [
            ("walk", (0, 92, 150, 130)), ("walk", (35, 128, 140, 182)), ("walk", (35, 180, 108, 262)),  # west sand
            ("block", (46, 198, 102, 242)),  # spiky bush
            ("walk", (140, 84, 548, 150)),  # log deck (the huts block with their footprints)
            ("walk", (548, 75, 595, 185)), ("walk", (595, 125, 622, 185)),  # east sand
        ] + [("walk", (620 + 8 * i, 125 + 8 * i, 632 + 8 * i, 188 + 8 * i)) for i in range(6)] + [  # upper stairs
            ("walk", (668, 170, 700, 262)), ("walk", (624, 262, 700, 344)),  # by the mountain door, lower ledge
        ] + [("walk", (543 + 7 * i, 345 - 15 * i // 2, 555 + 7 * i, 392 - 15 * i // 2)) for i in range(12)] + [  # lower stairs
            ("walk", (510, 340, 545, 438)),  # sand column down to the south path
            ("walk", (152, 380, 516, 408)),  # bridges
            ("walk", (228, 372, 316, 432)), ("block", (255, 355, 291, 386)),  # island, the cave's stone door
            ("walk", (110, 336, 160, 420)),  # grass block
        ],
        # The sand ledge by the mountain door is a step above the blue grass:
        # drop down it, jump back up.
        "height": {"faces": [("box", (672, 264, 701, 284))]},
    },
    "hoohoo_hut_w": {"sheet": _HOOHOO_IN, "crop": (26, 64, 238, 306), "walk": never, "hard": sky, "smooth": 1,
                     "islands": 1, "seeds": [(160, 200)],
                     "fixes": [("walk", (17, 143, 196, 208)), ("walk", (49, 131, 137, 143)), ("walk", (49, 96, 71, 131)),
                               ("block", (17, 126, 48, 176)),  # pot
                               ("walk", (146, 204, 177, 239))]},  # doorway
    "hoohoo_hut_e": {"sheet": _HOOHOO_IN, "crop": (313, 70, 510, 312), "walk": never, "hard": sky, "smooth": 1,
                     "islands": 1, "seeds": [(90, 190)],
                     "fixes": [("walk", (10, 135, 154, 208)), ("walk", (39, 100, 67, 135)), ("walk", (137, 95, 154, 135)),
                               ("block", (10, 110, 40, 158)),  # pot
                               ("walk", (26, 206, 58, 238))]},  # doorway
})


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


# --- Height layer ---------------------------------------------------------------
# <map>_height.png gives the ground a level, for raised ground you must jump
# onto (see "Height" in game/scripts/world.gd): grey level * LEVEL_STEP, and
# FACE (white) for a ledge face, the drawn side of raised ground that can be
# jumped up (if it is low enough) or dropped down. A map's "height" entry:
#   "levels": [(level, "box", (l, t, r, b)),
#              (level, "flood", [seed points], colour test, (l, t, r, b) or None)]
#       painted in order; "flood" fills the walkable pixels of that colour
#       connected to the seeds (inside the box), then grows 2px over outlines.
#   "faces": [("box", (l, t, r, b)),
#             ("auto", colour test, (shortest, tallest), (l, t, r, b) or None)]
#       "auto" finds walls drawn in that colour between walkable ground above
#       and below (a column of blocked pixels, mostly that colour, between
#       shortest and tallest px) and makes them ledge faces.
#   "flat": [(l, t, r, b)] boxes reset to level 0 with no faces (applied last).
# Hand edits in the map editor are kept: the height layer is only written when
# it doesn't exist yet or with --heights.
LEVEL_STEP = 50
FACE = 255


def flood(mask, art, seeds, test, box):
    w, h = mask.size
    l, t, r, b = box or (0, 0, w, h)
    mp, ap = mask.load(), art.load()
    seen = set()
    q = deque((x, y) for x, y in seeds if mp[x, y] == 255 and test(*ap[x, y]))
    seen.update(q)
    while q:
        x, y = q.popleft()
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if l <= nx < r and t <= ny < b and (nx, ny) not in seen and mp[nx, ny] == 255 and test(*ap[nx, ny]):
                seen.add((nx, ny))
                q.append((nx, ny))
    return seen


def auto_faces(mask, art, test, runs, box):
    """Columns of blocked pixels mostly in the wall colour, with walkable
    ground right above and below, between runs[0] and runs[1] px tall."""
    w, h = mask.size
    l, t, r, b = box or (0, 0, w, h)
    mp, ap = mask.load(), art.load()
    out = []
    for x in range(max(0, l), min(w, r)):
        y = max(1, t)
        while y < min(h - 1, b):
            if mp[x, y] == 0 and mp[x, y - 1] == 255:
                y1 = y
                while y1 < h and mp[x, y1] == 0:
                    y1 += 1
                n = y1 - y
                if y1 < h and runs[0] <= n <= runs[1] and \
                        sum(1 for yy in range(y, y1) if test(*ap[x, yy])) >= 0.6 * n:
                    out.extend((x, yy) for yy in range(y, y1))
                y = y1
            else:
                y += 1
    return out


def build_height(map_id, cfg, art, mask):
    w, h = art.size
    height = Image.new("L", (w, h), 0)
    hp = height.load()
    src = art.convert("RGB")
    for level, kind, *args in cfg.get("levels", []):
        v = level * LEVEL_STEP
        if kind == "box":
            height.paste(v, args[0])
        else:
            seeds, test, box = args
            pixels = flood(mask, src, seeds, test, box)
            grow = Image.new("L", (w, h), 0)
            gp = grow.load()
            for x, y in pixels:
                gp[x, y] = 255
            grow = grow.filter(ImageFilter.MaxFilter(5))
            height.paste(v, mask=grow)
    for kind, *args in cfg.get("faces", []):
        if kind == "box":
            height.paste(FACE, args[0])
        else:
            for x, y in auto_faces(mask, src, *args):
                hp[x, y] = FACE
    for box in cfg.get("flat", []):
        height.paste(0, box)
    height.save(os.path.join(OUT, map_id + "_height.png"))
    print(map_id, "height", height.size)


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
    if cfg.get("smooth", 5) > 1:
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
    return mask


def touch_up(art, cfg):
    """Art fixes for a freshly cropped map (see the phase 4 notes above MAPS.update)."""
    px = art.load()
    white = (255, 255, 255)
    for dst, src, *period in cfg.get("fill_white", []):
        for y in range(dst[1], dst[3]):
            for x in range(dst[0], dst[2]):
                if px[x, y] != white:
                    continue
                if period:
                    # Same row, a column of the same phase in the first source
                    # box that has one (for patterns repeating every `period` px).
                    for box in (src if isinstance(src[0], tuple) else [src]):
                        xs = [sx for sx in range(box[0], box[2]) if (sx - x) % period[0] == 0 and px[sx, y] != white]
                        if xs:
                            px[x, y] = px[xs[0], y]
                            break
                else:
                    tw, th = src[2] - src[0], src[3] - src[1]
                    px[x, y] = px[src[0] + (x - dst[0]) % tw, src[1] + (y - dst[1]) % th]
    for dst, src, flip in cfg.get("patch", []):
        piece = art.crop(src)
        if flip:
            piece = piece.transpose(Image.FLIP_LEFT_RIGHT)
        art.paste(piece, dst[:2])
    if cfg.get("fill_black"):
        # Black gaps between the pieces of the rip (not the black outlines:
        # only black patches of at least 300 pixels), filled from a tile.
        w, h = art.size
        bg = Image.new("L", (w, h), 0)
        bp = bg.load()
        for y in range(h):
            for x in range(w):
                if px[x, y] == (0, 0, 0):
                    bp[x, y] = 255
        gaps = set()
        for area, edge, pixels in components(bg, 255):
            if area >= 300:
                gaps.update(pixels)
        for dst, src in cfg["fill_black"]:
            tw, th = src[2] - src[0], src[3] - src[1]
            for x, y in gaps:
                if dst[0] <= x < dst[2] and dst[1] <= y < dst[3]:
                    px[x, y] = px[src[0] + (x - dst[0]) % tw, src[1] + (y - dst[1]) % th]
    for box, colour in cfg.get("paint", []):
        art.paste(colour, box)
    if "white" in cfg:
        w, h = art.size
        bg = Image.new("L", (w, h), 0)
        bp = bg.load()
        for y in range(h):
            for x in range(w):
                if px[x, y] == white:
                    bp[x, y] = 255
        for area, edge, pixels in components(bg, 255):
            if area >= 64:  # small white bits are part of the art (sparkles, eyes)
                for x, y in pixels:
                    px[x, y] = cfg["white"]


def build(map_id, cfg, root, heights=False):
    if root:
        src = Image.open(os.path.join(root, cfg["sheet"])).convert("RGB")
        art = src.crop(cfg["crop"])
        touch_up(art, cfg)
        os.makedirs(OUT, exist_ok=True)
        art.save(os.path.join(OUT, map_id + ".png"))
    else:
        art = Image.open(os.path.join(OUT, map_id + ".png")).convert("RGB")
    mask = build_mask(map_id, cfg, art)
    if "height" in cfg:
        if heights or not os.path.exists(os.path.join(OUT, map_id + "_height.png")):
            build_height(map_id, cfg["height"], art, mask)
        else:
            print(map_id, "height: kept %s_height.png (it may have hand edits; pass --heights to rebuild it)" % map_id)


# --- Prop outlines ---------------------------------------------------------------
# A prop is drawn over the characters as a piece of the map picture. Its
# default outline (map_props.gd) is its rectangle, or a rounded canopy plus a
# trunk strip for a tree; both take in bits of the ground round the prop
# (water, sand, grass in the corners), which then cover anyone behind it.
# --outlines writes "poly" (the outline traced round the prop's art, relative
# to its rect) and "poly_for" (the rect size it was traced for) into
# <map>_props.json; map_props.gd draws that outline while the rect keeps its
# size.
#
# The teal Outskirts trees (51x72 props) all share one sprite, but they stand
# in rows that overlap, so their outline comes from this table: the canopy
# row by row (first row 1), then the trunk and roots. It was measured by
# comparing every tree of the Outskirts: pixels that are the same in most
# of them are the tree.
TREE_51x72 = [(22, 28), (24, 29), (22, 31), (20, 33), (19, 34), (19, 34), (18, 35), (18, 35), (10, 35), (8, 35)] + \
    [(7, 35)] * 5 + [(7, 43)] + [(7, 45)] * 5 + [(2, 45)] * 12 + [(2, 47)] * 5 + [(3, 47)] * 6 + [(3, 43)] * 5 + \
    [(15, 33)] * 22  # rows 1-71


# Outlines drawn by hand (relative to the prop's rect), for props whose
# art has no closed outline to trace: (map, prop name) -> points.
HAND_OUTLINES = {
    ("outskirts", "big_tree_n"): [(2, 0), (110, 0), (110, 82), (84, 86), (76, 100), (68, 104), (70, 128), (38, 128),
                                  (38, 104), (30, 100), (22, 86), (2, 82)],
    ("outskirts", "platform_ne_long"): [(2, 0), (208, 0), (208, 58), (178, 58), (178, 94), (162, 94), (162, 58),
                                        (80, 58), (80, 102), (65, 102), (65, 58), (2, 58)],
    ("outskirts", "platform_ne_1"): [(0, 0), (46, 0), (46, 56), (31, 58), (31, 96), (13, 96), (13, 58), (0, 56)],
    ("outskirts", "platform_ne_2"): [(0, 0), (80, 0), (80, 58), (48, 58), (48, 96), (32, 96), (32, 58), (0, 58)],
    ("outskirts", "platform_ne_3"): [(0, 0), (92, 0), (92, 56), (46, 56), (46, 96), (30, 96), (30, 56), (0, 56)],
}


def span_poly(spans, first_row):
    """A simple polygon round rows of [left, right] pixel spans (each row's
    span overlapping the next one's)."""
    right, left = [], []
    for i, (l, r) in enumerate(spans):
        y = first_row + i
        right += [(r + 1, y), (r + 1, y + 1)]
        left += [(l, y), (l, y + 1)]
    pts = right + left[::-1]
    out = []
    for i, b in enumerate(pts):
        a, c = pts[i - 1], pts[(i + 1) % len(pts)]
        if (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0]) != 0:
            out.append(list(b))
    return out


def trace_prop(art, rect, dark=95):
    """Row spans of the art inside `rect` enclosed by its dark outline: the
    ground is flooded in from the rect's edges, the prop is the biggest piece
    left. None when that piece is too small to be the prop (the outline has
    gaps, or the prop runs off the rect)."""
    x0, y0, w, h = rect
    W, H = art.size
    px = art.load()

    def is_dark(x, y):
        X, Y = x0 + x, y0 + y
        if not (0 <= X < W and 0 <= Y < H):
            return False
        r, g, b = px[X, Y][:3]
        return 0.299 * r + 0.587 * g + 0.114 * b < dark

    out = set()
    q = deque((x, y) for x in range(w) for y in (0, h - 1) if not is_dark(x, y))
    q.extend((x, y) for y in range(h) for x in (0, w - 1) if not is_dark(x, y))
    out.update(q)
    while q:
        x, y = q.popleft()
        for n in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= n[0] < w and 0 <= n[1] < h and n not in out and not is_dark(*n):
                out.add(n)
                q.append(n)
    inside = {(x, y) for x in range(w) for y in range(h)} - out
    best = set()
    while inside:
        comp = {inside.pop()}
        q = deque(comp)
        while q:
            x, y = q.popleft()
            for n in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if n in inside:
                    inside.discard(n)
                    comp.add(n)
                    q.append(n)
        if len(comp) > len(best):
            best = comp
    if len(best) < 0.35 * w * h:
        return None
    rows = {}
    for x, y in best:
        l, r = rows.get(y, (x, x))
        rows[y] = (min(l, x), max(r, x))
    ys = sorted(rows)
    spans = [rows[y] for y in ys]
    if ys[-1] - ys[0] + 1 != len(ys) or any(a[1] < b[0] or b[1] < a[0] for a, b in zip(spans, spans[1:])):
        return None
    return ys[0], spans


def write_outlines(map_id):
    path = os.path.join(OUT, map_id + "_props.json")
    if not os.path.exists(path):
        return
    art = Image.open(os.path.join(OUT, map_id + ".png")).convert("RGB")
    with open(path) as f:
        props = json.load(f)["props"]
    traced = 0
    for p in props:
        x, y, w, h = p["rect"]
        p.pop("poly", None)
        p.pop("poly_for", None)
        hand = HAND_OUTLINES.get((map_id, p.get("name")))
        if hand:
            p["poly"] = [list(v) for v in hand]
            p["poly_for"] = [w, h]
            traced += 1
            continue
        if p.get("shape") == "tree" and (w, h) == (51, 72):
            found = (1, TREE_51x72)
        else:
            found = trace_prop(art, p["rect"])
        if found:
            p["poly"] = span_poly(found[1], found[0])
            p["poly_for"] = [w, h]
            traced += 1
    with open(path, "w") as f:
        f.write('{"props": [\n' + ",\n".join(json.dumps(p, separators=(",", ":")) for p in props) + "\n]}\n")
    print(map_id, "outlines: %d of %d props" % (traced, len(props)))


if __name__ == "__main__":
    args = sys.argv[1:]
    rebuild_heights = "--heights" in args
    if "--outlines" in args:
        for map_id in [a for a in args if a != "--outlines"] or list(MAPS):
            write_outlines(map_id)
        sys.exit()
    args = [a for a in args if a != "--heights"]
    root = None if args and args[0] == "--mask-only" else (args[0] if args else None)
    if not args:
        sys.exit(__doc__)
    ids = args[1:]
    for map_id, cfg in MAPS.items():
        if ids and map_id not in ids:
            continue
        build(map_id, cfg, root, rebuild_heights)
