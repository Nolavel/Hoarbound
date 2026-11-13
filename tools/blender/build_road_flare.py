"""Builds the Emberline signal flare after the owner's reference sheet (2026-11-13), real scale.

The flare stands along +Y in Godot (Blender +Z): the burning end, a metal cap with five vents, at
y = +0.11; the pull end at y = -0.11 with a hex collar, a red clip and a steel pull ring below.
From the vent end: metal cap, red band, red tube with the two labels, knurled black grip, red band,
hex collar, dark end cap, clip and ring. The front label (EMBERLINE, mountain mark) faces +Z, the
warning label (SIGNAL FLARE / PULL - IGNITE - SIGNAL) faces -Z.
Material slots: Flare_Paint (worn red paint and labels, one texture over the whole length),
Flare_Grip (knurled rubber), Flare_Metal (worn gunmetal), Flare_Ring (steel), Flare_Vent (the holes).
Run: python3 tools/blender/build_road_flare.py [--render out_dir]
Writes assets/items/road_flare/RoadFlare.glb with its textures packed in.
"""
import math
import os
import sys

import bpy  # must load before bmesh
import bmesh
import numpy as np
from mathutils import Matrix, Vector
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = "assets/items/road_flare/RoadFlare.glb"
FONTS = ["/usr/share/fonts/opentype/inter/InterDisplay-Black.otf", "/usr/share/fonts/opentype/inter/InterDisplay-Bold.otf",
	"/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"]
FONTS_MEDIUM = ["/usr/share/fonts/opentype/inter/InterDisplay-SemiBold.otf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"]
HALF = 0.11  # body half length (Godot y), the old tube's size, so Henry's grip fits unchanged
TUBE_R = 0.0160
SEG = 40
SLOTS = ["Flare_Paint", "Flare_Grip", "Flare_Metal", "Flare_Ring", "Flare_Vent"]
PAINT, GRIP, METAL, RING, VENT = range(5)
## Paint texture: u runs the length from the vent end (u = 0) to the pull end; v runs round.
PAINT_W, PAINT_H = 2048, 1024
RNG = np.random.default_rng(1337)


def main() -> None:
	render_dir = sys.argv[sys.argv.index("--render") + 1] if "--render" in sys.argv else ""
	bpy.ops.wm.read_factory_settings(use_empty=True)
	os.makedirs(os.path.dirname(OUT), exist_ok=True)
	materials = _materials()
	obj = _flare(materials)
	bpy.ops.object.select_all(action="SELECT")
	bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_yup=True,
		export_apply=True, export_materials="EXPORT", export_image_format="AUTO")
	print("road flare: wrote %s (%d verts, %d tris)" % (OUT, len(obj.data.vertices), sum(len(p.vertices) - 2 for p in obj.data.polygons)))
	if render_dir:
		_render(render_dir)


# --- geometry -------------------------------------------------------------------------------

def _u(z: float) -> float:
	return (HALF - z) / (2.0 * HALF)


