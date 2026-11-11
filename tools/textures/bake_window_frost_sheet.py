#!/usr/bin/env python3
"""Bakes the two tileable window-frost textures of frosted_glass.gdshader, both at 1 mm per pixel.

- frost_edge_strip.png (1024 x 384, tiles along x): fern-frost feathers grown up from a frame line on the
  bottom row. The shader lays it along each edge of a pane, so a pane of any size gets feathers of true size.
- frost_field.png (1024 x 1024, tiles both ways): rows of small feathers along scratches and wipe streaks,
  small fans from free specks, sparse hoar. The shader lays it over the pane in metres.

Channels of both: R crystal lines (rachis and barbs), G granular hoar, B unused, A smooth thickness
(blurred R + G), for relief-free thickness and melt order.

Scale follows K. Libbrecht's window-frost notes (branches of a few millimetres; scratches and streaks on the
glass guide where crystals nucleate). Deterministic for a given seed.

Usage: python3 tools/textures/bake_window_frost_sheet.py [out dir] [seed]
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SS = 3  # supersampling for line drawing


def tile_noise(h, w, cell, rng):
    """Smooth value noise in 0..1, periodic over (h, w), features about `cell` pixels wide."""
    gh, gw = max(1, h // cell), max(1, w // cell)
    grid = rng.random((gh, gw)).astype(np.float32)
    padded = np.pad(grid, 2, mode="wrap")
    scale_h, scale_w = h / gh, w / gw
    img = Image.fromarray((padded * 255).astype(np.uint8)).resize(
        (int(round((gw + 4) * scale_w)), int(round((gh + 4) * scale_h))), Image.BICUBIC)
    oy, ox = int(round(2 * scale_h)), int(round(2 * scale_w))
    return np.asarray(img, dtype=np.float32)[oy:oy + h, ox:ox + w] / 255.0


def tile_fbm(h, w, cell, rng, octaves=3):
    out = np.zeros((h, w), np.float32)
    amp, total = 0.5, 0.0
    for _ in range(octaves):
        out += tile_noise(h, w, max(cell, 2), rng) * amp
        total += amp
        amp *= 0.5
        cell //= 2
    return out / total


def tile_blur(arr, radius, wrap_y):
    """Gaussian blur that wraps along x, and along y when `wrap_y`."""
    pad = int(radius * 3) + 1
    padded = np.pad(arr, ((pad, pad) if wrap_y else (0, 0), (pad, pad)), mode="wrap")
    img = Image.fromarray((np.clip(padded, 0.0, 1.0) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(radius))
    out = np.asarray(img, dtype=np.float32) / 255.0
    return out[pad:-pad, pad:-pad] if wrap_y else out[:, pad:-pad]


class Canvas:
    """Line canvas that repeats strokes across its seams so the result tiles."""

    def __init__(self, w, h, wrap_y, rnd):
        self.w, self.h, self.wrap_y, self.rnd = w, h, wrap_y, rnd
        self.image = Image.new("L", (w * SS, h * SS), 0)
        self.draw = ImageDraw.Draw(self.image)

    def stroke(self, pts, value, width=1):
        for ox in (-self.w, 0, self.w):
            for oy in ((-self.h, 0, self.h) if self.wrap_y else (0,)):
                self.draw.line([((x + ox) * SS, (y + oy) * SS) for x, y in pts], fill=value, width=width)

    def plume(self, x, y, angle, length, depth=0):
        """One feather: a bent rachis with barbs that swell and taper, sometimes sprouting smaller feathers."""
        rnd = self.rnd
        step = 1.3
        count = max(4, int(length / step))
        bend = rnd.uniform(-0.9, 0.9) / count
        barb_gap = rnd.uniform(0.75, 1.15)  # each side gets one every other gap: barbs nearly touch
        barb_angle = math.radians(rnd.uniform(38.0, 58.0))
        fullness = rnd.uniform(0.22, 0.40)
        pts = [(x, y)]
        since_barb = 0.0
        side = 1
        for i in range(count):
            angle += bend + rnd.gauss(0.0, 0.012)
            x += math.cos(angle) * step
            y += math.sin(angle) * step
            pts.append((x, y))
            u = (i + 1) / count
            since_barb += step
            if since_barb >= barb_gap and u > 0.04:
                since_barb = 0.0
                side = -side
                reach = length * fullness * math.sin(math.pi * u ** 0.62) ** 0.8 * rnd.uniform(0.75, 1.1)
                if reach > 1.2:
                    a = angle + side * barb_angle
                    curl = -side * rnd.uniform(0.0, 0.5) / max(reach, 1.0)
                    bx, by = x, y
                    barb = [(bx, by)]
                    for j in range(max(2, int(reach / 1.5))):
                        a += curl * 1.5
                        bx += math.cos(a) * 1.5
                        by += math.sin(a) * 1.5
                        barb.append((bx, by))
                        # Barbules on the long barbs of big feathers.
                        if reach > 14.0 and j % 2 == 1:
                            # Uneven in angle and length, or neighbouring barbs weave a regular lattice.
                            for s in (-1, 1):
                                t = a + s * barb_angle * rnd.uniform(0.6, 1.4)
                                small = reach * 0.16 * (1.0 - j * 1.5 / reach) * rnd.uniform(0.3, 1.2)
                                if small > 0.8 and rnd.random() < 0.6:
                                    self.stroke([(bx, by), (bx + math.cos(t) * small, by + math.sin(t) * small)], 85)
                    self.stroke(barb, int(rnd.uniform(150, 235)), 2)
            if depth < 2 and length > 22.0 and 0.12 < u < 0.8 and rnd.random() < 0.035:
                self.plume(x, y, angle + rnd.choice((-1, 1)) * rnd.uniform(0.45, 1.05), length * rnd.uniform(0.35, 0.65), depth + 1)
        self.stroke(pts, 255, 3 if length > 30.0 else 2)

    def lines(self):
        return np.asarray(self.image.resize((self.w, self.h), Image.LANCZOS), dtype=np.float32) / 255.0


def pack(lines, hoar, wrap_y):
    body = np.clip(lines * 0.8 + hoar * 0.55, 0.0, 1.0)
    smooth = np.clip(tile_blur(body, 5.0, wrap_y) * 1.6, 0.0, 1.0)
    out = np.stack([lines, hoar, np.zeros_like(lines), smooth], axis=-1)
    return Image.fromarray((out * 255.0 + 0.5).astype(np.uint8), "RGBA")


def bake_edge(seed):
    """Feathers from the frame line (the bottom row) up; the top rows stay empty so edges never clip."""
    w, h = 1024, 384
    rnd = random.Random(seed)
    canvas = Canvas(w, h, False, rnd)
    pos = 0.0
    while pos < w:
        pos += rnd.uniform(0.4, 1.6) * 6.0
        length = 40.0 + 240.0 * rnd.random() ** 1.5
        canvas.plume(pos, h + 2.0, -math.pi / 2 + rnd.uniform(-1.0, 1.0), min(length, 250.0))
    lines = canvas.lines()
    rng = np.random.default_rng(seed)
    height = (h - 1 - np.arange(h, dtype=np.float32))[:, None] / h  # 0 on the frame line, 1 at the top
    clumps = tile_fbm(h, w, 64, rng)
    # Hoar packs the first centimetres off the frame and thins out with a ragged limit.
    density = np.clip(1.15 - height * 4.2 + (clumps - 0.5) * 0.9, 0.0, 1.0)
    grains = tile_fbm(h, w, 2, rng, 2)
    hoar = np.clip((grains - (0.74 - density * 0.46)) * 4.0, 0.0, 1.0)
    near = tile_blur(lines, 3.0, False)
    hoar = np.clip(hoar + np.clip(near * 2.2, 0.0, 1.0) * np.clip((grains - 0.42) * 5.0, 0.0, 1.0) * 0.8, 0.0, 1.0)
    # Nothing may reach the top rows: the shader stops sampling there.
    fade = np.clip((1.0 - height) * 12.0, 0.0, 1.0)
    return pack(lines * fade, hoar * fade, False)


def bake_field(seed):
    w = h = 1024
    rnd = random.Random(seed + 1)
    canvas = Canvas(w, h, True, rnd)
    # Along scratches and wipe streaks: rows of small feathers either side.
    for _ in range(5):
        x, y = rnd.uniform(0, w), rnd.uniform(0, h)
        a = rnd.uniform(0.0, math.pi)
        wobble = rnd.uniform(-0.0015, 0.0015)
        run = rnd.uniform(180.0, 520.0)
        d = 0.0
        while d < run:
            d += rnd.uniform(3.0, 10.0)
            a += wobble * 6.0
            if rnd.random() < 0.8:
                canvas.plume(x + math.cos(a) * d, y + math.sin(a) * d,
                    a + rnd.choice((-1, 1)) * rnd.uniform(0.5, 1.4), rnd.uniform(8.0, 42.0), 1)
    # Free nuclei: a fan of a few feathers from one speck, each leaning off its neighbour.
    for _ in range(60):
        x, y = rnd.uniform(0, w), rnd.uniform(0, h)
        start = rnd.uniform(0.0, math.tau)
        size = rnd.uniform(14.0, 95.0) * (0.45 + 0.55 * rnd.random())
        for k in range(rnd.randint(2, 5)):
            canvas.plume(x, y, start + (k - 1.5) * rnd.uniform(0.35, 0.8), size * rnd.uniform(0.5, 1.0), 1)
    lines = canvas.lines()
    rng = np.random.default_rng(seed + 1)
    grains = tile_fbm(h, w, 2, rng, 2)
    clumps = tile_fbm(h, w, 96, rng)
    hoar = np.clip((grains - (0.74 - np.clip(clumps - 0.35, 0.0, 1.0) * 0.20)) * 4.0, 0.0, 1.0)
    near = tile_blur(lines, 3.0, True)
    hoar = np.clip(hoar + np.clip(near * 2.2, 0.0, 1.0) * np.clip((grains - 0.42) * 5.0, 0.0, 1.0) * 0.8, 0.0, 1.0)
    return pack(lines, hoar, True)


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "assets/environment/windows"
    seed = int(sys.argv[2]) if len(sys.argv) > 2 else 727
    os.makedirs(target, exist_ok=True)
    bake_edge(seed).save(os.path.join(target, "frost_edge_strip.png"), optimize=True)
    bake_field(seed).save(os.path.join(target, "frost_field.png"), optimize=True)
    print("baked", target)
