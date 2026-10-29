"""Builds the hatchet and the claw hammer (#260) after the owner's Build-Rite references, real scale.

Both stand with the handle along +Y from y = 0 (the butt) and the head on top; the hatchet's blade and
the hammer's face point +X, the label faces +Z. Material slots the game maps to its own shaders:
Tool_Metal (rusty steel), Tool_Edge (the honed bevel), Tool_Handle (coloured plastic), Tool_Grip
(dark rubber), Tool_Tag (the store label, UVs over its texture).
The price tags are drawn here too: assets/items/<tool>/<tool>_tag.png (alpha marks torn edges).
Run: python3 tools/blender/build_hand_tools.py [--render out_dir]
Writes assets/items/axe/Axe.glb and assets/items/hammer/Hammer.glb.
"""
import math
import os
import random
import sys

import bpy  # must load before bmesh
import bmesh
from mathutils import Matrix, Vector
from PIL import Image, ImageDraw, ImageFont

FONTS = ["/usr/share/fonts/opentype/inter/InterDisplay-Bold.otf", "/usr/share/fonts/opentype/inter/Inter-Bold.otf",
	"/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"]
SEGMENTS = 18
SLOTS = ["Tool_Metal", "Tool_Edge", "Tool_Handle", "Tool_Grip", "Tool_Tag"]
METAL, EDGE, HANDLE, GRIP, TAG = range(5)


def main() -> None:
	render_dir = sys.argv[sys.argv.index("--render") + 1] if "--render" in sys.argv else ""
	_tag("assets/items/axe/axe_tag.png", (0.93, 0.68, 0.16), ["BUILD-RITE"], "$24.99", 11)
	_tag("assets/items/hammer/hammer_tag.png", (0.93, 0.68, 0.16), ["BUILD-RITE", "HAMMER"], "$9.49", 23)
	for name, build, colour in (("Axe", _axe, (0.85, 0.62, 0.12, 1.0)), ("Hammer", _hammer, (0.72, 0.13, 0.08, 1.0))):
		bpy.ops.wm.read_factory_settings(use_empty=True)
		materials = _materials(colour)
		obj = build(materials)
		out = "assets/items/%s/%s.glb" % (name.lower(), name)
		os.makedirs(os.path.dirname(out), exist_ok=True)
		bpy.ops.object.select_all(action="SELECT")
		bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_yup=True,
			export_apply=True, export_materials="EXPORT")
		print("hand tools: wrote %s (%d verts)" % (out, len(obj.data.vertices)))
		if render_dir:
			_render(render_dir, name.lower())


## The hatchet: a lofted wedge head with a bearded blade, a curved oval handle with a dark rubber
## grip and logo patch, the price label, and a flat butt with a triangular hole.
def _axe(materials: list) -> bpy.types.Object:
	bm = bmesh.new()
	zones = [(0.0, HANDLE), (0.062, GRIP), (0.165, HANDLE)]
	_handle(bm, 0.36, 0.0165, 0.0115, zones, curve=0.012)
	_butt(bm, 0.0215, 0.0125, HANDLE)
	_label(bm, 0.19, 0.267, 0.0165, 0.0115, 0.012, 0.36)  # tag aspect 1.75 over half the girth
	_axe_head(bm)
	return _object("Axe", bm, materials)


## The claw hammer: an eye block, a round neck to an octagonal face, a curved split claw, a red
## handle with a ribbed rubber grip, the price label and the holed butt.
def _hammer(materials: list) -> bpy.types.Object:
	bm = bmesh.new()
	zones = [(0.0, HANDLE), (0.045, GRIP), (0.16, HANDLE)]
	_handle(bm, 0.30, 0.0155, 0.011, zones, curve=0.006, ribs=(0.05, 0.155))
	_butt(bm, 0.0195, 0.0115, HANDLE)
	_label(bm, 0.183, 0.256, 0.0155, 0.011, 0.006, 0.30)
	_hammer_head(bm)
	return _object("Hammer", bm, materials)


