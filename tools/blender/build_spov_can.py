"""Builds the SPoV canned meat prop from the artist's source (CanModel.rar, see the handoff).

Body and pull ring come as separate FBX parts without materials, rotated -90 deg and scaled 100,
the ring parked at the origin inside the body. This script makes them a game prop:
- real scale: 10.4 cm long, the size of a 340 g luncheon-meat tin; base centred at the origin;
- the lid seam's 40 edges shared by three faces (wall, rolled rim, recessed lid) are split,
  so smoothing never averages across them; normals face outward, sharp above 40 deg;
- the ring lies flat on the recessed lid at one end, its rivet tab towards the centre;
- materials: the painted label (Textures/color.png) is paper, matte and non-metal; the
  source Metallic map marks the whole surface metal, so the label is masked out of it.
Run: python3 tools/blender/build_spov_can.py [source_dir] [--render out_dir]
source_dir defaults to the archive unpacked with `unar` into a temporary folder.
Writes assets/items/spov_can/SPoV_Can.glb (nodes SPoV_Can_Body, SPoV_Can_Ring).
"""
import math
import os
import shutil
import subprocess
import sys
import tempfile

import bpy  # must load before bmesh
import bmesh
import numpy as np
from mathutils import Matrix, Vector

ARCHIVE = "assets/source/spov_canned_meat/CanModel.rar"
OUT = "assets/items/spov_can/SPoV_Can.glb"
## Length of a 340 g luncheon-meat tin, metres; the artist's proportions are kept.
REAL_LENGTH = 0.104
## Recessed lid height in source units (the faces at this level face up).
LID_Z = 0.976
## Ring placement on the lid, source units: tab end towards the centre, a rim's width inside.
RING_END_INSET = 0.24
## Paper label: roughness, and how far its colour must differ from the bare-metal base map.
LABEL_ROUGHNESS = 0.82
LABEL_DIFF = 0.12


def main() -> None:
	args = [a for a in sys.argv[1:] if not a.startswith("--")]
	render_dir = sys.argv[sys.argv.index("--render") + 1] if "--render" in sys.argv else None
	if render_dir in args:
		args.remove(render_dir)
	source = args[0] if args else _unpack()
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.ops.import_scene.fbx(filepath=os.path.join(source, "can_uv_2.fbx"))
	body = _only_new_mesh(set())
	seen = {body}
	bpy.ops.import_scene.fbx(filepath=os.path.join(source, "can_pin_uv.fbx"))
	ring = _only_new_mesh(seen)
	_fix_body(body)
	_place_ring(ring)
	scale = REAL_LENGTH / (_bbox(body)[1].x - _bbox(body)[0].x)
	base = _bbox(body)[0].z
	centre = (_bbox(body)[0] + _bbox(body)[1]) * 0.5
	to_game = Matrix.Scale(scale, 4) @ Matrix.Translation(Vector((-centre.x, -centre.y, -base)))
	for obj in (body, ring):
		obj.data.transform(to_game)
		obj.data.update()
		_smooth(obj, 40.0)
	body.name = body.data.name = "SPoV_Can_Body"
	ring.name = ring.data.name = "SPoV_Can_Ring"
	body.data.materials.append(_body_material(source))
	ring.data.materials.append(_ring_material(source))
	lo, hi = _bbox(body)
	print("spov can: body %.1f x %.1f x %.1f cm, %d tris; ring %d tris" % ((hi.x - lo.x) * 100, (hi.y - lo.y) * 100,
		(hi.z - lo.z) * 100, _tris(body), _tris(ring)))
	os.makedirs(os.path.dirname(OUT), exist_ok=True)
	bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_apply=True,
		export_image_format="AUTO", export_materials="EXPORT")
	print("spov can: wrote", OUT)
	if render_dir:
		_render(render_dir, body)


def _unpack() -> str:
	target = tempfile.mkdtemp(prefix="spov_can_")
	if shutil.which("unar") is None:
		sys.exit("spov can: pass the unpacked source folder, or install unar to unpack %s" % ARCHIVE)
	subprocess.run(["unar", "-q", "-o", target, ARCHIVE], check=True)
	return os.path.join(target, "CanModel")


