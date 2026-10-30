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
	## The armature's action would overwrite these pose edits on any frame change (an earlier
	## cloth drape plays frames), so it is lifted for the re-pose and put back after.
	action = arm.animation_data.action if arm.animation_data else None
	if action is not None:
		arm.animation_data.action = None
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
	if action is not None:
		arm.animation_data.action = action
	bpy.context.view_layer.update()


def _turn_down(rig, bone, angle):
	"""Rotates a pose bone about the world Y axis (front to back) through its head."""
	pose_bone = rig.pose.bones[bone]
	pose_bone.rotation_mode = "QUATERNION"
	rest = rig.data.bones[bone].matrix_local
	local = rest.inverted() @ Matrix.Rotation(angle, 4, "Y") @ rest
	pose_bone.rotation_quaternion = local.to_quaternion() @ pose_bone.rotation_quaternion
	bpy.context.view_layer.update()


def fit_outside(obj, body, margin, below=None, above=None):
	"""Pushes any point of obj inside the body out to `margin` metres past its surface. With
	`below`, only points lower than that height: over an open mesh (the jeans' waist), points
	above its rim would otherwise read as inside and collapse onto it."""
	mod = obj.modifiers.new("Fit", "SHRINKWRAP")
	mod.target = body
	mod.wrap_method = "NEAREST_SURFACEPOINT"
	mod.wrap_mode = "OUTSIDE"  # only points inside move; OUTSIDE_SURFACE lays every point on the target
	mod.offset = margin
	if below is not None or above is not None:
		group = obj.vertex_groups.new(name="FitBelow")
		group.add([v.index for v in obj.data.vertices
			if (below is None or (obj.matrix_world @ v.co).z < below)
			and (above is None or (obj.matrix_world @ v.co).z > above)], 1.0, "REPLACE")
		mod.vertex_group = group.name
	bpy.context.view_layer.objects.active = obj
	bpy.ops.object.modifier_apply(modifier="Fit")
	if below is not None or above is not None:
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


def coverage(body, garments, reach=0.2):
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


def merge_weights(obj, sources, target, where=None):
	"""Adds the weight each vertex has in the `sources` groups to `target` and drops them, so
	those vertices follow `target` alone (none is left unweighted). With `where` (world point ->
	bool), only for the vertices it accepts."""
	if target not in obj.vertex_groups:
		obj.vertex_groups.new(name=target)
	dst = obj.vertex_groups[target]
	groups = [obj.vertex_groups[n] for n in sources if n in obj.vertex_groups]
	indices = {g.index for g in groups}
	for v in obj.data.vertices:
		if where is not None and not where(obj.matrix_world @ v.co):
			continue
		moved = sum(g.weight for g in v.groups if g.group in indices)
		if moved > 0.0:
			current = next((g.weight for g in v.groups if g.group == dst.index), 0.0)
			dst.add([v.index], min(current + moved, 1.0), "REPLACE")
			for g in groups:
				g.remove([v.index])
	if where is None:
		for g in groups:
			obj.vertex_groups.remove(g)



def weld(obj, dist=0.0002):
	"""Merges coincident points (glTF splits them on UV seams): one connected cloth, UVs kept."""
	import bmesh
	bm = bmesh.new()
	bm.from_mesh(obj.data)
	bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=dist)
	bm.to_mesh(obj.data)
	bm.free()


def split_largest(obj, name):
	"""Splits obj into its largest connected piece (kept as obj) and the rest (returned as a new
	object `name`, or None): the cloth to simulate and the small parts riding on it."""
	import bmesh
	bm = bmesh.new()
	bm.from_mesh(obj.data)
	seen = set()
	islands = []
	for v in bm.verts:
		if v in seen:
			continue
		stack = [v]
		island = []
		while stack:
			x = stack.pop()
			if x in seen:
				continue
			seen.add(x)
			island.append(x.index)
			stack.extend(e.other_vert(x) for e in x.link_edges if e.other_vert(x) not in seen)
		islands.append(island)
	bm.free()
	islands.sort(key=len, reverse=True)
	if len(islands) < 2:
		return None
	rest = {i for island in islands[1:] for i in island}
	bpy.ops.object.select_all(action="DESELECT")
	bpy.context.view_layer.objects.active = obj
	obj.select_set(True)
	bpy.ops.object.mode_set(mode="EDIT")
	bpy.ops.mesh.select_all(action="DESELECT")
	bpy.ops.object.mode_set(mode="OBJECT")
	for v in obj.data.vertices:
		v.select = v.index in rest
	bpy.ops.object.mode_set(mode="EDIT")
	bpy.ops.mesh.separate(type="SELECTED")
	bpy.ops.object.mode_set(mode="OBJECT")
	parts = [o for o in bpy.context.selected_objects if o != obj]
	parts[0].name = parts[0].data.name = name
	return parts[0]


