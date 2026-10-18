"""Cuts the Teehee Ruins' puzzle pieces (game/scripts/dungeon.gd) out of the
Superstar Saga object sheets into game/assets/dungeon/:

  rock.png    a hammer rock and the frames of it breaking (a strip of 5)
  switch.png  a switch: off (X) and on (O), a strip of 2
  gate.png    crossed planks barring a way
  lock.png    a stone face that opens for a Ruins Key
  block.png   a ? block (holds a key) and the block once hit, a strip of 2
  prize.png   the big gold block at the end of the ruins

Usage: python3 tools/make_dungeon.py "<path to Mario&LuigiMMO folder>"
"""
import os
import sys

from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "assets", "dungeon")
_MISC = "MISC UI AND MORE/Game Boy Advance - Mario & Luigi_ Superstar Saga - Miscellaneous - "
OBJECTS = _MISC + "Overworld Objects.png"
BLOCKS = _MISC + "Blocks & Platforms.png"


def cut(sheet, box):
    """The sprite in box, its background (the sheet's top left colour) made
    clear and trimmed away."""
    bg = sheet.getpixel((0, 0))[:3]
    im = sheet.crop(box).convert("RGBA")
    px = im.load()
    for y in range(im.size[1]):
        for x in range(im.size[0]):
            if px[x, y][:3] == bg:
                px[x, y] = (0, 0, 0, 0)
    return im.crop(im.getbbox())


def clear_edges(im, colour):
    """Makes `colour` clear where it touches the picture's edge (a backdrop
    drawn behind a sprite on the sheet)."""
    px = im.load()
    w, h = im.size
    todo = [(x, y) for x in range(w) for y in (0, h - 1)] + [(x, y) for y in range(h) for x in (0, w - 1)]
    while todo:
        x, y = todo.pop()
        if 0 <= x < w and 0 <= y < h and px[x, y][:3] == colour and px[x, y][3]:
            px[x, y] = (0, 0, 0, 0)
            todo += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    return im.crop(im.getbbox())


def strip(frames):
    """Frames side by side in cells of the biggest frame, feet on the bottom row."""
    w = max(f.size[0] for f in frames)
    h = max(f.size[1] for f in frames)
    out = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        out.paste(f, (i * w + (w - f.size[0]) // 2, h - f.size[1]))
    return out


def frames_in(sheet, box):
    """The separate sprites in a row (split on clear columns)."""
    row = cut(sheet, box)
    a = row.split()[3].load()
    cols = [any(a[x, y] for y in range(row.size[1])) for x in range(row.size[0])]
    out, start = [], None
    for x, used in enumerate(cols + [False]):
        if used and start is None:
            start = x
        elif not used and start is not None:
            f = row.crop((start, 0, x, row.size[1]))
            out.append(f.crop(f.getbbox()))
            start = None
    return out


if __name__ == "__main__":
    root = sys.argv[1]
    objects = Image.open(os.path.join(root, OBJECTS)).convert("RGB")
    blocks = Image.open(os.path.join(root, BLOCKS)).convert("RGB")
    os.makedirs(OUT, exist_ok=True)
    rock = frames_in(objects, (0, 0, 215, 48))[:5]
    strip(rock).save(os.path.join(OUT, "rock.png"))
    switches = frames_in(objects, (0, 1210, 280, 1280))
    strip([switches[0], switches[4]]).save(os.path.join(OUT, "switch.png"))
    cut(objects, (275, 1640, 340, 1680)).save(os.path.join(OUT, "gate.png"))
    clear_edges(cut(objects, (278, 1708, 328, 1782)), (90, 89, 90)).save(os.path.join(OUT, "lock.png"))
    strip([cut(blocks, (31, 4, 56, 34)), cut(blocks, (48, 38, 68, 64))]).save(os.path.join(OUT, "block.png"))
    cut(blocks, (93, 264, 145, 316)).save(os.path.join(OUT, "prize.png"))
    for name in sorted(os.listdir(OUT)):
        if name.endswith(".png"):
            print(name, Image.open(os.path.join(OUT, name)).size)