## Handle: an elliptical loft (rx across the blade direction X, rz across Z) bowed by `curve` toward
## -X at mid-length, swelling at the butt; each section takes its zone's material.
def _handle(bm: bmesh.types.BMesh, length: float, rx: float, rz: float, zones: list, curve: float, ribs: tuple = ()) -> None:
	sections = []
	steps = 44
	for k in range(steps + 1):
		y = 0.05 + (length - 0.05) * k / steps
		t = (y - 0.05) / (length - 0.05)
		swell = 1.0 + 0.32 * max(0.0, 1.0 - t / 0.18) ** 2
		taper = 1.0 - 0.12 * t
		rib = 1.0
		if ribs and ribs[0] < y < ribs[1]:
			rib = 1.0 + 0.06 * max(0.0, math.sin((y - ribs[0]) / 0.008 * math.pi * 2.0))
		material = HANDLE
		for start, mat in zones:
			if y >= start:
				material = mat
		sections.append((Vector((_bow(y, length, curve), y, 0.0)), rx * swell * taper * rib, rz * swell * taper * rib, material))
	_loft(bm, sections, cap_start=False, cap_end=True)


def _bow(y: float, length: float, curve: float) -> float:
	return -curve * math.sin(math.pi * min(max(y / length, 0.0), 1.0))


## The butt: a flat knob flaring under the handle with a triangular hole, extruded across Z: an
## outer ring and the hole's triangle resampled to the same count, bridged quad by quad.
def _butt(bm: bmesh.types.BMesh, rx: float, rz: float, material: int) -> None:
	n = 24
	centre = Vector((0.0, 0.028))
	outer = []
	hole = []
	corners = [Vector((0.0, 0.04)), Vector((-0.0075, 0.014)), Vector((0.0075, 0.014))]
	for k in range(n):
		a = math.pi * 0.5 + k / n * math.tau
		low = max(0.0, -math.sin(a))
		outer.append(Vector((math.cos(a) * rx * (0.9 + 0.14 * low), centre.y + math.sin(a) * (0.026 + 0.003 * low))))
		hole.append(_triangle_point(corners, k / n))
	rings = []
	for z in (rz, -rz):
		rings.append(([bm.verts.new((p.x, p.y, z)) for p in outer], [bm.verts.new((p.x, p.y, z * 1.0)) for p in hole]))
	faces = []
	(top_o, top_h), (bot_o, bot_h) = rings
	for k in range(n):
		j = (k + 1) % n
		faces.append(bm.faces.new((top_o[k], top_o[j], top_h[j], top_h[k])))
		faces.append(bm.faces.new((bot_o[j], bot_o[k], bot_h[k], bot_h[j])))
		faces.append(bm.faces.new((top_o[j], top_o[k], bot_o[k], bot_o[j])))
		faces.append(bm.faces.new((top_h[k], top_h[j], bot_h[j], bot_h[k])))
	for f in faces:
		f.material_index = material
		f.smooth = False


## A point a share t of the way round a closed polygon (by perimeter length).
def _triangle_point(corners: list, t: float) -> Vector:
	edges = [(corners[i], corners[(i + 1) % len(corners)]) for i in range(len(corners))]
	total = sum((b - a).length for a, b in edges)
	walk = t * total
	for a, b in edges:
		length = (b - a).length
		if walk <= length:
			return a.lerp(b, walk / length)
		walk -= length
	return corners[0]


## The store label: a thin band right round the handle between y0 and y1, the tag texture twice
## round it (u 0..2, repeating), so it reads from either side.
def _label(bm: bmesh.types.BMesh, y0: float, y1: float, rx: float, rz: float, curve: float, length: float) -> None:
	uv_layer = bm.loops.layers.uv.verify()
	cols = 24
	rows = 8
	grid = []
	for r in range(rows + 1):
		y = y0 + (y1 - y0) * r / rows
		t = (y - 0.05) / (length - 0.05)
		scale = (1.0 - 0.12 * t) * 1.06
		row = []
		for c in range(cols + 1):
			a = math.radians(-180.0 + 360.0 * c / cols)
			row.append(bm.verts.new((_bow(y, length, curve) + math.sin(a) * rx * scale, y, math.cos(a) * rz * scale)))
		grid.append(row)
	for r in range(rows):
		for c in range(cols):
			f = bm.faces.new((grid[r][c], grid[r][c + 1], grid[r + 1][c + 1], grid[r + 1][c]))
			f.material_index = TAG
			f.smooth = True
			for loop, (rr, cc) in zip(f.loops, ((r, c), (r, c + 1), (r + 1, c + 1), (r + 1, c))):
				loop[uv_layer].uv = (2.0 * cc / cols + 0.5, rr / rows)  # each copy centred on +Z / -Z