def ride_on(part, cloth):
	"""Binds `part` (buttons, belt, loops) to `cloth` with Surface Deform at rest, so whatever the
	cloth then does carries it along. Apply with apply_ride() after the cloth is applied."""
	mod = part.modifiers.new("Ride", "SURFACE_DEFORM")
	mod.target = cloth
	bpy.context.view_layer.objects.active = part
	bpy.ops.object.surfacedeform_bind(modifier="Ride")


def apply_ride(part):
	bpy.context.view_layer.objects.active = part
	bpy.ops.object.modifier_apply(modifier="Ride")


def drape(obj, colliders, fabric, frames, pin=None, shrink=None):
	"""Settles obj on the body as cloth (Blender Cloth, gravity, collision with `colliders`) and
	applies the final frame. fabric: dict of Cloth settings (mass, stiffness...). pin: vertex
	indices held in place (a waistband, a collar). shrink: {vertex index: weight} pulled in by
	fabric["shrink"] at weight 1 (cloth gathered into a boot)."""
	scene = bpy.context.scene
	for collider in colliders:
		if not any(m.type == "COLLISION" for m in collider.modifiers):
			collider.modifiers.new("Collision", "COLLISION")
		collider.collision.thickness_outer = fabric.get("collider_thickness", 0.003)
		collider.collision.cloth_friction = 5.0
	cloth = obj.modifiers.new("Cloth", "CLOTH")
	s = cloth.settings
	s.quality = fabric.get("quality", 8)
	s.mass = fabric["mass"]
	s.tension_stiffness = s.compression_stiffness = fabric["stretch"]
	s.shear_stiffness = fabric.get("shear", fabric["stretch"])
	s.bending_stiffness = fabric["bending"]
	s.air_damping = 1.0
	if pin:
		group = obj.vertex_groups.new(name="Pin")
		for i, w in (pin.items() if isinstance(pin, dict) else ((i, 1.0) for i in pin)):
			group.add([i], w, "REPLACE")
		s.vertex_group_mass = "Pin"
		s.pin_stiffness = fabric.get("pin_stiffness", 1.0)
	if shrink:
		group = obj.vertex_groups.new(name="Shrink")
		for i, w in shrink.items():
			group.add([i], w, "REPLACE")
		## The group's weight blends shrink_min (weight 0) to shrink_max (weight 1).
		s.vertex_group_shrink = "Shrink"
		s.shrink_min = 0.0
		s.shrink_max = fabric.get("shrink", 0.0)
	c = cloth.collision_settings
	c.distance_min = fabric.get("distance", 0.004)
	c.use_self_collision = False
	cloth.point_cache.frame_start = 1
	cloth.point_cache.frame_end = frames
	scene.frame_start = 1
	scene.frame_end = frames
	for frame in range(1, frames + 1):
		scene.frame_set(frame)
	bpy.context.view_layer.objects.active = obj
	bpy.ops.object.modifier_apply(modifier="Cloth")
	scene.frame_set(1)
	for name in ("Pin", "Shrink"):
		if name in obj.vertex_groups:
			obj.vertex_groups.remove(obj.vertex_groups[name])
	for collider in colliders:
		for m in [m for m in collider.modifiers if m.type == "COLLISION"]:
			collider.modifiers.remove(m)


def smooth_weights(obj, passes=2):
	"""Evens out the skin weights so the cloth stretches and compresses smoothly in game."""
	bpy.context.view_layer.objects.active = obj
	obj.select_set(True)
	bpy.ops.object.mode_set(mode="WEIGHT_PAINT")
	bpy.ops.object.vertex_group_smooth(group_select_mode="ALL", factor=0.5, repeat=passes)
	bpy.ops.object.mode_set(mode="OBJECT")
	bpy.ops.object.vertex_group_normalize_all(lock_active=False)


