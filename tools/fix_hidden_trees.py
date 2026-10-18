"""Adds the teal trees that make_maps.py's find_trees missed as props.

find_trees matches a tree by its canopy top, so a tree standing behind
another one (its top hidden) was left out: it had no footprint, so you could
walk through its trunk, and nothing was drawn over you when you stood behind
it. This finds every trunk of the Outskirts tree sprite that no prop covers
(by matching the trunk and lower canopy, which show even when the top is
hidden), adds a tree prop for it, and closes the gap to the next tree in the
row like close_tree_rows does. A tree almost all hidden (only its trunk shows
between the trees in front) just gets its footprint blocked on the mask.

Usage: python3 tools/fix_hidden_trees.py [map ids...]   (default: the maps below)
Then re-run tools/make_dark_areas.py so the dark copies pick the fix up.
"""
import json
import os
import sys
from collections import deque

from PIL import Image

MAPS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "assets", "maps")
DEFAULT = ["outskirts", "outskirts_woods", "outskirts_east"]
W, H = 51, 72
# The part of the sprite that shows below a tree in front: rows 56-70, the
# trunk and the roots (columns 12-37).
ROWS, COLS = range(56, 71), range(12, 38)


def template():
    """The sprite (and a prop's outline) from a whole tree of the woods."""
    art = Image.open(os.path.join(MAPS, "outskirts_woods.png")).convert("RGB")
    props = json.load(open(os.path.join(MAPS, "outskirts_woods_props.json")))["props"]
    best = None
    for p in props:
        if p.get("shape") != "tree":
            continue
        x, y = p["rect"][:2]
        votes = sum(1 for q in props if q is not p and q.get("shape") == "tree"
                    and _same(art, x, y, art, q["rect"][0], q["rect"][1]) > 0.9)
        if best is None or votes > best[0]:
            best = (votes, p)
    p = best[1]
    x, y = p["rect"][:2]
    return art.crop((x, y, x + W, y + H)).load(), p


def _same(a, ax, ay, b, bx, by):
    pa, pb = a.load(), b.load()
    n = hit = 0
    for v in ROWS:
        for u in COLS:
            if 0 <= ax + u < a.size[0] and 0 <= ay + v < a.size[1] and 0 <= bx + u < b.size[0] and 0 <= by + v < b.size[1]:
                n += 1
                hit += pa[ax + u, ay + v] == pb[bx + u, by + v]
    return hit / n if n else 0


def fix(map_id, tpl, sample):
    art = Image.open(os.path.join(MAPS, map_id + ".png")).convert("RGB")
    px = art.load()
    path = os.path.join(MAPS, map_id + "_props.json")
    data = json.load(open(path))
    props = data["props"]
    trees = [p for p in props if p.get("shape") == "tree"]
    w, h = art.size
    # The trunk column (rows 56-70 of column 24) is what has to match exactly
    # most of the time; then the whole strip, loosely (a neighbour's roots
    # and shadows overlap it).
    trunk = [(24, v) for v in ROWS]
    found = []
    for y in range(-60, h - 60):
        for x in range(-30, w - 20):
            ok = sum(1 for u, v in trunk if 0 <= x + u < w and 0 <= y + v < h and px[x + u, y + v] == tpl[u, v])
            if ok < 12:
                continue
            n = hit = 0
            for v in ROWS:
                for u in COLS:
                    if 0 <= x + u < w and 0 <= y + v < h:
                        n += 1
                        hit += px[x + u, y + v] == tpl[u, v]
            if n and hit / n >= 0.6:
                found.append((x, y))
    added = []
    for x, y in found:
        if any(abs(t["rect"][0] - x) <= 3 and abs(t["rect"][1] - y) <= 3 for t in trees + added):
            continue
        p = {"kind": "tree", "rect": [x, y, W, H], "base": y + 71, "foot": [x + 18, y + 64, 12, 7],
             "name": "tree", "shape": "tree"}
        if "poly" in sample:
            p["poly"], p["poly_for"] = sample["poly"], sample["poly_for"]
        added.append(p)
    mask_path = os.path.join(MAPS, map_id + "_mask.png")
    mask = Image.open(mask_path).convert("L")
    every = trees + added
    feet = [p["foot"] for p in every]
    stumps = []
    for bx, by in bare_trunks(art, mask):
        if not any(f[0] - 2 <= bx <= f[0] + f[2] + 2 and f[1] - 2 <= by <= f[1] + f[3] + 4 for f in feet):
            stumps.append({"foot": [bx - 6, by - 5, 12, 7], "base": by + 2})
    if not added and not stumps:
        print(map_id, "nothing to add")
        return
    for p in added + stumps:
        f = p["foot"]
        mask.paste(0, (f[0], f[1], f[0] + f[2], f[1] + f[3]))
    added += stumps
    every += stumps
    for a in every:  # close_tree_rows, for the pairs with a new tree in them
        for b in every:
            if a is b or (a not in added and b not in added):
                continue
            fa, fb = a["foot"], b["foot"]
            if abs(a["base"] - b["base"]) > 6 or not 0 < fb[0] - fa[0] <= 56:
                continue
            top, bottom = max(fa[1], fb[1]), min(fa[1] + fa[3], fb[1] + fb[3])
            if bottom > top:
                mask.paste(0, (fa[0] + fa[2], top, fb[0], bottom))
    mask.save(mask_path)
    props += [p for p in added if "rect" in p]
    with open(path, "w") as f:  # one prop per line, like make_maps.py writes it
        f.write('{"props": [\n' + ",\n".join(json.dumps(p, separators=(",", ":")) for p in props) + "\n]}\n")
    print(map_id, "added trees", [p["rect"][:2] for p in added if "rect" in p],
          "trunks", [p["foot"][:2] for p in stumps])


TRUNK = {(248, 216, 64), (224, 184, 64)}


def bare_trunks(art, mask):
    """Bottoms of the trunks you can stand on: pieces of trunk colour the size
    and shape of a tree's trunk (11-15 wide, 14-18 tall) on walkable ground."""
    w, h = art.size
    px, mp = art.load(), mask.load()
    seen = set()
    out = []
    for y in range(h):
        for x in range(w):
            if (x, y) in seen or px[x, y] not in TRUNK:
                continue
            q = deque([(x, y)])
            seen.add((x, y))
            cells = []
            while q:
                cx, cy = q.popleft()
                cells.append((cx, cy))
                for n in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= n[0] < w and 0 <= n[1] < h and n not in seen and px[n] in TRUNK:
                        seen.add(n)
                        q.append(n)
            xs = [c[0] for c in cells]
            ys = [c[1] for c in cells]
            if not (60 <= len(cells) <= 110 and 11 <= max(xs) - min(xs) + 1 <= 15 and 14 <= max(ys) - min(ys) + 1 <= 18):
                continue
            by = max(ys)
            bx = sorted(c[0] for c in cells if c[1] >= by - 2)
            bx = bx[len(bx) // 2]
            if mp[bx, by - 1] > 128:
                out.append((bx, by))
    return out


if __name__ == "__main__":
    tpl, sample = template()
    for m in sys.argv[1:] or DEFAULT:
        fix(m, tpl, sample)
