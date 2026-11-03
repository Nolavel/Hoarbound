"""Builds Henry's outfit around the UAL mannequin as skinned, continuous meshes.

Each garment is cut from a copy of the body by bone region, pushed out along the
normals and thickened, so it inherits the body's skin weights and bends at the
elbows and knees exactly like the body. Skin under each garment is split into
Skin_<item> meshes the game hides while that item is worn.
Run: python3 tools/blender/build_henry_outfit.py [--render out_dir]
Writes assets/characters/henry/henry_outfit.glb (body + garments + armature + clips).
Boots are the owner's model (assets/items/boots/boots.glb), skinned here from the body.
"""
import json
import math
import os
import struct
import sys

import bpy  # must load before bmesh
import bmesh
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import owner_garments as G  # noqa: E402

SOURCE = "assets/animation/ual/Unreal-Godot/UAL1_Standard.glb"
OUT = "assets/characters/henry/henry_outfit.glb"
## The owner's boots, modelled in the mannequin's rest pose; they replace the generated boots.
BOOTS_SOURCE = "assets/items/boots/boots.glb"
## The owner's jacket and trousers (CC-BY, credits in assets/characters/gear/CREDITS.md).
JACKET_SOURCE = "assets/characters/gear/plaid_jacket.glb"
PANTS_SOURCE = "assets/characters/gear/reality_texture_man_pants.glb"
## Game budget for the jeans (faces) and how far each layer sits past what it covers, metres.
PANTS_FACES = 20000
## The cloth proxy the jeans ride on (faces).
PANTS_PROXY_FACES = 9000
PANTS_MARGIN = 0.006
## The crotch web: cloth this near the midline below the crotch and this far off the body is laid on it.
CROTCH_HALF = 0.05
CROTCH_SLACK = 0.012
## How far above the crotch each leg's cloth keeps to its own leg's bones.
CROTCH_SEAM = 0.01
## Half-width of the crotch seam band handed to the pelvis (all of it on the seam, none at the edge).
CROTCH_PELVIS = 0.025
## Cloth drape: frames settled, the held band at the waist / collar (m), and fabric settings.
DRAPE_FRAMES = 40
PIN_BAND = 0.03
DENIM = {"mass": 0.4, "stretch": 40.0, "bending": 10.0, "distance": 0.004}
FLANNEL = {"mass": 0.3, "stretch": 30.0, "bending": 10.0, "distance": 0.005, "pin_stiffness": 2.0}
## Jacket: frames settled, its collar band held fully and the front placket held softly.
JACKET_FRAMES = 30
COLLAR_BAND = 0.08
## The shoulder-and-collar zone whose weights are blended: above this height, this far either side.
COLLAR_FROM = 1.45
COLLAR_HALF = 0.32
## The cuff zone (T-pose, beyond this distance from the centre) whose weights are blended, metres.
CUFF_FROM = 0.64
## Above the jacket's hem the jeans are laid on the body: from this far up (none) to this (full),
## this far off the skin, metres.
WAIST_HUG_FROM = 0.03
## The pack straps' path on the jacket: its measured points, how far either side the cloth's weights are smoothed
## (so the cloth under a strap moves as one and never pokes through it), metres, and smoothing passes.
STRAP_POINTS = "scenes/actors/player/henry/strap_points.json"
STRAP_CORRIDOR = 0.035
STRAP_SEAM = 0.03
STRAP_SMOOTH_PASSES = 12
## Spring chains: how many round the hem and the collar, and how far up each zone reaches, metres.
HEM_CHAINS = 8
HEM_ZONE = 0.16
COLLAR_CHAINS = 5
COLLAR_ZONE = 0.09
## How far toward the front (m, along -Y from the neck) the collar's chains fade out.
COLLAR_FADE = 0.05
WAIST_HUG_FULL = 0.08
WAIST_HUG_MARGIN = 0.003
PLACKET_HALF = 0.07
PLACKET_HOLD = 0.6
## Sleeves are held from this far past the shoulder joint outwards, this firmly.
SLEEVE_HOLD_FROM = 0.05
SLEEVE_HOLD = 0.8
JACKET_MARGIN = 0.008
## Jacket girth over the model (length kept) and cuff reach past the wrist (m).
JACKET_WIDEN = 1.05
SLEEVE_PAST_WRIST = 0.03
## Tucked jeans taper onto the leg from this far above the boots' cuff and end this far below it.
TUCK_DEPTH = 0.04
## Tucked legs taper onto the shin over this height above the rim and lie this far off the skin.
TUCK_TAPER = 0.06
TUCK_OFF_SKIN = 0.004
## Inside the boot the jeans keep this far in from its shell, metres.
BOOT_WALL = 0.004
## Imported piece name prefix -> outfit mesh (both feet joined into one).
BOOT_PARTS = {"Boot_New_": "Outfit_Boots", "Boot_Lining_": "Outfit_BootLining", "Boot_Fur_": "Outfit_BootFur"}
## The shafts hug the shin: from this height (no change) to this one (full), the shell sits this
## far off the skin (room for the tucked jeans, laid 4 mm off it), metres.
SHAFT_SNUG_FROM = 0.14
SHAFT_SNUG_FULL = 0.22
SHAFT_GAP = 0.010
## Boots scaled up by this about each sole's centre (x = +-BOOT_CENTRE_X, on the floor).
BOOT_SCALE = 1.055
## Above the tread (the foot's underside, this height) no skin may come within this of the shell, metres.
BOOT_SOLE_TOP = 0.0
BOOT_SKIN_MARGIN = 0.008
## The lining keeps this far inside the shell, metres.
LINING_INSET = 0.002
BOOT_CENTRE_X = 0.089

JACKET_COLOUR = (0.30, 0.34, 0.20)
## Insulated work glove after the owner's reference: olive back, tan knuckle and fingertip
## leather, dark palm; a dark gauntlet with a strap, a red pull tab and a tan patch.
GLOVE_OLIVE = (0.19, 0.19, 0.11)
GLOVE_TAN = (0.60, 0.41, 0.21)
GLOVE_PALM = (0.17, 0.12, 0.09)
GLOVE_STRAP = (0.08, 0.07, 0.06)
GLOVE_TAB = (0.58, 0.12, 0.08)
## name: (colour, push-out metres, shell thickness, smoothing passes)
## Smoothing irons out the mannequin's muscles so cloth reads as panels.
SWEATER_COLOUR = (0.80, 0.72, 0.58)
## Knit textures (tools/blender/make_knit_textures.py) and the size one tile covers on the body, metres.
KNIT_BODY = "assets/characters/gear/knit_body_%s.png"
KNIT_RIB = "assets/characters/gear/knit_rib_%s.png"
KNIT_TILE = 0.096
## Turtleneck: from this far under the neck bone to this far over the head bone (the jaw), its air off
## the skin, knit thickness and the turned-down fold, metres.
TURTLENECK_BELOW = 0.0
TURTLENECK_ABOVE = 0.12
TURTLENECK_GAP = 0.004
TURTLENECK_THICK = 0.014
TURTLENECK_FOLD = 0.05
## The widest the tube's lowest rings follow the skin (any wider would reach the shoulders), metres.
TURTLENECK_MAX_R = 0.075
## Above the shoulders the tube follows the whole neck, its front included, up to this radius.
TURTLENECK_TOP_R = 0.13
GARMENTS = {
	"Jacket": (JACKET_COLOUR, 0.030, 0.010, 12),
	"Pants": ((0.27, 0.30, 0.36), 0.019, 0.008, 8),
	"Boots": ((0.30, 0.22, 0.15), 0.020, 0.012, 6),
	"Sole": ((0.17, 0.12, 0.09), 0.022, 0.014, 2),
	"Beanie": ((0.52, 0.20, 0.16), 0.008, 0.008, 6),
	"BeanieCuff": ((0.46, 0.17, 0.14), 0.020, 0.012, 4),
	"Gloves": (GLOVE_OLIVE, 0.014, 0.006, 3),
	"GloveCuff": ((0.14, 0.11, 0.08), 0.044, 0.010, 8),
	## The knit sweater under the jacket (thin, it is hidden but at the open front and cuffs) and its
	## thick turtleneck rolled up the whole neck.
	"Sweater": (SWEATER_COLOUR, 0.002, 0.002, 10),
	"Collar": (SWEATER_COLOUR, 0.018, 0.012, 8),
}
BODY_COLOUR = (0.55, 0.55, 0.56)
TRIM_COLOUR = (0.19, 0.21, 0.13)  # placket and seams
ZIP_COLOUR = (0.35, 0.35, 0.33)
## Jacket skirt: bottom as a share of body height, push-out and flare in metres.
SKIRT_BOTTOM = 0.385
SKIRT_PUSH = 0.034
SKIRT_FLARE = 0.045
SKIRT_LEG_FOLLOW = 0.9  # thigh share at the hem; the top ring stays on the pelvis
DECIMATE_RATIO = 0.35
## The mannequin's fingers are dense; gloves keep far fewer faces.
DECIMATE_BY_GARMENT = {"Gloves": 0.1, "GloveCuff": 1.0}
CUTS = {}
## Garments whose edge follows whole faces; the rest also keep faces straddling it.
CLEAN_EDGE = set()
HOOD_COLOUR = (0.28, 0.32, 0.19)