def follow(obj, other, top, bottom, above=False):
	"""Past `top` towards `bottom` (fully beyond it; bottom may lie above top) obj takes `other`'s
	skin weights from its nearest face: cloth inside a boot moves exactly as the boot does, and
	trousers under a jacket as the jacket does, so the layers never cross in a pose."""
	group = obj.vertex_groups.new(name="Follow")
	for v in obj.data.vertices:
		z = (obj.matrix_world @ v.co).z
		t = min(max((top - z) / (top - bottom), 0.0), 1.0)
		if t > 0.0:
			group.add([v.index], t * t * (3.0 - 2.0 * t), "REPLACE")
	mod = obj.modifiers.new("Follow", "DATA_TRANSFER")
	mod.object = other
	mod.use_vert_data = True
	mod.data_types_verts = {"VGROUP_WEIGHTS"}
	mod.vert_mapping = "POLYINTERP_NEAREST"
	mod.layers_vgroup_select_src = "ALL"
	mod.layers_vgroup_select_dst = "NAME"
	mod.mix_mode = "REPLACE"
	mod.mix_factor = 1.0
	mod.vertex_group = "Follow"
	bpy.context.view_layer.objects.active = obj
	bpy.ops.object.modifier_apply(modifier="Follow")
	obj.vertex_groups.remove(obj.vertex_groups["Follow"])
	bpy.ops.object.vertex_group_normalize_all(lock_active=False)


def widen(obj, arm, factor):
	"""A looser cut by `factor` in girth only, never in length: the body about the spine (x and
	depth), each sleeve about the arm's axis (depth and height), blended across the shoulder."""
	shoulder = (arm.matrix_world @ arm.data.bones["upperarm_l"].head_local)
	arm_y = shoulder.y
	arm_z = shoulder.z
	inv = obj.matrix_world.inverted()
	points = [obj.matrix_world @ v.co for v in obj.data.vertices]
	centre_y = sum(p.y for p in points) / len(points)
	for v, p in zip(obj.data.vertices, points):
		t = min(max((abs(p.x) - (shoulder.x - 0.05)) / 0.1, 0.0), 1.0)
		t = t * t * (3.0 - 2.0 * t)
		body = p.copy()
		body.x *= factor
		body.y = centre_y + (p.y - centre_y) * factor
		sleeve = p.copy()
		sleeve.y = arm_y + (p.y - arm_y) * factor
		sleeve.z = arm_z + (p.z - arm_z) * factor
		v.co = inv @ body.lerp(sleeve, t)
	obj.data.update()



def centre_sleeves(obj, arm):
	"""Centres each sleeve on the arm with one smooth offset along it: per 2 cm slice the gap between
	the sleeve's centre and the line from the shoulder joint to the wrist is measured, a straight
	line (least squares, by points) is fitted to those gaps and applied, blending in past the
	shoulder. Cut to hang, a re-posed sleeve sits below the arm, whose top then pokes through.
	Per-slice offsets would shear the cuff, where band, placket and turn-up overlap."""
	from mathutils import Vector
	inv = obj.matrix_world.inverted()
	points = [obj.matrix_world @ v.co for v in obj.data.vertices]
	for side, (upper, hand) in {1: ("upperarm_l", "hand_l"), -1: ("upperarm_r", "hand_r")}.items():
		a = arm.matrix_world @ arm.data.bones[upper].head_local
		b = arm.matrix_world @ arm.data.bones[hand].head_local
		slices = {}
		for i, p in enumerate(points):
			if p.x * side > a.x * side + 0.02:
				slices.setdefault(int(p.x * side / 0.02), []).append(i)
		samples = []
		for key, idx in slices.items():
			x = (key + 0.5) * 0.02
			t = (x * side - a.x) / (b.x - a.x)
			axis = a.lerp(b, min(max(t, 0.0), 1.0))
			centre = sum((points[i] for i in idx), Vector()) / len(idx)
			samples.append((x, axis.y - centre.y, axis.z - centre.z, len(idx)))
		n = sum(s_[3] for s_ in samples)
		mx = sum(s_[0] * s_[3] for s_ in samples) / n
		var = sum((s_[0] - mx) ** 2 * s_[3] for s_ in samples)
		fit = []
		for k in (1, 2):
			m = sum(s_[k] * s_[3] for s_ in samples) / n
			slope = sum((s_[0] - mx) * (s_[k] - m) * s_[3] for s_ in samples) / var if var > 0.0 else 0.0
			fit.append((m, slope))
		for i, p in enumerate(points):
			x = p.x * side
			if x <= a.x * side + 0.02:
				continue
			w = min(max((x - a.x * side - 0.02) / 0.08, 0.0), 1.0)
			w = w * w * (3.0 - 2.0 * w)
			dy = fit[0][0] + fit[0][1] * (x - mx)
			dz = fit[1][0] + fit[1][1] * (x - mx)
			points[i] = p + Vector((0.0, dy, dz)) * w
	for v, p in zip(obj.data.vertices, points):
		v.co = inv @ p
	obj.data.update()

