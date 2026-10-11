"""Change report between two library builds: update source -> normalize -> compare -> report.

Default 'previous' is the library the last build replaced (raw_cache/previous_library/).
Nothing is regenerated here; the editor generator reads this report to plan selective work.
"""
from __future__ import annotations

import json
import sqlite3
from collections import Counter, defaultdict
from pathlib import Path

from . import paths
from .library import PREVIOUS
from .model import RECON_RANK

TRACKED = ("height_m", "levels", "roof_shape", "address", "width_m", "name")


def _load(path: Path) -> tuple[dict, dict]:
    con = sqlite3.connect(path)
    idx = {fid: (fam, cls, gh) for fid, fam, cls, gh in con.execute("SELECT feature_id, family, class, geometry_hash FROM feature_index")}
    attrs = defaultdict(dict)
    q = f"""SELECT fi.feature_id, n.name, a.value_json, p.reconstruction_class FROM attribute_store a JOIN feature_index fi ON fi.fid = a.fid
        JOIN attribute_name n ON n.name_id = a.name_id JOIN provenance p ON p.prov_id = a.prov_id
        WHERE a.selected = 1 AND n.name IN ({','.join('?' * len(TRACKED))})"""
    try:
        rows = con.execute(q, TRACKED).fetchall()
    except sqlite3.OperationalError:  # libraries written before provenance normalisation
        rows = con.execute(f"SELECT feature_id, name, value_json, reconstruction_class FROM attribute WHERE selected = 1 AND name IN ({','.join('?' * len(TRACKED))})", TRACKED).fetchall()
    for fid, name, val, recon in rows:
        attrs[fid][name] = (json.loads(val), recon)
    con.close()
    return idx, attrs


def run(previous: str | None = None) -> dict:
    prev_path = Path(previous) if previous else PREVIOUS
    if not prev_path.exists():
        raise SystemExit(f"no previous library at {prev_path}; nothing to compare (first build)")
    old_idx, old_attr = _load(prev_path)
    new_idx, new_attr = _load(paths.LIBRARY)
    out = defaultdict(Counter)
    samples = defaultdict(list)
    for fid, (fam, cls, gh) in new_idx.items():
        if fid not in old_idx:
            out[fam]["added"] += 1
            samples[f"{fam}:added"].append(fid)
            continue
        if old_idx[fid][2] != gh:
            out[fam]["geometry_changed"] += 1
            samples[f"{fam}:geometry_changed"].append(fid)
        if old_idx[fid][1] != cls:
            out[fam]["class_changed"] += 1
        for name in TRACKED:
            o, n = old_attr.get(fid, {}).get(name), new_attr.get(fid, {}).get(name)
            if o is None and n is None:
                continue
            if o is None:
                out[fam][f"{name}_added"] += 1
            elif n is None:
                out[fam][f"{name}_lost"] += 1
            elif o[0] != n[0]:
                if RECON_RANK.get(n[1], 0) > RECON_RANK.get(o[1], 0):
                    out[fam][f"{name}_improved"] += 1
                else:
                    out[fam][f"{name}_changed"] += 1
    for fid, (fam, _, _) in old_idx.items():
        if fid not in new_idx:
            out[fam]["removed"] += 1
            samples[f"{fam}:removed"].append(fid)
    result = {"previous": str(prev_path), "current": str(paths.LIBRARY), "by_family": {k: dict(v) for k, v in sorted(out.items())},
              "samples": {k: v[:20] for k, v in samples.items()}}
    (paths.REPORTS / "change_report.json").write_text(json.dumps(result, indent=1) + "\n", encoding="utf-8")
    lines = ["# Reality Library change report", "", f"previous: `{prev_path.name}` -> current", ""]
    for fam, c in result["by_family"].items():
        parts = [f"+{c.get('added', 0)}", f"-{c.get('removed', 0)}", f"{c.get('geometry_changed', 0)} geometry changed"]
        parts += [f"{v} {k.replace('_', ' ')}" for k, v in sorted(c.items()) if k not in ("added", "removed", "geometry_changed")]
        lines.append(f"- **{fam}**: " + ", ".join(parts))
    if not result["by_family"]:
        lines.append("- no changes")
    (paths.REPORTS / "change_report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines))
    return result
