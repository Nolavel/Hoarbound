"""Builds the 727 Fort Street exterior dressing (2020 permit, as built) as assets/world/key_west/landmarks/kw_727_exterior.glb.

The parts and every number come from tools/world/reality/facade_727.py; this script only turns them into
meshes. Frame: the landmark plan frame (Godot +X = u along the facade, +Z = v towards Fort Street, +Y up,
origin at the landmark ground), so KeyWest727Shelter places it under its House node. Meshes named *-col
get static collision on import. Run: python3 tools/blender/build_727_exterior.py (needs pip bpy, shapely).
"""
import json
import os
import sys

import bpy  # must load before bmesh
import bmesh
import mathutils
import shapely

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "world"))
from reality import facade_727  # noqa: E402

SPEC = os.path.join(ROOT, "data/world/key_west/reality/landmarks/kw_727_fort_st.json")
SHELL = os.path.join(ROOT, "assets/world/key_west/landmarks/kw_727_fort_st.glb")
OUT = os.path.join(ROOT, "assets/world/key_west/landmarks/kw_727_exterior.glb")
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"


def _linear(c: int) -> float:
	s = c / 255.0
	return s / 12.92 if s <= 0.04045 else ((s + 0.055) / 1.055) ** 2.4


def _material(name: str, srgb: tuple) -> bpy.types.Material:
	mat = bpy.data.materials.new(name)
	bsdf = mat.node_tree.nodes["Principled BSDF"] if mat.node_tree else None
	if bsdf is None:
		mat.use_nodes = True
		bsdf = mat.node_tree.nodes["Principled BSDF"]
	bsdf.inputs["Base Color"].default_value = (*[_linear(c) for c in srgb], 1.0)
	bsdf.inputs["Roughness"].default_value = 0.4 if name == "canopy_steel" else 0.85
	return mat


def _p(u: float, y: float, v: float) -> tuple:
	"""Godot plan (u, y, v) -> Blender (x, y, z); the glTF exporter turns Blender Z-up into Godot Y-up."""
	return (u, -v, y)


def _object(name: str, bm: bmesh.types.BMesh, mat: bpy.types.Material) -> None:
	mesh = bpy.data.meshes.new(name)
	bm.to_mesh(mesh)
	bm.free()
	mesh.materials.append(mat)
	bpy.context.collection.objects.link(bpy.data.objects.new(name, mesh))


def _box(part: dict, mat) -> None:
	(u0, y0, v0), (u1, y1, v1) = part["box"]
	bm = bmesh.new()
	verts = [bm.verts.new(_p(u, y, v)) for u in (u0, u1) for y in (y0, y1) for v in (v0, v1)]
	for f in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
		bm.faces.new([verts[i] for i in f])
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	_object(part["name"] + ("-col" if part["collision"] else ""), bm, mat)


def _rod(part: dict, mat) -> None:
	bm = bmesh.new()
	a, b = part["from"], part["to"]
	bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=part["radius"], radius2=part["radius"], depth=1.0)
	pa, pb = mathutils.Vector(_p(*a)), mathutils.Vector(_p(*b))
	axis = pb - pa
	rot = mathutils.Vector((0, 0, 1)).rotation_difference(axis.normalized()).to_matrix().to_4x4()
	scale = mathutils.Matrix.Diagonal((1, 1, axis.length, 1))
	bmesh.ops.transform(bm, matrix=mathutils.Matrix.Translation((pa + pb) / 2) @ rot @ scale, verts=bm.verts)
	_object(part["name"], bm, mat)


def _prism(part: dict, mat) -> None:
	bm = bmesh.new()
	rings = part["polygon_uv"]
	poly = shapely.Polygon(rings[0], rings[1:])
	for tri in shapely.delaunay_triangles(poly).geoms:
		if not poly.contains(tri.representative_point()):
			continue
		pts = list(tri.exterior.coords)[:3]
		bm.faces.new([bm.verts.new(_p(u, part["top_y"], v)) for u, v in pts])
	for ring in rings:
		for (ua, va), (ub, vb) in zip(ring[:-1], ring[1:]):
			bm.faces.new([bm.verts.new(_p(ua, part["bottom_y"], va)), bm.verts.new(_p(ub, part["bottom_y"], vb)),
				bm.verts.new(_p(ub, part["top_y"], vb)), bm.verts.new(_p(ua, part["top_y"], va))])
	bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	_object(part["name"], bm, mat)


def _text(part: dict, mat) -> None:
	curve = bpy.data.curves.new(part["name"], "FONT")
	curve.body = part["text"]
	curve.font = bpy.data.fonts.load(FONT)
	curve.size = part["cap_h"] / 0.73  # DejaVu Serif cap height is 0.73 of the em
	curve.extrude = 0.02
	curve.align_x, curve.align_y = "CENTER", "CENTER"
	obj = bpy.data.objects.new(part["name"], curve)
	bpy.context.collection.objects.link(obj)
	u, y, v = part["centre"]
	obj.location = _p(u, y, v)
	obj.rotation_euler = (1.5707963, 0.0, 0.0)  # the letters face +v (Fort Street)
	bpy.context.view_layer.objects.active = obj
	obj.select_set(True)
	bpy.ops.object.convert(target="MESH")
	obj.data.materials.clear()
	obj.data.materials.append(mat)


def main() -> None:
	bpy.ops.wm.read_factory_settings(use_empty=True)
	spec = json.load(open(SPEC, encoding="utf-8"))
	roof = facade_727.roof_outline_from_glb(SHELL, spec["interior"]["plan_yaw_rad"])
	mats = {k: _material(k, v) for k, v in facade_727.MATERIALS.items()}
	build = {"box": _box, "rod": _rod, "prism": _prism, "text": _text}
	for part in facade_727.parts(spec, roof):
		build[part["kind"]](part, mats[part["material"]])
	bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_apply=True)
	print("727 exterior:", OUT, len(facade_727.parts(spec, roof)), "parts; deferred:",
		[p["name"] for p in facade_727.deferred(spec, roof)])


if __name__ == "__main__":
	main()
