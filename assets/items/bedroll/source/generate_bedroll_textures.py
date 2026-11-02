"""Painted, spatially conditioned textile maps for the one-sheet bedroll.

Marks follow wear causes (edges, seams, handling and pressure), rather than
placing strokes uniformly over the UV sheet. Fixed seed makes rebuilds stable.
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parents[1] / "textures"
OUT.mkdir(parents=True, exist_ok=True)
W, H = 768, 1536
rng = np.random.default_rng(727)
u, v = np.meshgrid((np.arange(W) + .5) / W, 1 - (np.arange(H) + .5) / H)


def field(w, h):
    image = Image.fromarray(rng.integers(0, 256, (h, w), dtype=np.uint8))
    return np.asarray(image.resize((W, H), Image.Resampling.BICUBIC), dtype=np.float32) / 255 - .5


def oval(x, y, rx, ry):
    return np.exp(-2.7 * (((u - x) / rx) ** 2 + ((v - y) / ry) ** 2))


def smooth(a, b, value):
    t = np.clip((value - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


coarse = field(9, 13)
medium = field(35, 56)
fine = field(190, 340)
edge_dist = np.minimum.reduce((u, 1 - u, v, 1 - v))
edge_wear = (1 - smooth(.018, .075, edge_dist)) * (.55 + .45 * smooth(-.28, .25, medium))
seam_near = np.zeros_like(u)
for seam in (.2, .4, .6, .8):
    seam_near = np.maximum(seam_near, np.exp(-((v - seam) / .014) ** 2))

# Major colour masses stay low contrast and follow handled/abraded regions.
burgundy = .65 * oval(.29, .78, .49, .35) + .50 * oval(.82, .26, .40, .30)
smoke = .72 * oval(.82, .73, .32, .24) + .61 * oval(.19, .17, .37, .25)
shade = coarse * 8 + medium * 2.4
top = np.empty((H, W, 3), dtype=np.float32)
for channel, base in enumerate((60, 49, 44)):
    top[:, :, channel] = base + shade
top += burgundy[:, :, None] * np.array((21, -3, 12), dtype=np.float32)
top += smoke[:, :, None] * np.array((7, 11, 13), dtype=np.float32)
top -= seam_near[:, :, None] * np.array((8, 7, 6), dtype=np.float32)

# The underside is graphite brown; broad patches suggest older damp fabric.
underside = np.empty_like(top)
for channel, base in enumerate((58, 51, 48)):
    underside[:, :, channel] = base + coarse * 7 + medium * 1.8
underside += (.95 * oval(.26, .62, .48, .40))[:, :, None] * np.array((25, -3, 13))
underside += (.95 * oval(.79, .79, .40, .28))[:, :, None] * np.array((8, 17, 21))
# Two broad rubbed areas sit on the final outer wrap, beside the straps.
outside_rub = .82 * oval(.25, .83, .14, .10) + .69 * oval(.75, .91, .12, .07)
underside += outside_rub[:, :, None] * np.array((19, 18, 19))
underside -= seam_near[:, :, None] * np.array((5, 5, 5))

# Sparse hand-placed rubs break the otherwise smooth outer wrap. They have
# directions and locations tied to handling rather than random screen noise.
def scuffs(rgb, paths):
    base = Image.fromarray(np.uint8(np.clip(rgb, 0, 255))).convert("RGBA")
    overlay = Image.new("RGBA", (W, H))
    brush = ImageDraw.Draw(overlay)
    for points, width, alpha in paths:
        brush.line([(round(x*W), round((1-y)*H)) for x,y in points],
                   fill=(138, 126, 121, alpha), width=width, joint="curve")
    return np.asarray(Image.alpha_composite(base, overlay).convert("RGB"), dtype=np.float32)

top = scuffs(top, [
    ([(.025,.81),(.060,.80),(.091,.786)],5,43),
    ([(.096,.79),(.135,.777)],3,35),
    ([(.89,.36),(.935,.34),(.965,.333)],4,33),
    ([(.15,.22),(.19,.213),(.23,.208)],3,30),
    ([(.75,.61),(.80,.604),(.85,.594)],3,26),
])
underside = scuffs(underside, [
    ([(.16,.85),(.21,.846),(.27,.833)],5,64),
    ([(.23,.863),(.30,.852),(.35,.842)],3,52),
    ([(.32,.822),(.38,.818)],3,42),
    ([(.66,.94),(.71,.936),(.77,.926)],5,58),
    ([(.72,.901),(.79,.893),(.84,.884)],3,42),
    ([(.85,.90),(.90,.889)],3,35),
    ([(.08,.69),(.13,.682),(.17,.677)],4,37),
    ([(.91,.72),(.95,.708)],3,32),
])

# Abrasion has causes: binding, stitch channels, two ground-contact zones.
contact = .34 * oval(.23, .14, .21, .11) + .40 * oval(.74, .82, .20, .13)
handling = .22 * oval(.16, .53, .17, .13) + .24 * oval(.84, .47, .14, .14)
anchor = .66 * edge_wear + .13 * seam_near + contact + handling
broken = smooth(.01, .30, medium + .06 * fine)
wear = np.clip(anchor * broken * 105, 0, 115)

# Broad dents in the cloth; their centre coordinates match the mesh.
indent = (.68 * oval(.29, .69, .13, .10)
          + .55 * oval(.74, .35, .11, .09)
          + .47 * oval(.53, .51, .16, .07)
          + .25 * seam_near)
indent = np.clip(indent * (1 + .13 * medium), 0, 1)

# Ordered coarse weave only affects the close normal; it is not a grunge mask.
weave = np.sin(2 * np.pi * (175*u + .12*np.sin(7*v))) * np.sin(2 * np.pi * 315*v)
fiber_height = 128 + 38 * weave

# A few short, frayed splits only where the textile is also abraded.
split = Image.new("L", (W, H), 0)
draw = ImageDraw.Draw(split)
def point(x, y):
    return (round(x * W), round((1 - y) * H))
for path in (
    ((.080, .768), (.093, .754), (.109, .750), (.118, .735)),
    ((.823, .303), (.811, .290), (.793, .285), (.781, .271)),
    ((.462, .518), (.472, .511), (.467, .497)),
):
    draw.line([point(*p) for p in path], fill=130, width=3)
split = split.filter(ImageFilter.GaussianBlur(.65))

def save(name, data):
    image = Image.fromarray(np.uint8(np.clip(data, 0, 255)))
    image.save(OUT / name, optimize=True)
    print(OUT / name)

save("bedroll_top_color.png", top)
save("bedroll_bottom_color.png", underside)
save("bedroll_wear_mask.png", wear)
save("bedroll_indent_mask.png", (1 - indent) * 255)
save("bedroll_fiber_height.png", fiber_height)
split.save(OUT / "bedroll_split_mask.png", optimize=True)
print(OUT / "bedroll_split_mask.png")
