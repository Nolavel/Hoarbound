"""Builds the thermos prop (#260) procedurally: a 0.5 l steel vacuum flask, painted and worn.

Real scale: 7.5 cm across, 24 cm tall with the lid shut; base centred at the origin, +Y up in Godot.
- body: a cylinder with a rounded foot and a shoulder that narrows to the neck;
- neck: bare steel with a two-turn external thread (visible when the lid is open);
- lid: a flip-top cap that does not come off: it turns on a hinge at the back (+X side of the
  neck collar is the latch, -X the hinge). The lid is its own node, Thermos_Lid, with its origin on
  the hinge axis, so the game opens it by rotating that node about its local Z.
Material slots carry names the game maps to its worn-paint shader (carabiner.gdshader):
Thermos_Paint (body), Thermos_LidPaint (lid), Thermos_Steel (neck, thread, hinge, latch).
Run: python3 tools/blender/build_thermos.py [--render out_dir]
Writes assets/items/thermos/Thermos.glb (nodes Thermos_Body, Thermos_Lid).
"""
import math
import os
import sys

import bpy  # must load before bmesh
import bmesh
from mathutils import Matrix, Vector

OUT = "assets/items/thermos/Thermos.glb"
## Body radius, body height to the shoulder top, and the neck, metres (Blender Z up).
RADIUS = 0.0375
BODY_H = 0.185
FOOT_ROUND = 0.006
SHOULDER_H = 0.018
NECK_R = 0.026
NECK_H = 0.022
## Thread: pitch, turns, ridge depth.
THREAD_PITCH = 0.004
THREAD_TURNS = 2.0
THREAD_DEPTH = 0.0016
## Lid: cap radius, height, hinge offset from the axis, segments round.
LID_R = 0.031
LID_H = 0.034
HINGE_OUT = 0.034
SEGMENTS = 40


def main() -> None:
	render_dir = sys.argv[sys.argv.index("--render") + 1] if "--render" in sys.argv else ""
	bpy.ops.wm.read_factory_settings(use_empty=True)
	paint = _material("Thermos_Paint", (0.20, 0.30, 0.22, 1.0), 0.0, 0.6)
	lid_paint = _material("Thermos_LidPaint", (0.16, 0.24, 0.18, 1.0), 0.0, 0.6)
	steel = _material("Thermos_Steel", (0.62, 0.62, 0.64, 1.0), 1.0, 0.35)
	body = _body(paint, steel)
	lid = _lid(lid_paint, steel)
	## Blender Z up to Godot Y up happens in the exporter (+Y up); names are the game's contract.
	os.makedirs(os.path.dirname(OUT), exist_ok=True)
	bpy.ops.object.select_all(action="SELECT")
	bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_yup=True,
		export_apply=True, export_materials="EXPORT")
	print("thermos: wrote %s (body %d verts, lid %d verts)" % (OUT, len(body.data.vertices), len(lid.data.vertices)))
	if render_dir:
		_render(render_dir, lid)


## The body: a lathe profile (foot, wall, shoulder, neck collar) spun round Z, plus the thread.
def _body(paint: bpy.types.Material, steel: bpy.types.Material) -> bpy.types.Object:
	neck_top = BODY_H + SHOULDER_H + NECK_H
	profile = [(0.0, 0.0)]
	for k in range(5):
		a = (k / 4.0) * math.pi * 0.5
		profile.append((RADIUS - FOOT_ROUND + math.sin(a) * FOOT_ROUND, FOOT_ROUND - math.cos(a) * FOOT_ROUND))
	profile += [(RADIUS, BODY_H - 0.004), (RADIUS - 0.0015, BODY_H)]
	for k in range(1, 6):
		t = k / 5.0
		profile.append((RADIUS - 0.0015 + (NECK_R + 0.002 - RADIUS + 0.0015) * math.sin(t * math.pi * 0.5), BODY_H + SHOULDER_H * t))
	## The steel neck starts at the collar ring.
	steel_from = len(profile)
	profile += [(NECK_R, BODY_H + SHOULDER_H), (NECK_R, neck_top - 0.002), (NECK_R - 0.002, neck_top), (NECK_R - 0.006, neck_top)]
	mesh = bpy.data.meshes.new("Thermos_Body")
	bm = bmesh.new()
	rings = []
	for i in range(SEGMENTS):
		a = i / SEGMENTS * math.tau
		ring = [bm.verts.new((r * math.cos(a), r * math.sin(a), z)) for r, z in profile]
		rings.append(ring)
	for i in range(SEGMENTS):
		a, b = rings[i], rings[(i + 1) % SEGMENTS]
		for k in range(len(profile) - 1):
			face = bm.faces.new((a[k], b[k], b[k + 1], a[k + 1]))
			face.material_index = 1 if k >= steel_from - 1 else 0
			face.smooth = True
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	bm.to_mesh(mesh)
	bm.free()
	obj = bpy.data.objects.new("Thermos_Body", mesh)
	bpy.context.collection.objects.link(obj)
	mesh.materials.append(paint)
	mesh.materials.append(steel)
	_thread(obj, BODY_H + SHOULDER_H + 0.003)
	_hinge_block(obj, BODY_H + SHOULDER_H)
	return obj


