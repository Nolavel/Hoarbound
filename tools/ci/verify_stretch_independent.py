#!/usr/bin/env python3
"""Single-process screenshot validation. Comparisons require separate process manifests."""
import json
import sys
from pathlib import Path
from PIL import Image

folder = Path(sys.argv[1])
expected_mode, expected_group = sys.argv[2:4]
size = tuple(map(int, sys.argv[4].split("x")))
scale = float(sys.argv[5])
report = json.loads((folder / "manifest.json").read_text())
rows = report.get("shots", [])
issues = list(report.get("notes", []))
if len(rows) != 1:
    issues.append(f"expected exactly one screenshot, got {len(rows)}")
else:
    row = rows[0]
    for key, value in [("mode", expected_mode), ("group", expected_group), ("requested", list(size)), ("window", list(size)), ("png", list(size))]:
        if row.get(key) != value:
            issues.append(f"{key}: {row.get(key)!r} != {value!r}")
    if abs(row.get("scale3d", -1) - scale) > 0.0001:
        issues.append("3D scale mismatch")
    expected_internal = list((1920, 1080) if expected_mode == "viewport" else size)
    if row.get("internal") != expected_internal:
        issues.append(f"INTERNAL_NOT_NATIVE: {row.get('internal')} != {expected_internal}")
    if row.get("flat") or not row.get("ok"):
        issues.append("empty or failed screenshot")
    if expected_mode == "viewport" and size == (1920, 1080) and row.get("source") != "viewport":
        issues.append("1080p viewport did not capture native frame")
    file = Path(row.get("file", ""))
    if file.exists():
        with Image.open(file) as img:
            if img.size != size:
                issues.append(f"actual PNG {img.size} != {size}")
    else:
        issues.append("missing PNG")
verdict = {"case": folder.name, "mode": expected_mode, "group": expected_group,
           "resolution": size, "scale3d": scale, "success": not issues, "issues": issues,
           "row": rows[0] if rows else None}
(folder / "case_verdict.json").write_text(json.dumps(verdict, ensure_ascii=False, indent=2))
print("STRETCH_AB_VERDICT", json.dumps(verdict, ensure_ascii=False))
sys.exit(0 if not issues else 1)
