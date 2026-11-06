class_name ContainerClearance
extends RefCounted

## Keeps the pack clear of the furniture it is framed by, and the view clear to what lies inside (owner: the pack
## never passes into a cabinet, a drawer or a door, and every item inside shows). Every part is an oriented box.

## The gap kept between the pack and any part of the furniture; the step it moves out by, and how far at most.
const GAP_M: float = 0.02
const STEP_M: float = 0.01
const MAX_PUSH_M: float = 1.2
## What hangs off the pack keeps this far over the floor, metres.
const FLOOR_CLEAR_M: float = 0.03
## The view turns up and aside in these steps, at most this far; it backs off in these steps, at most this far.
const TURN_STEP_DEG: float = 5.0
const TURN_UP_MAX_DEG: float = 50.0
const TURN_SIDE_MAX_DEG: float = 30.0
const BACK_STEP_M: float = 0.05
const BACK_MAX_M: float = 1.5
## It first tries this much nearer, so what is framed fills the frame (tight), metres.
const NEAR_MAX_M: float = 0.6
## What is framed stays within this much of the frame (NDC), the load bar and the cards' strips left free.
const FRAME_EDGE_X: float = 0.95
const FRAME_TOP: float = 0.88
const FRAME_BOTTOM: float = -0.7


## Every visible part of `container`'s furniture (doors and drawers as they stand now; items and the frost of
## any container left out): [[Transform3D, AABB], ...], world.
static func furniture_parts(container: ItemContainer) -> Array:
	var parts: Array = []
	for node: Node in container.furniture_root().find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree() or _in_container(mesh):
			continue
		parts.append([mesh.global_transform, mesh.mesh.get_aabb()])
	return parts


## What the pack takes up, in its own space, its front panel folded `panel_deg` out: [[Transform3D, AABB], ...]
## (its meshes, the open panel's sweep, a column under each pin as deep and wide as its hanger: placed at a cut,
## a hanger already inside a part could never swing clear of it by contact).
static func pack_shape(pack: PackRig, panel_deg: float) -> Array:
	var to_pack: Transform3D = pack.global_transform.affine_inverse()
	var canvas: BackpackModel = pack.get_canvas()
	var shape: Array = []
	var hangs: Array[Node] = pack.find_children("*", "PendulumHang", true, false)
	for node: Node in pack.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree() or mesh.name == &"FrontPanel":
			continue
		if hangs.any(func(hang: Node) -> bool: return hang.is_ancestor_of(mesh)):
			continue
		shape.append([to_pack * mesh.global_transform, mesh.mesh.get_aabb()])
	shape.append([to_pack * canvas.global_transform, canvas.open_panel_box(panel_deg)])
	for node: Node in hangs:
		var hang := node as PendulumHang
		var pin: Vector3 = to_pack * hang.global_position
		var reach: float = 0.0
		var wide: float = 0.0
		for part: Node in hang.find_children("*", "MeshInstance3D", true, false):
			var mesh := part as MeshInstance3D
			if mesh.mesh == null or not mesh.is_visible_in_tree():
				continue
			var box: AABB = mesh.global_transform * mesh.mesh.get_aabb()
			for i: int in 8:
				var off: Vector3 = box.get_endpoint(i) - hang.global_position
				reach = maxf(reach, off.length())
				wide = maxf(wide, Vector2(off.x, off.z).length())
		if reach > 0.0:
			var half: float = minf(wide, reach) * 0.5
			var low := Vector3(pin.x - half, pin.y - reach, pin.z - half)
			shape.append([Transform3D.IDENTITY, AABB(low, Vector3(half * 2.0, reach, half * 2.0))])
	return shape


## How far below the pack's middle what hangs off it reaches at most (each pin's height less its reach), metres.
static func hang_depth(pack: PackRig) -> float:
	var deepest: float = pack.size.y * 0.5
	for node: Node in pack.find_children("*", "PendulumHang", true, false):
		var hang := node as PendulumHang
		var reach: float = 0.0
		for part: Node in hang.find_children("*", "MeshInstance3D", true, false):
			var mesh := part as MeshInstance3D
			if mesh.mesh == null or not mesh.is_visible_in_tree():
				continue
			var box: AABB = mesh.global_transform * mesh.mesh.get_aabb()
			for i: int in 8:
				reach = maxf(reach, box.get_endpoint(i).distance_to(hang.global_position))
		var pin_drop: float = (pack.global_transform.affine_inverse() * hang.global_position).y
		deepest = maxf(deepest, reach - pin_drop)
	return deepest