def _only_new_mesh(seen: set) -> bpy.types.Object:
	meshes = [o for o in bpy.context.scene.objects if o.type == "MESH" and o not in seen]
	assert len(meshes) == 1, "expected one mesh per FBX, got %d" % len(meshes)
	obj = meshes[0]
	obj.data.transform(obj.matrix_world)
	obj.matrix_world = Matrix.Identity(4)
	return obj


## Splits the lid seam (edges with three faces) and points every face outward.
def _fix_body(body: bpy.types.Object) -> None:
	bm = bmesh.new()
	bm.from_mesh(body.data)
	seam = [e for e in bm.edges if len(e.link_faces) > 2]
	bmesh.ops.split_edges(bm, edges=seam)
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	left = sum(1 for e in bm.edges if len(e.link_faces) > 2)
	print("spov can: split %d lid-seam edges, %d left" % (len(seam), left))
	bm.to_mesh(body.data)
	bm.free()


## Flat on the recessed lid at the +X end; the source ring's tab points +Y, turned to -X.
def _place_ring(ring: bpy.types.Object) -> None:
	ring.data.transform(Matrix.Rotation(math.radians(90.0), 4, "Z"))
	lo, hi = _bbox(ring)
	body_end = 2.09
	offset = Vector((body_end - RING_END_INSET - hi.x, -(lo.y + hi.y) * 0.5, LID_Z - lo.z + 0.002))
	ring.data.transform(Matrix.Translation(offset))


def _smooth(obj: bpy.types.Object, angle_deg: float) -> None:
	mesh = obj.data
	mesh.shade_smooth()
	mesh.set_sharp_from_angle(angle=math.radians(angle_deg))


def _image(path: str) -> np.ndarray:
	img = bpy.data.images.load(path, check_existing=True)
	px = np.array(img.pixels[:], dtype=np.float32).reshape(img.size[1], img.size[0], img.channels)
	return px


def _new_image(name: str, rgba: np.ndarray, non_color: bool) -> bpy.types.Image:
	h, w = rgba.shape[:2]
	img = bpy.data.images.new(name, w, h, alpha=False, float_buffer=False)
	img.colorspace_settings.name = "Non-Color" if non_color else "sRGB"
	img.pixels.foreach_set(np.ascontiguousarray(rgba, dtype=np.float32).ravel())
	img.update()
	img.file_format = "PNG"
	img.pack()
	return img


## Paper label where the painted map differs from the bare-metal base; small specks are metal.
def _label_mask(source: str) -> np.ndarray:
	paint = _image(os.path.join(source, "Textures", "color.png"))[..., :3]
	metal = _image(os.path.join(source, "Textures", "DefaultMaterial_BaseColor.png"))[..., :3]
	diff = np.abs(paint - metal).mean(axis=2)
	mask = (diff > LABEL_DIFF).astype(np.float32)
	## Close the paint's worn speckles so the label stays one surface (3x3 majority, twice).
	for _i in range(2):
		pad = np.pad(mask, 1, mode="edge")
		votes = sum(pad[1 + dy:pad.shape[0] - 1 + dy, 1 + dx:pad.shape[1] - 1 + dx] for dy in (-1, 0, 1) for dx in (-1, 0, 1))
		mask = (votes >= 5).astype(np.float32)
	print("spov can: label covers %.0f %% of the body texture" % (mask.mean() * 100.0))
	return mask


def _metal_roughness(rough: np.ndarray, metal: np.ndarray, label: np.ndarray) -> np.ndarray:
	r = rough[..., 0] * (1.0 - label) + LABEL_ROUGHNESS * label
	m = metal[..., 0] * (1.0 - label)
	return np.dstack([np.ones_like(r), r, m, np.ones_like(r)])


