class_name TactileArmReach
extends SkeletonModifier3D

## Lab-only two-bone reach for issue #198.
##
## Unlike DoorHandIK this modifier does not flatten a palm onto a plane. It owns
## only shoulder/elbow/wrist reach and refuses anatomically implausible targets:
## over-extension, over-compression and elbow crossing through Henry's midline.

@export var upper_bone: StringName = &"upperarm_r"
@export var lower_bone: StringName = &"lowerarm_r"
@export var hand_bone: StringName = &"hand_r"
@export_range(0.80, 0.99, 0.01) var max_extension_ratio: float = 0.95
@export_range(0.05, 0.45, 0.01) var min_reach_ratio: float = 0.28
@export_range(0.0, 0.15, 0.005) var max_midline_cross_m: float = 0.035
@export_range(1.0, 30.0, 0.5) var blend_in_rate: float = 9.0
@export_range(1.0, 30.0, 0.5) var blend_out_rate: float = 7.0
@export_range(0.0, 1.0, 0.05) var outward_elbow_bias: float = 0.18

var _hand: StringName = &"RIGHT"
var _goal_world: Vector3 = Vector3.ZERO
var _goal_weight: float = 0.0
var _weight: float = 0.0
var _index: Dictionary = {}
var _debug: Dictionary = {}


func configure_hand(hand: StringName) -> void:
	_hand = hand
	var suffix: String = "l" if hand == &"LEFT" else "r"
	upper_bone = StringName("upperarm_" + suffix)
	lower_bone = StringName("lowerarm_" + suffix)
	hand_bone = StringName("hand_" + suffix)


func set_goal(point_world: Vector3, weight: float = 1.0) -> void:
	_goal_world = point_world
	_goal_weight = clampf(weight, 0.0, 1.0)


func release() -> void:
	_goal_weight = 0.0


func get_weight() -> float:
	return _weight


func get_debug() -> Dictionary:
	return _debug.duplicate(true)


