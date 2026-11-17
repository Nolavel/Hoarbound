#!/usr/bin/env python3
"""Contact sheets for the stretch study. Originals are never resized in place.

Overview sheets are downscaled for scanning. The crop sheets paste native
pixels from the top centre, so text sharpness is not judged from the overview.
"""
from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

from PIL import Image, ImageDraw


def png_size(path: Path) -> tuple[int, int]:
    data = path.read_bytes()[:24]
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"not a png: {path}")
    width, height = struct.unpack(">II", data[16:24])
    return width, height


def fit(image: Image.Image, height: int) -> Image.Image:
    scale = height / image.height
    return image.resize((max(1, int(image.width * scale)), height), Image.Resampling.BOX)


def label(image: Image.Image, text: str) -> Image.Image:
    bar = Image.new("RGB", (image.width, 28), (16, 18, 20))
    draw = ImageDraw.Draw(bar)
    draw.text((8, 6), text, fill=(236, 232, 220))
    sheet = Image.new("RGB", (image.width, image.height + 28), (8, 8, 8))
    sheet.paste(bar, (0, 0))
    sheet.paste(image.convert("RGB"), (0, 28))
    return sheet


def side_by_side(left: Image.Image, right: Image.Image) -> Image.Image:
    width = left.width + right.width + 8
    height = max(left.height, right.height)
    sheet = Image.new("RGB", (width, height), (8, 8, 8))
    sheet.paste(left, (0, 0))
    sheet.paste(right, (left.width + 8, 0))
    return sheet


def native_crop(path: Path, box: tuple[int, int, int, int]) -> Image.Image:
    with Image.open(path) as image:
        width, height = image.size
        x0, y0, x1, y1 = box
        x0 = max(0, min(width - 1, x0))
        y0 = max(0, min(height - 1, y0))
        x1 = max(x0 + 1, min(width, x1))
        y1 = max(y0 + 1, min(height, y1))
        return image.crop((x0, y0, x1, y1)).convert("RGB")


def main() -> int:
    out = Path(sys.argv[1])
    sheets = out / "sheets"
    sheets.mkdir(parents=True, exist_ok=True)
    problems: list[str] = []
    manifest_path = out / "manifest.json"
    rows = []
    if manifest_path.exists():
        rows = json.loads(manifest_path.read_text())["shots"]
    for png in sorted(out.rglob("*.png")):
        if "sheets" in png.parts:
            continue
        try:
            size = png_size(png)
        except ValueError as exc:
            problems.append(str(exc))
            continue
        print(f"PNG {size[0]}x{size[1]} {png.relative_to(out)}")
    pairs: dict[tuple[str, str], dict[str, Path]] = {}
    for row in rows:
        if row["group"] == "scale3d" or not row.get("file"):
            continue
        key = (row["group"], f"{row['requested'][0]}x{row['requested'][1]}")
        pairs.setdefault(key, {})[row["mode"]] = Path(row["file"])
        if tuple(row["png"]) != tuple(row["requested"]):
            problems.append(f"{row['file']} png {row['png']} != {row['requested']}")
        if row.get("flat"):
            problems.append(f"{row['file']} looks flat")
        if not row.get("ok"):
            problems.append(f"{row['file']} shot not ok")
    for (group, size), modes in sorted(pairs.items()):
        if "viewport" not in modes or "canvas_items" not in modes:
            continue
        left_path, right_path = modes["viewport"], modes["canvas_items"]
        if not left_path.exists() or not right_path.exists():
            problems.append(f"missing pair {group} {size}")
            continue
        with Image.open(left_path) as left_raw, Image.open(right_path) as right_raw:
            overview = side_by_side(
                label(fit(left_raw, 480), f"viewport {size}"),
                label(fit(right_raw, 480), f"canvas_items {size}"),
            )
        overview.save(sheets / f"{group}_{size}_overview.jpg", quality=85)
        width = png_size(left_path)[0]
        crop_w = min(960, width)
        x0 = max(0, (width - crop_w) // 2)
        crops = side_by_side(
            label(native_crop(left_path, (x0, 0, x0 + crop_w, 180)), f"viewport {size} native top"),
            label(native_crop(right_path, (x0, 0, x0 + crop_w, 180)), f"canvas_items {size} native top"),
        )
        crops.save(sheets / f"{group}_{size}_top_native.jpg", quality=90)
    scale_rows = [row for row in rows if row["group"] == "scale3d" and row.get("ok")]
    by_size: dict[str, list[dict]] = {}
    for row in scale_rows:
        by_size.setdefault(f"{row['requested'][0]}x{row['requested'][1]}", []).append(row)
    for size, group_rows in sorted(by_size.items()):
        tiles = []
        for row in sorted(group_rows, key=lambda item: item["scale3d"], reverse=True):
            path = Path(row["file"])
            if not path.exists():
                continue
            with Image.open(path) as raw:
                tiles.append(label(fit(raw, 360), f"canvas_items {size} 3d x{row['scale3d']}"))
        if len(tiles) >= 2:
            sheet = tiles[0]
            for tile in tiles[1:]:
                sheet = side_by_side(sheet, tile)
            sheet.save(sheets / f"scale3d_{size}_overview.jpg", quality=85)
    print("SHEETS", sheets)
    if problems:
        print("STRETCH_VALIDATE_FAIL")
        for problem in problems:
            print(problem)
        return 1
    print("STRETCH_VALIDATE_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
