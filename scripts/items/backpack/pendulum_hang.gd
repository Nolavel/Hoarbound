class_name PendulumHang
extends Node3D

## Something hanging from a pivot (#260): it swings so its -Y follows gravity less the pivot's
## acceleration, on a damped spring kept in world space, so it lags when its parent turns or swings.
## Origin: the pivot; the hanging thing lies down -Y from it.

## It struck what it touches: the swing's rate into it, rad/s (a fresh touch or a hard re-strike).
signal knocked(rate: float)

## Longest step the spring takes in one frame, seconds: a hitch's long frame would blow it up.
const MAX_SPRING_STEP_S: float = 0.05
## Contact: the most it turns per Newton step, rad, and the steps per frame. Points farther than
## CONTACT_NEAR_M from the obstacle cannot reach it in one frame's turn and are left out.
const CONTACT_NEAR_M: float = 0.06
const MAX_CONTACT_TILT: float = 0.35
const CONTACT_ITERATIONS: int = 4
## A contact whose point barely moves along its normal as it turns cannot be cleared by turning, m/rad.
const MIN_LEVER_M: float = 0.002
## Each Newton step reaches this much past the linear estimate, so it lands clear and bisection
## backs it off; and the bisection steps.
const OVERSHOOT: float = 1.5
const BISECTIONS: int = 6
## Contact keeps this gap (a collision margin): the points are a 2 cm sample of the surface, and the
## surface between them may bulge up to a few millimetres nearer the obstacle.
const CONTACT_MARGIN: float = 0.004
## Friction while touching: share of the swing's rate kept each frame in contact.
const CONTACT_FRICTION: float = 0.5
## Resting contact this shallow (well inside the margin, so out of sight) is left as it is: a
## physics engine's contact slop, so a hanger lying on something does not re-solve every frame.
const CONTACT_SLOP: float = 0.0015
## A strike faster than this into what it touches is a knock, rad/s; while it rests on something,
## only one this many times harder counts again.
const KNOCK_MIN_RATE: float = 0.6
const KNOCK_RESTRIKE: float = 2.5

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
## The swing's rate as the frame began, before the spring's step: a strike is judged on it.
var _speed_before: Vector3 = Vector3.ZERO


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
	_speed_before = _dir_speed
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
## (inelastic contact) and rubbing off half the rest (friction). It turns about the pin (free: toward
## the normal) by the least angle that clears every point; depth left is worked off next frame.
func _resolve_contact(to_parent: Basis) -> void:
	var pivot: Vector3 = global_position
	var from_parent: Basis = to_parent.inverse()
	var points: PackedVector3Array = _all_points()
	## Broad phase: its bounding sphere well clear of everything means no point can touch.
	var centre := Vector3.ZERO
	for point: Vector3 in points:
		centre += point
	centre /= maxf(points.size(), 1.0)
	var radius: float = 0.0
	for point: Vector3 in points:
		radius = maxf(radius, point.distance_to(centre))
	var pose := Basis(Quaternion(Vector3.DOWN, (to_parent * _dir).normalized()))
	if (contact_depth.call(pivot + from_parent * (pose * centre)) as Vector4).w + radius + CONTACT_MARGIN < 0.0:
		_touching = false
		return
	var hit: Array = _deepest_hit(points, to_parent, _dir, pivot, true)
	var depth: float = (hit[0] as Vector4).w
	if depth <= 0.0:
		_touching = false
		return
	points = hit[2]
	if _touching and depth < CONTACT_SLOP:
		_dir_speed *= CONTACT_FRICTION  # resting on it inside the margin: nothing to correct
		return
	var start: Vector4 = hit[0]
	var axis: Vector3
	if hinge_axis != Vector3.ZERO:
		axis = (from_parent * hinge_axis).normalized()
	else:
		axis = _dir.cross(contact_out if contact_out != Vector3.ZERO else Vector3(start.x, start.y, start.z))
		if axis.length() < 0.000001:
			return
		axis = axis.normalized()
	var before: Vector3 = _dir
	var angle: float
	if hinge_axis != Vector3.ZERO:
		angle = _clear_angle(points, to_parent, pivot, axis, hit, depth)
	elif (_deepest_hit(points, to_parent, _dir.rotated(axis, MAX_CONTACT_TILT), pivot)[0] as Vector4).w > 0.0:
		angle = MAX_CONTACT_TILT  # still in at the widest tilt: go that far and finish next frame
	else:
		angle = _bisect(points, to_parent, pivot, axis, 0.0, MAX_CONTACT_TILT)
	if absf(angle) < 0.000001:
		return
	_dir = _dir.rotated(axis, angle).normalized()
	var out: Vector3 = (_dir - before).normalized()
	var into: float = maxf(-_speed_before.dot(out), 0.0)
	if into > KNOCK_MIN_RATE * (KNOCK_RESTRIKE if _touching else 1.0):
		knocked.emit(into)
	_touching = true
	if _dir_speed.dot(out) < 0.0:
		_dir_speed -= out * _dir_speed.dot(out)
	_dir_speed *= CONTACT_FRICTION


