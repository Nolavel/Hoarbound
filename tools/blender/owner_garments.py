"""Fits the owner's downloaded garments (assets/characters/gear/, CC-BY, see CREDITS.md) onto the
UAL mannequin for build_henry_outfit.py.

Method, as in common garment-retargeting pipelines (Blender Data Transfer + Shrinkwrap):
1. Re-pose: a garment modelled in an A-pose is bound to a copy of the armature posed to match
   it, then posed back to the mannequin's T-pose and applied.
2. Fit: Shrinkwrap in Outside Surface mode pushes only points inside the body out to a margin.
3. Skin: weights from the body's nearest face (Data Transfer, nearest face interpolated).
"""
import math

import bpy
from mathutils import Matrix


def import_joined(path, name, keep):
	"""Imports a glTF and joins the mesh objects whose name passes `keep` into one object `name`,
	transforms applied. Everything else imported is removed."""
	before = set(bpy.data.objects)
	bpy.ops.import_scene.gltf(filepath=path)
	imported = [o for o in bpy.data.objects if o not in before]
	bpy.context.view_layer.update()
	meshes = [o.name for o in imported if o.type == "MESH" and keep(o.name)]
	worlds = {n: bpy.data.objects[n].matrix_world.copy() for n in meshes}
	for n in meshes:
		obj = bpy.data.objects[n]
		obj.parent = None
		obj.matrix_world = worlds[n]
	for o in imported:
		if o.name not in meshes:
			bpy.data.objects.remove(o)
	bpy.ops.object.select_all(action="DESELECT")
	for n in meshes:
		bpy.data.objects[n].select_set(True)
	bpy.context.view_layer.objects.active = bpy.data.objects[meshes[0]]
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	if len(meshes) > 1:
		bpy.ops.object.join()
	obj = bpy.context.view_layer.objects.active
	obj.name = obj.data.name = name
	return obj


def decimate_to(obj, faces, keep_edges=False):
	"""Collapse-decimates obj to about `faces` faces (UVs kept). keep_edges: open edges (a sewn
	garment's separate panels) are weighted so collapse leaves them, else the panels pull apart."""
	if len(obj.data.polygons) <= faces:
		return
	import bmesh
	bpy.context.view_layer.objects.active = obj
	mod = obj.modifiers.new("Decimate", "DECIMATE")
	mod.ratio = faces / len(obj.data.polygons)
	if keep_edges:
		bm = bmesh.new()
		bm.from_mesh(obj.data)
		edge = [v.index for v in bm.verts if any(e.is_boundary for e in v.link_edges)]
		bm.free()
		group = obj.vertex_groups.new(name="KeepEdges")
		group.add(edge, 1.0, "REPLACE")
		mod.vertex_group = group.name
		mod.invert_vertex_group = True
		mod.vertex_group_factor = 10.0
	bpy.ops.object.modifier_apply(modifier="Decimate")
	if keep_edges:
		obj.vertex_groups.remove(obj.vertex_groups["KeepEdges"])


def sleeve_droop(obj, side, shoulder_x):
	"""Angle (radians) the sleeve on `side` (+1 left, -1 right) hangs below horizontal: a least
	squares line through the sleeve's centreline from just past the shoulder to the cuff."""
	bins = {}
	for v in obj.data.vertices:
		x = (obj.matrix_world @ v.co).x * side
		if x > shoulder_x + 0.1:
			bins.setdefault(round(x * 40.0), []).append((obj.matrix_world @ v.co).z)
	line = [(k / 40.0, sum(z) / len(z)) for k, z in sorted(bins.items()) if len(z) > 8]
	n = len(line)
	mx = sum(p[0] for p in line) / n
	mz = sum(p[1] for p in line) / n
	slope = sum((p[0] - mx) * (p[1] - mz) for p in line) / sum((p[0] - mx) ** 2 for p in line)
	return math.atan(-slope)


