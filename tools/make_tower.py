"""Builds the Boss Tower floors (boss_tower_* in Game.MAPS) from the Beanbean
Castle rooms: each floor is the castle hall (the top one the throne room)
with its colours turned, so every floor looks different. The walk masks are
the rooms' own.

Usage: python3 tools/make_tower.py [floor ids...]
"""
import colorsys
import os
import shutil
import sys

from PIL import Image

MAPS = os.path.join(os.path.dirname(__file__), "..", "game", "assets", "maps")

# floor id: (source room, hue turn (0-1), saturation factor, brightness factor)
FLOORS = {
    "boss_tower_1": ("castle_hall", 0.55, 1.0, 0.95),   # violet
    "boss_tower_2": ("castle_hall", 0.80, 1.0, 0.85),   # Bowser red
    "boss_tower_3": ("castle_hall", 0.40, 0.9, 0.8),    # deep blue
    "boss_tower_4": ("castle_hall", 0.92, 1.0, 0.9),    # gold
    "boss_tower_5": ("castle_hall", 0.28, 0.8, 0.65),   # dark teal
    "boss_tower_top": ("throne_room", 0.72, 1.0, 0.7),  # dark crimson throne
}


def recolor(im, turn, sat, val):
    im = im.convert("RGBA")
    px = im.load()
    cache = {}
    for y in range(im.size[1]):
        for x in range(im.size[0]):
            c = px[x, y]
            if c not in cache:
                h, s, v = colorsys.rgb_to_hsv(c[0] / 255, c[1] / 255, c[2] / 255)
                r, g, b = colorsys.hsv_to_rgb((h + turn) % 1.0, min(1.0, s * sat), min(1.0, v * val))
                cache[c] = (round(r * 255), round(g * 255), round(b * 255), c[3])
            px[x, y] = cache[c]
    return im


if __name__ == "__main__":
    for floor, (src, turn, sat, val) in FLOORS.items():
        if len(sys.argv) > 1 and floor not in sys.argv[1:]:
            continue
        recolor(Image.open(os.path.join(MAPS, src + ".png")), turn, sat, val).save(os.path.join(MAPS, floor + ".png"))
        shutil.copy(os.path.join(MAPS, src + "_mask.png"), os.path.join(MAPS, floor + "_mask.png"))
        print(floor, "from", src)