TORSO = {"pelvis", "spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r"}
ARMS = {"upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r"}
LEGS = {"thigh_l", "thigh_r", "calf_l", "calf_r"}
FEET = {"foot_l", "foot_r", "ball_l", "ball_r", "ball_leaf_l", "ball_leaf_r"}
FINGERS = ("thumb_", "index_", "middle_", "ring_", "pinky_")
## Glove cuff starts this far along the hand bone, under the sleeve that ends at 0.3.
GLOVE_CUFF_T = 0.0
## The insulated gauntlet rides over the sleeve from this share of the forearm to the wrist.
GAUNTLET_T = 0.80


def dominant(mesh, obj):
	names = {g.index: g.name for g in obj.vertex_groups}
	out = []
	for v in mesh.vertices:
		best = max(v.groups, key=lambda g: g.weight, default=None)
		out.append(names.get(best.group, "") if best else "")
	return out


def bone_t(arm, bone, p):
	"""Position of p along a bone, 0 at head and 1 at tail, in world space."""
	b = arm.data.bones[bone]
	h = arm.matrix_world @ b.head_local
	t = arm.matrix_world @ b.tail_local
	d = t - h
	return (p - h).dot(d) / d.length_squared


def regions(body, arm):
	"""Per-vertex garment name, or '' for skin, measured on the rest pose."""
	mesh = body.data
	dom = dominant(mesh, body)
	world = [body.matrix_world @ v.co for v in mesh.vertices]
	zs = [p.z for p in world]
	height = max(zs) - min(zs)
	floor = min(zs)
	hem = floor + 0.475 * height  # jacket hem just below the hips
	boot_top = floor + 0.17 * height
	## The trousers end under the boots' fur cuff: tucked deeper they poke through the rigid shaft.
	pants_low = boot_cuff_bottom() + 0.005
	pants_high = hem + 0.08  # tucked under the jacket
	neck_z = arm.matrix_world @ arm.data.bones["neck_01"].head_local
	head = arm.matrix_world @ arm.data.bones["Head"].head_local
	beanie_z = head.z + 0.56 * (max(zs) - head.z)
	out = []
	extra = []
	for i, p in enumerate(world):
		b = dom[i]
		layers = set()
		if (b in LEGS or b in FEET) and pants_low < p.z < boot_top + 0.04:
			layers.add("Pants")
		if (b in LEGS and hem - 0.02 < p.z < pants_high) or (b == "pelvis" and p.z < pants_high):
			layers.add("Pants")
		if b == "Head" and beanie_z - 0.005 < p.z < beanie_z + 0.045:
			layers.add("BeanieCuff")
		if b in FEET and p.z < floor + 0.035:
			layers.add("Sole")
		if b.startswith("hand_") and GLOVE_CUFF_T <= bone_t(arm, b, p) < 0.3:
			layers.add("Gloves")
		if (b.startswith("lowerarm_") and bone_t(arm, b, p) > GAUNTLET_T) or (b.startswith("hand_") and bone_t(arm, b, p) < 0.12):
			layers.add("GloveCuff")
		if (b in TORSO and p.z > hem + 0.02) or b in ARMS or b == "neck_01":
			layers.add("Sweater")
		if b == "neck_01" or (b in ("spine_03", "clavicle_l", "clavicle_r") and p.z > neck_z.z - 0.03 and abs(p.x) < 0.09):
			layers.add("Collar")
		extra.append(layers)
		b = dom[i]
		side = b[-1:] if b.endswith(("_l", "_r")) else ""
		if b in ("Head",) and p.z > beanie_z:
			out.append("Beanie")
		elif b == "neck_01":  # high collar up to the jaw
			out.append("Jacket")
		elif (b in TORSO and p.z > hem + 0.01) or b in ARMS or (b.startswith("hand_") and bone_t(arm, b, p) < 0.3):  # sleeve to the knuckles
			out.append("Jacket")
		elif b in LEGS and p.z > hem and b.startswith("thigh"):
			out.append("Jacket")
		elif b.startswith(FINGERS) or b.startswith("hand_"):
			out.append("Gloves")
		elif (b in FEET or b in LEGS) and p.z < boot_top:
			out.append("Boots")
		elif b in LEGS or b in FEET:
			out.append("Pants")
		else:
			out.append("")
	## Rest-pose heights where a garment edge is cut straight.
	CUTS["hem"] = hem
	CUTS["skirt_bottom"] = floor + SKIRT_BOTTOM * height
	CUTS.update({"Pants": (pants_low, None), "Boots": (None, boot_top),
		"Beanie": (beanie_z, None)})
	## Overlap: a vertex may belong to its own garment plus the tucked-in layer.
	return [({r} if r else set()) | extra[i] for i, r in enumerate(out)]


def material(name, colour):
	m = bpy.data.materials.new(name)
	m.diffuse_color = (*colour, 1.0)
	m.use_nodes = True
	bsdf = m.node_tree.nodes["Principled BSDF"]
	bsdf.inputs["Base Color"].default_value = (*colour, 1.0)
	bsdf.inputs["Roughness"].default_value = 0.85
	return m


