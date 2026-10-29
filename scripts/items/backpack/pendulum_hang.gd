class_name PendulumHang
extends Node3D

## Something hanging from a pivot (#260): it swings so its -Y follows gravity less the pivot's
## acceleration, on a damped spring kept in world space, so it lags when its parent turns or swings.
## Origin: the pivot; the hanging thing lies down -Y from it.

## It struck what it touches: the swing's rate into it, rad/s (a fresh touch or a hard re-strike).
signal knocked(rate: float)

## Longest step the spring takes in one frame, seconds: a hitch's long frame would blow it up.
const MAX_SPRING_STEP_S: float = 0.05
## Contact: points closer than this to the obstacle join the search; free, the most it tilts in a
## frame, rad (any depth left is worked off over the next frames, as position-based contact does).
const CONTACT_NEAR_M: float = 0.06
const MAX_CONTACT_TILT: float = 0.35
## On a hinge: the search step and how far either way it looks for a clear angle, rad.
const CONTACT_STEP: float = 0.087
## Contact keeps this gap (a collision margin): the points are a 1 cm sample of the surface, and the
## surface between them may bulge up to ~3 mm nearer the obstacle.
const CONTACT_MARGIN: float = 0.003
## Friction while touching: share of the swing's rate kept each frame in contact.
const CONTACT_FRICTION: float = 0.5
## A strike faster than this into what it touches is a knock, rad/s; while it rests on something,
## only one this many times harder counts again.
const KNOCK_MIN_RATE: float = 0.6
const KNOCK_RESTRIKE: float = 2.5
const HINGE_REACH: float = 1.4

## Pendulum spring: frequency (Hz) and damping (under 1 overshoots), and the widest swing from
## the parent's down, degrees.
@export var swing_hz: float = 1.9
@export var swing_damping: float = 0.18
@export var max_swing_deg: float = 55.0

## Optional contact: points of the hanging thing (this node's space) and a callable that takes a
## world point and returns Vector4(outward normal, depth inside the obstacle; <= 0 is clear).
## Whatever hangs from this one (child PendulumHangs) counts too, as it is posed now.
var contact_points: PackedVector3Array = PackedVector3Array()
var contact_depth: Callable = Callable()
## A hinge (parent's space; zero = none): something hung on a pin, like a mug's handle on a rod,
## only turns about the pin, so its hanging direction stays square to it.
var hinge_axis: Vector3 = Vector3.ZERO
## Free hangers only: a fixed world direction to lean out along on contact (zero = the deepest
## point's normal); one steady direction keeps a hanger touching several things from chattering.
var contact_out: Vector3 = Vector3.ZERO

## Hanging direction and its rate, world space; the node's basis is derived from them.
var _dir: Vector3 = Vector3.DOWN
var _dir_speed: Vector3 = Vector3.ZERO
var _last_position: Vector3 = Vector3.ZERO
var _last_velocity: Vector3 = Vector3.ZERO
var _has_last: bool = false
var _touching: bool = false


func _process(delta: float) -> void:
	if delta <= 0.0 or not is_inside_tree() or get_parent_node_3d() == null:
		return
	var at: Vector3 = global_position
	if not _has_last:
		_last_position = at
		_dir = get_parent_node_3d().global_basis.orthonormalized() * Vector3.DOWN
		_has_last = true
		return
	var velocity: Vector3 = (at - _last_position) / delta
	var accel: Vector3 = (velocity - _last_velocity) / delta
	_last_position = at
	_last_velocity = velocity
	if not accel.is_finite() or accel.length() > 80.0:
		accel = Vector3.ZERO  # a teleport, not a swing
	## It hangs along gravity less the pivot's acceleration; the state lives in world space.
	var pull: Vector3 = Vector3.DOWN * 9.8 - accel
	var target: Vector3 = pull.normalized() if pull.length() > 0.5 else Vector3.DOWN
	var omega: float = TAU * swing_hz
	var step: float = minf(delta, MAX_SPRING_STEP_S)
	_dir_speed += ((target - _dir) * omega * omega - _dir_speed * 2.0 * swing_damping * omega) * step
	_dir = (_dir + _dir_speed * step).normalized()
	var to_parent: Basis = get_parent_node_3d().global_basis.orthonormalized().inverse()
	_keep_on_hinge(to_parent)
	var local: Vector3 = to_parent * _dir
	if not local.is_finite():
		local = Vector3.DOWN
		_dir_speed = Vector3.ZERO
	var limit: float = deg_to_rad(max_swing_deg)
	if local.angle_to(Vector3.DOWN) > limit:
		local = Vector3.DOWN.slerp(local, limit / local.angle_to(Vector3.DOWN)).normalized()
	_dir = to_parent.inverse() * local
	if contact_depth.is_valid():
		_resolve_contact(to_parent)
		_keep_on_hinge(to_parent)
		local = (to_parent * _dir).normalized()
	basis = Basis(Quaternion(Vector3.DOWN, local))


## Holds the hanging direction and its rate square to the hinge, if there is one.
func _keep_on_hinge(to_parent: Basis) -> void:
	if hinge_axis == Vector3.ZERO:
		return
	var pin: Vector3 = (to_parent.inverse() * hinge_axis).normalized()
	var square: Vector3 = _dir - pin * _dir.dot(pin)
	if square.length() > 0.0001:
		_dir = square.normalized()
	_dir_speed -= pin * _dir_speed.dot(pin)


