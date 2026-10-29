class_name PendulumHang
extends Node3D

## Something hanging from a pivot (#260): it swings so its -Y follows gravity less the pivot's
## acceleration, on a damped spring. A carabiner in its loop, a mug on the carabiner's rod.
## Origin: the pivot; the hanging thing lies down -Y from it.

## Pendulum spring: frequency (Hz) and damping (under 1 overshoots), and the widest swing from
## the parent's down, degrees.
@export var swing_hz: float = 1.9
@export var swing_damping: float = 0.18
@export var max_swing_deg: float = 55.0

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
		_has_last = true
		return
	var velocity: Vector3 = (at - _last_position) / delta
	var accel: Vector3 = (velocity - _last_velocity) / delta
	_last_position = at
	_last_velocity = velocity
	if accel.length() > 80.0:
		accel = Vector3.ZERO  # a teleport, not a swing
	## It hangs along gravity less the pivot's acceleration, in the parent's space.
	var pull: Vector3 = get_parent_node_3d().global_basis.orthonormalized().inverse() * (Vector3.DOWN * 9.8 - accel)
	var target: Vector3 = pull.normalized() if pull.length() > 0.5 else Vector3.DOWN
	var omega: float = TAU * swing_hz
	_dir_speed += ((target - _dir) * omega * omega - _dir_speed * 2.0 * swing_damping * omega) * delta
	_dir = (_dir + _dir_speed * delta).normalized()
	var limit: float = deg_to_rad(max_swing_deg)
	if _dir.angle_to(Vector3.DOWN) > limit:
		_dir = Vector3.DOWN.slerp(_dir, limit / _dir.angle_to(Vector3.DOWN)).normalized()
	basis = Basis(Quaternion(Vector3.DOWN, _dir))
