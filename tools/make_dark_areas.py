"""Builds the late-game areas and their enemies by recolouring art already in
the repo (like tools/make_tower.py does for the Boss Tower):

  twilight_meadow  the Outskirts Meadow at dusk   (levels 10-18)
  shadow_woods     the Outskirts Woods at night   (levels 18-30)
  (its east path leads on to Teehee Valley, levels 30-40: tools/make_maps.py)

The maps keep the walk masks and props of the maps they come from, with a few
edge pixels blocked where the copy has a path that leads nowhere (see SEAL).
The enemies are colour swaps of the Outskirts enemies (Gloomba, Dark Koopa...);
their stats live in Game.ENEMIES.

Usage: python3 tools/make_dark_areas.py
"""
import colorsys
import os
import shutil

from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "assets")
MAPS = os.path.join(ROOT, "maps")
CHARS = os.path.join(ROOT, "characters")

# map id: (source map, light colour the art is lit by (r, g, b multipliers), saturation factor)
AREAS = {
    "twilight_meadow": ("outskirts_east", (1.0, 0.72, 0.62), 0.85),  # sunset
    "shadow_woods": ("outskirts_woods", (0.42, 0.5, 0.78), 0.8),     # moonlit night
}
# Blocks the edge rows of a copy where the original had an exit we don't use:
# map id: list of (x, y, w, h) rectangles to paint black on the walk mask.
SEAL = {
    "twilight_meadow": [(340, 0, 90, 6)],        # the meadow's north path (to Stardust Fields)
}

# enemy id: (source sprite, hue turn, saturation factor, brightness factor,
#            only recolour saturated pixels: keeps eyes and outlines)
ENEMIES = {
    "gloomba": ("goomba", 0.55, 0.7, 0.75, True),
    "dark_koopa": ("koopa", 0.5, 0.8, 0.6, True),
    "dark_beanie": ("beanie", 0.6, 1.0, 0.7, True),
    "bony_beetle": ("buzzy_beetle", 0.0, 0.15, 1.6, True),
    "dark_bones": ("dry_bones", 0.0, 0.5, 0.45, False),
    "shadow_guy": ("shy_guy", 0.75, 0.9, 0.45, True),
    "gold_goomba": ("goomba", 0.09, 1.4, 1.25, True),
    # Teehee Valley and the Ruins (levels 30-40)
    "dune_goomba": ("goomba", 0.05, 1.0, 1.08, True),
    "dune_beanie": ("beanie", 0.85, 1.0, 1.1, True),
    "sun_koopa": ("koopa", 0.95, 1.3, 1.05, True),
    "crystal_beetle": ("buzzy_beetle", 0.3, 1.2, 1.3, True),
    "blaze_guy": ("shy_guy", 0.08, 1.0, 1.1, True),
    "pharaoh_bones": ("dry_bones", 0.5, 1.5, 1.0, True),
}


def light(im, rgb, sat):
    """The art under coloured light: each pixel's colour times `rgb`, after
    taking some saturation out so the light colour reads."""
    im = im.convert("RGBA")
    px = im.load()
    cache = {}
    for y in range(im.size[1]):
        for x in range(im.size[0]):
            c = px[x, y]
            if c not in cache:
                h, s, v = colorsys.rgb_to_hsv(c[0] / 255, c[1] / 255, c[2] / 255)
                r, g, b = colorsys.hsv_to_rgb(h, s * sat, v)
                cache[c] = (round(min(255, r * 255 * rgb[0])), round(min(255, g * 255 * rgb[1])),
                            round(min(255, b * 255 * rgb[2])), c[3])
            px[x, y] = cache[c]
    return im


def recolor(im, turn, sat, val, colored_only=False):
    im = im.convert("RGBA")
    px = im.load()
    cache = {}
    for y in range(im.size[1]):
        for x in range(im.size[0]):
            c = px[x, y]
            if c[3] == 0:
                continue
            if c not in cache:
                h, s, v = colorsys.rgb_to_hsv(c[0] / 255, c[1] / 255, c[2] / 255)
                if colored_only and s < 0.2:
                    cache[c] = c
                else:
                    r, g, b = colorsys.hsv_to_rgb((h + turn) % 1.0, min(1.0, s * sat), min(1.0, v * val))
                    cache[c] = (round(r * 255), round(g * 255), round(b * 255), c[3])
            px[x, y] = cache[c]
    return im


if __name__ == "__main__":
    for area, (src, rgb, sat) in AREAS.items():
        light(Image.open(os.path.join(MAPS, src + ".png")), rgb, sat).save(os.path.join(MAPS, area + ".png"))
        mask = Image.open(os.path.join(MAPS, src + "_mask.png")).convert("L")
        for x, y, w, h in SEAL.get(area, []):
            mask.paste(0, (x, y, x + w, y + h))
        mask.save(os.path.join(MAPS, area + "_mask.png"))
        props = os.path.join(MAPS, src + "_props.json")
        if os.path.exists(props):
            shutil.copy(props, os.path.join(MAPS, area + "_props.json"))
        print(area, "from", src)
    for enemy, (src, turn, sat, val, colored) in ENEMIES.items():
        recolor(Image.open(os.path.join(CHARS, src + ".png")), turn, sat, val, colored).save(os.path.join(CHARS, enemy + ".png"))
        print(enemy, "from", src)