## Leans the hanging thing off what it touches, dropping the swing's rate into the obstacle
## (inelastic contact) and rubbing off half the rest (friction). On a hinge it is a one-angle problem: the nearest clear angle either way
## about the pin (coarse steps, then bisection). Free, it tilts toward the deepest point's normal.
func _resolve_contact(to_parent: Basis) -> void:
	var pivot: Vector3 = global_position
	var near := PackedVector3Array()
	var start := Vector4(0.0, 0.0, 0.0, -1.0)
	var pose := Basis(Quaternion(Vector3.DOWN, (to_parent * _dir).normalized()))
	var from_parent: Basis = to_parent.inverse()
	var points: PackedVector3Array = _all_points()
	for point: Vector3 in points:
		var hit: Vector4 = contact_depth.call(pivot + from_parent * (pose * point))
		hit.w += CONTACT_MARGIN
		if hit.w > -CONTACT_NEAR_M:
			near.append(point)
		if hit.w > start.w:
			start = hit
	if start.w <= 0.0:
		_touching = false
		return
	var axis: Vector3
	var angle: float = 0.0
	if hinge_axis != Vector3.ZERO:
		axis = (from_parent * hinge_axis).normalized()
		angle = _nearest_clear(points, to_parent, pivot, axis)
	else:
		axis = _dir.cross(contact_out if contact_out != Vector3.ZERO else Vector3(start.x, start.y, start.z))
		if axis.length() < 0.000001:
			return
		axis = axis.normalized()
		angle = _clear_along(near, to_parent, pivot, axis, 0.0, MAX_CONTACT_TILT)
	if absf(angle) < 0.000001:
		return
	var before: Vector3 = _dir
	_dir = _dir.rotated(axis, angle).normalized()
	var out: Vector3 = (_dir - before).normalized()
	var into: float = maxf(-_dir_speed.dot(out), 0.0)
	if into > KNOCK_MIN_RATE * (KNOCK_RESTRIKE if _touching else 1.0):
		knocked.emit(into)
	_touching = true
	if _dir_speed.dot(out) < 0.0:
		_dir_speed -= out * _dir_speed.dot(out)
	_dir_speed *= CONTACT_FRICTION


## Its own contact points and those of whatever hangs from it, as posed now, in its space.
func _all_points() -> PackedVector3Array:
	var points: PackedVector3Array = contact_points.duplicate()
	var to_local: Transform3D = global_transform.affine_inverse()
	for node: Node in find_children("*", "PendulumHang", true, false):
		var below := node as PendulumHang
		var into_here: Transform3D = to_local * below.global_transform
		for point: Vector3 in below.contact_points:
			points.append(into_here * point)
	return points


## Signed turn about `axis` that clears the points, backing out the way it came in (against its
## swing) first: CONTACT_STEP steps up to HINGE_REACH, never past the swing limit, then bisection.
## Zero if no clear angle is found.
func _nearest_clear(points: PackedVector3Array, to_parent: Basis, pivot: Vector3, axis: Vector3) -> float:
	var back: float = -signf(_dir_speed.dot(axis.cross(_dir))) if _dir_speed.length() > 0.0001 else 1.0
	var limit: float = deg_to_rad(max_swing_deg)
	var steps: int = int(ceil(HINGE_REACH / CONTACT_STEP))
	for sign: float in [back, -back]:
		for k: int in range(1, steps + 1):
			var angle: float = sign * k * CONTACT_STEP
			var turned: Vector3 = _dir.rotated(axis, angle)
			if (to_parent * turned).angle_to(Vector3.DOWN) > limit:
				break
			if _deepest(points, to_parent, turned, pivot) <= 0.0:
				return _clear_along(points, to_parent, pivot, axis, sign * (k - 1) * CONTACT_STEP, angle)
	## Wedged: take the least-deep angle within reach rather than stay in.
	var best: float = 0.0
	var best_depth: float = _deepest(points, to_parent, _dir, pivot)
	for k: int in range(-steps, steps + 1):
		var turned: Vector3 = _dir.rotated(axis, k * CONTACT_STEP)
		if (to_parent * turned).angle_to(Vector3.DOWN) > limit:
			continue
		var depth: float = _deepest(points, to_parent, turned, pivot)
		if depth < best_depth:
			best_depth = depth
			best = k * CONTACT_STEP
	return best


## Bisects between a blocked turn and a clear one about `axis`; returns the clear end.
func _clear_along(points: PackedVector3Array, to_parent: Basis, pivot: Vector3, axis: Vector3, blocked: float, clear: float) -> float:
	if _deepest(points, to_parent, _dir.rotated(axis, clear), pivot) > 0.0:
		return clear  # still in at the widest tilt: go that far and finish next frame
	for _i: int in range(10):
		var mid: float = (blocked + clear) * 0.5
		if _deepest(points, to_parent, _dir.rotated(axis, mid), pivot) > 0.0:
			blocked = mid
		else:
			clear = mid
	return clear


## Deepest of `points` inside the obstacle with the hanging thing posed along world direction dir.
func _deepest(points: PackedVector3Array, to_parent: Basis, dir: Vector3, pivot: Vector3) -> float:
	var pose := Basis(Quaternion(Vector3.DOWN, (to_parent * dir).normalized()))
	var from_parent: Basis = to_parent.inverse()
	var deepest: float = -1.0
	for point: Vector3 in points:
		deepest = maxf(deepest, (contact_depth.call(pivot + from_parent * (pose * point)) as Vector4).w + CONTACT_MARGIN)
	return deepest