def _lathe(bm: bmesh.types.BMesh, profile: list, mat: int, sides: int = SEG, smooth: bool = True,
		uv: str = "paint", phase: float = 0.0, cap_bottom: bool = False, cap_top: bool = False) -> None:
	"""Revolves (z, r) points round the Z axis. uv 'paint' maps length/angle into the paint texture."""
	uv_layer = bm.loops.layers.uv.verify()
	rings = []
	for z, r in profile:
		ring = []
		for i in range(sides + 1):
			a = phase + 2.0 * math.pi * i / sides
			ring.append(bm.verts.new((r * math.cos(a), r * math.sin(a), z)))
		rings.append(ring)
	for k in range(len(rings) - 1):
		for i in range(sides):
			f = bm.faces.new((rings[k][i], rings[k][i + 1], rings[k + 1][i + 1], rings[k + 1][i]))
			f.material_index = mat
			f.smooth = smooth
			for loop in f.loops:
				x, y, z = loop.vert.co
				a = (math.atan2(y, x) - phase) % (2.0 * math.pi)
				if loop.vert in (rings[k][sides], rings[k + 1][sides]):
					a = 2.0 * math.pi
				if uv == "paint":
					loop[uv_layer].uv = (_u(z), a / (2.0 * math.pi))
				else:
					loop[uv_layer].uv = (a / (2.0 * math.pi) * 3.0, z * 18.0)
	for flag, ring, z, r in ((cap_bottom, rings[0], profile[0][0], profile[0][1]), (cap_top, rings[-1], profile[-1][0], profile[-1][1])):
		if not flag:
			continue
		verts = ring[:sides]
		f = bm.faces.new(verts if ring is rings[-1] else list(reversed(verts)))
		f.material_index = mat
		f.smooth = False
		for loop in f.loops:
			x, y, _ = loop.vert.co
			loop[uv_layer].uv = (0.5 + x * 12.0, 0.5 + y * 12.0) if uv != "paint" else (0.995, 0.5 + y * 2.0)


def _box(bm: bmesh.types.BMesh, centre: Vector, size: Vector, mat: int, rot: Matrix = Matrix.Identity(3)) -> None:
	uv_layer = bm.loops.layers.uv.verify()
	res = bmesh.ops.create_cube(bm, size=1.0)
	verts = res["verts"]
	for v in verts:
		v.co = rot @ Vector((v.co.x * size.x, v.co.y * size.y, v.co.z * size.z)) + centre
	faces = {f for v in verts for f in v.link_faces}
	for f in faces:
		f.material_index = mat
		f.smooth = False
		for loop in f.loops:
			x, y, z = loop.vert.co
			loop[uv_layer].uv = (0.56 + z * 0.3, 0.1 + (x + y) * 1.5) if mat == PAINT else (x * 20.0 + y * 20.0, z * 20.0)


def _torus(bm: bmesh.types.BMesh, centre: Vector, major: float, minor: float, mat: int, seg: int = 28, tube: int = 10) -> None:
	"""A ring in the XZ plane (axis along Y)."""
	uv_layer = bm.loops.layers.uv.verify()
	grid = []
	for i in range(seg):
		a = 2.0 * math.pi * i / seg
		row = []
		for j in range(tube):
			b = 2.0 * math.pi * j / tube
			rr = major + minor * math.cos(b)
			row.append(bm.verts.new(centre + Vector((rr * math.cos(a), minor * math.sin(b), rr * math.sin(a)))))
		grid.append(row)
	for i in range(seg):
		for j in range(tube):
			f = bm.faces.new((grid[i][j], grid[(i + 1) % seg][j], grid[(i + 1) % seg][(j + 1) % tube], grid[i][(j + 1) % tube]))
			f.material_index = mat
			f.smooth = True
			for loop in f.loops:
				x, y, z = loop.vert.co
				loop[uv_layer].uv = (x * 30.0, z * 30.0)


