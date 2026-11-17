#!/usr/bin/env python3
"""Fail on non-native UI, 3D budget regression or source mismatches."""
import json
import math
import sys
from pathlib import Path
from PIL import Image

directory = Path(sys.argv[1])
mode, group, size_arg, tier_arg = sys.argv[2:]
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