## A helical ridge round the neck: a small triangle swept up THREAD_TURNS turns, joined to the body.
def _thread(body: bpy.types.Object, z0: float) -> None:
	bm = bmesh.new()
	steps = int(SEGMENTS * THREAD_TURNS)
	prev = None
	first = None
	for s in range(steps + 1):
		a = s / SEGMENTS * math.tau
		z = z0 + THREAD_PITCH * s / SEGMENTS
		c, n = math.cos(a), math.sin(a)
		tri = [bm.verts.new(((NECK_R - 0.0002) * c, (NECK_R - 0.0002) * n, z - 0.0012)),
			bm.verts.new(((NECK_R + THREAD_DEPTH) * c, (NECK_R + THREAD_DEPTH) * n, z)),
			bm.verts.new(((NECK_R - 0.0002) * c, (NECK_R - 0.0002) * n, z + 0.0012))]
		if prev:
			for k in range(2):
				f = bm.faces.new((prev[k], tri[k], tri[k + 1], prev[k + 1]))
				f.smooth = True
		else:
			first = tri
		prev = tri
	bm.faces.new(first)
	bm.faces.new(list(reversed(prev)))
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	_append_bmesh(body, bm, 1)


## The hinge knuckles and the latch keeper on the collar (steel, part of the body).
def _hinge_block(body: bpy.types.Object, z: float) -> None:
	bm = bmesh.new()
	## Hinge knuckle pair at -X, axis along Y.
	for y in (-0.008, 0.008):
		res = bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=0.0028, radius2=0.0028, depth=0.006,
			matrix=Matrix.Translation((-HINGE_OUT, y, z + NECK_H)) @ Matrix.Rotation(math.pi * 0.5, 4, "X"))
	bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation((-HINGE_OUT + 0.004, 0.0, z + NECK_H - 0.006)) @ Matrix.Diagonal((0.008, 0.022, 0.012, 1.0)))
	## Latch keeper at +X: a small ledge under the lid's catch.
	bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation((NECK_R + 0.006, 0.0, z + NECK_H - 0.008)) @ Matrix.Diagonal((0.006, 0.012, 0.004, 1.0)))
	for f in bm.faces:
		f.smooth = False
	_append_bmesh(body, bm, 1)


