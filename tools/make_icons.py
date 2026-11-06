"""Draws the pack's own addon icons (the ones the game's AddOns list shows).

  python -I tools/make_icons.py

- addons/ForeverUI/Media/Icon.tga: the minimap button's look, an F on the
  dark flat square with a 1px black edge.
- addons/ForeverUI_XPBar/Media/Icon.tga: the XP bar: blue XP, the quests'
  XP in yellow, the rest dark.

Our own art, drawn here from rectangles (no font, nothing of Blizzard's).
Drawn four times larger and scaled down, for soft edges.
"""
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZE = 64
UP = 4                       # drawn this many times larger

GROUND = (16, 16, 18, 255)   # the buttons' 0.06 ground
EDGE = (0, 0, 0, 255)
GOLD = (255, 199, 38, 255)   # the F's "Gold" color
BLUE = (51, 140, 255, 255)
YELLOW = (255, 199, 38, 255)
TRACK = (40, 40, 46, 255)


def canvas():
    s = SIZE * UP
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, s - 1, s - 1], fill=EDGE)
    e = 2 * UP
    d.rectangle([e, e, s - 1 - e, s - 1 - e], fill=GROUND)
    return img, d


def box(d, x0, y0, x1, y1, color):
    """A rectangle in 64-pixel units."""
    d.rectangle([x0 * UP, y0 * UP, x1 * UP - 1, y1 * UP - 1], fill=color)


def save(img, rel):
    path = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.resize((SIZE, SIZE), Image.LANCZOS).save(path)
    print("%s (%dx%d)" % (rel, SIZE, SIZE))


def foreverui():
    img, d = canvas()
    # the F: a stem, the top bar, the middle bar; with a 2px black outline
    parts = [(20, 12, 29, 52), (20, 12, 46, 21), (20, 28, 41, 36)]
    for x0, y0, x1, y1 in parts:
        box(d, x0 - 2, y0 - 2, x1 + 2, y1 + 2, EDGE)
    for x0, y0, x1, y1 in parts:
        box(d, x0, y0, x1, y1, GOLD)
    save(img, os.path.join("addons", "ForeverUI", "Media", "Icon.tga"))


def xpbar():
    img, d = canvas()
    # the bar, with its black edge, a third of the way
    box(d, 8, 24, 56, 40, EDGE)
    box(d, 10, 26, 54, 38, TRACK)
    box(d, 10, 26, 32, 38, BLUE)
    box(d, 32, 26, 42, 38, YELLOW)
    # the level's ticks above and below
    for x in (18, 28, 38, 48):
        box(d, x, 18, x + 2, 22, (120, 120, 130, 255))
        box(d, x, 42, x + 2, 46, (120, 120, 130, 255))
    save(img, os.path.join("addons", "ForeverUI_XPBar", "Media", "Icon.tga"))


if __name__ == "__main__":
    foreverui()
    xpbar()
