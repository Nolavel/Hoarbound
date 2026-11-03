"""Procedural chunky knit textures for Henry's sweater: stockinette for the body and sleeves, 2x2 rib for
the turtleneck. Each stitch is a pair of slanted yarn loops (the knit "V"); fibre noise is added, and
albedo, tangent-space normal and ORM (glTF: AO in R, roughness in G, metallic in B) come from one height map.
Run: python3 tools/blender/make_knit_textures.py   (writes assets/characters/gear/knit_*.png)
"""
import os

import numpy as np
from PIL import Image

OUT = "assets/characters/gear"
SIZE = 1024
## Stitches across and down one tile (seamless), and the yarn colour (oatmeal wool).
COLUMNS = 16
ROWS = 20
YARN = np.array([0.80, 0.72, 0.58])
## How strongly the height map bends the normals, and roughness of wool.
NORMAL_STRENGTH = 6.0
ROUGHNESS = 0.92


def loops(u, v):
	"""Height of one stitch cell (u, v in 0..1, v down): the knit "V" of two long yarn grains leaning in
	towards the bottom, each reaching into the rows above and below (taken from the neighbours too)."""
	h = np.zeros_like(u)
	for dv in (-1.0, 0.0, 1.0):
		for side in (-1.0, 1.0):
			## Left grain top-left to bottom-centre, right grain mirrored.
			cx = 0.5 + side * 0.22
			du = u - cx
			dw = v - 0.5 - dv
			a = side * 0.45
			x = du * np.cos(a) + dw * np.sin(a)
			y = -du * np.sin(a) + dw * np.cos(a)
			r = (x / 0.19) ** 2 + (y / 0.62) ** 2
			h = np.maximum(h, np.clip(1.0 - r, 0.0, 1.0) ** 0.5)
	return h


def fibre(rng, shape, scale):
	"""Tileable fibre noise: random phases of a few periodic waves."""
	yy, xx = np.mgrid[0:shape[0], 0:shape[1]] / shape[0]
	n = np.zeros(shape)
	for _ in range(24):
		kx, ky = rng.integers(8, 64, 2) * scale
		n += np.sin(2 * np.pi * (kx * xx + ky * yy) + rng.random() * 6.28) / 24
	return n


def height_map(rib):
	yy, xx = np.mgrid[0:SIZE, 0:SIZE] / SIZE
	cols = COLUMNS if not rib else COLUMNS
	u = (xx * cols) % 1.0
	v = (yy * ROWS) % 1.0
	h = loops(u, v)
	if rib:
		## 2x2 rib: two knit columns raised, two purl columns sunk.
		col = np.floor(xx * cols).astype(int) % 4
		h = np.where(col < 2, h * 1.0 + 0.15, h * 0.35)
	rng = np.random.default_rng(7 if rib else 3)
	h = h + 0.08 * fibre(rng, h.shape, 1)
	return (h - h.min()) / (h.max() - h.min())


def normal_from(h):
	dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5 * NORMAL_STRENGTH
	dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5 * NORMAL_STRENGTH
	n = np.dstack((-dx, dy, np.ones_like(h)))
	n /= np.linalg.norm(n, axis=2, keepdims=True)
	return ((n * 0.5 + 0.5) * 255).astype(np.uint8)


def write(name, rib):
	h = height_map(rib)
	shade = 0.55 + 0.45 * h
	albedo = np.clip(YARN[None, None, :] * shade[..., None], 0.0, 1.0)
	Image.fromarray((albedo ** (1 / 2.2) * 255).astype(np.uint8)).save(os.path.join(OUT, "knit_%s_albedo.png" % name))
	Image.fromarray(normal_from(h)).save(os.path.join(OUT, "knit_%s_normal.png" % name))
	orm = np.dstack((0.6 + 0.4 * h, np.full_like(h, ROUGHNESS), np.zeros_like(h)))
	Image.fromarray((orm * 255).astype(np.uint8)).save(os.path.join(OUT, "knit_%s_orm.png" % name))


if __name__ == "__main__":
	write("body", False)
	write("rib", True)
	print("knit textures written to", OUT)