def _material(name: str, base: bpy.types.Image, mr: bpy.types.Image, normal: bpy.types.Image) -> bpy.types.Material:
	mat = bpy.data.materials.new(name)
	mat.use_nodes = True
	mat.use_backface_culling = True  # closed tin: single-sided
	nodes, links = mat.node_tree.nodes, mat.node_tree.links
	bsdf = nodes["Principled BSDF"]
	tex = nodes.new("ShaderNodeTexImage")
	tex.image = base
	links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
	mr_tex = nodes.new("ShaderNodeTexImage")
	mr_tex.image = mr
	split = nodes.new("ShaderNodeSeparateColor")
	links.new(mr_tex.outputs["Color"], split.inputs["Color"])
	links.new(split.outputs["Green"], bsdf.inputs["Roughness"])
	links.new(split.outputs["Blue"], bsdf.inputs["Metallic"])
	n_tex = nodes.new("ShaderNodeTexImage")
	n_tex.image = normal
	n_map = nodes.new("ShaderNodeNormalMap")
	links.new(n_tex.outputs["Color"], n_map.inputs["Color"])
	links.new(n_map.outputs["Normal"], bsdf.inputs["Normal"])
	return mat


def _body_material(source: str) -> bpy.types.Material:
	t = os.path.join(source, "Textures")
	label = _label_mask(source)
	paint = _image(os.path.join(t, "color.png"))
	paint[..., 3] = 1.0  # the source alpha copies Metallic; the label is opaque paper
	base = _new_image("SPoV_Can_Body_Albedo", paint, False)
	mr = _new_image("SPoV_Can_Body_MetalRough", _metal_roughness(
		_image(os.path.join(t, "DefaultMaterial_Roughness.png")), _image(os.path.join(t, "DefaultMaterial_Metallic.png")), label), True)
	normal = bpy.data.images.load(os.path.join(t, "DefaultMaterial_Normal.png"))
	normal.colorspace_settings.name = "Non-Color"
	return _material("SPoV_Can_Body", base, mr, normal)


def _ring_material(source: str) -> bpy.types.Material:
	t = os.path.join(source, "Pin_textures")
	base = bpy.data.images.load(os.path.join(t, "DefaultMaterial_BaseColor.png"))
	rough = _image(os.path.join(t, "DefaultMaterial_Roughness.png"))
	mr = _new_image("SPoV_Can_Ring_MetalRough", _metal_roughness(rough, _image(os.path.join(t, "DefaultMaterial_Metallic.png")),
		np.zeros(rough.shape[:2], dtype=np.float32)), True)
	normal = bpy.data.images.load(os.path.join(t, "DefaultMaterial_Normal.png"))
	normal.colorspace_settings.name = "Non-Color"
	return _material("SPoV_Can_Ring", base, mr, normal)


def _bbox(obj: bpy.types.Object) -> tuple:
	vs = [v.co for v in obj.data.vertices]
	return (Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs))),
		Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs))))


def _tris(obj: bpy.types.Object) -> int:
	return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def _render(out_dir: str, body: bpy.types.Object) -> None:
	os.makedirs(out_dir, exist_ok=True)
	scene = bpy.context.scene
	scene.render.engine = "CYCLES"
	scene.cycles.device = "CPU"
	scene.cycles.samples = 48
	scene.render.resolution_x, scene.render.resolution_y = 800, 600
	world = bpy.data.worlds.new("W")
	world.use_nodes = True
	world.node_tree.nodes["Background"].inputs[0].default_value = (0.62, 0.64, 0.68, 1.0)
	scene.world = world
	sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
	sun.data.energy = 3.5
	sun.rotation_euler = (math.radians(50), 0, math.radians(35))
	scene.collection.objects.link(sun)
	cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
	cam.data.lens = 70
	scene.collection.objects.link(cam)
	scene.camera = cam
	target = Vector((0.0, 0.0, 0.035))
	for name, d in {"front": Vector((0.25, -1.0, 0.45)), "back": Vector((-0.3, 1.0, 0.4)), "top": Vector((0.2, -0.35, 1.0)),
			"end": Vector((1.0, -0.25, 0.35))}.items():
		cam.location = target + d.normalized() * 0.32
		cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
		scene.render.filepath = os.path.join(out_dir, "spov_%s.png" % name)
		bpy.ops.render.render(write_still=True)


main()