## Its own contact points and every other one of whatever hangs from it (that one's own contact
## does the fine work), as posed now, in its space.
func _all_points() -> PackedVector3Array:
	var points: PackedVector3Array = contact_points.duplicate()
	var to_local: Transform3D = global_transform.affine_inverse()
	for node: Node in find_children("*", "PendulumHang", true, false):
		var below := node as PendulumHang
		var into_here: Transform3D = to_local * below.global_transform
		for i: int in range(0, below.contact_points.size(), 2):
			points.append(into_here * below.contact_points[i])
	return points


## On a hinge: least turn about `axis` that clears the points. Newton steps on the deepest point's depth
## (position-based contact, Müller et al. 2007) find a clear turn; bisection then backs it off to the
## least one. Wedged, it is the least-deep turn tried.
func _clear_angle(points: PackedVector3Array, to_parent: Basis, pivot: Vector3, axis: Vector3, hit: Array, depth: float) -> float:
	var limit: float = deg_to_rad(max_swing_deg)
	var blocked: float = 0.0
	var best: float = 0.0
	var best_depth: float = depth
	for _i: int in range(CONTACT_ITERATIONS):
		var normal := Vector3((hit[0] as Vector4).x, (hit[0] as Vector4).y, (hit[0] as Vector4).z)
		## How far the deepest point moves along its normal per radian of turn about the axis.
		var lever: float = axis.cross((hit[1] as Vector3) - pivot).dot(normal)
		if absf(lever) < MIN_LEVER_M:
			return best
		var next: float = clampf(blocked + depth / lever * OVERSHOOT, blocked - MAX_CONTACT_TILT, blocked + MAX_CONTACT_TILT)
		if (to_parent * _dir.rotated(axis, next)).angle_to(Vector3.DOWN) > limit:
			return best
		hit = _deepest_hit(points, to_parent, _dir.rotated(axis, next), pivot)
		depth = (hit[0] as Vector4).w
		if depth <= 0.0:
			return _bisect(points, to_parent, pivot, axis, blocked, next)
		if depth < best_depth:
			best = next
			best_depth = depth
		blocked = next
	return best


## Bisects between a blocked turn and a clear one about `axis`; returns the clear end.
func _bisect(points: PackedVector3Array, to_parent: Basis, pivot: Vector3, axis: Vector3, blocked: float, clear: float) -> float:
	for _i: int in range(BISECTIONS):
		var mid: float = (blocked + clear) * 0.5
		if (_deepest_hit(points, to_parent, _dir.rotated(axis, mid), pivot)[0] as Vector4).w > 0.0:
			blocked = mid
		else:
			clear = mid
	return clear


## The deepest of `points` with the hanging thing posed along world direction dir:
## [Vector4(outward normal, depth plus margin), its world position].
## With `gather`, a third entry: the points within CONTACT_NEAR_M, the only ones that can touch
## within one frame's turn.
func _deepest_hit(points: PackedVector3Array, to_parent: Basis, dir: Vector3, pivot: Vector3, gather: bool = false) -> Array:
	var pose := Basis(Quaternion(Vector3.DOWN, (to_parent * dir).normalized()))
	var from_parent: Basis = to_parent.inverse()
	var deepest := Vector4(0.0, 0.0, 0.0, -INF)
	var at: Vector3 = pivot
	var near := PackedVector3Array()
	for point: Vector3 in points:
		var world: Vector3 = pivot + from_parent * (pose * point)
		var hit: Vector4 = contact_depth.call(world)
		if gather and hit.w + CONTACT_MARGIN > -CONTACT_NEAR_M:
			near.append(point)
		if hit.w > deepest.w:
			deepest = hit
			at = world
	deepest.w += CONTACT_MARGIN
	return [deepest, at, near]