def build_garment(body, arm, name, region, spec):
	colour, push, thick, passes = spec
	obj = body.copy()
	obj.data = body.data.copy()
	obj.name = obj.data.name = "Outfit_" + name
	bpy.context.collection.objects.link(obj)
	bm = bmesh.new()
	bm.from_mesh(obj.data)
	bm.verts.ensure_lookup_table()
	keep = {i for i, r in enumerate(region) if name in r}
	## A face touching the region stays: the body is low-poly, so large shin
	## triangles would otherwise leave holes on both sides of a seam.
	test = all if name in CLEAN_EDGE else any
	bmesh.ops.delete(bm, geom=[f for f in bm.faces if not test(v.index in keep for v in f.verts)], context="FACES")
	bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
	## glTF splits vertices on UV seams; weld them or the push opens cracks.
	bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)
	bm.normal_update()
	rest = {v: (v.co.copy(), v.normal.copy()) for v in bm.verts}
	for _ in range(passes):
		bmesh.ops.smooth_vert(bm, verts=bm.verts, factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
	bm.normal_update()
	## Push from the smoothed surface by a uniform depth covering most muscle peaks;
	## skin under the garment is masked, so the rare peak left cannot poke through.
	sunk = sorted(max(0.0, (rest[v][0] - v.co).dot(v.normal)) for v in bm.verts)
	depth = push + sunk[int(len(sunk) * 0.7)]
	low, high = CUTS.get(name, (None, None))
	for v in bm.verts:
		v.co += v.normal * depth
		if low is not None and rest[v][0].z < low:
			v.co.z = max(v.co.z, low)
		if high is not None and rest[v][0].z > high:
			v.co.z = min(v.co.z, high)
	bm.to_mesh(obj.data)
	bm.free()
	obj.data.materials.clear()
	obj.data.materials.append(material(name, colour))
	bpy.context.view_layer.objects.active = obj
	dec = obj.modifiers.new("Decimate", "DECIMATE")
	dec.ratio = DECIMATE_BY_GARMENT.get(name, DECIMATE_RATIO)
	sol = obj.modifiers.new("Solidify", "SOLIDIFY")
	sol.thickness = thick
	sol.offset = -1.0
	sol.use_rim = True
	for mod in ("Decimate", "Solidify"):
		bpy.ops.object.modifier_move_to_index(modifier=mod, index=0)
		bpy.ops.object.modifier_apply(modifier=mod)
	for p in obj.data.polygons:
		p.use_smooth = False
	return obj


## Garment piece to the equipment mesh name (GarmentData.mesh_node_name) it belongs to.
ITEM_OF = {"Sweater": "Sweater", "Collar": "Sweater", "Jacket": "Coat", "Hood": "Coat", "Skirt": "Coat", "Trim": "Coat", "Pants": "Trousers", "Boots": "Boots", "Sole": "Boots",
	"Beanie": "Hat", "BeanieCuff": "Hat", "Gloves": "Gloves", "GloveCuff": "Gloves"}
## Which garment owns skin under overlapping layers, outermost first.
SKIN_PRIORITY = ("Jacket", "Gloves", "Boots", "Pants")


def _segment_distance(p, a, b):
	d = b - a
	t = max(0.0, min(1.0, (p - a).dot(d) / d.length_squared))
	return (p - (a + d * t)).length, t


def style_gloves(gloves, cuff, arm):
	"""Paints the reference's panels by face: which bone a face sits on and whether it faces
	the back of the hand or the palm. Materials stay flat colours for the NPR look."""
	bones = {b.name: (arm.matrix_world @ b.head_local, arm.matrix_world @ b.tail_local) for b in arm.data.bones}
	backs = {}
	for side in ("l", "r"):
		h = bones["hand_" + side][0]
		back = (bones["index_01_" + side][0] - h).cross(bones["pinky_01_" + side][0] - h).normalized()
		backs[side] = back if side == "l" else -back
	hand_bones = [n for n in bones if n.startswith(("hand_",) + FINGERS)]
	for colour in (GLOVE_TAN, GLOVE_PALM):
		gloves.data.materials.append(material("Gloves", colour))
	for poly in gloves.data.polygons:
		c = gloves.matrix_world @ poly.center
		n = (gloves.matrix_world.to_3x3() @ poly.normal).normalized()
		name, t = min(((bn, _segment_distance(c, *bones[bn])) for bn in hand_bones), key=lambda x: x[1][0])[0:2]
		t = t[1]
		facing = n.dot(backs[name[-1]])
		if facing < -0.1:
			poly.material_index = 2
		elif name.endswith(("_03_l", "_03_r")) or (facing > 0.3 and name.startswith(FINGERS) and name[-4:-2] == "01" and t < 0.45):
			poly.material_index = 1
	_settle_panels(gloves, passes=2)
	for colour in (GLOVE_STRAP, GLOVE_TAB, GLOVE_TAN):
		cuff.data.materials.append(material("GloveCuff", colour))
	for poly in cuff.data.polygons:
		c = cuff.matrix_world @ poly.center
		n = (cuff.matrix_world.to_3x3() @ poly.normal).normalized()
		side = "l" if c.x > 0 else "r"
		fore = bones["lowerarm_" + side]
		_d, t = _segment_distance(c, *fore)
		axis = (fore[1] - fore[0]).normalized()
		back = backs[side]
		lateral = axis.cross(back).normalized()
		if 0.87 < t < 0.93:
			poly.material_index = 2 if n.dot(lateral) > 0.93 else 1
		elif 0.94 < t and n.dot(back) > 0.6:
			poly.material_index = 3


def _settle_panels(obj, passes):
	"""Majority vote with edge neighbours, so decimated triangles form whole panels, not specks."""
	mesh = obj.data
	neighbours = [set() for _ in mesh.polygons]
	by_edge = {}
	for poly in mesh.polygons:
		for key in poly.edge_keys:
			by_edge.setdefault(key, []).append(poly.index)
	for faces in by_edge.values():
		for a in faces:
			neighbours[a].update(f for f in faces if f != a)
	for _ in range(passes):
		current = [p.material_index for p in mesh.polygons]
		for poly in mesh.polygons:
			votes = [current[poly.index]] + [current[f] for f in neighbours[poly.index]]
			poly.material_index = max(set(votes), key=votes.count)


## The owner's model garments: the skin under them is found by what covers it. The draped cloth
## (jeans, jacket) by coverage alone; the rigid boots also keep their region.
MODELLED = ("Boots", "Pants", "Jacket")
DRAPED = ("Pants", "Jacket")


def split_body(body, region, covered):
	"""Moves skin fully inside a garment (one ring from its border) into Skin_<item>
	meshes, which the game hides while that item is worn. Under the owner's modelled garments
	`covered` (per vertex, from rays) decides alone: a draped garment need not keep its old region."""
	owner = [next((g for g in SKIN_PRIORITY if g in r), "") for r in region]
	owner = [c if c else (o if o not in DRAPED else "") for o, c in zip(owner, covered)]
	bm = bmesh.new()
	bm.from_mesh(body.data)
	bm.verts.ensure_lookup_table()
	border = {v.index for v in bm.verts if owner[v.index] and any(
		owner[e.other_vert(v).index] != owner[v.index] for e in v.link_edges)}
	## Skin one ring either side of the boots' edge: hidden under the rigid boot shaft and its cuff.
	boot_edge = {v.index for v in bm.verts if owner[v.index] == "Boots" or any(
		owner[e.other_vert(v).index] == "Boots" for e in v.link_edges)}
	face_owner = {}
	for f in bm.faces:
		labels = {owner[v.index] for v in f.verts}
		if labels and labels <= set(MODELLED):
			## Under modelled layers: the innermost of them owns it (the boot, then the jeans).
			face_owner[f.index] = ITEM_OF[next(g for g in MODELLED if g in labels)]
		elif len(labels) == 1 and "" not in labels and not any(v.index in border for v in f.verts):
			face_owner[f.index] = ITEM_OF[labels.pop()]
		elif labels <= {"Boots", "Pants"} and any(v.index in boot_edge for v in f.verts):
			## The owner's boots are rigid shells, not pushed-out skin: the edge ring of big shin
			## faces would show through them, and above the boot the trousers cover it.
			face_owner[f.index] = ITEM_OF["Boots"]
	bm.free()
	skin = material("Skin", BODY_COLOUR)
	for item in sorted(set(face_owner.values())) + [""]:
		part = body if item == "" else body.copy()
		if item:
			part.data = body.data.copy()
			part.name = part.data.name = "Skin_" + item
			bpy.context.collection.objects.link(part)
		pm = bmesh.new()
		pm.from_mesh(part.data)
		pm.faces.ensure_lookup_table()
		drop = [f for f in pm.faces if face_owner.get(f.index, "") != item]
		bmesh.ops.delete(pm, geom=drop, context="FACES")
		bmesh.ops.delete(pm, geom=[v for v in pm.verts if not v.link_faces], context="VERTS")
		pm.to_mesh(part.data)
		pm.free()
		part.data.materials.clear()
		part.data.materials.append(skin)


def build():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.ops.import_scene.gltf(filepath=SOURCE)
	for o in list(bpy.data.objects):
		if o.type == "MESH" and o.name != "Mannequin":
			bpy.data.objects.remove(o)
	arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
	body = bpy.data.objects["Mannequin"]
	region = regions(body, arm)
	built = {name: build_garment(body, arm, name, region, spec) for name, spec in GARMENTS.items()}
	style_gloves(built["Gloves"], built["GloveCuff"], arm)
	owner_boots(arm, body, [built.pop("Boots"), built.pop("Sole")])
	sweater = built.pop("Sweater")
	bpy.data.objects.remove(built.pop("Collar"))
	knit(sweater, arm, KNIT_BODY)
	## Cloth first, on the bare body: the jeans, then the jacket over them; the boots come after.
	pants = owner_pants(arm, body, built.pop("Pants"))
	jacket = owner_jacket(arm, body, built.pop("Jacket"), pants)
	collar = owner_turtleneck(arm, body, jacket)
	## The sweater moves with the jacket where it lies under it, so the two never cross.
	collar_base = min((collar.matrix_world @ v.co).z for v in collar.data.vertices)
	G.follow(sweater, jacket, collar_base, collar_base - 0.05)
	## The jeans' waist and belt are always under the jacket: laid flat on the body there, so a
	## bend never pushes them through it (they stuck out by up to 3 cm crouching or rolling).
	hem = min((jacket.matrix_world @ v.co).z for v in jacket.data.vertices)
	G.hug_above(pants, body, hem + WAIST_HUG_FROM, hem + WAIST_HUG_FULL, WAIST_HUG_MARGIN)
	tuck_pants(body, pants)
	finish_pants(arm, body, pants, jacket, hem)
	## Under the straps the cloth follows the shoulders, not the head (the head-look turns the neck):
	## its weights are smoothed, then neck weight goes to the upper spine, all of it within the corridor
	## and less and less across the seam beyond.
	distance = strap_distance()
	G.smooth_weights_where(jacket, lambda p: distance(p) < STRAP_CORRIDOR + STRAP_SEAM, passes=STRAP_SMOOTH_PASSES)
	G.shift_weights(jacket, "neck_01", "spine_03",
		lambda p: 1.0 - min(max((distance(p) - STRAP_CORRIDOR) / STRAP_SEAM, 0.0), 1.0))
	cloth_bones(arm, jacket, hem, lambda p: distance(p) < STRAP_CORRIDOR)
	boots = bpy.data.objects["Outfit_Boots"]
	split_body(body, region, G.coverage(body, [(collar, "Collar"), (sweater, "Sweater"), (boots, "Boots"),
		(pants, "Pants"), (jacket, "Jacket")]))
	## The sweater is always worn: the skin under it is never shown.
	bpy.data.objects.remove(bpy.data.objects["Skin_Sweater"])
	## The plaid jacket has its own collar and no hood; the old generated hood sat on it like a scarf.
	return arm


def owner_pants(arm, body, generated):
	"""The owner's jeans, draped on the body as cloth: welded into one cloth, decimated, then settled by gravity (held at the waist) on a sparse proxy they and their small
	parts (belt, loops) ride on."""
	bpy.data.objects.remove(generated)
	pants = G.import_joined(PANTS_SOURCE, "Outfit_Pants", lambda n: True)
	G.weld(pants)
	parts = G.split_largest(pants, "Outfit_PantsParts")
	G.decimate_to(pants, PANTS_FACES)
	G.fit_outside(pants, body, PANTS_MARGIN)
	## The cloth is simulated on a sparse proxy; the jeans (and their parts) ride on it.
	proxy = G.proxy_of(pants, PANTS_PROXY_FACES, "PantsProxy")
	G.ride_on(pants, proxy)
	if parts is not None:
		G.ride_on(parts, proxy)
	waist = max((proxy.matrix_world @ v.co).z for v in proxy.data.vertices)
	pin = [v.index for v in proxy.data.vertices if (proxy.matrix_world @ v.co).z > waist - PIN_BAND]
	G.drape(proxy, [body], DENIM, DRAPE_FRAMES, pin=pin)
	G.apply_ride(pants)
	if parts is not None:
		G.apply_ride(parts)
	bpy.data.objects.remove(proxy)
	if parts is not None:
		bpy.ops.object.select_all(action="DESELECT")
		parts.select_set(True)
		pants.select_set(True)
		bpy.context.view_layer.objects.active = pants
		bpy.ops.object.join()
	## The drape leaves a web between the legs 11 cm below the crotch; a crotch seam sits on the body.
	crotch = min((body.matrix_world @ v.co).z for v in body.data.vertices
		if abs((body.matrix_world @ v.co).x) < 0.01 and (body.matrix_world @ v.co).z > 0.5)
	G.close_crotch(pants, body, crotch, CROTCH_HALF, PANTS_MARGIN, CROTCH_SLACK)
	G.raise_seam(pants, body, crotch + CROTCH_SEAM, CROTCH_PELVIS, PANTS_MARGIN)
	return pants


def tuck_pants(body, pants):
	"""The boots go on after the cloth, and the jeans are tucked in: from a little above the shaft's
	rim each leg tapers onto the shin, lies 4 mm off it inside the 10 mm the shaft leaves, is kept
	inside the shell and is cut off by a plane 4 cm down, hidden in the boot. Geometry, not cloth:
	cloth starting inside the boot's thin wall is thrown apart by the collision."""
	boots = bpy.data.objects["Outfit_Boots"]
	shaft_top = max((boots.matrix_world @ v.co).z for v in boots.data.vertices)
	G.tuck(pants, body, shaft_top + TUCK_TAPER, shaft_top - 0.005, TUCK_OFF_SKIN)
	G.keep_inside(pants, boots, shaft_top, shaft_top - 0.02, BOOT_WALL)
	G.cut_below(pants, shaft_top - TUCK_DEPTH)


def finish_pants(arm, body, pants, jacket, hem):
	"""Skins the draped jeans from the body, weights evened so the cloth stretches smoothly. Where
	another layer overlaps them they take its weights, so the layers move as one and never cross:
	the boot's inside the shaft, the jacket's under it."""
	G.skin_from(pants, body, LEGS | FEET | TORSO)
	G.smooth_weights(pants)
	## Smoothing runs across the crotch seam: below it each leg's cloth follows its own leg only,
	## or the seam is dragged across the gap when the legs part; the seam itself follows the pelvis.
	crotch = min((body.matrix_world @ v.co).z for v in body.data.vertices
		if abs((body.matrix_world @ v.co).x) < 0.01 and (body.matrix_world @ v.co).z > 0.5) + CROTCH_SEAM
	for own, other in (("l", "r"), ("r", "l")):
		side = 1.0 if own == "l" else -1.0
		for bone in ("thigh", "calf"):
			G.merge_weights(pants, ["%s_%s" % (bone, other)], "%s_%s" % (bone, own),
				where=lambda p, side=side: p.x * side >= CROTCH_PELVIS and p.z < crotch)
	for bone in ("thigh_l", "thigh_r", "calf_l", "calf_r"):
		G.shift_weights(pants, bone, "pelvis",
			lambda p: max(0.0, 1.0 - abs(p.x) / CROTCH_PELVIS) if p.z < crotch else 0.0)
	boots = bpy.data.objects["Outfit_Boots"]
	shaft_top = max((boots.matrix_world @ v.co).z for v in boots.data.vertices)
	G.follow(pants, boots, shaft_top + 0.02, shaft_top - 0.01)
	G.follow(pants, jacket, hem + WAIST_HUG_FROM, hem + WAIST_HUG_FULL)
	G.bind(pants, arm)


def owner_jacket(arm, body, generated, pants):
	"""The owner's plaid jacket on its own dense mesh: re-posed from its A-pose to the T-pose by its
	measured sleeve droop, sleeves fitted to Henry's arms and centred on them, 5% wider in girth,
	then draped over the body and the jeans (collar, placket and sleeves held); skinned."""
	bpy.data.objects.remove(generated)
	jacket = G.import_joined(JACKET_SOURCE, "Outfit_Jacket", lambda n: True)
	G.weld(jacket)
	buttons = G.split_largest(jacket, "Outfit_JacketButtons")
	shoulder = (arm.matrix_world @ arm.data.bones["upperarm_l"].head_local).x
	droop = {side: G.sleeve_droop(jacket, side, shoulder) for side in (1, -1)}
	print("owner_jacket: sleeve droop deg", {k: round(math.degrees(v), 1) for k, v in droop.items()})
	if buttons is not None:
		G.ride_on(buttons, jacket)
	G.repose_arms(jacket, arm, droop)
	G.fit_sleeves(jacket, arm, SLEEVE_PAST_WRIST)
	G.centre_sleeves(jacket, arm)
	G.widen(jacket, arm, JACKET_WIDEN)
	G.fit_outside(jacket, body, JACKET_MARGIN)
	waist = max((pants.matrix_world @ v.co).z for v in pants.data.vertices)
	G.fit_outside(jacket, pants, PANTS_MARGIN, below=waist - 0.02)
	if buttons is not None:
		G.apply_ride(buttons)
	## Simulated on the jacket's own mesh: a sparser proxy bent the plaid (decimated UVs) or, bound
	## to it, threw spikes where the hem and the folded collar run past its edges.
	proxy = jacket
	if buttons is not None:
		G.ride_on(buttons, jacket)
	## Held while it settles, as a jacket is buttoned before draping: the collar fully, the front
	## placket (where the two fronts overlap) and the sleeves softly; the body drapes.
	collar = max((proxy.matrix_world @ v.co).z for v in proxy.data.vertices)
	pin = {}
	for v in proxy.data.vertices:
		p = proxy.matrix_world @ v.co
		if p.z > collar - COLLAR_BAND or abs(p.x) > CUFF_FROM:
			## The collar and the cuffs are stiff bands: held as cut, never draped.
			pin[v.index] = 1.0
		elif abs(p.x) < PLACKET_HALF and p.y < 0.0 and p.z > waist - 0.1:
			pin[v.index] = PLACKET_HOLD
		elif abs(p.x) > shoulder + SLEEVE_HOLD_FROM:
			## Sleeves held on the T-posed arms: on the sparse mesh the thin arm slips between the
			## sleeve's points and gravity drags the sleeve off it; the pose gives the folds.
			pin[v.index] = SLEEVE_HOLD
	## On the body only: resting on the jeans the hem crumpled; afterwards it is lifted off them.
	G.drape(proxy, [body], FLANNEL, JACKET_FRAMES, pin=pin)
	G.fit_outside(jacket, pants, PANTS_MARGIN, below=waist - 0.02)
	if buttons is not None:
		G.apply_ride(buttons)
	if buttons is not None:
		bpy.ops.object.select_all(action="DESELECT")
		buttons.select_set(True)
		jacket.select_set(True)
		bpy.context.view_layer.objects.active = jacket
		bpy.ops.object.join()
	G.skin_from(jacket, body)
	## Hand and finger weights go to the forearm: the cuff rides it instead of crumpling with the fist.
	for side in ("l", "r"):
		hand = [g.name for g in jacket.vertex_groups if g.name.endswith("_" + side) and g.name.startswith(("hand_",) + FINGERS)]
		G.merge_weights(jacket, hand, "lowerarm_" + side)
	## The collar reaches the jaw, whose nearest bone is the head: it follows the neck instead, or a
	## turn of the head would tear it.
	G.merge_weights(jacket, ["Head"], "neck_01")
	## Across the shoulders and collar neighbouring points took neck, collarbone and upper arm
	## apart; the weights there are blended so the seam bends instead of tearing.
	G.smooth_weights_where(jacket, lambda p: p.z > COLLAR_FROM and abs(p.x) < COLLAR_HALF)
	## So across the front placket, where the two overlapping fronts took spine and collarbones apart.
	G.smooth_weights_where(jacket, lambda p: abs(p.x) < PLACKET_HALF and p.y < 0.0)
	## And at the cuffs, whose turn-up took forearm and (merged) hand weights apart and opened.
	G.smooth_weights_where(jacket, lambda p: abs(p.x) > CUFF_FROM)
	## No weight smoothing here: it smears the torso's weights onto the upper sleeves, which then
	## stay at the body when the arms hang.
	G.bind(jacket, arm)
	return jacket


def owner_turtleneck(arm, body, jacket):
	"""The sweater's high, thick turtleneck: a knitted tube round the whole neck from the collarbones to
	the jaw, its top turned down, inside the jacket's collar, skinned from the neck and head so it follows them."""
	neck = arm.matrix_world @ arm.data.bones["neck_01"].head_local
	head = arm.matrix_world @ arm.data.bones["Head"].head_local
	collar = G.turtleneck(body, neck, head, neck.z - TURTLENECK_BELOW, head.z + TURTLENECK_ABOVE,
		TURTLENECK_GAP, TURTLENECK_THICK, TURTLENECK_FOLD, TURTLENECK_MAX_R, TURTLENECK_TOP_R, jacket)
	knit(collar, arm, KNIT_RIB)
	G.skin_from(collar, body)
	G.bind(collar, arm)
	return collar


def knit(obj, arm, textures):
	"""Knit wool on a sweater piece: tube UVs (round each arm along it, round the body up it) so the
	stitches run straight at a real size, and the albedo, normal and ORM textures."""
	import math
	me = obj.data
	uv = me.uv_layers.get("UVMap") or me.uv_layers.new(name="UVMap")
	names = {g.index: g.name for g in obj.vertex_groups}
	world = obj.matrix_world
	for poly in me.polygons:
		coords = []
		for li in poly.loop_indices:
			v = me.vertices[me.loops[li].vertex_index]
			p = world @ v.co
			arm_w = sum(g.weight for g in v.groups if names[g.group].startswith(("upperarm", "lowerarm", "hand")))
			if arm_w > 0.5:
				## Arms lie along X in the rest T-pose: round the arm, then along it.
				side = 1.0 if p.x > 0.0 else -1.0
				coords.append((math.atan2(p.z - 1.42, -p.y) * 0.055, p.x * side))
			else:
				coords.append((math.atan2(p.x, -p.y) * 0.16, p.z))
		## Keep each face on one side of the tube's back seam.
		us = [c[0] for c in coords]
		if max(us) - min(us) > 0.2:
			period = 2.0 * math.pi * (0.055 if abs(max(us)) < 0.2 else 0.16)
			coords = [(c[0] + period if c[0] < 0.0 else c[0], c[1]) for c in coords]
		for li, (u, w) in zip(poly.loop_indices, coords):
			uv.data[li].uv = (u / KNIT_TILE, w / KNIT_TILE)
	mat = bpy.data.materials.new("Knit_" + obj.name)
	mat.use_nodes = True
	nodes = mat.node_tree.nodes
	links = mat.node_tree.links
	bsdf = nodes["Principled BSDF"]
	albedo = nodes.new("ShaderNodeTexImage")
	albedo.image = bpy.data.images.load(os.path.abspath(textures % "albedo"))
	links.new(albedo.outputs["Color"], bsdf.inputs["Base Color"])
	orm = nodes.new("ShaderNodeTexImage")
	orm.image = bpy.data.images.load(os.path.abspath(textures % "orm"))
	orm.image.colorspace_settings.name = "Non-Color"
	split = nodes.new("ShaderNodeSeparateColor")
	links.new(orm.outputs["Color"], split.inputs["Color"])
	links.new(split.outputs["Green"], bsdf.inputs["Roughness"])
	links.new(split.outputs["Blue"], bsdf.inputs["Metallic"])
	normal = nodes.new("ShaderNodeTexImage")
	normal.image = bpy.data.images.load(os.path.abspath(textures % "normal"))
	normal.image.colorspace_settings.name = "Non-Color"
	nmap = nodes.new("ShaderNodeNormalMap")
	links.new(normal.outputs["Color"], nmap.inputs["Color"])
	links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
	me.materials.clear()
	me.materials.append(mat)
	for p in me.polygons:
		p.use_smooth = True


def strap_distance():
	"""How far a point is from the pack straps' measured centre line on the jacket (STRAP_POINTS, rest
	centres in Godot space, written by tools/runtime/measure_strap_points.gd)."""
	sides = json.load(open(STRAP_POINTS))["sides"]
	lines = []
	for rows in sides:
		pts = [Vector((r[5][0], -r[5][2], r[5][1])) for r in rows]
		lines += list(zip(pts[:-1], pts[1:]))

	def distance(p):
		best = 1e9
		for a, b in lines:
			ab = b - a
			t = min(max((p - a).dot(ab) / max(ab.length_squared, 1e-12), 0.0), 1.0)
			best = min(best, (a + ab * t - p).length)
		return best
	return distance


def cloth_bones(arm, jacket, hem, corridor):
	"""Spring-bone chains for the jacket's hem and collar (driven in game by SpringBoneSimulator3D):
	HEM_CHAINS round the hem from the pelvis, COLLAR_CHAINS round the collar from the upper spine,
	the cloth there handed over to them, fading in from where each zone starts."""
	pts = [jacket.matrix_world @ v.co for v in jacket.data.vertices]
	band = [p for p in pts if p.z < hem + HEM_ZONE]
	torso = (sum(p.x for p in band) / len(band), sum(p.y for p in band) / len(band))
	## Half a step off the front, so the two flaps of the open jacket each get their own chains.
	step = 2.0 * math.pi / HEM_CHAINS
	angles = [step * (k + 0.5) for k in range(HEM_CHAINS)]
	hem_chains = G.add_chains(arm, jacket, "hem", "pelvis", HEM_CHAINS, hem + HEM_ZONE, hem + 0.005, torso, angles)
	G.weight_to_chains(jacket, hem_chains, torso, hem + HEM_ZONE, hem)
	neck = arm.matrix_world @ arm.data.bones["neck_01"].head_local
	top = max(p.z for p in pts)
	## The collar stands only round the back (+Y); in front it falls into the lapels, faded out.
	angles = [math.pi * (k + 0.5) / COLLAR_CHAINS for k in range(COLLAR_CHAINS)]
	collar_chains = G.add_chains(arm, jacket, "collar", "spine_03", COLLAR_CHAINS, top - COLLAR_ZONE, top - 0.005,
		(neck.x, neck.y), angles, inset=0.005)
	G.weight_to_chains(jacket, collar_chains, (neck.x, neck.y), top - COLLAR_ZONE, top,
		lambda p: 0.0 if corridor(p) else abs(p.x - neck.x) < COLLAR_HALF and min(max((p.y - neck.y + COLLAR_FADE) / COLLAR_FADE, 0.0), 1.0))


def boot_cuff_bottom():
	"""Lowest point of the owner's boots' fur cuff, Blender Z (glTF Y), read from the GLB."""
	with open(BOOTS_SOURCE, "rb") as f:
		data = f.read()
	length = struct.unpack("<I", data[12:16])[0]
	gltf = json.loads(data[20:20 + length])
	nodes = gltf["nodes"]
	parent = {child: i for i, n in enumerate(nodes) for child in n.get("children", [])}
	low = math.inf
	for i, node in enumerate(nodes):
		if not node.get("name", "").startswith("Boot_Fur_") or "mesh" not in node:
			continue
		y = 0.0
		walk = i
		while walk is not None:
			y += nodes[walk].get("translation", [0.0, 0.0, 0.0])[1]
			walk = parent.get(walk)
		for prim in gltf["meshes"][node["mesh"]]["primitives"]:
			low = min(low, y + gltf["accessors"][prim["attributes"]["POSITION"]]["min"][1])
	return low


def owner_boots(arm, body, generated):
	"""Swaps the generated boots for the owner's: each piece keeps its textured material and
	takes the body's skin weights from the nearest face (foot and leg bones only)."""
	for obj in generated:
		bpy.data.objects.remove(obj)
	before = set(bpy.data.objects)
	bpy.ops.import_scene.gltf(filepath=BOOTS_SOURCE)
	imported = [o for o in bpy.data.objects if o not in before]
	extras = [o.name for o in imported if o.type != "MESH"]
	mesh_names = [o.name for o in imported if o.type == "MESH"]
	bpy.context.view_layer.update()
	for obj in imported:
		obj.matrix_parent_inverse.identity()
	for obj in imported:
		world = obj.matrix_world.copy()
		obj.parent = None
		obj.matrix_world = world
	keep = FEET | LEGS
	for prefix, name in BOOT_PARTS.items():
		parts = [bpy.data.objects[n] for n in mesh_names if n.startswith(prefix)]
		bpy.ops.object.select_all(action="DESELECT")
		for o in parts:
			o.select_set(True)
		bpy.context.view_layer.objects.active = parts[0]
		bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
		if len(parts) > 1:
			bpy.ops.object.join()
		obj = bpy.context.view_layer.objects.active
		obj.name = obj.data.name = name
	snug_shafts(body)
	for name in BOOT_PARTS.values():
		obj = bpy.data.objects[name]
		bpy.context.view_layer.objects.active = obj
		for group in body.vertex_groups:
			if group.name in keep:
				obj.vertex_groups.new(name=group.name)
		mod = obj.modifiers.new("Weights", "DATA_TRANSFER")
		mod.object = body
		mod.use_vert_data = True
		mod.data_types_verts = {"VGROUP_WEIGHTS"}
		mod.vert_mapping = "POLYINTERP_NEAREST"
		mod.layers_vgroup_select_src = "ALL"
		mod.layers_vgroup_select_dst = "NAME"
		bpy.ops.object.modifier_apply(modifier="Weights")
		bpy.ops.object.vertex_group_normalize_all(lock_active=False)
		obj.parent = arm
		obj.modifiers.new("Armature", "ARMATURE").object = arm
	for extra in extras:
		bpy.data.objects.remove(bpy.data.objects[extra])


def snug_shafts(body):
	"""Wraps each boot's shaft round the shin: above the ankle the shell is laid on the leg with
	room for the tucked jeans and the boot wall, growing in from the ankle to full at the calf, so
	no leg shows past it; the lining and the fur cuff ride on the shell. Foot and sole unchanged."""
	shell = bpy.data.objects["Outfit_Boots"]
	lining = bpy.data.objects["Outfit_BootLining"]
	riders = [lining, bpy.data.objects["Outfit_BootFur"]]
	## A touch larger (owner), about each boot's sole centre so the soles stay on the floor.
	floor = min((shell.matrix_world @ v.co).z for v in shell.data.vertices)
	for obj in [shell] + riders:
		inv = obj.matrix_world.inverted()
		for v in obj.data.vertices:
			p = obj.matrix_world @ v.co
			centre = Vector((math.copysign(BOOT_CENTRE_X, p.x), 0.0, floor))
			v.co = inv @ (centre + (p - centre) * BOOT_SCALE)
		obj.data.update()
	for rider in riders:
		G.ride_on(rider, shell)
	group = shell.vertex_groups.new(name="Shaft")
	for v in shell.data.vertices:
		z = (shell.matrix_world @ v.co).z
		t = min(max((z - SHAFT_SNUG_FROM) / (SHAFT_SNUG_FULL - SHAFT_SNUG_FROM), 0.0), 1.0)
		if t > 0.0:
			group.add([v.index], t * t * (3.0 - 2.0 * t), "REPLACE")
	mod = shell.modifiers.new("Snug", "SHRINKWRAP")
	mod.target = body
	mod.wrap_method = "NEAREST_SURFACEPOINT"
	mod.wrap_mode = "ABOVE_SURFACE"
	mod.offset = SHAFT_GAP
	mod.vertex_group = "Shaft"
	bpy.context.view_layer.objects.active = shell
	bpy.ops.object.modifier_apply(modifier="Snug")
	shell.vertex_groups.remove(shell.vertex_groups["Shaft"])
	## Wherever the leg or foot still comes through above the sole, only those points move out.
	G.fit_outside(shell, body, BOOT_SKIN_MARGIN, above=BOOT_SOLE_TOP)
	for rider in riders:
		G.apply_ride(rider)
	## The lining stopped under the rim, leaving a dark slot between shell and leg: its top band
	## is drawn up to the rim, laid on the shin just inside the shell.
	shell_top = max((shell.matrix_world @ v.co).z for v in shell.data.vertices)
	lining_top = max((lining.matrix_world @ v.co).z for v in lining.data.vertices)
	inv = lining.matrix_world.inverted()
	for v in lining.data.vertices:
		p = lining.matrix_world @ v.co
		if p.z > lining_top - 0.03:
			t = (p.z - (lining_top - 0.03)) / 0.03
			p.z += t * (shell_top - lining_top)
			v.co = inv @ p
	lining.data.update()
	## The lining never shows through: it is kept inside the shell everywhere.
	G.keep_inside(lining, shell, 10.0, 9.0, LINING_INSET)


def finish(obj, arm, name, colour, thick):
	"""Skins a new mesh to the armature, thickens it and gives it flat shading."""
	obj.parent = arm
	obj.modifiers.new("Armature", "ARMATURE").object = arm
	obj.data.materials.append(material(name, colour))
	bpy.context.view_layer.objects.active = obj
	if thick > 0.0:
		sol = obj.modifiers.new("Solidify", "SOLIDIFY")
		sol.thickness = thick
		sol.offset = -1.0
		sol.use_rim = True
		bpy.ops.object.modifier_move_to_index(modifier="Solidify", index=0)
		bpy.ops.object.modifier_apply(modifier="Solidify")
	for p in obj.data.polygons:
		p.use_smooth = False


def build_skirt(arm, body):
	"""The coat below the hips: one flared tube around both legs, skinned mostly to
	the pelvis and partly to each thigh, so it swings instead of splitting."""
	pelvis = arm.matrix_world @ arm.data.bones["pelvis"].head_local
	left_x = (arm.matrix_world @ arm.data.bones["thigh_l"].head_local).x - pelvis.x
	top, bottom = CUTS["hem"] + 0.09, CUTS["skirt_bottom"]  # top tucks under the coat
	segments, rows = 24, 5
	## An ellipse around hips and thighs, deeper at the back than the front; it
	## bridges the gap between the legs instead of following it.
	rx = front = back = 0.0
	for v in body.data.vertices:
		p = body.matrix_world @ v.co
		if bottom - 0.02 < p.z < top:
			rx = max(rx, abs(p.x - pelvis.x))
			front = max(front, pelvis.y - p.y)
			back = max(back, p.y - pelvis.y)
	measured = [0.0] * segments
	for v in body.data.vertices:
		p = body.matrix_world @ v.co
		if bottom - 0.02 < p.z < top:
			d = Vector((p.x - pelvis.x, p.y - pelvis.y))
			i = int((math.atan2(d.y, d.x) + math.pi) / (2 * math.pi) * segments) % segments
			measured[i] = max(measured[i], d.length)
	## Never inside the body: the larger of the ellipse and the measured outline.
	radius = []
	for i in range(segments):
		a = (i + 0.5) / segments * 2 * math.pi - math.pi
		ry = back if math.sin(a) > 0.0 else front
		ellipse = rx * ry / math.hypot(ry * math.cos(a), rx * math.sin(a))
		radius.append(max(ellipse, measured[i - 1], measured[i], measured[(i + 1) % segments]))
	mesh = bpy.data.meshes.new("Outfit_Skirt")
	skirt = bpy.data.objects.new("Outfit_Skirt", mesh)
	bpy.context.collection.objects.link(skirt)
	bm = bmesh.new()
	grid = []
	for r in range(rows):
		t = r / (rows - 1)
		z = top + (bottom - top) * t
		ring = []
		for i in range(segments):
			a = (i + 0.5) / segments * 2 * math.pi - math.pi
			rad = radius[i] + SKIRT_PUSH * (0.6 if r == 0 else 1.0) + SKIRT_FLARE * t
			ring.append(bm.verts.new((pelvis.x + math.cos(a) * rad, pelvis.y + math.sin(a) * rad, z)))
		grid.append(ring)
	for r in range(rows - 1):
		for i in range(segments):
			j = (i + 1) % segments
			bm.faces.new((grid[r][i], grid[r][j], grid[r + 1][j], grid[r + 1][i]))
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	bm.to_mesh(mesh)
	bm.free()
	groups = {n: skirt.vertex_groups.new(name=n) for n in ("pelvis", "thigh_l", "thigh_r")}
	for idx, v in enumerate(mesh.vertices):
		t = (idx // segments) / (rows - 1)
		## The hem follows the thighs: sides their own leg, the centre line both
		## legs' average, so a leg swinging forward carries the cloth with it.
		leg = SKIRT_LEG_FOLLOW * t
		to_left = 0.5 + 0.5 * max(-1.0, min(1.0, (v.co.x - pelvis.x) / 0.08 * math.copysign(1.0, left_x)))
		groups["pelvis"].add([idx], 1.0 - leg, "REPLACE")
		groups["thigh_l"].add([idx], leg * to_left, "REPLACE")
		groups["thigh_r"].add([idx], leg * (1.0 - to_left), "REPLACE")
	finish(skirt, arm, "Skirt", JACKET_COLOUR, 0.010)
	return skirt


def build_trim(arm, sources):
	"""Placket with a zip down the front and seams at shoulders, cuffs and waist:
	ribbons laid on the coat's surface by ray casts, skinned like the nearest
	coat vertex."""
	from mathutils.bvhtree import BVHTree
	from mathutils.kdtree import KDTree
	deps = bpy.context.evaluated_depsgraph_get()
	trees, weights, kd_points = [], [], []
	for src in sources:
		trees.append(BVHTree.FromObject(src, deps))
		names = {g.index: g.name for g in src.vertex_groups}
		for v in src.data.vertices:
			kd_points.append(src.matrix_world @ v.co)
			weights.append({names[g.group]: g.weight for g in v.groups})
	kd = KDTree(len(kd_points))
	for i, p in enumerate(kd_points):
		kd.insert(p, i)
	kd.balance()

	def hit(origin, direction):
		best = None
		for tree in trees:
			loc, normal, _i, dist = tree.ray_cast(origin, direction)
			if loc is not None and (best is None or dist < best[2]):
				best = (loc, normal, dist)
		return best

	pelvis = arm.matrix_world @ arm.data.bones["pelvis"].head_local
	neck = arm.matrix_world @ arm.data.bones["neck_01"].head_local
	strips = []  # (points, normals, across, width, lift, colour name)
	## Placket and zip: straight down the front (-Y) from the collar to the hem.
	pts, nrm = [], []
	steps = 28
	for k in range(steps + 1):
		z = neck.z + 0.02 + (CUTS["skirt_bottom"] + 0.01 - neck.z - 0.02) * k / steps
		h = hit(Vector((pelvis.x, pelvis.y - 1.0, z)), Vector((0.0, 1.0, 0.0)))
		if h:
			pts.append(h[0])
			nrm.append(h[1])
	strips.append((pts, nrm, Vector((1.0, 0.0, 0.0)), 0.045, 0.006, "Trim"))
	strips.append((pts, nrm, Vector((1.0, 0.0, 0.0)), 0.008, 0.010, "Zip"))
	## Rings: rays from outside toward a bone axis at a share t of its length.
	def ring(bone, t, width):
		b = arm.data.bones[bone]
		h0, t0 = arm.matrix_world @ b.head_local, arm.matrix_world @ b.tail_local
		axis = (t0 - h0).normalized()
		centre = h0 + (t0 - h0) * t
		u = axis.orthogonal().normalized()
		w = axis.cross(u)
		rp, rn = [], []
		for k in range(25):
			a = k / 24 * 2 * math.pi
			out = u * math.cos(a) + w * math.sin(a)
			hh = hit(centre + out * 0.6, -out)
			if hh:
				rp.append(hh[0])
				rn.append(hh[1])
		strips.append((rp, rn, axis, width, 0.005, "Trim"))
	for side in ("l", "r"):
		ring("upperarm_" + side, 0.06, 0.018)
		ring("lowerarm_" + side, 0.98, 0.022)
	ring("spine_01", 0.2, 0.02)
	## Ribbons of quads; each vertex copies the nearest coat vertex's weights.
	objs = []
	for pts, nrm, across, width, lift, colour in strips:
		if len(pts) < 2:
			continue
		mesh = bpy.data.meshes.new("strip")
		obj = bpy.data.objects.new("strip", mesh)
		bpy.context.collection.objects.link(obj)
		bm = bmesh.new()
		rows = []
		for p, n in zip(pts, nrm):
			side = (across - n * across.dot(n)).normalized() * width * 0.5
			base = p + n * lift
			rows.append((bm.verts.new(base - side), bm.verts.new(base + side)))
		for a, b in zip(rows, rows[1:]):
			if (a[0].co - b[0].co).length < 0.12:  # skip jumps across gaps
				bm.faces.new((a[0], a[1], b[1], b[0]))
		bm.to_mesh(mesh)
		bm.free()
		for vi, v in enumerate(mesh.vertices):
			_co, idx, _d = kd.find(v.co)
			for gname, wgt in weights[idx].items():
				g = obj.vertex_groups.get(gname) or obj.vertex_groups.new(name=gname)
				g.add([vi], wgt, "REPLACE")
		obj.data.materials.append(material(colour, TRIM_COLOUR if colour == "Trim" else ZIP_COLOUR))
		objs.append(obj)
	bpy.ops.object.select_all(action="DESELECT")
	for obj in objs:
		obj.select_set(True)
	bpy.context.view_layer.objects.active = objs[0]
	bpy.ops.object.join()
	trim = objs[0]
	trim.name = trim.data.name = "Outfit_Trim"
	trim.parent = arm
	trim.modifiers.new("Armature", "ARMATURE").object = arm
	bpy.context.view_layer.objects.active = trim
	sol = trim.modifiers.new("Solidify", "SOLIDIFY")
	sol.thickness = 0.004
	bpy.ops.object.modifier_move_to_index(modifier="Solidify", index=0)
	bpy.ops.object.modifier_apply(modifier="Solidify")
	for p in trim.data.polygons:
		p.use_smooth = False



def build_hood(arm, body):
	"""A hood folded down behind the neck: a flattened ring skinned to neck and chest."""
	neck = arm.matrix_world @ arm.data.bones["neck_01"].head_local
	bpy.ops.mesh.primitive_torus_add(major_radius=0.12, minor_radius=0.05, major_segments=12,
		minor_segments=6, location=(neck.x, neck.y + 0.03, neck.z + 0.075))
	hood = bpy.context.active_object
	hood.name = hood.data.name = "Outfit_Hood"
	hood.scale = (1.05, 0.95, 0.75)
	hood.rotation_euler = (math.radians(-18), 0.0, 0.0)  # tips up at the back
	bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
	bm = bmesh.new()
	bm.from_mesh(hood.data)
	for v in bm.verts:
		if v.co.y < -0.02:  # the front of the ring hides under the collar
			v.co.z -= 0.03
	bm.to_mesh(hood.data)
	bm.free()
	for bone, w in (("neck_01", 0.6), ("spine_03", 0.4)):
		g = hood.vertex_groups.new(name=bone)
		g.add(range(len(hood.data.vertices)), w, "REPLACE")
	hood.parent = arm
	hood.matrix_parent_inverse = arm.matrix_world.inverted()
	hood.modifiers.new("Armature", "ARMATURE").object = arm
	hood.data.materials.append(material("Hood", HOOD_COLOUR))
	for p in hood.data.polygons:
		p.use_smooth = False


def export(arm):
	os.makedirs(os.path.dirname(OUT), exist_ok=True)
	bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_animations=True,
		export_animation_mode="ACTIONS", export_apply=False, export_yup=True)


def render(arm, out_dir):
	"""Idle/walk/sprint turnaround stills with Cycles on the CPU."""
	scene = bpy.context.scene
	for o in bpy.data.objects:
		o.hide_render = o.name.startswith("Skin_")  # all items worn, as in game
	scene.render.engine = "CYCLES"
	scene.cycles.device = "CPU"
	scene.cycles.samples = 24
	scene.render.resolution_x, scene.render.resolution_y = 640, 800
	world = bpy.data.worlds.new("W")
	world.color = (0.8, 0.8, 0.82)
	world.use_nodes = True
	world.node_tree.nodes["Background"].inputs[0].default_value = (0.75, 0.76, 0.78, 1.0)
	world.node_tree.nodes["Background"].inputs[1].default_value = 0.45
	scene.world = world
	sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
	sun.data.energy = 3.0
	sun.rotation_euler = (math.radians(50), 0, math.radians(35))
	scene.collection.objects.link(sun)
	cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
	cam.data.lens = 50
	scene.collection.objects.link(cam)
	scene.camera = cam
	arm.animation_data_create()
	shots = [("Idle_Loop", 0.3), ("Walk_Loop", 0.25), ("Sprint_Loop", 0.25)]
	views = {"front": 0.0, "side": 90.0, "back34": 150.0}
	for clip, phase in shots:
		act = bpy.data.actions[clip]
		arm.animation_data.action = act
		f0, f1 = act.frame_range
		scene.frame_set(int(f0 + phase * (f1 - f0)))
		for view, deg in views.items():
			a = math.radians(deg)
			cam.location = Vector((math.sin(a) * 4.2, -math.cos(a) * 4.2, 1.0))
			cam.rotation_euler = (math.radians(88), 0, a)
			scene.render.filepath = os.path.join(out_dir, f"{clip}_{view}.png")
			bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
	armature = build()
	export(armature)
	if "--render" in sys.argv:
		render(armature, sys.argv[sys.argv.index("--render") + 1])