## The pack's place moved the least way, along one of `ways` (world), until no part of `shape` there comes within
## GAP_M of any of `parts`, then lifted until what hangs `depth` below its middle clears the floor at `floor_y`:
## [Transform3D, the distance moved (INF when no way clears within MAX_PUSH_M)].
static func place_pack(placed: Transform3D, shape: Array, parts: Array, ways: Array[Vector3], floor_y: float,
		depth: float) -> Array:
	placed.origin.y += maxf(floor_y + FLOOR_CLEAR_M + depth - placed.origin.y, 0.0)
	var best: Transform3D = placed
	var moved: float = INF
	for way: Vector3 in ways:
		var step: Vector3 = way.normalized() * STEP_M
		var at: Transform3D = placed
		for i: int in int(MAX_PUSH_M / STEP_M) + 1:
			if i * STEP_M >= moved:
				break
			if not touches(at, shape, parts, GAP_M):
				best = at
				moved = i * STEP_M
				break
			at.origin += step
	return [best, moved]


## Whether any of `shape` placed at `placed` comes within `gap` of any of `parts`.
static func touches(placed: Transform3D, shape: Array, parts: Array, gap: float) -> bool:
	for mine: Array in shape:
		var xf: Transform3D = placed * (mine[0] as Transform3D)
		for part: Array in parts:
			if boxes_overlap(xf, mine[1], part[0], part[1], gap):
				return true
	return false


## The view turned about what it frames (up first, then aside, the least turn that works) and backed off until
## it sees every one of `targets` past `parts` and `pack_parts`, every one of `framed` (the pack) past `parts`,
## stands in no part and frames them all with `scenery` (world; framed, not needed in sight), as near as that
## allows: the view unchanged when none works.
static func aim_view(view: Transform3D, targets: Array[Vector3], framed: Array[Vector3], scenery: Array[Vector3],
		parts: Array, pack_parts: Array, fov: float, aspect: float) -> Transform3D:
	var blockers: Array = parts.duplicate()
	blockers.append_array(pack_parts)
	var pivot := Vector3.ZERO
	for point: Vector3 in framed:
		pivot += point / framed.size()
	var turns: Array[Vector2] = []
	var up: float = 0.0
	while up <= TURN_UP_MAX_DEG + 0.01:
		var side: float = 0.0
		while side <= TURN_SIDE_MAX_DEG + 0.01:
			turns.append(Vector2(up, side))
			if side > 0.0:
				turns.append(Vector2(up, -side))
			side += TURN_STEP_DEG
		up += TURN_STEP_DEG
	turns.sort_custom(func(a: Vector2, b: Vector2) -> bool: return absf(a.x) + absf(a.y) < absf(b.x) + absf(b.y))
	var tans := Vector2(tan(deg_to_rad(fov) * 0.5) * aspect, tan(deg_to_rad(fov) * 0.5))
	var all: Array[Vector3] = targets.duplicate()
	all.append_array(framed)
	all.append_array(scenery)
	for turn: Vector2 in turns:
		var spin := Basis(Vector3.UP, deg_to_rad(turn.y)) * Basis(view.basis.x.normalized(), -deg_to_rad(turn.x))
		var turned := Transform3D(spin * view.basis, pivot + spin * (view.origin - pivot))
		if turned.basis.y.y <= 0.05:
			continue
		var back: float = -NEAR_MAX_M
		while back <= BACK_MAX_M:
			var eye := Transform3D(turned.basis, turned.origin + turned.basis.z.normalized() * back)
			if _frames_all(eye, all, tans):
				if _sees_all(eye.origin, targets, blockers) and _sees_all(eye.origin, framed, parts) \
						and not _inside_any(eye.origin, blockers):
					return eye
			back += BACK_STEP_M
	return view