## Hatchet head: vertical sections from the poll (-X) to the edge (+X); the blade drops into a beard
## and thins to the edge; the last 12 mm is the honed bevel.
def _axe_head(bm: bmesh.types.BMesh) -> None:
	xs = [-0.046, -0.04, -0.02, -0.012, 0.0, 0.012, 0.02, 0.035, 0.05, 0.065, 0.08, 0.092, 0.1, 0.106, 0.112, 0.116]
	rings = []
	for x in xs:
		f = min(max(0.0, (x - 0.012) / 0.104), 1.0)
		top = 0.358 + 0.012 * f ** 1.6
		bottom = 0.300 - 0.042 * f ** 1.8
		half = 0.0165 * (1.0 - f) ** 0.9 + 0.0009
		if x < -0.012:
			half = 0.0175
			top, bottom = 0.356, 0.304
		bev = min(0.0025, half * 0.6)
		ring = [bm.verts.new((x, top - bev, half)), bm.verts.new((x, top, half - bev)), bm.verts.new((x, top, -half + bev)),
			bm.verts.new((x, top - bev, -half)), bm.verts.new((x, bottom + bev, -half)), bm.verts.new((x, bottom, -half + bev)),
			bm.verts.new((x, bottom, half - bev)), bm.verts.new((x, bottom + bev, half))]
		rings.append((ring, EDGE if x > 0.103 else METAL))
	for k in range(len(rings) - 1):
		a, mat = rings[k]
		b, _ = rings[k + 1]
		for i in range(8):
			face = bm.faces.new((a[i], a[(i + 1) % 8], b[(i + 1) % 8], b[i]))
			face.material_index = mat
			face.smooth = False
	cap = bm.faces.new(list(reversed(rings[0][0])))
	cap.material_index = METAL
	end = bm.faces.new(rings[-1][0])
	end.material_index = EDGE


## Hammer head: eye block round the handle top, a round neck to an octagonal striking face (+X), and a
## curved claw (-X) split into two prongs.
def _hammer_head(bm: bmesh.types.BMesh) -> None:
	_box(bm, (0.0, 0.31, 0.0), (0.019, 0.019, 0.0135), METAL)
	sections = []
	for k in range(9):
		x = 0.016 + 0.046 * k / 8
		r = 0.0115 if x < 0.035 else 0.0165
		if x > 0.058:
			r = 0.0150
		sections.append((Vector((x, 0.312, 0.0)), r, r, METAL))
	_loft(bm, sections, axis="X", cap_start=True, cap_end=True, segments=8)
	for side in (-1.0, 1.0):
		claw = []
		for k in range(10):
			t = k / 9.0
			x = -0.016 - 0.062 * t
			y = 0.318 - 0.042 * t ** 2.0
			w = 0.017 * (1.0 - 0.6 * t)
			h = 0.02 * (1.0 - 0.55 * t)
			claw.append((Vector((x, y, side * (0.0035 + w * 0.5))), h, w * 0.5, METAL))
		_loft(bm, claw, axis="X", cap_start=True, cap_end=True, segments=6, tilt=True)


def _box(bm: bmesh.types.BMesh, centre: tuple, half: tuple, material: int) -> None:
	res = bmesh.ops.create_cube(bm, size=1.0)
	for v in res["verts"]:
		v.co = Vector((centre[0] + v.co.x * half[0] * 2.0, centre[1] + v.co.y * half[1] * 2.0, centre[2] + v.co.z * half[2] * 2.0))
	for f in {f for v in res["verts"] for f in v.link_faces}:
		f.material_index = material
		f.smooth = False


