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

# rows: boxes for the down / side / up walk rows (a box may repeat when a sheet
# only has one direction). side_faces_left: the side row looks left on the
# source sheet and gets mirrored. Optional: "bg" overrides the background colour,
# "strip" lists extra colours to clear (drawn-on shadows), "flood" clears only
# background that touches the frame edge (for white sheets with white sprites).
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
    "waluigi": {"sheet": "Playable Characters GOOD/Custom _ Edited - Mario Customs - Waluigi - Waluigi (Overworld, Mario & Luigi_ Superstar Saga-Style).png",
                "rows": [(0, 10, 126, 56), (0, 61, 126, 107), (126, 10, 248, 56)], "side_faces_left": True},
    "rosalina": {"sheet": "Playable Characters GOOD/Custom _ Edited - Mario Customs - Rosalina & Luma - Rosalina (Mario & Luigi_ Superstar Saga-Style).png",
                 "rows": [(28, 19, 232, 61), (32, 105, 232, 149), (34, 149, 232, 192)], "side_faces_left": True,
                 "bg": (255, 255, 255), "flood": True},
    "toadette": {"sheet": "Playable Characters GOOD/Custom _ Edited - Mario Customs - Toadette & Peachette - Toadette (Mario & Luigi_ Superstar Saga-Style).png",
                 "rows": [(0, 76, 150, 101), (0, 27, 183, 52), (0, 52, 183, 76)], "side_faces_left": True, "flood": True},
    "bowser_jr": {"sheet": "Playable Characters EVIL/Custom _ Edited - Mario Customs - Bowser Jr. - Bowser Jr. (Mario & Luigi_ Superstar Saga-Style).png",
                  "rows": [(278, 112, 313, 155), (372, 112, 405, 155), (313, 112, 343, 155)], "side_faces_left": True},
    "shadow_mario": {"sheet": "Playable Characters EVIL/Custom _ Edited - Mario Customs - Other Bosses - Shadow Mario (Mario & Luigi_ Superstar Saga-Style).png",
                     "rows": [(88, 240, 116, 281), (63, 240, 86, 281), (36, 240, 62, 281)], "side_faces_left": False},
    "pianta": {"sheet": "NPCs/Custom _ Edited - Mario Customs - Piantas - Piantas (Superstar Saga-Style).png",
               "rows": [(0, 196, 128, 240), (128, 196, 232, 240), (0, 196, 128, 240)], "side_faces_left": False},
    "galoomba": {"sheet": "Enemies/Custom _ Edited - Mario Customs - Goomba & Related Enemies - Galoomba (Mario & Luigi_ Superstar Saga-Style).png",
                 "rows": [(0, 150, 200, 172), (0, 235, 200, 257), (0, 176, 200, 198)], "side_faces_left": False},
    "koopa": {"sheet": "Enemies/Custom _ Edited - Mario Customs - Koopa Troopa & Related Enemies - Koopa Troopa (Mario & Luigi_ Superstar Saga-Style).png",
              "rows": [(0, 585, 140, 616), (0, 651, 140, 682), (0, 618, 140, 649)], "side_faces_left": False},
    "dry_bones": {"sheet": "Enemies/Custom _ Edited - Mario Customs - Dry Bones & Related Enemies - Dry Bones (Mario & Luigi_ Superstar Saga-Style).png",
                  "rows": [(0, 481, 130, 512), (0, 547, 130, 581), (0, 515, 130, 546)], "side_faces_left": False},
    "shy_guy": {"sheet": "Enemies/Custom _ Edited - Mario Customs - Shy Guy, Snifit & Related Enemies - Shy Guy (Mario & Luigi_ Superstar Saga-Style).png",
                "rows": [(0, 30, 175, 75)] * 3, "side_faces_left": True, "strip": [(84, 109, 142)]},
    "buzzy_beetle": {"sheet": "Enemies/Custom _ Edited - Mario Customs - Buzzy Beetle, Spiny & Related Enemies - Buzzy Beetle (Mario & Luigi_ Superstar Saga-Style).png",
                     "rows": [(0, 27, 220, 55)] * 3, "side_faces_left": True},
}

