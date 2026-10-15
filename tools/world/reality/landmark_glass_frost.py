#!/usr/bin/env python3
"""Gives an enterable landmark's window glass per-pane frost data (frosted_glass.gdshader).

python3 tools/world/reality/landmark_glass_frost.py <landmark.glb> <landmark_spec.json>

Every vertex of the glTF node "Glass" is matched to its window opening in the spec's interior plan
(nearest opening centre in plan u/v). It gains TEXCOORD_0 (0..1 across the pane, 0 at the top) and
COLOR_0 = (cold coverage, heated room, pattern seed, 1). Cold coverage of a house with content inside is
60-80 %, fixed per window by a hash of its name; heated rooms clear further at runtime with their
zone's warmth. Other buffers stay byte-identical. The spec and the authoring manifest record the new
sha256; the manifest state becomes artist_modified, so landmarks.py will not overwrite the asset.
"""
import datetime
import hashlib
import json
import math
import os
import struct
import sys

import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
MANIFEST = os.path.join(ROOT, "data/world/key_west/reality/authoring/asset_manifest.json")
COVERAGE_RANGE = (0.6, 0.8)  # owner rule: a house with content inside keeps 60-80 % frost on its windows


def _read_glb(path: str) -> tuple[dict, bytearray]:
    data = open(path, "rb").read()
    js_len = struct.unpack("<I", data[12:16])[0]
    gltf = json.loads(data[20:20 + js_len])
    bin_len = struct.unpack("<I", data[20 + js_len:24 + js_len])[0]
    return gltf, bytearray(data[28 + js_len:28 + js_len + bin_len])


def _write_glb(path: str, gltf: dict, blob: bytearray) -> None:
    gltf["buffers"] = [{"byteLength": len(blob)}]
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    blob += b"\0" * (-len(blob) % 4)
    body = struct.pack("<I4s", len(js), b"JSON") + js + struct.pack("<I4s", len(blob), b"BIN\0") + bytes(blob)
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, 12 + len(body)) + body)


def _append(gltf: dict, blob: bytearray, arr: np.ndarray, typ: str) -> int:
    while len(blob) % 4:
        blob.append(0)
    raw = arr.tobytes()
    gltf["bufferViews"].append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(raw), "target": 34962})
    blob.extend(raw)
    gltf["accessors"].append({"bufferView": len(gltf["bufferViews"]) - 1, "componentType": 5126, "count": int(arr.shape[0]), "type": typ})
    return len(gltf["accessors"]) - 1


def _unit_hash(text: str) -> float:
    return int(hashlib.sha256(text.encode()).hexdigest()[:8], 16) / 0xFFFFFFFF


def main() -> None:
    glb, spec_path = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
    spec = json.load(open(spec_path, encoding="utf-8"))
    interior = spec["interior"]
    yaw = float(interior["plan_yaw_rad"])
    heated = {r["id"]: bool(r["heated"]) for r in interior["rooms"]}
    windows = [o for o in interior["openings"] if o["kind"] == "window"]
    gltf, blob = _read_glb(glb)
    node = next(n for n in gltf["nodes"] if n.get("name") == "Glass")
    prim = gltf["meshes"][node["mesh"]]["primitives"][0]
    if "COLOR_0" in prim["attributes"]:
        raise SystemExit("glass already carries frost data")
    acc = gltf["accessors"][prim["attributes"]["POSITION"]]
    view = gltf["bufferViews"][acc["bufferView"]]
    pos = np.frombuffer(bytes(blob[view["byteOffset"]:view["byteOffset"] + view["byteLength"]]), np.float32).reshape(-1, 3)
    ## Basis(UP, yaw) maps plan (u, v) to local (x, z); its inverse maps the glass back onto the plan.
    c, s = math.cos(yaw), math.sin(yaw)
    u = pos[:, 0] * c - pos[:, 2] * s
    v = pos[:, 0] * s + pos[:, 2] * c
    centres = np.array([o["centre_uv"] for o in windows], float)
    nearest = np.argmin((u[:, None] - centres[None, :, 0]) ** 2 + (v[:, None] - centres[None, :, 1]) ** 2, axis=1)
    uv = np.zeros((len(pos), 2), np.float32)
    color = np.ones((len(pos), 4), np.float32)
    per_window = {}
    for k, o in enumerate(windows):
        sel = nearest == k
        along = u[sel] - o["centre_uv"][0] if abs(o["outward_uv"][1]) > 0.5 else v[sel] - o["centre_uv"][1]
        uv[sel, 0] = np.clip(along / float(o["width_m"]) + 0.5, 0.0, 1.0)
        uv[sel, 1] = np.clip((float(o["y1"]) - pos[sel, 1]) / (float(o["y1"]) - float(o["y0"])), 0.0, 1.0)
        cover = COVERAGE_RANGE[0] + (COVERAGE_RANGE[1] - COVERAGE_RANGE[0]) * _unit_hash(o["name"])
        color[sel] = (cover, 1.0 if heated.get(o["room"], False) else 0.0, _unit_hash(o["name"] + "|seed"), 1.0)
        per_window[o["name"]] = {"room": o["room"], "heated": heated.get(o["room"], False), "cold_coverage": round(cover, 3),
                                 "vertices": int(sel.sum())}
    prim["attributes"]["TEXCOORD_0"] = _append(gltf, blob, uv, "VEC2")
    prim["attributes"]["COLOR_0"] = _append(gltf, blob, color, "VEC4")
    _write_glb(glb, gltf, blob)
    sha = hashlib.sha256(open(glb, "rb").read()).hexdigest()
    stamp = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()
    spec["window_frost"] = {"tool": "tools/world/reality/landmark_glass_frost.py", "cold_coverage_range": list(COVERAGE_RANGE),
                            "warm_coverage": 0.2, "windows": per_window, "built_at": stamp}
    spec["asset_sha256"] = sha
    with open(spec_path, "w", encoding="utf-8") as f:
        f.write(json.dumps(spec, indent=1, ensure_ascii=False) + "\n")
    manifest = json.load(open(MANIFEST, encoding="utf-8"))
    rel = os.path.relpath(glb, ROOT).replace(os.sep, "/")
    rec = next(a for a in manifest["assets"] if a.get("godot_scene") == "res://" + rel)
    rec.update({"authoring_state": "artist_modified", "asset_sha256": sha, "updated_at": stamp,
                "asset_revision": int(rec.get("asset_revision") or 0) + 1,
                "authored_by": "tools/world/reality/landmark_glass_frost.py (per-pane frost data; other buffers unchanged)"})
    with open(MANIFEST, "w", encoding="utf-8") as f:
        f.write(json.dumps(manifest, indent=1, ensure_ascii=False) + "\n")
    print(json.dumps({"windows": len(windows), "vertices": int(len(pos)), "per_window": per_window}))


main()
