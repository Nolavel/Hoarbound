#!/usr/bin/env python3
"""Fail on non-native UI, 3D budget regression or source mismatches."""
import json
import math
import sys
from pathlib import Path
from PIL import Image


def validate_clarity(directory, mode, group, size_arg, tier_arg):
    width, height = map(int, size_arg.split("x"))
    tier = float(tier_arg)
    raw = json.loads((directory / "manifest.json").read_text())
    shots = raw.get("shots", [])
    problems = list(raw.get("notes", []))
    wanted = ["A_production", "B_native"]
    if group == "hud" and size_arg == "1920x1080":
        wanted += ["C_production_no_fxaa", "D_native_no_fxaa"]
    if not raw.get("passed") or not raw.get("frozen_scene"):
        problems.append("capture failed or scene was not frozen")
    if raw.get("method") != "forward_plus" or raw.get("driver") != "vulkan":
        problems.append("renderer fallback invalidates this comparison")
    if [s.get("variant") for s in shots] != wanted:
        problems.append("missing or reordered A/B variants")
    first = shots[0] if shots else {}
    quality = {0.67: "low", 0.77: "medium", 1.0: "high"}.get(tier)
    for shot in shots:
        native = shot.get("variant") in ("B_native", "D_native_no_fxaa")
        scale = 1.0 if native else min(1.0, math.sqrt(1920 * 1080 * tier ** 2 / (width * height)))
        no_fxaa = "no_fxaa" in shot.get("variant", "")
        expected = {"mode": "canvas_items", "group": group, "quality": quality,
                    "requested": [width, height], "window": [width, height],
                    "internal": [width, height], "png": [width, height],
                    "screen_space_aa": 0 if no_fxaa else 1, "flat": False, "ok": True}
        for field, value in expected.items():
            if shot.get(field) != value:
                problems.append(f"{shot.get('variant')} {field}: {shot.get(field)!r} != {value!r}")
        if abs(shot.get("scale3d", -999) - scale) > 0.002:
            problems.append(f"{shot.get('variant')} incorrect actual 3D scale")
        for field in ("player_xyz", "camera_xyz", "camera_forward", "fov", "msaa_3d", "taa", "fsr_sharpness", "scale3d_mode"):
            if shot.get(field) != first.get(field):
                problems.append(f"{shot.get('variant')} changed controlled field {field}")
        path = Path(shot["file"])
        if not path.exists():
            problems.append(f"missing {path.name}")
        else:
            with Image.open(path) as picture:
                if picture.size != (width, height):
                    problems.append("PNG dimensions changed")
    # Exact 1:1 crops for review, never resize or sharpen the source screenshots.
    if len(shots) >= 2 and not problems:
        from PIL import ImageDraw, ImageChops, ImageStat
        box = (width // 2 - 200, height // 2 - 160, width // 2 + 200, height // 2 + 160)
        sheet = Image.new("RGB", (400 * len(shots), 350), (24, 28, 32))
        draw = ImageDraw.Draw(sheet)
        for index, shot in enumerate(shots):
            with Image.open(shot["file"]) as picture:
                sheet.paste(picture.convert("RGB").crop(box), (index * 400, 30))
            draw.text((index * 400 + 8, 8), shot["variant"], fill="white")
        sheet.save(directory / "comparison_1to1.png")
        with Image.open(shots[0]["file"]) as a, Image.open(shots[1]["file"]) as b:
            difference = ImageChops.difference(a.convert("RGB"), b.convert("RGB"))
            raw["ab_mean_absolute_pixel_difference"] = sum(ImageStat.Stat(difference).mean) / 3
    report = {"success": not problems, "problems": problems, "manifest": raw}
    (directory / "verdict.json").write_text(json.dumps(report, indent=2))
    print("CLARITY_VERDICT", json.dumps(report))
    return 0 if not problems else 1


directory = Path(sys.argv[1])
mode, group, size_arg, tier_arg = sys.argv[2:6]
if len(sys.argv) == 7 and sys.argv[6] == "clarity":
    sys.exit(validate_clarity(directory, mode, group, size_arg, tier_arg))
width, height = (int(x) for x in size_arg.split("x"))
tier = float(tier_arg)
raw = json.loads((directory / "manifest.json").read_text())
shots = raw.get("shots", [])
problems = list(raw.get("notes", []))
if not raw.get("passed") or len(shots) != 1:
    problems.append("invalid capture manifest or shot count")
else:
    shot = shots[0]
    native_root = (width, height) if mode == "canvas_items" else (1920, 1080)
    expected_scale = tier if mode == "viewport" else min(1.0, math.sqrt((1920 * 1080 * tier * tier) / (width * height)))
    expected_budget = 1920 * 1080 * tier * tier
    for field, wanted in {"mode":mode, "group":group,
                          "internal":list(native_root), "requested":[width,height],
                          "png":[width,height], "window":[width,height]}.items():
        if shot.get(field) != wanted:
            problems.append(f"{field} expected={wanted!r} actual={shot.get(field)!r}")
    if abs(shot.get("scale3d", -999) - expected_scale) > 0.002:
        problems.append(f"3D scale expected={expected_scale:.6f} actual={shot.get('scale3d')}")
    if shot.get("estimated_3d_pixels", float("inf")) > expected_budget * 1.008 + 1:
        problems.append(f"3D rendered pixels exceeded old GPU tier budget: {shot.get('estimated_3d_pixels')} > {expected_budget}")
    if shot.get("flat") or not shot.get("ok"):
        problems.append("capture blank/not-ok")
    path = Path(shot["file"])
    if not path.exists():
        problems.append("PNG missing")
    else:
        with Image.open(path) as picture:
            if picture.size != (width,height):
                problems.append("PNG native dimensions wrong")
report = {"success":not problems, "mode":mode, "group":group,
          "window":[width,height], "tier":tier,
          "problems":problems, "shot":shots[0] if shots else None}
(directory / "verdict.json").write_text(json.dumps(report, indent=2))
print("NATIVE_FINAL_VERDICT",json.dumps(report))
sys.exit(0 if not problems else 1)

