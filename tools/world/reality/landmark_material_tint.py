#!/usr/bin/env python3
"""Sets one named material's base colour in an artist-modified landmark glb.

python3 tools/world/reality/landmark_material_tint.py <landmark.glb> <landmark_spec.json> <material> <r> <g> <b>

Only that material's baseColorFactor changes; the binary buffers stay byte-identical. The spec and the
authoring manifest record the new sha256 and the tint (as landmark_glass_frost.py does), so
landmarks.py keeps its hands off the asset.
"""
import datetime
import hashlib
import json
import os
import struct
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
MANIFEST = os.path.join(ROOT, "data/world/key_west/reality/authoring/asset_manifest.json")


def _read_glb(path: str) -> tuple[dict, bytes]:
    data = open(path, "rb").read()
    js_len = struct.unpack("<I", data[12:16])[0]
    gltf = json.loads(data[20:20 + js_len])
    bin_len = struct.unpack("<I", data[20 + js_len:24 + js_len])[0]
    return gltf, data[28 + js_len:28 + js_len + bin_len]


def _write_glb(path: str, gltf: dict, blob: bytes) -> None:
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    blob += b"\0" * (-len(blob) % 4)
    body = struct.pack("<I4s", len(js), b"JSON") + js + struct.pack("<I4s", len(blob), b"BIN\0") + blob
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, 12 + len(body)) + body)


def main() -> None:
    glb, spec_path, name = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2]), sys.argv[3]
    colour = [round(float(c), 3) for c in sys.argv[4:7]]
    gltf, blob = _read_glb(glb)
    material = next(m for m in gltf["materials"] if m.get("name") == name)
    pbr = material.setdefault("pbrMetallicRoughness", {})
    before = pbr.get("baseColorFactor", [1.0, 1.0, 1.0, 1.0])
    pbr["baseColorFactor"] = colour + [before[3]]
    _write_glb(glb, gltf, blob)
    sha = hashlib.sha256(open(glb, "rb").read()).hexdigest()
    stamp = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()
    spec = json.load(open(spec_path, encoding="utf-8"))
    spec.setdefault("material_tints", {})[name] = {"tool": "tools/world/reality/landmark_material_tint.py",
                                                   "from": before[:3], "to": colour, "built_at": stamp}
    spec["asset_sha256"] = sha
    with open(spec_path, "w", encoding="utf-8") as f:
        f.write(json.dumps(spec, indent=1, ensure_ascii=False) + "\n")
    manifest = json.load(open(MANIFEST, encoding="utf-8"))
    rel = os.path.relpath(glb, ROOT).replace(os.sep, "/")
    rec = next(a for a in manifest["assets"] if a.get("godot_scene") == "res://" + rel)
    rec.update({"authoring_state": "artist_modified", "asset_sha256": sha, "updated_at": stamp,
                "asset_revision": int(rec.get("asset_revision") or 0) + 1,
                "authored_by": "tools/world/reality/landmark_material_tint.py (%s base colour; buffers unchanged)" % name})
    with open(MANIFEST, "w", encoding="utf-8") as f:
        f.write(json.dumps(manifest, indent=1, ensure_ascii=False) + "\n")
    print(json.dumps({"material": name, "from": before, "to": pbr["baseColorFactor"], "sha256": sha}))


main()