# Townsfolk you can talk to (the NPCS table in game.gd). They stand still, so a
# row may be a box around a single pose. The Beanbean Kingdom Residents sheet
# has one column per direction (left, front, back, right), so its boxes pick
# one pose each.
_NPC = "NPCs/Game Boy Advance - Mario & Luigi_ Superstar Saga - Non-Playable Characters - "
_RESIDENTS = _NPC + "Beanbean Kingdom Residents.png"
NPCS = {
    "bean_elder": {"sheet": _RESIDENTS, "rows": [(23, 2, 40, 28), (60, 2, 77, 28), (41, 2, 58, 28)], "side_faces_left": False},
    "bean_villager": {"sheet": _RESIDENTS, "rows": [(101, 2, 119, 36), (141, 2, 159, 36), (121, 2, 139, 36)], "side_faces_left": False},
    "bean_kid": {"sheet": _RESIDENTS, "rows": [(264, 2, 281, 36), (302, 2, 319, 36), (283, 2, 300, 36)], "side_faces_left": False},
    "bean_girl": {"sheet": _RESIDENTS, "rows": [(21, 180, 38, 211), (60, 180, 77, 211), (40, 180, 57, 211)], "side_faces_left": False},
    "bean_guard": {"sheet": _NPC + "Beanbean Guards.png",
                   "rows": [(0, 3, 226, 39), (0, 42, 180, 78), (0, 79, 226, 115)], "side_faces_left": True},
    "shopkeeper": {"sheet": "Maps/Game Boy Advance - Mario & Luigi_ Superstar Saga - Maps - Beanbean Castle Town Shop (Interior).png",
                   "rows": [(188, 116, 295, 153), (188, 44, 295, 82), (188, 153, 295, 190)], "side_faces_left": True, "flood": True},
    "toad_blue": {"sheet": _NPC + "Toads.png", "rows": [(0, 2, 176, 35), (0, 35, 176, 67), (0, 69, 176, 101)], "side_faces_left": True},
    "toadsworth": {"sheet": _NPC + "Toadsworth.png", "rows": [(0, 60, 145, 89), (0, 29, 145, 58), (0, 91, 145, 120)], "side_faces_left": True},
    "dr_toad": {"sheet": _NPC + "Dr. Toad.png", "rows": [(0, 4, 176, 35), (0, 75, 176, 106), (0, 40, 176, 71)],
                "side_faces_left": True, "flood": True},
    "lady_lima": {"sheet": _NPC + "Lady Lima.png", "rows": [(225, 48, 350, 85), (225, 86, 360, 123), (225, 12, 350, 49)],
                  "side_faces_left": False, "flood": True},
    "queen_bean": {"sheet": _NPC + "Queen Bean.png", "rows": [(3, 670, 54, 715), (423, 670, 464, 715), (213, 670, 264, 715)],
                   "side_faces_left": False},
    "koopa_troop": {"sheet": _NPC + "Koopa Troopas.png", "rows": [(0, 5, 212, 40), (0, 40, 212, 75), (0, 76, 212, 111)], "side_faces_left": False},
    "koopa_troop_red": {"sheet": _NPC + "Koopa Troopas.png", "rows": [(0, 117, 212, 152), (0, 152, 212, 187), (0, 188, 212, 223)],
                        "side_faces_left": False},
    "border_bro": {"sheet": _NPC + "Border Bros.png", "rows": [(12, 32, 128, 74), (12, 82, 146, 122), (130, 32, 250, 74)],
                   "side_faces_left": False, "flood": True},
    "hoohoo_villager": {"sheet": _NPC + "Hoohooligans.png", "rows": [(0, 104, 150, 142), (0, 67, 150, 103), (0, 29, 150, 67)],
                        "side_faces_left": False, "strip": [(80, 80, 80)]},
    "hoohoo_villager_b": {"sheet": _NPC + "Hoohooligans.png", "rows": [(150, 104, 295, 142), (150, 141, 295, 179), (150, 29, 295, 67)],
                          "side_faces_left": False, "strip": [(80, 80, 80)]},
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


def frames_in(im, bg, box, strip=(), flood=False):
    x0, y0, x1, y1 = box
    px = im.load()
    clear = {bg, *strip}
    fg = lambda x, y: px[x, y][3] > 0 and px[x, y][:3] not in clear
    rows = [b for b in bands([any(fg(x, y) for x in range(x0, x1)) for y in range(y0, y1)]) if b[1] - b[0] > 6]
    ya, yb = y0 + rows[0][0], y0 + rows[-1][1]
    cols = [c for c in bands([any(fg(x, y) for y in range(ya, yb)) for x in range(x0, x1)]) if c[1] - c[0] > 4]
    frames = []
    for a, b in cols:
        fr = im.crop((x0 + a, ya, x0 + b, yb))
        p = fr.load()
        if flood:  # only clear background touching the edges, keeps white caps/eyes
            w, h = fr.size
            todo = [(x, y) for x in range(w) for y in (0, h - 1)] + [(x, y) for y in range(h) for x in (0, w - 1)]
            while todo:
                x, y = todo.pop()
                if 0 <= x < w and 0 <= y < h and p[x, y][3] > 0 and p[x, y][:3] in clear:
                    p[x, y] = (0, 0, 0, 0)
                    todo += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
        else:
            for y in range(fr.size[1]):
                for x in range(fr.size[0]):
                    if p[x, y][:3] in clear:
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
    bg = tuple(cfg.get("bg") or max(im.getcolors(1 << 24))[1][:3])  # most common colour = background
    boxes = cfg["rows"] or auto_rows(im, bg)
    rows = [frames_in(im, bg, b, [tuple(c) for c in cfg.get("strip", ())], cfg.get("flood", False)) for b in boxes]
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
    for name, cfg in {**CHARACTERS, **NPCS}.items():
        if len(sys.argv) > 2 and name not in sys.argv[2:]:
            continue
        build(name, cfg, root)