## Whether `point` (world) shows to `eye` with nothing of `blockers` in between.
static func sees(eye: Vector3, point: Vector3, blockers: Array) -> bool:
	for part: Array in blockers:
		if segment_hits(eye, point, part[0], part[1]):
			return false
	return true


## The middle of what shows of `node` (its visible meshes), world.
static func middle_of(node: Node3D) -> Vector3:
	var box := AABB()
	var found: bool = false
	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		var part: AABB = mesh.global_transform * mesh.mesh.get_aabb()
		box = part if not found else box.merge(part)
		found = true
	return box.get_center() if found else node.global_position


## Whether two oriented boxes (each `xf` * `box`) come within `gap` of each other (separating axes).
static func boxes_overlap(a_xf: Transform3D, a_box: AABB, b_xf: Transform3D, b_box: AABB, gap: float) -> bool:
	var a_axes: Array[Vector3] = _half_axes(a_xf, a_box)
	var b_axes: Array[Vector3] = _half_axes(b_xf, b_box)
	var between: Vector3 = b_xf * b_box.get_center() - a_xf * a_box.get_center()
	var tests: Array[Vector3] = []
	for axis: Vector3 in a_axes:
		tests.append(axis)
	for axis: Vector3 in b_axes:
		tests.append(axis)
	for a: Vector3 in a_axes:
		for b: Vector3 in b_axes:
			tests.append(a.cross(b))
	for axis: Vector3 in tests:
		if axis.length_squared() < 1e-10:
			continue
		var unit: Vector3 = axis.normalized()
		var reach: float = gap
		for half: Vector3 in a_axes:
			reach += absf(half.dot(unit))
		for half: Vector3 in b_axes:
			reach += absf(half.dot(unit))
		if absf(between.dot(unit)) > reach:
			return false
	return true


## Whether the segment `from`..`to` (world) passes through the oriented box `xf` * `box`.
static func segment_hits(from: Vector3, to: Vector3, xf: Transform3D, box: AABB) -> bool:
	var inverse: Transform3D = xf.affine_inverse()
	var a: Vector3 = inverse * from
	var b: Vector3 = inverse * to
	var enter: float = 0.0
	var leave: float = 1.0
	for axis: int in 3:
		var run: float = b[axis] - a[axis]
		var low: float = box.position[axis]
		var high: float = box.end[axis]
		if absf(run) < 1e-9:
			if a[axis] < low or a[axis] > high:
				return false
			continue
		var t0: float = (low - a[axis]) / run
		var t1: float = (high - a[axis]) / run
		enter = maxf(enter, minf(t0, t1))
		leave = minf(leave, maxf(t0, t1))
		if enter > leave:
			return false
	return true


static func _half_axes(xf: Transform3D, box: AABB) -> Array[Vector3]:
	var half: Vector3 = box.size * 0.5
	return [xf.basis.x * half.x, xf.basis.y * half.y, xf.basis.z * half.z]


static func _frames_all(view: Transform3D, points: Array[Vector3], tans: Vector2) -> bool:
	var to_view: Transform3D = view.affine_inverse()
	for point: Vector3 in points:
		var local: Vector3 = to_view * point
		if local.z > -0.05:
			return false
		var ndc := Vector2(local.x / (-local.z * tans.x), local.y / (-local.z * tans.y))
		if absf(ndc.x) > FRAME_EDGE_X or ndc.y > FRAME_TOP or ndc.y < FRAME_BOTTOM:
			return false
	return true


static func _sees_all(eye: Vector3, targets: Array[Vector3], blockers: Array) -> bool:
	for point: Vector3 in targets:
		if not sees(eye, point, blockers):
			return false
	return true


static func _inside_any(point: Vector3, parts: Array) -> bool:
	for part: Array in parts:
		if (part[1] as AABB).grow(0.05).has_point((part[0] as Transform3D).affine_inverse() * point):
			return true
	return false


static func _in_container(node: Node) -> bool:
	var up: Node = node.get_parent()
	while up != null:
		if up is ItemContainer:
			return true
		up = up.get_parent()
	return false
