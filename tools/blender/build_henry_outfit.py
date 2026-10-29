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

SOURCE = "assets/animation/ual/Unreal-Godot/UAL1_Standard.glb"
OUT = "assets/characters/henry/henry_outfit.glb"
## The owner's boots, modelled in the mannequin's rest pose; they replace the generated boots.
BOOTS_SOURCE = "assets/items/boots/boots.glb"
## Imported piece name prefix -> outfit mesh (both feet joined into one).
BOOT_PARTS = {"Boot_New_": "Outfit_Boots", "Boot_Lining_": "Outfit_BootLining", "Boot_Fur_": "Outfit_BootFur"}

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
GARMENTS = {
	"Jacket": (JACKET_COLOUR, 0.030, 0.010, 12),
	"Pants": ((0.27, 0.30, 0.36), 0.019, 0.008, 8),
	"Boots": ((0.30, 0.22, 0.15), 0.020, 0.012, 6),
	"Sole": ((0.17, 0.12, 0.09), 0.022, 0.014, 2),
	"Beanie": ((0.52, 0.20, 0.16), 0.008, 0.008, 6),
	"BeanieCuff": ((0.46, 0.17, 0.14), 0.020, 0.012, 4),
	"Gloves": (GLOVE_OLIVE, 0.014, 0.006, 3),
	"GloveCuff": ((0.14, 0.11, 0.08), 0.044, 0.010, 8),
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
ITEM_OF = {"Jacket": "Coat", "Hood": "Coat", "Skirt": "Coat", "Trim": "Coat", "Pants": "Trousers", "Boots": "Boots", "Sole": "Boots",
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


def split_body(body, region):
	"""Moves skin fully inside a garment (one ring from its border) into Skin_<item>
	meshes, which the game hides while that item is worn."""
	owner = [next((g for g in SKIN_PRIORITY if g in r), "") for r in region]
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
		if len(labels) == 1 and "" not in labels and not any(v.index in border for v in f.verts):
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
	split_body(body, region)
	build_hood(arm, body)
	skirt = build_skirt(arm, body)
	build_trim(arm, [built["Jacket"], skirt])
	return arm


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