def proxy_of(obj, faces, name):
	"""A sparse copy of obj (about `faces` faces) to simulate; obj and its riders are bound to it."""
	proxy = obj.copy()
	proxy.data = obj.data.copy()
	proxy.name = proxy.data.name = name
	bpy.context.collection.objects.link(proxy)
	for group in list(proxy.vertex_groups):
		proxy.vertex_groups.remove(group)
	decimate_to(proxy, faces)
	return proxy


def smooth_weights_where(obj, where, passes=6):
	"""Smooths the skin weights of only the vertices `where` accepts (world point -> bool): a seam
	where neighbouring points lean on different bones blends instead of tearing in a pose."""
	bpy.ops.object.select_all(action="DESELECT")
	bpy.context.view_layer.objects.active = obj
	obj.select_set(True)
	for v in obj.data.vertices:
		v.select = where(obj.matrix_world @ v.co)
	bpy.ops.object.mode_set(mode="WEIGHT_PAINT")
	obj.data.use_paint_mask_vertex = True
	bpy.ops.object.vertex_group_smooth(group_select_mode="ALL", factor=0.5, repeat=passes)
	obj.data.use_paint_mask_vertex = False
	bpy.ops.object.mode_set(mode="OBJECT")
	bpy.ops.object.vertex_group_normalize_all(lock_active=False)


def hug_above(obj, body, z_from, z_full, margin):
	"""Lays obj onto the body above height z_from (fully from z_full up) at `margin`: a lower layer
	that is always under an upper one (trousers' waist and belt under a jacket) stays flat enough
	that bending never pushes it through."""
	group = obj.vertex_groups.new(name="Hug")
	for v in obj.data.vertices:
		z = (obj.matrix_world @ v.co).z
		if z > z_from:
			t = min(max((z - z_from) / (z_full - z_from), 0.0), 1.0)
			group.add([v.index], t * t * (3.0 - 2.0 * t), "REPLACE")
	mod = obj.modifiers.new("Hug", "SHRINKWRAP")
	mod.target = body
	mod.wrap_method = "NEAREST_SURFACEPOINT"
	mod.wrap_mode = "ABOVE_SURFACE"
	mod.offset = margin
	mod.vertex_group = "Hug"
	bpy.context.view_layer.objects.active = obj
	bpy.ops.object.modifier_apply(modifier="Hug")
	obj.vertex_groups.remove(obj.vertex_groups["Hug"])