def repose_arms(obj, arm, droop):
	"""Brings a garment from an A-pose to the armature's T-pose. droop: {side: radians} per arm."""
	bones = {1: "upperarm_l", -1: "upperarm_r"}
	saved = {pb.name: pb.matrix_basis.copy() for pb in arm.pose.bones}
	for side, bone in bones.items():
		_turn_down(arm, bone, side * droop[side])
	## The body in the garment's pose gives it weights that match where its sleeves are.
	body = bpy.data.objects["Mannequin"]
	posed = body.copy()
	posed.data = body.data.copy()
	bpy.context.collection.objects.link(posed)
	bpy.context.view_layer.objects.active = posed
	for mod in list(posed.modifiers):
		if mod.type == "ARMATURE":
			bpy.ops.object.modifier_apply(modifier=mod.name)
	skin_from(obj, posed)
	bpy.data.objects.remove(posed)
	## A copy of the armature whose rest is this A-pose; posed back to T, it carries the garment.
	temp = arm.copy()
	temp.data = arm.data.copy()
	temp.animation_data_clear()
	bpy.context.collection.objects.link(temp)
	bpy.ops.object.select_all(action="DESELECT")
	bpy.context.view_layer.objects.active = temp
	temp.select_set(True)
	bpy.ops.object.mode_set(mode="POSE")
	bpy.ops.pose.armature_apply(selected=False)
	for side, bone in bones.items():
		_turn_down(temp, bone, -side * droop[side])
	bpy.ops.object.mode_set(mode="OBJECT")
	mod = obj.modifiers.new("Repose", "ARMATURE")
	mod.object = temp
	bpy.context.view_layer.objects.active = obj
	bpy.ops.object.modifier_apply(modifier="Repose")
	for group in list(obj.vertex_groups):
		obj.vertex_groups.remove(group)
	bpy.data.objects.remove(temp)
	for pb in arm.pose.bones:
		pb.matrix_basis = saved[pb.name]
	bpy.context.view_layer.update()


def _turn_down(rig, bone, angle):
	"""Rotates a pose bone about the world Y axis (front to back) through its head."""
	pose_bone = rig.pose.bones[bone]
	pose_bone.rotation_mode = "QUATERNION"
	rest = rig.data.bones[bone].matrix_local
	local = rest.inverted() @ Matrix.Rotation(angle, 4, "Y") @ rest
	pose_bone.rotation_quaternion = local.to_quaternion() @ pose_bone.rotation_quaternion
	bpy.context.view_layer.update()


def fit_outside(obj, body, margin, below=None):
	"""Pushes any point of obj inside the body out to `margin` metres past its surface. With
	`below`, only points lower than that height: over an open mesh (the jeans' waist), points
	above its rim would otherwise read as inside and collapse onto it."""
	mod = obj.modifiers.new("Fit", "SHRINKWRAP")
	mod.target = body
	mod.wrap_method = "NEAREST_SURFACEPOINT"
	mod.wrap_mode = "OUTSIDE_SURFACE"
	mod.offset = margin
	if below is not None:
		group = obj.vertex_groups.new(name="FitBelow")
		group.add([v.index for v in obj.data.vertices if (obj.matrix_world @ v.co).z < below], 1.0, "REPLACE")
		mod.vertex_group = group.name
	bpy.context.view_layer.objects.active = obj
	bpy.ops.object.modifier_apply(modifier="Fit")
	if below is not None:
		obj.vertex_groups.remove(obj.vertex_groups["FitBelow"])


def skin_from(obj, body, keep=None):
	"""Gives obj the body's skin weights from the nearest face, only for groups in `keep` if given."""
	for group in body.vertex_groups:
		if (keep is None or group.name in keep) and group.name not in obj.vertex_groups:
			obj.vertex_groups.new(name=group.name)
	mod = obj.modifiers.new("Weights", "DATA_TRANSFER")
	mod.object = body
	mod.use_vert_data = True
	mod.data_types_verts = {"VGROUP_WEIGHTS"}
	mod.vert_mapping = "POLYINTERP_NEAREST"
	mod.layers_vgroup_select_src = "ALL"
	mod.layers_vgroup_select_dst = "NAME"
	bpy.context.view_layer.objects.active = obj
	bpy.ops.object.modifier_apply(modifier="Weights")
	bpy.ops.object.vertex_group_normalize_all(lock_active=False)


def bind(obj, arm):
	obj.parent = arm
	obj.modifiers.new("Armature", "ARMATURE").object = arm


def cut_below(obj, z):
	"""Cuts obj along the plane at height z and drops what lies below (hidden inside the boots).
	An exact bisection: decimated faces can span far past the line and would leave spikes."""
	import bmesh
	bm = bmesh.new()
	bm.from_mesh(obj.data)
	bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0.0, 0.0, z),
		plane_no=(0.0, 0.0, 1.0), clear_inner=True)
	bm.to_mesh(obj.data)
	bm.free()


def coverage(body, garments, reach=0.08):
	"""Per body vertex, the label of the innermost garment over it (garments: [(object, label)],
	inner first), or "": a ray from the skin out along its normal, as a body mask is made for
	layered clothing. Rest pose, world space."""
	import bmesh
	from mathutils.bvhtree import BVHTree
	trees = []
	for obj, label in garments:
		bm = bmesh.new()
		bm.from_mesh(obj.data)
		bm.transform(obj.matrix_world)
		trees.append((BVHTree.FromBMesh(bm), label))
		bm.free()
	out = []
	world = body.matrix_world
	normal_world = world.to_3x3().inverted().transposed()
	for v in body.data.vertices:
		p = world @ v.co
		n = (normal_world @ v.normal).normalized()
		best = ""
		best_d = reach
		for tree, label in trees:
			hit = tree.ray_cast(p - n * 0.002, n, reach)
			if hit[0] is not None and hit[3] < best_d:
				best, best_d = label, hit[3]
		out.append(best)
	return out