func _process_modification() -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null:
		return
	var delta: float = clampf(get_process_delta_time(), 0.001, 0.05)
	var rate: float = blend_in_rate if _goal_weight > _weight else blend_out_rate
	_weight = move_toward(_weight, _goal_weight, rate * delta)
	if _weight <= 0.001:
		_debug = {"feasible": false, "reason": "released", "hand": String(_hand)}
		return

	var u: int = _bone(skeleton, upper_bone)
	var l: int = _bone(skeleton, lower_bone)
	var h: int = _bone(skeleton, hand_bone)
	if u < 0 or l < 0 or h < 0:
		_debug = {"feasible": false, "reason": "missing_bones", "hand": String(_hand)}
		return

	var upper_pose: Transform3D = skeleton.get_bone_global_pose(u)
	var lower_pose: Transform3D = skeleton.get_bone_global_pose(l)
	var hand_pose: Transform3D = skeleton.get_bone_global_pose(h)
	var shoulder: Vector3 = upper_pose.origin
	var elbow: Vector3 = lower_pose.origin
	var wrist: Vector3 = hand_pose.origin
	var a: float = shoulder.distance_to(elbow)
	var b: float = elbow.distance_to(wrist)
	if a < 0.001 or b < 0.001:
		_debug = {"feasible": false, "reason": "zero_length", "hand": String(_hand)}
		return

	var to_rig: Transform3D = skeleton.global_transform.affine_inverse()
	var target: Vector3 = to_rig * _goal_world
	var reach: Vector3 = target - shoulder
	var raw_distance: float = reach.length()
	var full_length: float = a + b
	var reach_ratio: float = raw_distance / maxf(full_length, 0.001)
	var min_distance: float = maxf(absf(a - b) + 0.012, full_length * min_reach_ratio)
	var max_distance: float = full_length * max_extension_ratio
	if raw_distance > max_distance:
		_set_debug(skeleton, false, "overreach", reach_ratio, shoulder, elbow, wrist, target)
		return
	if raw_distance < min_distance:
		_set_debug(skeleton, false, "overcompressed", reach_ratio, shoulder, elbow, wrist, target)
		return

	var dir: Vector3 = reach.normalized() if reach.length_squared() > 1e-8 else (wrist - shoulder).normalized()
	var clip_bend: Vector3 = (elbow - shoulder) - dir * (elbow - shoulder).dot(dir)
	var side_sign: float = -1.0 if _hand == &"LEFT" else 1.0
	var outward: Vector3 = Vector3.RIGHT * side_sign + Vector3.DOWN * 0.20
	outward -= dir * outward.dot(dir)
	if outward.length_squared() < 1e-8:
		outward = Vector3.RIGHT * side_sign
	outward = outward.normalized()
	var bend: Vector3 = outward
	if clip_bend.length_squared() > 1e-8:
		bend = clip_bend.normalized().slerp(outward, outward_elbow_bias)
	bend -= dir * bend.dot(dir)
	if bend.length_squared() < 1e-8:
		_set_debug(skeleton, false, "degenerate_bend", reach_ratio, shoulder, elbow, wrist, target)
		return
	bend = bend.normalized()

	var d: float = clampf(raw_distance, min_distance, max_distance)
	var cos_a: float = clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var sin_a: float = sqrt(maxf(0.0, 1.0 - cos_a * cos_a))
	var new_elbow: Vector3 = shoulder + dir * a * cos_a + bend * a * sin_a
	var new_wrist: Vector3 = shoulder + dir * d

	## UAL rig X is lateral. Keep the elbow on its anatomical side; a small cross
	## allowance handles near-centre targets without permitting a torso stab-through.
	if new_elbow.x * side_sign < -max_midline_cross_m:
		_set_debug(skeleton, false, "elbow_crosses_midline", reach_ratio, shoulder, new_elbow, new_wrist, target)
		return

	var old_upper: Vector3 = elbow - shoulder
	var new_upper: Vector3 = new_elbow - shoulder
	if old_upper.length_squared() < 1e-8 or new_upper.length_squared() < 1e-8:
		return
	var turn_upper := Basis(Quaternion(old_upper.normalized(), new_upper.normalized()))
	upper_pose.basis = turn_upper * upper_pose.basis
	skeleton.set_bone_global_pose(u, upper_pose)

	var old_fore: Vector3 = turn_upper * (wrist - elbow)
	var new_fore: Vector3 = new_wrist - new_elbow
	if old_fore.length_squared() < 1e-8 or new_fore.length_squared() < 1e-8:
		return
	var turn_lower := Basis(Quaternion(old_fore.normalized(), new_fore.normalized()))
	lower_pose.basis = turn_lower * turn_upper * lower_pose.basis
	lower_pose.origin = new_elbow
	skeleton.set_bone_global_pose(l, lower_pose)

	hand_pose.basis = turn_lower * turn_upper * hand_pose.basis
	hand_pose.origin = new_wrist
	skeleton.set_bone_global_pose(h, hand_pose)
	_set_debug(skeleton, true, "ok", reach_ratio, shoulder, new_elbow, new_wrist, target)


func _set_debug(
		skeleton: Skeleton3D,
		feasible: bool,
		reason: String,
		reach_ratio: float,
		shoulder: Vector3,
		elbow: Vector3,
		wrist: Vector3,
		target: Vector3) -> void:
	_debug = {
		"hand": String(_hand),
		"feasible": feasible,
		"reason": reason,
		"reach_ratio": reach_ratio,
		"weight": _weight,
		"shoulder_world": skeleton.global_transform * shoulder,
		"elbow_world": skeleton.global_transform * elbow,
		"wrist_world": skeleton.global_transform * wrist,
		"target_world": skeleton.global_transform * target,
	}


func _bone(skeleton: Skeleton3D, bone: StringName) -> int:
	if not _index.has(bone):
		_index[bone] = skeleton.find_bone(bone)
	return int(_index[bone])