def _flare(materials: list) -> bpy.types.Object:
	bm = bmesh.new()
	h = HALF
	# Vent end: a ten-sided worn metal cap, bevelled into its flat face.
	_lathe(bm, [(0.094, 0.0166), (0.0955, 0.0176), (h - 0.0025, 0.0176), (h, 0.0158)], METAL, sides=10, smooth=False,
		uv="metal", phase=math.pi / 10.0, cap_top=True)
	# Five vents: dark discs set a hair proud of the face, four round one.
	for x, y in [(0.0, 0.0)] + [(0.0085 * math.cos(a), 0.0085 * math.sin(a)) for a in (0.4, 0.4 + math.pi / 2, 0.4 + math.pi, 0.4 + 1.5 * math.pi)]:
		_disc(bm, Vector((x, y, h + 0.0002)), 0.0023, VENT)
		_lathe(bm, [(h - 0.0035, 0.0023), (h + 0.0002, 0.0023)], VENT, sides=12, uv="metal", phase=0.0)
		for v in bm.verts[-26:]:
			v.co.x += x
			v.co.y += y
	# Red band, the labelled tube, the knurled grip, a red band.
	_lathe(bm, [(0.0905, 0.0164), (0.094, 0.0164)], PAINT)
	_lathe(bm, [(0.0055, TUBE_R), (0.0905, TUBE_R)], PAINT)
	_lathe(bm, [(-0.0555, 0.0164), (0.0055, 0.0164)], GRIP, uv="metal")
	_lathe(bm, [(-0.064, 0.0163), (-0.0555, 0.0163)], PAINT)
	# Hex collar, chamfered.
	_lathe(bm, [(-0.0885, 0.0168), (-0.0865, 0.0196), (-0.0665, 0.0196), (-0.0645, 0.0168)], METAL, sides=6, smooth=False,
		uv="metal", phase=0.0, cap_bottom=True, cap_top=True)
	# Dark end cap.
	_lathe(bm, [(-h + 0.004, 0.0152), (-h + 0.0055, 0.0158), (-0.0885, 0.0158)], METAL, sides=SEG, uv="metal")
	_lathe(bm, [(-h, 0.0138), (-h + 0.004, 0.0152)], METAL, sides=SEG, uv="metal", cap_bottom=True)
	# Red clip: up the +X side from the collar, across the end to past the centre, a rivet on the side.
	_box(bm, Vector((0.0186, 0.0, -0.0935)), Vector((0.0042, 0.0125, 0.031)), PAINT)
	_box(bm, Vector((0.0062, 0.0, -h - 0.0022)), Vector((0.0290, 0.0125, 0.0044)), PAINT)
	_box(bm, Vector((-0.0058, 0.0, -h - 0.0050)), Vector((0.0050, 0.0125, 0.0090)), PAINT)
	_lathe(bm, [(-0.0035, 0.0026), (0.0, 0.0026)], METAL, sides=10, uv="metal", cap_top=True)
	rivet = bm.verts[-11:]
	for v in rivet:
		v.co = Matrix.Rotation(math.pi / 2, 3, "Y") @ v.co + Vector((0.0207, 0.0, -0.0905))
	# Pull ring through the clip's tab.
	_torus(bm, Vector((-0.0058, 0.0, -h - 0.0160)), 0.0098, 0.0016, RING)
	mesh = bpy.data.meshes.new("RoadFlare")
	bm.to_mesh(mesh)
	bm.free()
	obj = bpy.data.objects.new("RoadFlare", mesh)
	bpy.context.collection.objects.link(obj)
	for m in materials:
		mesh.materials.append(m)
	return obj


def _disc(bm: bmesh.types.BMesh, centre: Vector, r: float, mat: int, sides: int = 12) -> None:
	uv_layer = bm.loops.layers.uv.verify()
	verts = [bm.verts.new(centre + Vector((r * math.cos(2 * math.pi * i / sides), r * math.sin(2 * math.pi * i / sides), 0.0))) for i in range(sides)]
	f = bm.faces.new(verts)
	f.material_index = mat
	for loop in f.loops:
		loop[uv_layer].uv = (0.5, 0.5)


# --- textures -------------------------------------------------------------------------------