def fit_sleeves(obj, arm, overlap):
	"""Scales each sleeve along the arm (from the shoulder out) so its cuff ends `overlap` metres
	past the wrist: a garment cut for longer arms otherwise swallows the hand and its cuff takes
	the hand's weights and crumples."""
	for side, (upper, hand) in {1: ("upperarm_l", "hand_l"), -1: ("upperarm_r", "hand_r")}.items():
		shoulder = (arm.matrix_world @ arm.data.bones[upper].head_local).x * side
		wrist = (arm.matrix_world @ arm.data.bones[hand].head_local).x * side
		inv = obj.matrix_world.inverted()
		points = [(obj.matrix_world @ v.co) for v in obj.data.vertices]
		end = max(p.x * side for p in points)
		scale = (wrist + overlap - shoulder) / (end - shoulder)
		for v, p in zip(obj.data.vertices, points):
			x = p.x * side
			if x > shoulder:
				p.x = (shoulder + (x - shoulder) * scale) * side
				v.co = inv @ p
	obj.data.update()


def inflate(obj, depth):
	"""Moves every point of obj out along its smooth normal by `depth` metres (a looser cut).
	Coincident points (UV seams) move together, so seams do not open."""
	import bmesh
	from mathutils import Vector
	bm = bmesh.new()
	bm.from_mesh(obj.data)
	bm.normal_update()
	groups = {}
	for v in bm.verts:
		groups.setdefault(tuple(round(c, 5) for c in v.co), []).append(v)
	for verts in groups.values():
		n = Vector()
		for v in verts:
			n += v.normal
		if n.length > 0.0:
			n.normalize()
		for v in verts:
			v.co += n * depth
	bm.to_mesh(obj.data)
	bm.free()


def tuck(obj, body, top, bottom, margin):
	"""Trousers tucked into boots: between heights `top` and `bottom` each point is drawn in to
	`margin` past the leg (fully at `bottom`), so the cloth tapers inside the boot shaft."""
	group = obj.vertex_groups.new(name="Tuck")
	for v in obj.data.vertices:
		z = (obj.matrix_world @ v.co).z
		if z < top:
			t = min(max((top - z) / (top - bottom), 0.0), 1.0)
			group.add([v.index], t * t * (3.0 - 2.0 * t), "REPLACE")
	mod = obj.modifiers.new("Tuck", "SHRINKWRAP")
	mod.target = body
	mod.wrap_method = "NEAREST_SURFACEPOINT"
	mod.wrap_mode = "ABOVE_SURFACE"
	mod.offset = margin
	mod.vertex_group = group.name
	bpy.context.view_layer.objects.active = obj
	bpy.ops.object.modifier_apply(modifier="Tuck")
	obj.vertex_groups.remove(obj.vertex_groups["Tuck"])


def keep_inside(obj, shell, top, bottom, margin):
	"""Keeps points of obj below `top` inside the closed-normal `shell` by `margin` (fully from
	`bottom` down): trousers tucked into a rigid boot shaft stay inside it instead of piercing it."""
	group = obj.vertex_groups.new(name="Inside")
	for v in obj.data.vertices:
		z = (obj.matrix_world @ v.co).z
		if z < top:
			t = min(max((top - z) / (top - bottom), 0.0), 1.0)
			group.add([v.index], t * t * (3.0 - 2.0 * t), "REPLACE")
	mod = obj.modifiers.new("Inside", "SHRINKWRAP")
	mod.target = shell
	mod.wrap_method = "NEAREST_SURFACEPOINT"
	mod.wrap_mode = "INSIDE"
	mod.offset = margin
	mod.vertex_group = "Inside"
	bpy.context.view_layer.objects.active = obj
	bpy.ops.object.modifier_apply(modifier="Inside")
	obj.vertex_groups.remove(obj.vertex_groups["Inside"])


def merge_weights(obj, sources, target):
	"""Adds the weight each vertex has in the `sources` groups to `target` and drops them, so
	those vertices follow `target` alone (none is left unweighted)."""
	if target not in obj.vertex_groups:
		obj.vertex_groups.new(name=target)
	dst = obj.vertex_groups[target]
	indices = {obj.vertex_groups[n].index for n in sources if n in obj.vertex_groups}
	for v in obj.data.vertices:
		moved = sum(g.weight for g in v.groups if g.group in indices)
		if moved > 0.0:
			current = next((g.weight for g in v.groups if g.group == dst.index), 0.0)
			dst.add([v.index], min(current + moved, 1.0), "REPLACE")
	for n in sources:
		if n in obj.vertex_groups:
			obj.vertex_groups.remove(obj.vertex_groups[n])

