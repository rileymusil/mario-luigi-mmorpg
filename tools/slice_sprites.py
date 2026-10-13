"""Cuts walk cycles out of Spriters Resource sheets into the game's sheet format.

Each output sheet has 3 rows (down, right, up) of equal-size cells, feet at the
bottom-centre of each cell. Left is drawn by mirroring the right row.
Put the printed frame count in the CHARACTERS table in game/scripts/game.gd.

Usage: python3 tools/slice_sprites.py "<path to Mario&LuigiMMO folder>"
Add a character by adding an entry to CHARACTERS with the pixel box of each
row on its source sheet (left, top, right, bottom).
"""
import os
import sys

from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "game", "assets", "characters")

# rows: boxes for the down / side / up walk rows. side_faces_left: the side row
# looks left on the source sheet and gets mirrored.
CHARACTERS = {
    "mario": {"sheet": "Playable Characters GOOD/Game Boy Advance - Mario & Luigi_ Superstar Saga - Playable Characters - Mario (Overworld).png",
              "rows": [(0, 8, 176, 48), (0, 86, 176, 126), (0, 169, 176, 209)], "side_faces_left": False},
    "luigi": {"sheet": "Playable Characters GOOD/Game Boy Advance - Mario & Luigi_ Superstar Saga - Playable Characters - Luigi (Overworld).png",
              "rows": None, "side_faces_left": False},  # rows found automatically (same layout as Mario)
    "peach": {"sheet": "Playable Characters GOOD/Game Boy Advance - Mario & Luigi_ Superstar Saga - Non-Playable Characters - Princess Peach.png",
              "rows": [(0, 2, 215, 43), (0, 46, 215, 88), (0, 90, 215, 131)], "order": [0, 2, 1], "side_faces_left": False},
    "bowser": {"sheet": "Playable Characters EVIL/Game Boy Advance - Mario & Luigi_ Superstar Saga - Non-Playable Characters - Bowser (USA).png",
               "rows": [(0, 28, 260, 76), (0, 86, 260, 132), (0, 142, 260, 190)], "side_faces_left": True},
    "goomba": {"sheet": "Enemies/Game Boy Advance - Mario & Luigi_ Superstar Saga - Enemies - Goomba.png",
               "rows": [(0, 202, 185, 232), (0, 232, 185, 260), (0, 260, 185, 290)], "side_faces_left": False},
    "toad": {"sheet": "Partners GOOD/Game Boy Advance - Mario & Luigi_ Superstar Saga - Non-Playable Characters - Toad.png",
             "rows": None, "side_faces_left": True},
    "beanie": {"sheet": "Enemies/Game Boy Advance - Mario & Luigi_ Superstar Saga - Enemies - Beanie & Gold Beanie.png",
               "rows": [(0, 188, 172, 216), (0, 222, 172, 250), (0, 255, 172, 284)], "side_faces_left": True},
}


def bands(mask):
    out, start = [], None
    for i, v in enumerate(mask):
        if v and start is None:
            start = i
        if not v and start is not None:
            out.append((start, i))
            start = None
    if start is not None:
        out.append((start, len(mask)))
    return out


def frames_in(im, bg, box):
    x0, y0, x1, y1 = box
    px = im.load()
    fg = lambda x, y: px[x, y][3] > 0 and px[x, y][:3] != bg
    rows = [b for b in bands([any(fg(x, y) for x in range(x0, x1)) for y in range(y0, y1)]) if b[1] - b[0] > 6]
    ya, yb = y0 + rows[0][0], y0 + rows[-1][1]
    cols = [c for c in bands([any(fg(x, y) for y in range(ya, yb)) for x in range(x0, x1)]) if c[1] - c[0] > 4]
    frames = []
    for a, b in cols:
        fr = im.crop((x0 + a, ya, x0 + b, yb))
        p = fr.load()
        for y in range(fr.size[1]):
            for x in range(fr.size[0]):
                if p[x, y][:3] == bg:
                    p[x, y] = (0, 0, 0, 0)
        frames.append(fr.crop(fr.getbbox()) if fr.getbbox() else fr)
    return frames


def auto_rows(im, bg, xmax=176):
    px = im.load()
    mask = [any(px[x, y][:3] != bg for x in range(xmax)) for y in range(min(im.size[1], 400))]
    rows = [b for b in bands(mask) if b[1] - b[0] > 10][:5]
    return [(0, rows[i][0], xmax, rows[i][1]) for i in (0, 2, 4)]


def build(name, cfg, root):
    im = Image.open(os.path.join(root, cfg["sheet"])).convert("RGBA")
    bg = max(im.getcolors(1 << 24))[1][:3]  # most common colour = background
    boxes = cfg["rows"] or auto_rows(im, bg)
    rows = [frames_in(im, bg, b) for b in boxes]
    if "order" in cfg:
        rows = [rows[i] for i in cfg["order"]]
    if cfg["side_faces_left"]:
        rows[1] = [f.transpose(Image.FLIP_LEFT_RIGHT) for f in rows[1]]
    n = max(len(r) for r in rows)
    cw = max(f.size[0] for r in rows for f in r) + 2
    ch = max(f.size[1] for r in rows for f in r) + 2
    sheet = Image.new("RGBA", (cw * n, ch * 3), (0, 0, 0, 0))
    for ri, r in enumerate(rows):
        for ci in range(n):
            f = r[ci % len(r)]
            sheet.paste(f, (ci * cw + (cw - f.size[0]) // 2, ri * ch + ch - f.size[1]), f)
    os.makedirs(OUT, exist_ok=True)
    sheet.save(os.path.join(OUT, name + ".png"))
    print(name, [len(r) for r in rows], (cw, ch))


if __name__ == "__main__":
    root = sys.argv[1]
    for name, cfg in CHARACTERS.items():
        if len(sys.argv) > 2 and name not in sys.argv[2:]:
            continue
        build(name, cfg, root)