def _noise(h: int, w: int, scale: int, octaves: int = 4, wrap_v: bool = True) -> np.ndarray:
	"""Value noise in 0..1, tiling round v (rows) so the paint has no seam."""
	out = np.zeros((h, w), dtype=np.float32)
	amp, total = 1.0, 0.0
	for o in range(octaves):
		gh, gw = max(2, scale * 2 ** o), max(2, int(scale * 2 ** o * w / h))
		grid = RNG.random((gh + 1, gw + 1)).astype(np.float32)
		if wrap_v:
			grid[-1, :] = grid[0, :]
		img = Image.fromarray((grid * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
		out += np.asarray(img, dtype=np.float32) / 255.0 * amp
		total += amp
		amp *= 0.5
	return out / total


def _fit(draw: ImageDraw.ImageDraw, text: str, width: int, height: int, medium: bool = False) -> ImageFont.FreeTypeFont:
	"""Largest font whose text fits in width x height."""
	size = height
	while size > 8:
		font = _font(size, medium)
		l, t, r, b = draw.textbbox((0, 0), text, font=font)
		if r - l <= width and b - t <= height:
			return font
		size -= 2
	return _font(8, medium)


def _font(size: int, medium: bool = False) -> ImageFont.FreeTypeFont:
	for path in (FONTS_MEDIUM if medium else FONTS):
		if os.path.exists(path):
			return ImageFont.truetype(path, size)
	return ImageFont.load_default()


def _paint_texture() -> tuple:
	h, w = PAINT_H, PAINT_W
	mottle = _noise(h, w, 7, 4)
	patches = _noise(h, w, 11, 3)
	red_dark = np.array([0.33, 0.05, 0.04])
	red = np.array([0.55, 0.08, 0.05])
	red_light = np.array([0.70, 0.17, 0.10])
	t = mottle[..., None]
	col = np.where(t < 0.5, red_dark + (red - red_dark) * (t / 0.5), red + (red_light - red) * ((t - 0.5) / 0.5))
	# Hand-painted look: quantise the value into a few strokes of red.
	col = np.round(col * 14.0) / 14.0
	# Chips showing dark primer and bare metal, more at the ends and on the edges of the bands.
	chips = _noise(h, w, 22, 2)
	ends = np.clip(np.abs(np.linspace(-1.0, 1.0, w))[None, :] ** 8, 0.0, 1.0)
	chip_mask = (chips + patches * 0.3 + ends * 0.15) > 0.83
	col[chip_mask] = np.array([0.17, 0.12, 0.10])
	edge = (chips + patches * 0.3 + ends * 0.15) > 0.80
	col[edge & ~chip_mask] = col[edge & ~chip_mask] * 0.62
	rough = np.full((h, w), 0.72, dtype=np.float32)
	rough[chip_mask] = 0.55
	img = Image.fromarray((np.clip(col, 0, 1) ** (1 / 2.2) * 255).astype(np.uint8))
	labels = Image.new("RGBA", (w, h), (0, 0, 0, 0))
	_front_label(labels, v_centre=0.75)
	_back_label(labels, v_centre=0.25)
	img.paste(labels, (0, 0), labels)
	label_alpha = np.asarray(labels, dtype=np.float32)[..., 3] / 255.0
	rough = rough * (1.0 - label_alpha) + 0.9 * label_alpha
	return img, rough


def _label_box(v_centre: float) -> tuple:
	u0, u1 = int(_u(0.083) * PAINT_W), int(_u(0.010) * PAINT_W)
	half = int(0.155 * PAINT_H)
	vc = int((1.0 - v_centre) * PAINT_H)
	return u0, vc - half, u1, vc + half


def _worn_paper(layer: Image.Image, box: tuple) -> None:
	u0, v0, u1, v1 = box
	w, h = u1 - u0, v1 - v0
	paper = np.zeros((h, w, 4), dtype=np.float32)
	tone = _noise(h, w, 3, 3, wrap_v=False)
	base = np.array([0.86, 0.79, 0.64])
	paper[..., :3] = base * (0.88 + 0.14 * tone[..., None])
	tear = _noise(h, w, 12, 2, wrap_v=False)
	yy, xx = np.mgrid[0:h, 0:w]
	border = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy)).astype(np.float32)
	alpha = ((border > 6 + tear * 26) & (tear + _noise(h, w, 30, 1, wrap_v=False) * 0.4 < 1.05)).astype(np.float32)
	paper[..., 3] = alpha
	layer.paste(Image.fromarray((np.clip(paper, 0, 1) * 255).astype(np.uint8), "RGBA"), (u0, v0))


