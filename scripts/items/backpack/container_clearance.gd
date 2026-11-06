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


## What the pack takes up turned to `turn` (world), as offsets from its middle in world axes: [[Transform3D, AABB],
## ...]: its meshes, the open panel's sweep (`panel_deg`), and what hangs off it as it hangs at rest there (each
## PendulumHang's -Y down, square to its pin): placed at a cut, a hanger inside a part could never swing clear.
static func pack_shape(pack: PackRig, panel_deg: float, turn: Basis) -> Array:
	var canvas: BackpackModel = pack.get_canvas()
	var rest: Dictionary = {}
	var shape: Array = []
	for node: Node in pack.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree() or mesh.name == &"FrontPanel":
			continue
		shape.append([_at_rest(mesh, pack, turn, rest), mesh.mesh.get_aabb()])
	shape.append([_at_rest(canvas, pack, turn, rest), canvas.open_panel_box(panel_deg)])
	return shape


## The pack's middle moved the least way along one of `ways` (world) until no part of `shape` (pack_shape) there
## comes within GAP_M of any of `parts`, after lifting it until its lowest part clears the floor at `floor_y`:
## [Vector3, the distance moved (INF when no way clears within MAX_PUSH_M)].
static func place_pack(middle: Vector3, shape: Array, parts: Array, ways: Array[Vector3], floor_y: float) -> Array:
	var lowest: float = INF
	for mine: Array in shape:
		var xf: Transform3D = mine[0]
		for i: int in 8:
			lowest = minf(lowest, (xf * (mine[1] as AABB).get_endpoint(i)).y)
	middle.y += maxf(floor_y + FLOOR_CLEAR_M - (middle.y + lowest), 0.0)
	var best: Vector3 = middle
	var moved: float = INF
	for way: Vector3 in ways:
		var step: Vector3 = way.normalized() * STEP_M
		for i: int in int(MAX_PUSH_M / STEP_M) + 1:
			if i * STEP_M >= moved:
				break
			var at: Vector3 = middle + step * i
			if not touches(at, shape, parts, GAP_M):
				best = at
				moved = i * STEP_M
				break
	return [best, moved]


## Whether any of `shape` with the pack's middle at `middle` comes within `gap` of any of `parts`.
static func touches(middle: Vector3, shape: Array, parts: Array, gap: float) -> bool:
	var shift := Transform3D(Basis.IDENTITY, middle)
	for mine: Array in shape:
		var xf: Transform3D = shift * (mine[0] as Transform3D)
		for part: Array in parts:
			if boxes_overlap(xf, mine[1], part[0], part[1], gap):
				return true
	return false


## `shape` (pack_shape) with the pack's middle at `middle`, world: [[Transform3D, AABB], ...].
static func placed(middle: Vector3, shape: Array) -> Array:
	var out: Array = []
	for mine: Array in shape:
		out.append([Transform3D(Basis.IDENTITY, middle) * (mine[0] as Transform3D), mine[1]])
	return out


## The view turned about what it frames (up first, then aside, the least turn that works) and backed off until
## it sees every one of `targets` past `parts` and `pack_parts`, every one of `framed` (the pack) past `parts`,
## stands in no part and frames them all with `scenery` (world; framed, not needed in sight): from its own distance
## outward (from NEAR_MAX_M nearer when `near_first`); the view unchanged when none works.
static func aim_view(view: Transform3D, targets: Array[Vector3], framed: Array[Vector3], scenery: Array[Vector3],
		parts: Array, pack_parts: Array, fov: float, aspect: float, near_first: bool) -> Transform3D:
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
		var back: float = -NEAR_MAX_M if near_first else 0.0
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


## `node`'s pose with the pack at the origin turned to `turn` and every hanger at rest (memo in `rest`).
static func _at_rest(node: Node3D, pack: PackRig, turn: Basis, rest: Dictionary) -> Transform3D:
	if node == pack:
		return Transform3D(turn, Vector3.ZERO)
	if rest.has(node):
		return rest[node]
	var above: Transform3D = _at_rest(node.get_parent() as Node3D, pack, turn, rest)
	var local: Transform3D = node.transform
	var hang := node as PendulumHang
	if hang != null:
		var down: Vector3 = (above.basis.orthonormalized().inverse() * Vector3.DOWN).normalized()
		if hang.hinge_axis != Vector3.ZERO:
			var pin: Vector3 = hang.hinge_axis.normalized()
			var square: Vector3 = down - pin * down.dot(pin)
			down = square.normalized() if square.length() > 0.0001 else down
		local = Transform3D(Basis(Quaternion(Vector3.DOWN, down)), node.position)
	var pose: Transform3D = above * local
	rest[node] = pose
	return pose


static func _in_container(node: Node) -> bool:
	var up: Node = node.get_parent()
	while up != null:
		if up is ItemContainer:
			return true
		up = up.get_parent()
	return false