## A loft of elliptical sections: (centre, r1, r2, material). axis "Y" sweeps up (r1 along X, r2 along
## Z); "X" sweeps along X (r1 along Y, r2 along Z), tilted to the path's slope when `tilt`.
def _loft(bm: bmesh.types.BMesh, sections: list, axis: str = "Y", cap_start: bool = True, cap_end: bool = True,
		segments: int = SEGMENTS, tilt: bool = False) -> None:
	rings = []
	for idx, (c, r1, r2, mat) in enumerate(sections):
		ring = []
		slope = 0.0
		if tilt and len(sections) > 1:
			a = sections[max(idx - 1, 0)][0]
			b = sections[min(idx + 1, len(sections) - 1)][0]
			slope = math.atan2(b.y - a.y, b.x - a.x) + math.pi
		for s in range(segments):
			a = s / segments * math.tau + (math.pi / segments if segments == 8 else 0.0)
			if axis == "Y":
				ring.append(bm.verts.new((c.x + math.sin(a) * r1, c.y, c.z + math.cos(a) * r2)))
			else:
				dy = math.cos(a) * r1
				ring.append(bm.verts.new((c.x + math.sin(slope) * -dy * (1.0 if tilt else 0.0), c.y + dy * (math.cos(slope) * -1.0 if tilt else 1.0), c.z + math.sin(a) * r2)))
		rings.append((ring, mat))
	for k in range(len(rings) - 1):
		a, mat = rings[k]
		b, _ = rings[k + 1]
		for i in range(segments):
			face = bm.faces.new((a[i], a[(i + 1) % segments], b[(i + 1) % segments], b[i]))
			face.material_index = mat
			face.smooth = segments > 8
	if cap_start:
		face = bm.faces.new(list(reversed(rings[0][0])))
		face.material_index = rings[0][1]
	if cap_end:
		face = bm.faces.new(rings[-1][0])
		face.material_index = rings[-1][1]


def _object(name: str, bm: bmesh.types.BMesh, materials: list) -> bpy.types.Object:
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	mesh = bpy.data.meshes.new(name)
	bm.to_mesh(mesh)
	bm.free()
	## Built Y-up with the label on +Z; Blender is Z-up, so turn +Y to +Z (the label to -Y, which the
	## Y-up export makes Godot +Z again).
	mesh.transform(Matrix.Rotation(math.radians(90.0), 4, "X"))
	for material in materials:
		mesh.materials.append(material)
	obj = bpy.data.objects.new(name, mesh)
	bpy.context.collection.objects.link(obj)
	return obj


def _materials(handle_colour: tuple) -> list:
	specs = {"Tool_Metal": ((0.32, 0.17, 0.09, 1.0), 0.6, 0.7), "Tool_Edge": ((0.75, 0.74, 0.72, 1.0), 1.0, 0.3),
		"Tool_Handle": (handle_colour, 0.0, 0.5), "Tool_Grip": ((0.05, 0.05, 0.05, 1.0), 0.0, 0.85), "Tool_Tag": ((0.9, 0.88, 0.8, 1.0), 0.0, 0.8)}
	out = []
	for name in SLOTS:
		colour, metallic, rough = specs[name]
		material = bpy.data.materials.new(name)
		material.use_nodes = True
		bsdf = material.node_tree.nodes.get("Principled BSDF")
		bsdf.inputs["Base Color"].default_value = colour
		bsdf.inputs["Metallic"].default_value = metallic
		bsdf.inputs["Roughness"].default_value = rough
		out.append(material)
	return out