def _mountains(draw: ImageDraw.ImageDraw, x: int, y: int, s: int, colour: tuple) -> None:
	draw.polygon([(x, y + s), (x + int(s * 0.42), y + int(s * 0.12)), (x + int(s * 0.62), y + int(s * 0.5)),
		(x + int(s * 0.78), y + int(s * 0.3)), (x + int(s * 1.25), y + s)], fill=colour)
	draw.polygon([(x + int(s * 0.42), y + int(s * 0.12)), (x + int(s * 0.52), y + int(s * 0.32)),
		(x + int(s * 0.38), y + int(s * 0.42))], fill=(222, 206, 172, 255))


def _stripes(draw: ImageDraw.ImageDraw, x: int, y: int, w: int, h: int, colour: tuple) -> None:
	for i in range(4):
		x0 = x + i * w // 3
		draw.polygon([(x0, y + h), (x0 + w // 7, y + h), (x0 + w // 7 + h // 2, y), (x0 + h // 2, y)], fill=colour)


def _front_label(layer: Image.Image, v_centre: float) -> None:
	box = _label_box(v_centre)
	_worn_paper(layer, box)
	u0, v0, u1, v1 = box
	draw = ImageDraw.Draw(layer)
	ink = (30, 24, 22, 255)
	h = v1 - v0
	_mountains(draw, u0 + int(h * 0.12), v0 + int(h * 0.27), int(h * 0.46), ink)
	tx = u0 + int(h * 0.82)
	room = u1 - tx - int(h * 0.10)
	big = _fit(draw, "EMBERLINE", room, int(h * 0.34))
	draw.text((tx, v0 + int(h * 0.16)), "EMBERLINE", font=big, fill=ink, anchor="lt")
	small = _fit(draw, "SIGNAL FLARE", int(room * 0.72), int(h * 0.22))
	draw.text((tx + int(h * 0.04), v0 + int(h * 0.62)), "SIGNAL FLARE", font=small, fill=ink, anchor="lt")
	_stripes(draw, u1 - int(h * 0.62), v0 + int(h * 0.64), int(h * 0.42), int(h * 0.16), (178, 38, 28, 255))


def _back_label(target: Image.Image, v_centre: float) -> None:
	"""Drawn upright on its own sheet, then turned 180 deg: the warning reads from the ring end."""
	box = _label_box(v_centre)
	layer = Image.new("RGBA", target.size, (0, 0, 0, 0))
	_worn_paper(layer, box)
	u0, v0, u1, v1 = box
	draw = ImageDraw.Draw(layer)
	ink = (30, 24, 22, 255)
	h = v1 - v0
	s = int(h * 0.48)
	x, y = u0 + 46, v0 + int(h * 0.24)
	draw.polygon([(x + s // 2, y), (x + s, y + s), (x, y + s)], fill=(178, 38, 28, 255))
	draw.polygon([(x + s // 2, y + s // 6), (x + s - s // 7, y + s - s // 12), (x + s // 7, y + s - s // 12)], fill=(222, 206, 172, 255))
	draw.rectangle([x + s // 2 - s // 22, y + s // 3, x + s // 2 + s // 22, y + int(s * 0.7)], fill=ink)
	draw.ellipse([x + s // 2 - s // 18, y + int(s * 0.76), x + s // 2 + s // 18, y + int(s * 0.87)], fill=ink)
	tx = x + s + int(h * 0.12)
	stripe_w = int(h * 0.40)
	room = u1 - tx - stripe_w - int(h * 0.16)
	draw.text((tx, v0 + int(h * 0.17)), "SIGNAL FLARE", font=_fit(draw, "SIGNAL FLARE", room, int(h * 0.26)), fill=ink, anchor="lt")
	draw.line([(tx, v0 + int(h * 0.53)), (tx + room, v0 + int(h * 0.53))], fill=ink, width=max(2, h // 60))
	small = "PULL \u2022 IGNITE \u2022 SIGNAL"
	draw.text((tx, v0 + int(h * 0.62)), small, font=_fit(draw, small, room, int(h * 0.14), medium=True), fill=ink, anchor="lt")
	_stripes(draw, u1 - stripe_w - int(h * 0.08), v0 + int(h * 0.2), stripe_w, int(h * 0.6), (178, 38, 28, 255))
	sheet = layer.crop(box).rotate(180)
	target.paste(sheet, (u0, v0), sheet)


def _grip_textures() -> tuple:
	n = 512
	yy, xx = np.mgrid[0:n, 0:n].astype(np.float32) / n
	cells = 12.0
	a = (xx + yy) * cells
	b = (xx - yy) * cells
	da = np.abs(a - np.round(a))
	db = np.abs(b - np.round(b))
	groove = np.minimum(da, db)
	height = np.clip(groove / 0.5, 0.0, 1.0)
	wear = _noise(n, n, 6, 3)
	col = np.stack([0.07 + 0.08 * height, 0.065 + 0.075 * height, 0.06 + 0.07 * height], -1) * (0.85 + 0.3 * wear[..., None])
	col[(wear > 0.72) & (height > 0.6)] = np.array([0.22, 0.17, 0.14])
	gy, gx = np.gradient(height)
	normal = np.stack([0.5 - gx * 6.0, 0.5 + gy * 6.0, np.ones_like(gx)], -1)
	normal[..., 2] = 1.0
	return col, normal


def _metal_textures() -> tuple:
	n = 512
	tone = _noise(n, n, 6, 4)
	grime = _noise(n, n, 16, 2)
	base = np.array([0.23, 0.22, 0.21])
	worn = np.array([0.50, 0.46, 0.40])
	rust = np.array([0.26, 0.15, 0.09])
	col = base * (0.85 + 0.3 * tone[..., None])
	col[tone > 0.70] = worn
	col[grime > 0.86] = rust
	rough = np.where(tone > 0.70, 0.35, 0.6).astype(np.float32)
	metal = np.where(grime > 0.86, 0.2, 0.8).astype(np.float32)
	return col, rough, metal


def _image(name: str, rgb: np.ndarray, non_color: bool = False) -> bpy.types.Image:
	h, w = rgb.shape[:2]
	rgba = np.ones((h, w, 4), dtype=np.float32)
	rgba[..., :3] = rgb
	img = bpy.data.images.new(name, w, h, alpha=False)
	img.colorspace_settings.name = "Non-Color" if non_color else "sRGB"
	img.pixels.foreach_set(np.ascontiguousarray(np.flipud(rgba)).ravel())
	img.update()
	img.file_format = "PNG"
	img.pack()
	return img


def _bsdf_material(name: str, base: bpy.types.Image, rough_metal: bpy.types.Image = None,
		normal: bpy.types.Image = None, roughness: float = 0.7, metallic: float = 0.0,
		colour: tuple = (0.8, 0.8, 0.8, 1.0)) -> bpy.types.Material:
	mat = bpy.data.materials.new(name)
	mat.use_nodes = True
	nodes, links = mat.node_tree.nodes, mat.node_tree.links
	bsdf = nodes["Principled BSDF"]
	bsdf.inputs["Roughness"].default_value = roughness
	bsdf.inputs["Metallic"].default_value = metallic
	bsdf.inputs["Base Color"].default_value = colour
	if base is not None:
		tex = nodes.new("ShaderNodeTexImage")
		tex.image = base
		links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
	if rough_metal is not None:
		mr = nodes.new("ShaderNodeTexImage")
		mr.image = rough_metal
		split = nodes.new("ShaderNodeSeparateColor")
		links.new(mr.outputs["Color"], split.inputs["Color"])
		links.new(split.outputs["Green"], bsdf.inputs["Roughness"])
		links.new(split.outputs["Blue"], bsdf.inputs["Metallic"])
	if normal is not None:
		n_tex = nodes.new("ShaderNodeTexImage")
		n_tex.image = normal
		n_map = nodes.new("ShaderNodeNormalMap")
		links.new(n_tex.outputs["Color"], n_map.inputs["Color"])
		links.new(n_map.outputs["Normal"], bsdf.inputs["Normal"])
	return mat


def _materials() -> list:
	paint_img, paint_rough = _paint_texture()
	paint = np.asarray(paint_img, dtype=np.float32)[..., :3] / 255.0
	paint = paint ** 2.2  # back to linear for Blender's float buffer
	mr = np.stack([np.zeros_like(paint_rough), paint_rough, np.zeros_like(paint_rough)], -1)
	grip_col, grip_n = _grip_textures()
	metal_col, metal_rough, metal_metal = _metal_textures()
	metal_mr = np.stack([np.zeros_like(metal_rough), metal_rough, metal_metal], -1)
	return [
		_bsdf_material("Flare_Paint", _image("Flare_Paint_Albedo", paint), _image("Flare_Paint_MR", mr, True)),
		_bsdf_material("Flare_Grip", _image("Flare_Grip_Albedo", grip_col), None, _image("Flare_Grip_Normal", grip_n, True), 0.85),
		_bsdf_material("Flare_Metal", _image("Flare_Metal_Albedo", metal_col), _image("Flare_Metal_MR", metal_mr, True)),
		_bsdf_material("Flare_Ring", None, None, None, 0.32, 1.0, (0.62, 0.6, 0.57, 1.0)),
		_bsdf_material("Flare_Vent", None, None, None, 0.9, 0.0, (0.02, 0.018, 0.016, 1.0)),
	]


# --- preview --------------------------------------------------------------------------------

def _render(out_dir: str) -> None:
	os.makedirs(out_dir, exist_ok=True)
	scene = bpy.context.scene
	scene.render.engine = "CYCLES"
	scene.cycles.device = "CPU"
	scene.cycles.samples = 40
	scene.view_settings.view_transform = "Standard"  # AgX washes saturated red to salmon
	scene.render.resolution_x, scene.render.resolution_y = 1200, 700
	world = bpy.data.worlds.new("W")
	world.use_nodes = True
	world.node_tree.nodes["Background"].inputs[0].default_value = (0.06, 0.06, 0.07, 1.0)
	world.node_tree.nodes["Background"].inputs[1].default_value = 0.6
	scene.world = world
	key = bpy.data.objects.new("Key", bpy.data.lights.new("Key", "AREA"))
	key.data.energy = 30.0
	key.data.size = 0.4
	key.location = (0.25, -0.35, 0.35)
	key.rotation_euler = Vector((-0.25, 0.35, -0.35)).to_track_quat("-Z", "Y").to_euler()
	bpy.context.collection.objects.link(key)
	fill = bpy.data.objects.new("Fill", bpy.data.lights.new("Fill", "AREA"))
	fill.data.energy = 8.0
	fill.data.size = 0.6
	fill.location = (-0.35, 0.2, 0.15)
	fill.rotation_euler = Vector((0.35, -0.2, -0.15)).to_track_quat("-Z", "Y").to_euler()
	bpy.context.collection.objects.link(fill)
	cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
	bpy.context.collection.objects.link(cam)
	scene.camera = cam
	cam.data.lens = 70
	flare = bpy.data.objects["RoadFlare"]
	for label, rot, loc in (("front", (0.0, -math.pi / 2 - 0.25, 0.0), (0.0, -0.42, 0.06)),
			("back", (0.0, math.pi / 2 + 0.25, math.pi), (0.0, -0.42, 0.06)),
			("ends", (0.0, -math.pi / 2 - 0.25, -0.9), (0.0, -0.42, 0.06))):
		flare.rotation_euler = rot
		cam.location = loc
		cam.rotation_euler = (math.radians(80), 0.0, 0.0)
		scene.render.filepath = os.path.join(os.path.abspath(out_dir), "road_flare_%s.png" % label)
		bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
	main()
