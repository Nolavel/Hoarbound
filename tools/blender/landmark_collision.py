"""Gives a landmark .glb a simplified collision mesh, authored in Blender; the visual mesh stays byte-identical.

python tools/blender/landmark_collision.py -- <landmark.glb> <node-col> [--ratio 0.2] [--max-error 0.15]
(runs under Blender's Python: `blender --background --python ...` or the `bpy` wheel)

The node named <node-col> (Godot builds a trimesh body from every `-col` node) loses its suffix and keeps only
its look. A copy goes through Blender's Decimate (Collapse, `--ratio`) and is added as `<name>Collision-colonly`:
Godot builds the body from that copy and draws nothing. Error = distance from every source vertex and face centre
to the copy; the run fails above `--max-error` metres. The landmark spec and the authoring manifest record the
result; the manifest state becomes `artist_modified`, so `landmarks.py` will not overwrite the asset.
"""
import datetime
import hashlib
import json
import os
import struct
import sys

import bpy  # first: bmesh and mathutils come with it
import bmesh
import numpy as np
from mathutils.bvhtree import BVHTree

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
MANIFEST = os.path.join(ROOT, "data/world/key_west/reality/authoring/asset_manifest.json")
SPEC_DIR = os.path.join(ROOT, "data/world/key_west/reality/landmarks")


def _args() -> tuple[str, str, float, float]:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    ratio = float(argv[argv.index("--ratio") + 1]) if "--ratio" in argv else 0.2
    max_error = float(argv[argv.index("--max-error") + 1]) if "--max-error" in argv else 0.15
    return os.path.abspath(argv[0]), argv[1], ratio, max_error


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


def _append(gltf: dict, blob: bytearray, arr: np.ndarray, target: int, comp: int, typ: str, minmax: bool) -> int:
    while len(blob) % 4:
        blob.append(0)
    raw = arr.tobytes()
    gltf["bufferViews"].append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(raw), "target": target})
    blob.extend(raw)
    acc = {"bufferView": len(gltf["bufferViews"]) - 1, "componentType": comp, "count": int(arr.shape[0]), "type": typ}
    if minmax:
        acc["min"] = arr.min(axis=0).tolist()
        acc["max"] = arr.max(axis=0).tolist()
    gltf["accessors"].append(acc)
    return len(gltf["accessors"]) - 1


def _decimate(glb: str, node_name: str, ratio: float) -> tuple[np.ndarray, np.ndarray, np.ndarray, int]:
    """Collision copy of the node's mesh in glTF axes (positions, triangle indices), its error per sample, source tris."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb)
    src = next(o for o in bpy.data.objects if o.type == "MESH" and o.name == node_name)
    source = src.data
    samples = [v.co.copy() for v in source.vertices] + [p.center.copy() for p in source.polygons]
    copy = src.copy()
    copy.data = source.copy()
    bpy.context.scene.collection.objects.link(copy)
    modifier = copy.modifiers.new("collision", "DECIMATE")
    modifier.decimate_type = "COLLAPSE"
    modifier.ratio = ratio
    evaluated = copy.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = evaluated.to_mesh()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bvh = BVHTree.FromBMesh(bm)
    errors = np.array([bvh.find_nearest(p)[3] for p in samples])
    bm.verts.index_update()
    ## Blender Z-up back to glTF Y-up: (x, y, z) -> (x, z, -y).
    positions = np.array([(v.co.x, v.co.z, -v.co.y) for v in bm.verts], np.float32)
    indices = np.array([[v.index for v in f.verts] for f in bm.faces], np.uint32).reshape(-1)
    source_tris = sum(len(p.vertices) - 2 for p in source.polygons)
    bm.free()
    evaluated.to_mesh_clear()
    return positions, indices, errors, source_tris


def main() -> None:
    glb, node_name, ratio, max_error = _args()
    if not node_name.endswith("-col"):
        raise SystemExit(f"{node_name}: expected a '-col' node (Godot trimesh collision)")
    gltf, blob = _read_glb(glb)
    node = next((n for n in gltf["nodes"] if n.get("name") == node_name), None)
    if node is None:
        raise SystemExit(f"{glb} has no node {node_name}")
    positions, indices, errors, source_tris = _decimate(glb, node_name, ratio)
    error = {"mean_m": round(float(errors.mean()), 4), "p99_m": round(float(np.percentile(errors, 99)), 4),
             "max_m": round(float(errors.max()), 4)}
    if error["max_m"] > max_error:
        raise SystemExit(f"collision copy deviates {error['max_m']} m > {max_error} m; raise --ratio")
    base = node_name[:-len("-col")]
    node["name"] = base
    gltf["meshes"][node["mesh"]]["name"] = base
    pos = _append(gltf, blob, positions, 34962, 5126, "VEC3", True)
    ind = _append(gltf, blob, indices, 34963, 5125, "SCALAR", False)
    gltf["meshes"].append({"name": base + "Collision-colonly", "primitives": [{"attributes": {"POSITION": pos}, "indices": ind}]})
    gltf["nodes"].append({"name": base + "Collision-colonly", "mesh": len(gltf["meshes"]) - 1})
    gltf["scenes"][0]["nodes"].append(len(gltf["nodes"]) - 1)
    _write_glb(glb, gltf, blob)
    sha = hashlib.sha256(open(glb, "rb").read()).hexdigest()
    stamp = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()
    report = {"node": base, "method": f"Blender {bpy.app.version_string} Decimate Collapse ratio {ratio}",
              "source_triangles": source_tris, "collision_triangles": int(indices.size // 3), "error": error,
              "error_measure": "distance from every source vertex and face centre to the collision copy",
              "tool": "tools/blender/landmark_collision.py", "built_at": stamp}
    spec_path = os.path.join(SPEC_DIR, os.path.basename(glb)[:-4] + ".json")
    spec = json.load(open(spec_path, encoding="utf-8"))
    spec.setdefault("collision", {})[base] = report
    spec["asset_sha256"] = sha
    with open(spec_path, "w", encoding="utf-8") as f:
        f.write(json.dumps(spec, indent=1, ensure_ascii=False) + "\n")
    manifest = json.load(open(MANIFEST, encoding="utf-8"))
    rel = os.path.relpath(glb, ROOT).replace(os.sep, "/")
    rec = next(a for a in manifest["assets"] if a.get("godot_scene") == "res://" + rel)
    rec.update({"authoring_state": "artist_modified", "asset_sha256": sha, "updated_at": stamp,
                "asset_revision": int(rec.get("asset_revision") or 0) + 1,
                "authored_by": "tools/blender/landmark_collision.py (simplified collision; visual mesh unchanged)"})
    with open(MANIFEST, "w", encoding="utf-8") as f:
        f.write(json.dumps(manifest, indent=1, ensure_ascii=False) + "\n")
    print(json.dumps(report))


main()
