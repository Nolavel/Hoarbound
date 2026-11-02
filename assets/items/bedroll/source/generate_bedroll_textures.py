"""Deterministic, authored colour masses and wear masks for the bedroll.

The low-resolution painting canvas keeps marks broad at gameplay distance.
Only the marked abrasion and split clusters use seeded variation.
"""
from pathlib import Path
import random

from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parents[1] / "textures"
OUT.mkdir(parents=True, exist_ok=True)
W, H = 512, 1024
rng = random.Random(727)


def xy(u, v):
    return round(u * W), round((1 - v) * H)


def shape(draw, points, color):
    draw.polygon([xy(u, v) for u, v in points], fill=color)


top = Image.new("RGB", (W, H), (79, 88, 61))
td = ImageDraw.Draw(top, "RGBA")

# Quiet painted masses, aligned with the long axis of the padded sheet.
shape(td, [(0, .09), (.49, .10), (.47, .31), (.05, .37)], (125, 111, 72, 61))
shape(td, [(.42, .44), (1, .47), (1, .67), (.56, .64)], (42, 55, 45, 59))
shape(td, [(.07, .73), (.53, .70), (.51, .91), (.02, .94)], (128, 121, 82, 45))
shape(td, [(.69, .14), (.96, .17), (.91, .38), (.74, .33)], (132, 113, 76, 57))
shape(td, [(.16, .79), (.38, .80), (.40, .91), (.13, .90)], (49, 58, 49, 123))
for v in (.2,.4,.6,.8):
    td.line([xy(0,v),xy(.28,v+.002),xy(.65,v-.002),xy(1,v)],
            fill=(36,48,39,64),width=3)

# Field repairs have broken, stitched outlines instead of flat rectangles.
for x0, y0, x1, y1, color in [
    (.15, .79, .39, .91, (55, 65, 55, 210)),
    (.70, .17, .91, .30, (137, 119, 77, 154)),
]:
    corners = [(x0, y0 + .009), (x0 + .022, y0), (x1 - .015, y0 + .002),
               (x1, y0 + .014), (x1 - .008, y1 - .008),
               (x1 - .035, y1), (x0 + .012, y1 - .004)]
    shape(td, corners, color)
    for j in range(8):
        u = x0 + .017 + (j + .5) * (x1 - x0 - .034) / 8
        a, b = xy(u, y0 - .006), xy(u + .003, y0 + .006)
        td.line((a, b), fill=(180, 163, 107, 135), width=2)

bottom = Image.new("RGB", (W, H), (59, 68, 56))
bd = ImageDraw.Draw(bottom, "RGBA")
shape(bd, [(0, .13), (.53, .18), (.57, .39), (.02, .38)], (99, 104, 73, 50))
shape(bd, [(.37, .51), (1, .46), (1, .72), (.44, .68)], (31, 48, 43, 64))
shape(bd, [(.03, .80), (.78, .76), (.93, .93), (.04, .95)], (113, 107, 71, 43))
shape(bd, [(.04, .87), (.35, .84), (.58, .90), (.56, .98), (.07, .98)], (130, 113, 79, 46))
shape(bd, [(.51, .84), (.92, .80), (.98, .91), (.78, .97)], (27, 42, 37, 65))
for v in (.2,.4,.6,.8):
    bd.line([xy(0,v),xy(.34,v-.002),xy(.7,v+.002),xy(1,v)],
            fill=(26,38,34,63),width=3)

wear = Image.new("L", (W, H), 0)
wd = ImageDraw.Draw(wear)

# Wear concentrates on handled edges and two ground-contact areas.
for side in (0, 1):
    for y in (.06, .16, .29, .42, .61, .78, .89):
        span = rng.uniform(.035, .105)
        yy = y + rng.uniform(-.018, .018)
        edge_u = rng.uniform(.004, .020) if side == 0 else rng.uniform(.980, .996)
        points = [(edge_u, yy-span/2), (edge_u+(.024 if side==0 else -.024), yy-span*.22),
                  (edge_u+(.012 if side==0 else -.012), yy+span*.43), (edge_u, yy+span/2)]
        shape(wd, points, rng.randint(75, 135))

for u, v, dx, dy, count in [(.16, .78, .22, .10, 11), (.79, .27, .19, .10, 12),
                            (.51, .53, .11, .29, 11), (.22, .08, .20, .05, 7),
                            (.36, .89, .30, .10, 13), (.77, .92, .19, .08, 10)]:
    for _ in range(count):
        uu=u+rng.uniform(-dx/2, dx/2)
        vv=v+rng.uniform(-dy/2, dy/2)
        length=rng.uniform(.023,.095)
        p1=xy(uu,vv);p2=xy(uu+length, vv+rng.uniform(-.006,.006))
        wd.line((p1,p2), fill=rng.randint(66, 155), width=rng.randint(2,8))

# In cloth these read as a few frayed splits, not a uniform crackle filter.
cracks = Image.new("L", (W, H), 0)
cd = ImageDraw.Draw(cracks)
for route in [
    [(.10,.76),(.13,.75),(.15,.73),(.18,.735),(.20,.72)],
    [(.82,.31),(.80,.30),(.78,.285),(.76,.28),(.75,.255)],
    [(.48,.56),(.50,.54),(.49,.52),(.51,.505)],
    [(.91,.88),(.88,.87),(.85,.862)],
]:
    cd.line([xy(*p) for p in route], fill=182, width=3)
    u,v=route[len(route)//2]
    cd.line([xy(u,v),xy(u+rng.uniform(-.018,.018),v-.025)],fill=116,width=2)

# Soft low-resolution brush edges, then a little defined split contrast.
wear=wear.filter(ImageFilter.GaussianBlur(.8))
for name,img in [
    ("bedroll_top_color.png",top),
    ("bedroll_bottom_color.png",bottom),
    ("bedroll_wear_mask.png",wear),
    ("bedroll_split_mask.png",cracks),
]:
    dest=OUT/name
    img.resize((1024,2048), Image.Resampling.BICUBIC).save(dest,optimize=True)
    print(dest)
