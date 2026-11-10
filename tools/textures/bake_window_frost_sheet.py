#!/usr/bin/env python3
"""Bakes the frost sheet for the 727 window thaw probe (issue #281): fern-frost plumes grown from the frame,
from scratches and from free nuclei, at 1 mm per pixel on a 2.0 x 1.1 m pane.

Channels: R crystal lines (plumes, barbs), G granular hoar, B when frost reaches a texel (0 at the frame,
1 in the middle), A smooth thickness (blurred R + G) for relief-free thickness and melt order.

Scale follows K. Libbrecht's window-frost notes (branches of a few millimetres; scratches and streaks on the
glass guide where crystals nucleate). Deterministic for a given seed.

Usage: python3 tools/textures/bake_window_frost_sheet.py [out.png] [seed]
"""
import math
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

W, H = 2048, 1126  # 1 px = ~1 mm on the 2.0 x 1.1 m pane
SS = 3             # supersampling for line drawing


def noise(shape, cell, rng):
    """Smooth value noise in 0..1 with features about `cell` pixels wide."""
    h, w = shape
    small = rng.random((h // cell + 3, w // cell + 3)).astype(np.float32)
    img = Image.fromarray((small * 255).astype(np.uint8)).resize((w + 2 * cell, h + 2 * cell), Image.BICUBIC)
    return np.asarray(img, dtype=np.float32)[cell:cell + h, cell:cell + w] / 255.0


def fbm(shape, cell, rng, octaves=4):
    out = np.zeros(shape, np.float32)
    amp, total = 0.5, 0.0
    for _ in range(octaves):
        out += noise(shape, max(cell, 2), rng) * amp
        total += amp
        amp *= 0.5
        cell //= 2
    return out / total


class Sheet:
    def __init__(self, seed):
        self.rnd = random.Random(seed)
        self.lines = Image.new("L", (W * SS, H * SS), 0)
        self.draw = ImageDraw.Draw(self.lines)

    def stroke(self, pts, value, width=1):
        self.draw.line([(x * SS, y * SS) for x, y in pts], fill=value, width=width)

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
            if not (-20 <= x <= W + 20 and -20 <= y <= H + 20):
                break
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
                            for s in (-1, 1):
                                t = a + s * barb_angle
                                small = reach * 0.16 * (1.0 - j * 1.5 / reach)
                                if small > 0.8:
                                    self.stroke([(bx, by), (bx + math.cos(t) * small, by + math.sin(t) * small)], 120)
                    self.stroke(barb, int(rnd.uniform(150, 235)), 2)
            if depth < 2 and length > 22.0 and 0.12 < u < 0.8 and rnd.random() < 0.035:
                self.plume(x, y, angle + rnd.choice((-1, 1)) * rnd.uniform(0.45, 1.05), length * rnd.uniform(0.35, 0.65), depth + 1)
        self.stroke(pts, 255, 3 if length > 30.0 else 2)

    def grow(self):
        rnd = self.rnd
        # From the frame: the sill grows the longest feathers, the head of the pane the shortest.
        edges = [
            (lambda t: (t * W, H + 2.0), -math.pi / 2, (40.0, 280.0), 6.0),
            (lambda t: (-2.0, t * H), 0.0, (30.0, 200.0), 8.0),
            (lambda t: (W + 2.0, t * H), math.pi, (30.0, 200.0), 8.0),
            (lambda t: (t * W, -2.0), math.pi / 2, (20.0, 130.0), 10.0),
        ]
        for at, inward, (lo, hi), gap in edges:
            span = W if abs(math.cos(inward)) < 0.5 else H
            pos = 0.0
            while pos < span:
                pos += rnd.uniform(0.4, 1.6) * gap
                x, y = at(pos / span)
                length = lo + (hi - lo) * rnd.random() ** 1.5
                self.plume(x, y, inward + rnd.uniform(-1.0, 1.0), length)
        # Along scratches and wipe streaks: rows of small feathers either side.
        for _ in range(7):
            x, y = rnd.uniform(0.1, 0.9) * W, rnd.uniform(0.1, 0.9) * H
            a = rnd.uniform(0.0, math.pi)
            wobble = rnd.uniform(-0.0015, 0.0015)
            run = rnd.uniform(180.0, 620.0)
            d = 0.0
            while d < run:
                d += rnd.uniform(3.0, 10.0)
                a += wobble * 6.0
                px, py = x + math.cos(a) * d, y + math.sin(a) * d
                if 0 <= px <= W and 0 <= py <= H and rnd.random() < 0.8:
                    self.plume(px, py, a + rnd.choice((-1, 1)) * rnd.uniform(0.5, 1.4), rnd.uniform(8.0, 42.0), 1)
        # Free nuclei: small ice flowers, fewer towards the warm middle.
        placed = 0
        while placed < 95:
            x, y = rnd.uniform(0, W), rnd.uniform(0, H)
            edge = min(x, W - x, y * 1.3, (H - y) * 0.8) / (0.5 * H)
            if rnd.random() < edge * 1.1:
                continue
            placed += 1
            # A fan of a few feathers from one speck, not a star: each leans off its neighbour.
            start = rnd.uniform(0.0, math.tau)
            size = rnd.uniform(14.0, 95.0) * (0.45 + 0.55 * rnd.random())
            for k in range(rnd.randint(2, 5)):
                self.plume(x, y, start + (k - 1.5) * rnd.uniform(0.35, 0.8), size * rnd.uniform(0.5, 1.0), 1)


def bake(seed):
    sheet = Sheet(seed)
    sheet.grow()
    lines = np.asarray(sheet.lines.resize((W, H), Image.LANCZOS), dtype=np.float32) / 255.0
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    # When frost reaches a texel: distance from the frame (the sill counts nearer), bent by broad noise.
    # The frost is not a frame of one width: deep off the sill, shallow under the head, and uneven all round.
    edge = np.minimum(np.minimum(xx, W - 1 - xx), np.minimum(yy * 1.5, (H - 1 - yy) * 0.42)) / (0.5 * H)
    broad = fbm((H, W), 420, rng, 3)
    order = np.clip(edge * 1.3 + (broad - 0.5) * 1.15 + (fbm((H, W), 60, rng) - 0.5) * 0.18, 0.0, 1.0)
    # Granular hoar: fine grains packed by the frame and thinning out, with a ragged limit.
    grains = fbm((H, W), 2, rng, 2)
    clumps = fbm((H, W), 40, rng)
    density = np.clip(1.2 - order * 3.6 + (clumps - 0.5) * 0.8, 0.0, 1.0)
    hoar = np.clip((grains - (0.74 - density * 0.46)) * 4.0, 0.0, 1.0)
    # Hoar also clings to the feathers.
    near = np.asarray(Image.fromarray((lines * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(3.0)), dtype=np.float32) / 255.0
    hoar = np.clip(hoar + np.clip(near * 2.2, 0.0, 1.0) * np.clip((grains - 0.42) * 5.0, 0.0, 1.0) * 0.8, 0.0, 1.0)
    body = np.clip(lines * 0.8 + hoar * 0.55, 0.0, 1.0)
    smooth = np.asarray(Image.fromarray((body * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(5.0)), dtype=np.float32) / 255.0
    smooth = np.clip(smooth * 1.6, 0.0, 1.0)
    out = np.stack([lines, hoar, order, smooth], axis=-1)
    return Image.fromarray((out * 255.0 + 0.5).astype(np.uint8), "RGBA")


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "tests/demos/window_727_sdf/frost_sheet_727.png"
    bake(int(sys.argv[2]) if len(sys.argv) > 2 else 727).save(target, optimize=True)
    print("baked", target)