def add_chains(arm, obj, name, parent, count, z_top, z_bottom, axis_xy, angles=None, inset=0.01):
	"""Adds `count` two-bone chains round obj (a hem or a collar) to the armature, hanging from z_top
	to z_bottom (either way up) just inside obj's surface, each found by a ray from the vertical
	axis at axis_xy, parented to `parent`; returns [(angle, [bone names])]. Spring bones in game.
	An angle whose ray misses the cloth (an opening) gets no chain."""
	import math
	import bmesh
	from mathutils import Vector
	from mathutils.bvhtree import BVHTree
	bm = bmesh.new()
	bm.from_mesh(obj.data)
	bm.transform(obj.matrix_world)
	tree = BVHTree.FromBMesh(bm)
	bm.free()
	if angles is None:
		angles = [2.0 * math.pi * k / count for k in range(count)]
	bpy.ops.object.select_all(action="DESELECT")
	bpy.context.view_layer.objects.active = arm
	arm.select_set(True)
	bpy.ops.object.mode_set(mode="EDIT")
	inv = arm.matrix_world.inverted()
	chains = []
	for a in angles:
		out = Vector((math.cos(a), math.sin(a), 0.0))
		joints = []
		for z in (z_top, (z_top + z_bottom) * 0.5, z_bottom):
			## A ragged edge: step back toward the root until the ray meets cloth (up to 4 cm).
			hit = None
			for step in range(5):
				zz = z + math.copysign(0.01 * step, z_top - z_bottom)
				hit = tree.ray_cast(Vector((axis_xy[0], axis_xy[1], zz)), out, 0.6)[0]
				if hit is not None:
					break
			if hit is None:
				break
			joints.append(inv @ (hit - out * inset))
		if len(joints) < 3:
			continue
		names = []
		prev = arm.data.edit_bones[parent]
		for j in range(2):
			bone = arm.data.edit_bones.new("%s_%d_%d" % (name, len(chains), j))
			bone.head = joints[j]
			bone.tail = joints[j + 1]
			bone.parent = prev
			bone.use_connect = j > 0
			bone.use_deform = True
			prev = bone
			names.append(bone.name)
		chains.append((a, names))
	bpy.ops.object.mode_set(mode="OBJECT")
	return chains


def weight_to_chains(obj, chains, axis_xy, z_root, z_tip, where=None):
	"""Hands obj's points between z_root (none) and z_tip (fully; either way up) over to the chains:
	blended between the two chains nearest in angle round axis_xy and between each chain's two bones
	by height; the points' own weights fade out as the chains take over. `where(p)` may return a
	0..1 share instead of a bool, to fade a zone out at its edges."""
	import math
	world = obj.matrix_world
	span = z_tip - z_root
	groups = {}
	for _, names in chains:
		for n in names:
			groups[n] = obj.vertex_groups.get(n) or obj.vertex_groups.new(name=n)
	angles = [a for a, _ in chains]
	for v in obj.data.vertices:
		p = world @ v.co
		share = 1.0 if where is None else float(where(p))
		t = (p.z - z_root) / span
		if t <= 0.0 or share <= 0.0:
			continue
		t = min(t, 1.0)
		r = t * t * (3.0 - 2.0 * t) * share
		a = math.atan2(p.y - axis_xy[1], p.x - axis_xy[0]) % (2.0 * math.pi)
		dists = sorted((min(abs(a - c), 2.0 * math.pi - abs(a - c)), i) for i, c in enumerate(angles))
		(d0, i0), (d1, i1) = dists[0], dists[1]
		w0 = d1 / (d0 + d1) if d0 + d1 > 0.0 else 1.0
		for g in v.groups:
			g.weight *= (1.0 - r)
		for i, w in ((i0, w0), (i1, 1.0 - w0)):
			names = chains[i][1]
			tip = max(0.0, (t - 0.5) * 2.0)
			upper_w = r * w * (1.0 - tip)
			lower_w = r * w * tip
			if upper_w > 0.0:
				groups[names[0]].add([v.index], upper_w, "ADD")
			if lower_w > 0.0:
				groups[names[1]].add([v.index], lower_w, "ADD")
	bpy.context.view_layer.objects.active = obj
	bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
	bpy.ops.object.vertex_group_normalize_all(lock_active=False)


def shift_weights(obj, source, target, share):
	"""Moves `share(world point)` (0..1) of each vertex's `source` weight to `target`."""
	if source not in obj.vertex_groups:
		return
	src = obj.vertex_groups[source]
	dst = obj.vertex_groups.get(target) or obj.vertex_groups.new(name=target)
	for v in obj.data.vertices:
		k = share(obj.matrix_world @ v.co)
		if k <= 0.0:
			continue
		w = next((g.weight for g in v.groups if g.group == src.index), 0.0)
		if w <= 0.0:
			continue
		have = next((g.weight for g in v.groups if g.group == dst.index), 0.0)
		dst.add([v.index], min(have + w * k, 1.0), "REPLACE")
		if w * (1.0 - k) > 0.0:
			src.add([v.index], w * (1.0 - k), "REPLACE")
		else:
			src.remove([v.index])
