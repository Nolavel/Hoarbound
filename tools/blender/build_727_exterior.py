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
LEAF_OUT = os.path.join(ROOT, "assets/world/key_west/landmarks/kw_727_entrance_leaf.glb")
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
	_object(part["name"] + {True: "-col", "only": "-colonly"}.get(part["collision"], ""), bm, mat)


def _plate(part: dict, mat) -> None:
	"""A flat board: outline in the (u, y) plane, from v0 to v1 (it faces +v)."""
	bm = bmesh.new()
	ring = part["outline_uy"]
	back = [bm.verts.new(_p(u, y, part["v0"])) for u, y in ring]
	front = [bm.verts.new(_p(u, y, part["v1"])) for u, y in ring]
	bm.faces.new(front)
	bm.faces.new(list(reversed(back)))
	n = len(ring)
	for k in range(n):
		j = (k + 1) % n
		bm.faces.new([back[k], back[j], front[j], front[k]])
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	_object(part["name"], bm, mat)


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


## One mesh per material and collision role, so about 120 parts draw in about 15 calls; other materials take their own name.
MERGED = {("canopy_steel", True): "Canopy-col", ("canopy_steel", False): "CanopySteel", ("wood_tile", True): "Planters-col",
	("wood_tile", False): "AccentBands", ("wall_paint", False): "WallTrim", ("sign_red", False): "Sign",
	("door_paint", False): "ServiceDoors", ("equipment_grey", False): "Equipment"}


def _merge(parts: list) -> None:
	groups = dict(MERGED)
	for p in parts:
		key = (p["material"], p["collision"] is True)
		if p["collision"] != "only" and key not in groups:
			groups[key] = "".join(w.title() for w in p["material"].split("_")) + ("-col" if key[1] else "")
	for (material, collision), name in groups.items():
		names = [p["name"] + ("-col" if collision and p["kind"] == "box" else "") for p in parts
			if p["material"] == material and (p["collision"] is True) == collision and p["collision"] != "only"]
		objs = [bpy.data.objects[n] for n in names]
		if not objs:
			continue
		bpy.ops.object.select_all(action="DESELECT")
		for o in objs:
			o.select_set(True)
		bpy.context.view_layer.objects.active = objs[0]
		if len(objs) > 1:
			bpy.ops.object.join()
		objs[0].name = name
		objs[0].data.name = name


LEAF_T = 0.045  # 1-3/4 in storefront leaf
LEAF_STILE, LEAF_TOP, LEAF_BOTTOM, LEAF_BAR = 0.06, 0.06, 0.2, 0.045  # frame members (standard narrow-stile storefront; inferred)


def _leaf_box(bm, x0, x1, y0, y1, z0, z1) -> None:
	vs = [bm.verts.new((x, -z, y)) for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)]
	for f in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
		bm.faces.new([vs[i] for i in f])


def _entrance_leaf(spec: dict) -> None:
	"""The opening leaf of the storefront for HingedDoor: DoorLeaf (bronze frame, 2 x 2 lites, pulls) with DoorGlass.

	Godot frame of the hut leaf: centred, x across the leaf, y up, z through it. The glass carries the frost data the
	window panes get from landmark_glass_frost.py (UV 0..1 across the pane, COLOR = coverage, heated, seed).
	"""
	from reality import landmark_glass_frost as frost
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bronze = _material("storefront_bronze", facade_727.STOREFRONT_BRONZE)
	door = next(o for o in spec["interior"]["openings"] if o["name"] == "MainDoor")
	w, h = float(door["width_m"]) - 0.01, float(door["y1"]) - float(door["y0"]) - 0.02
	x0, x1, y0, y1, t = -w / 2, w / 2, -h / 2, h / 2, LEAF_T / 2
	bm = bmesh.new()
	_leaf_box(bm, x0, x0 + LEAF_STILE, y0, y1, -t, t)
	_leaf_box(bm, x1 - LEAF_STILE, x1, y0, y1, -t, t)
	_leaf_box(bm, x0, x1, y1 - LEAF_TOP, y1, -t, t)
	_leaf_box(bm, x0, x1, y0, y0 + LEAF_BOTTOM, -t, t)
	_leaf_box(bm, x0, x1, -LEAF_BAR / 2, LEAF_BAR / 2, -t, t)
	_leaf_box(bm, -LEAF_BAR / 2, LEAF_BAR / 2, y0, y1, -t, t)
	for z in (t, -t - 0.06):  # pulls on both faces, by the free edge (+x; the hinge is at -x)
		_leaf_box(bm, x1 - 0.13, x1 - 0.1, -0.35, 0.35, z, z + 0.06)
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	_object("DoorLeaf", bm, bronze)
	glass_mat = bpy.data.materials.new("window_glass")
	gm = bpy.data.meshes.new("DoorGlass")
	gx0, gx1, gy0, gy1 = x0 + LEAF_STILE, x1 - LEAF_STILE, y0 + LEAF_BOTTOM, y1 - LEAF_TOP
	gt = 0.006
	verts = [(x, -z, y) for x in (gx0, gx1) for y in (gy0, gy1) for z in (-gt, gt)]
	gm.from_pydata(verts, [], [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)])
	uv = gm.uv_layers.new(name="UVMap")
	for loop in gm.loops:  # u across the pane, v = 0 at its top, as landmark_glass_frost.py gives the panes
		x, _, y = verts[loop.vertex_index]
		uv.data[loop.index].uv = ((x - gx0) / (gx1 - gx0), (gy1 - y) / (gy1 - gy0))
	cover = frost.COVERAGE_RANGE[0] + (frost.COVERAGE_RANGE[1] - frost.COVERAGE_RANGE[0]) * frost._unit_hash("MainDoor")
	col = gm.color_attributes.new("Color", "FLOAT_COLOR", "POINT")
	for k in range(8):
		col.data[k].color = (cover, 1.0, frost._unit_hash("MainDoor|seed"), 1.0)
	gm.materials.append(glass_mat)
	glass = bpy.data.objects.new("DoorGlass", gm)
	bpy.context.collection.objects.link(glass)
	glass.parent = bpy.data.objects["DoorLeaf"]
	bpy.ops.export_scene.gltf(filepath=LEAF_OUT, export_format="GLB", export_yup=True, export_apply=True,
		export_vertex_color="ACTIVE")
	print("727 entrance leaf:", LEAF_OUT, round(w, 3), "x", round(h, 3))


def main() -> None:
	bpy.ops.wm.read_factory_settings(use_empty=True)
	spec = json.load(open(SPEC, encoding="utf-8"))
	roof = facade_727.roof_outline_from_glb(SHELL, spec["interior"]["plan_yaw_rad"])
	mats = {k: _material(k, v) for k, v in facade_727.MATERIALS.items()}
	build = {"box": _box, "rod": _rod, "prism": _prism, "text": _text, "plate": _plate}
	parts = facade_727.parts(spec, roof)
	blocked = facade_727.covered(spec, parts)
	if blocked:
		raise SystemExit(f"exterior parts block openings: {blocked}")
	for part in parts:
		build[part["kind"]](part, mats[part["material"]])
	_merge(parts)
	bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_apply=True)
	print("727 exterior:", OUT, len(parts), "parts")
	_entrance_leaf(spec)


if __name__ == "__main__":
	main()