## A worn store label, 256 x 448 px: dark logo patch with the house mark, the brand on a yellow band,
## the price, a barcode; grime speckles and torn edges (transparent).
def _tag(path: str, yellow: tuple, brand: list, price: str, seed: int) -> None:
	rnd = random.Random(seed)
	w, h = 256, 448
	img = Image.new("RGBA", (w, h), (232, 226, 206, 255))
	d = ImageDraw.Draw(img)
	font = _font
	y_col = tuple(int(c * 255) for c in yellow)
	d.rectangle((0, 0, w, 120), fill=(46, 46, 50, 255))
	house = [(128, 22), (176, 58), (166, 58), (166, 98), (90, 98), (90, 58), (80, 58)]
	d.polygon(house, outline=y_col, width=7)
	d.rectangle((116, 70, 140, 98), outline=y_col, width=6)
	d.rectangle((0, 120, w, 196 + 44 * (len(brand) - 1)), fill=y_col)
	y = 132
	for line in brand:
		size = 44 if len(line) > 7 else 50
		text_w = d.textlength(line, font=font(size))
		d.text(((w - text_w) / 2, y), line, fill=(30, 28, 26, 255), font=font(size))
		y += 48
	two = len(brand) > 1
	price_size = 64 if two else 78
	y += 18 if two else 30
	text_w = d.textlength(price, font=font(price_size))
	d.text(((w - text_w) / 2, y), price, fill=(24, 22, 20, 255), font=font(price_size))
	y += price_size + (14 if two else 26)
	bar_h = 50 if two else 70
	x = 38
	while x < w - 38:
		bar = rnd.choice((2, 3, 5))
		d.rectangle((x, y, x + bar, y + bar_h), fill=(20, 20, 20, 255))
		x += bar + rnd.choice((2, 3, 4))
	digits = "".join(str(rnd.randint(0, 9)) for _ in range(12))
	d.text((40, y + bar_h + 4), digits, fill=(30, 30, 30, 255), font=font(22))
	## Grime and scuffs, then torn corners and a ragged edge (alpha 0 shows the handle through).
	px = img.load()
	for _ in range(2600):
		cx, cy = rnd.randrange(w), rnd.randrange(h)
		r, g, b, a = px[cx, cy]
		k = rnd.uniform(0.55, 0.9)
		px[cx, cy] = (int(r * k), int(g * k * 0.97), int(b * k * 0.93), a)
	for _ in range(90):
		cx, cy = rnd.randrange(w), rnd.randrange(h)
		d.ellipse((cx - 4, cy - 3, cx + rnd.randint(3, 12), cy + rnd.randint(2, 6)), fill=(150, 138, 118, 255))
	for corner in ((0, h), (w, h), (w, 120)):
		rx, ry = rnd.randint(24, 60), rnd.randint(24, 60)
		d.polygon([(corner[0], corner[1]), (corner[0] + (rx if corner[0] == 0 else -rx), corner[1]),
			(corner[0], corner[1] - ry)], fill=(0, 0, 0, 0))
	for yy in range(120, h, 6):
		cut = rnd.randint(0, 6)
		d.rectangle((0, yy, cut, yy + 6), fill=(0, 0, 0, 0))
		d.rectangle((w - rnd.randint(0, 6), yy, w, yy + 6), fill=(0, 0, 0, 0))
	os.makedirs(os.path.dirname(path), exist_ok=True)
	img.save(path)
	print("hand tools: wrote %s" % path)


def _font(size: int) -> ImageFont.FreeTypeFont:
	for path in FONTS:
		if os.path.exists(path):
			return ImageFont.truetype(path, size)
	return ImageFont.load_default()


## Optional geometry check: a three-quarter Cycles render with the slot colours.
def _render(out_dir: str, name: str) -> None:
	os.makedirs(out_dir, exist_ok=True)
	scene = bpy.context.scene
	scene.render.engine = "CYCLES"
	scene.cycles.samples = 24
	scene.render.resolution_x = 640
	scene.render.resolution_y = 640
	cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
	scene.collection.objects.link(cam)
	scene.camera = cam
	cam.location = (0.25, -0.62, 0.2)
	direction = Vector((0.03, 0.0, 0.19)) - cam.location
	cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
	sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
	scene.collection.objects.link(sun)
	sun.rotation_euler = (math.radians(50), 0.0, math.radians(30))
	scene.world = bpy.data.worlds.new("w")
	scene.world.color = (0.2, 0.2, 0.22)
	scene.render.filepath = os.path.join(out_dir, name + ".png")
	bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
	main()