## The flip-top lid: a domed cap, a knuckle on the hinge axis and a catch over the latch.
## Built round the hinge axis so its object origin is the axis (Blender Y axis line at -X).
def _lid(paint: bpy.types.Material, steel: bpy.types.Material) -> bpy.types.Object:
	z0 = BODY_H + SHOULDER_H + NECK_H - 0.012
	bm = bmesh.new()
	profile = [(0.0, LID_H + 0.002), (LID_R * 0.6, LID_H + 0.001), (LID_R - 0.004, LID_H - 0.002), (LID_R, LID_H - 0.007), (LID_R, 0.0), (LID_R - 0.003, 0.0)]
	rings = []
	for i in range(SEGMENTS):
		a = i / SEGMENTS * math.tau
		rings.append([bm.verts.new((r * math.cos(a), r * math.sin(a), z0 + z)) for r, z in profile])
	for i in range(SEGMENTS):
		a, b = rings[i], rings[(i + 1) % SEGMENTS]
		for k in range(len(profile) - 1):
			f = bm.faces.new((a[k], b[k], b[k + 1], a[k + 1]))
			f.smooth = True
	## Grip ribs round the cap's skirt.
	for i in range(0, SEGMENTS, 2):
		a = i / SEGMENTS * math.tau
		bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation(((LID_R + 0.0006) * math.cos(a), (LID_R + 0.0006) * math.sin(a), z0 + LID_H * 0.45))
			@ Matrix.Rotation(a, 4, "Z") @ Matrix.Diagonal((0.0014, 0.0018, LID_H * 0.6, 1.0)))
	steel_start = len(bm.faces)
	## Knuckle on the hinge axis, between the body's two knuckles.
	bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=0.0028, radius2=0.0028, depth=0.009,
		matrix=Matrix.Translation((-HINGE_OUT, 0.0, BODY_H + SHOULDER_H + NECK_H)) @ Matrix.Rotation(math.pi * 0.5, 4, "X"))
	bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation((-HINGE_OUT + 0.003, 0.0, z0 + 0.004)) @ Matrix.Diagonal((0.006, 0.008, 0.006, 1.0)))
	## Catch: a tab down the +X side that hooks the keeper.
	bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation((LID_R + 0.003, 0.0, z0 - 0.002)) @ Matrix.Diagonal((0.004, 0.012, 0.016, 1.0)))
	for f in list(bm.faces)[steel_start:]:
		f.material_index = 1
		f.smooth = False
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	mesh = bpy.data.meshes.new("Thermos_Lid")
	bm.to_mesh(mesh)
	bm.free()
	mesh.materials.append(paint)
	mesh.materials.append(steel)
	obj = bpy.data.objects.new("Thermos_Lid", mesh)
	bpy.context.collection.objects.link(obj)
	## Origin on the hinge axis, so rotating the node about the axis opens the lid.
	pivot = Vector((-HINGE_OUT, 0.0, BODY_H + SHOULDER_H + NECK_H))
	mesh.transform(Matrix.Translation(-pivot))
	obj.location = pivot
	return obj


def _append_bmesh(obj: bpy.types.Object, bm: bmesh.types.BMesh, material_index: int) -> None:
	for f in bm.faces:
		f.material_index = material_index
	temp = bpy.data.meshes.new("part")
	bm.to_mesh(temp)
	bm.free()
	joined = bmesh.new()
	joined.from_mesh(obj.data)
	joined.from_mesh(temp)
	joined.to_mesh(obj.data)
	joined.free()
	bpy.data.meshes.remove(temp)


def _material(name: str, colour: tuple, metallic: float, roughness: float) -> bpy.types.Material:
	material = bpy.data.materials.new(name)
	material.use_nodes = True
	bsdf = material.node_tree.nodes.get("Principled BSDF")
	bsdf.inputs["Base Color"].default_value = colour
	bsdf.inputs["Metallic"].default_value = metallic
	bsdf.inputs["Roughness"].default_value = roughness
	return material


## Optional check renders: shut and open (lid turned 110 deg on its hinge), three-quarter view.
def _render(out_dir: str, lid: bpy.types.Object) -> None:
	os.makedirs(out_dir, exist_ok=True)
	scene = bpy.context.scene
	scene.render.engine = "CYCLES"
	scene.cycles.samples = 24
	scene.render.resolution_x = 640
	scene.render.resolution_y = 640
	cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
	scene.collection.objects.link(cam)
	scene.camera = cam
	cam.location = (0.32, -0.32, 0.26)
	cam.rotation_euler = (math.radians(68), 0.0, math.radians(45))
	sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
	scene.collection.objects.link(sun)
	sun.rotation_euler = (math.radians(50), 0.0, math.radians(30))
	scene.world = bpy.data.worlds.new("w")
	scene.world.color = (0.2, 0.2, 0.22)
	for i, angle in enumerate((0.0, 110.0)):
		lid.rotation_euler = (0.0, -math.radians(angle), 0.0)
		scene.render.filepath = os.path.join(out_dir, "thermos_%d.png" % i)
		bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
	main()
