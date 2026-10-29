class_name PendulumHang
extends Node3D

## Something hanging from a pivot (#260): it swings so its -Y follows gravity less the pivot's
## acceleration, on a damped spring kept in world space, so it lags when its parent turns or swings.
## Origin: the pivot; the hanging thing lies down -Y from it.

## Longest step the spring takes in one frame, seconds: a hitch's long frame would blow it up.
const MAX_SPRING_STEP_S: float = 0.05
## Contact: points closer than this to the obstacle join the search; the widest tilt it tries, rad.
const CONTACT_NEAR_M: float = 0.03
const MAX_CONTACT_TILT: float = 1.2

## Pendulum spring: frequency (Hz) and damping (under 1 overshoots), and the widest swing from
## the parent's down, degrees.
@export var swing_hz: float = 1.9
@export var swing_damping: float = 0.18
@export var max_swing_deg: float = 55.0

## Optional contact: points of the hanging thing (this node's space) and a callable that takes a
## world point and returns Vector4(outward normal, depth inside the obstacle; <= 0 is clear).
var contact_points: PackedVector3Array = PackedVector3Array()
var contact_depth: Callable = Callable()

## Hanging direction and its rate, world space; the node's basis is derived from them.
var _dir: Vector3 = Vector3.DOWN
var _dir_speed: Vector3 = Vector3.ZERO
var _last_position: Vector3 = Vector3.ZERO
var _last_velocity: Vector3 = Vector3.ZERO
var _has_last: bool = false


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
	var local: Vector3 = to_parent * _dir
	if not local.is_finite():
		local = Vector3.DOWN
		_dir_speed = Vector3.ZERO
	var limit: float = deg_to_rad(max_swing_deg)
	if local.angle_to(Vector3.DOWN) > limit:
		local = Vector3.DOWN.slerp(local, limit / local.angle_to(Vector3.DOWN)).normalized()
	_dir = to_parent.inverse() * local
	if contact_depth.is_valid() and not contact_points.is_empty():
		_resolve_contact(to_parent)
		local = (to_parent * _dir).normalized()
	basis = Basis(Quaternion(Vector3.DOWN, local))


## Leans the hanging thing off what it touches: the pendulum only tilts, so it finds by bisection
## the least tilt along the deepest point's contact normal that clears the points near contact,
## and drops the swing's rate into the obstacle (inelastic contact).
func _resolve_contact(to_parent: Basis) -> void:
	var pivot: Vector3 = global_position
	var near := PackedVector3Array()
	var start := Vector4(0.0, 0.0, 0.0, -1.0)
	var pose := Basis(Quaternion(Vector3.DOWN, (to_parent * _dir).normalized()))
	var from_parent: Basis = to_parent.inverse()
	for point: Vector3 in contact_points:
		var hit: Vector4 = contact_depth.call(pivot + from_parent * (pose * point))
		if hit.w > -CONTACT_NEAR_M:
			near.append(point)
		if hit.w > start.w:
			start = hit
	if start.w <= 0.0:
		return
	var axis: Vector3 = _dir.cross(Vector3(start.x, start.y, start.z))
	if axis.length() < 0.000001:
		return
	axis = axis.normalized()
	var low: float = 0.0
	var high: float = MAX_CONTACT_TILT
	for _i: int in range(12):
		var mid: float = (low + high) * 0.5
		if _deepest(near, to_parent, _dir.rotated(axis, mid), pivot) > 0.0:
			low = mid
		else:
			high = mid
	var before: Vector3 = _dir
	_dir = _dir.rotated(axis, high).normalized()
	var out: Vector3 = (_dir - before).normalized()
	if _dir_speed.dot(out) < 0.0:
		_dir_speed -= out * _dir_speed.dot(out)


## Deepest of `points` inside the obstacle with the hanging thing posed along world direction dir.
func _deepest(points: PackedVector3Array, to_parent: Basis, dir: Vector3, pivot: Vector3) -> float:
	var pose := Basis(Quaternion(Vector3.DOWN, (to_parent * dir).normalized()))
	var from_parent: Basis = to_parent.inverse()
	var deepest: float = -1.0
	for point: Vector3 in points:
		deepest = maxf(deepest, (contact_depth.call(pivot + from_parent * (pose * point)) as Vector4).w)
	return deepest
