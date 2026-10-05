class_name TactileHandGrip
extends SkeletonModifier3D

## Lab-only object-aware grip proof for #198.
##
## DoorHandIK gets the wrist to the prop. This modifier runs after it and wraps
## every finger chain around the measured cylinder volume. The targets are built
## from each phalanx length, so the hand cannot "reach" a point its bones cannot.
## HeldFit and production pickup ownership stay untouched until visual acceptance.

@export_range(1.0, 20.0, 0.5) var blend_in_rate: float = 9.0
@export_range(1.0, 20.0, 0.5) var blend_out_rate: float = 6.0
@export_range(0.0, 1.0, 0.05) var hand_orient_weight: float = 1.0

var _hand: StringName = &"RIGHT"
var _item_xf_world := Transform3D.IDENTITY
var _radius_m: float = 0.045
var _half_height_m: float = 0.07
var _goal_weight: float = 0.0
var _weight: float = 0.0
var _index: Dictionary = {}
var _missing_reported: Dictionary = {}


func set_goal(hand: StringName, item_xf_world: Transform3D, radius_m: float, half_height_m: float, weight: float = 1.0) -> void:
	_hand = hand
	_item_xf_world = item_xf_world
	_radius_m = maxf(radius_m, 0.012)
	_half_height_m = maxf(half_height_m, 0.02)
	_goal_weight = clampf(weight, 0.0, 1.0)


func release() -> void:
	_goal_weight = 0.0


func get_weight() -> float:
	return _weight


func _process_modification() -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null:
		return
	var delta: float = clampf(get_process_delta_time(), 0.001, 0.05)
	var rate: float = blend_in_rate if _goal_weight > _weight else blend_out_rate
	_weight = move_toward(_weight, _goal_weight, rate * delta)
	if _weight <= 0.001:
		return

	var suffix: String = "l" if _hand == &"LEFT" else "r"
	var hand_idx: int = _bone(skeleton, StringName("hand_" + suffix))
	var middle_idx: int = _bone(skeleton, StringName("middle_01_" + suffix))
	var index_idx: int = _bone(skeleton, StringName("index_01_" + suffix))
	var pinky_idx: int = _bone(skeleton, StringName("pinky_01_" + suffix))
	if hand_idx < 0 or middle_idx < 0 or index_idx < 0 or pinky_idx < 0:
		return

	var to_rig: Transform3D = skeleton.global_transform.affine_inverse()
	var center: Vector3 = to_rig * _item_xf_world.origin
	var axis: Vector3 = (to_rig.basis * _item_xf_world.basis.y.normalized()).normalized()
	var blend: float = smoothstep(0.0, 1.0, _weight)
	_orient_hand_to_cylinder(skeleton, hand_idx, middle_idx, index_idx, pinky_idx, center, axis, blend)

	## Radius drives curl depth. A small can closes the hand; a broad prop keeps it
	## open. The individual arc steps below are additionally limited by real bone length.
	var size_curl: float = clampf(0.060 / _radius_m, 0.60, 1.0)
	var finger_blend: float = blend * size_curl
	_bend_finger(skeleton, suffix, "index", center, axis, finger_blend, false)
	_bend_finger(skeleton, suffix, "middle", center, axis, finger_blend, false)
	_bend_finger(skeleton, suffix, "ring", center, axis, finger_blend, false)
	_bend_finger(skeleton, suffix, "pinky", center, axis, finger_blend, false)
	_bend_finger(skeleton, suffix, "thumb", center, axis, finger_blend, true)


func _orient_hand_to_cylinder(
		skeleton: Skeleton3D,
		hand_idx: int,
		middle_idx: int,
		index_idx: int,
		pinky_idx: int,
		center: Vector3,
		axis: Vector3,
		weight: float) -> void:
	var hand_pose: Transform3D = skeleton.get_bone_global_pose(hand_idx)
	var along: Vector3 = skeleton.get_bone_global_pose(middle_idx).origin - hand_pose.origin
	var across: Vector3 = skeleton.get_bone_global_pose(index_idx).origin - skeleton.get_bone_global_pose(pinky_idx).origin
	if along.length_squared() < 1e-8 or across.length_squared() < 1e-8:
		return
	var palm: Vector3 = along.cross(across) * (-1.0 if _hand == &"LEFT" else 1.0)
	var radial: Vector3 = hand_pose.origin - center
	radial -= axis * radial.dot(axis)
	if radial.length_squared() < 1e-8:
		return
	radial = radial.normalized()
	var tangent: Vector3 = axis.cross(radial)
	if tangent.length_squared() < 1e-8:
		return
	tangent = tangent.normalized()
	if tangent.dot(along) < 0.0:
		tangent = -tangent
	var have: Basis = _frame(along, palm)
	var want: Basis = _frame(tangent, -radial)
	if have == Basis() or want == Basis():
		return
	var turn: Quaternion = (want * have.inverse()).get_rotation_quaternion()
	var blended: Quaternion = Quaternion.IDENTITY.slerp(turn, hand_orient_weight * weight)
	hand_pose.basis = Basis(blended) * hand_pose.basis
	skeleton.set_bone_global_pose(hand_idx, hand_pose)


func _bend_finger(
		skeleton: Skeleton3D,
		suffix: String,
		finger: String,
		center: Vector3,
		axis: Vector3,
		weight: float,
		is_thumb: bool) -> void:
	var b1: int = _bone(skeleton, StringName(finger + "_01_" + suffix))
	var b2: int = _bone(skeleton, StringName(finger + "_02_" + suffix))
	var b3: int = _bone(skeleton, StringName(finger + "_03_" + suffix))
	if b1 < 0 or b2 < 0 or b3 < 0:
		return

	var p1: Vector3 = skeleton.get_bone_global_pose(b1).origin
	var p2: Vector3 = skeleton.get_bone_global_pose(b2).origin
	var p3: Vector3 = skeleton.get_bone_global_pose(b3).origin
	var l1: float = p1.distance_to(p2)
	var l2: float = p2.distance_to(p3)
	if l1 < 0.004 or l2 < 0.004:
		return
	## UE/UAL has no fingertip leaf. Distal flesh extends beyond bone 03; use the
	## previous phalanx as a conservative anatomical length proxy.
	var l3: float = l2 * (0.72 if is_thumb else 0.66)

	var radial: Vector3 = p1 - center
	radial -= axis * radial.dot(axis)
	if radial.length_squared() < 1e-8:
		return
	radial = radial.normalized()
	var axial: float = clampf((p1 - center).dot(axis), -_half_height_m * 0.84, _half_height_m * 0.84)
	var surface_r: float = _radius_m + (0.004 if is_thumb else 0.003)

	var tangent: Vector3 = axis.cross(radial).normalized()
	var current: Vector3 = p2 - p1
	var direction_sign: float = -1.0 if current.dot(tangent) < 0.0 else 1.0
	if is_thumb:
		direction_sign *= -1.0

	## Each angular step is derived from its own segment's chord length. This is
	## the key difference from the rejected proof: targets are reachable by the rig.
	var a1: float = _arc_step(l1, surface_r, 0.74 if is_thumb else 0.82) * direction_sign
	var a2: float = _arc_step(l2, surface_r, 0.82 if is_thumb else 0.92) * direction_sign
	var a3: float = _arc_step(l3, surface_r, 0.90 if is_thumb else 1.00) * direction_sign
	var r1: Vector3 = Basis(Quaternion(axis, a1)) * radial
	var r2: Vector3 = Basis(Quaternion(axis, a1 + a2)) * radial
	var r3: Vector3 = Basis(Quaternion(axis, a1 + a2 + a3)) * radial
	var target_2: Vector3 = center + axis * axial + r1 * surface_r
	var target_3: Vector3 = center + axis * axial + r2 * surface_r
	var target_tip: Vector3 = center + axis * axial + r3 * surface_r

	_aim_segment(skeleton, b1, b2, target_2, weight * (0.92 if is_thumb else 0.88))
	_aim_segment(skeleton, b2, b3, target_3, weight)
	_aim_terminal(skeleton, b2, b3, target_tip, weight)


func _arc_step(segment_length: float, radius: float, reach_share: float) -> float:
	var chord: float = minf(segment_length * reach_share, radius * 1.80)
	return 2.0 * asin(clampf(chord / maxf(2.0 * radius, 0.001), 0.05, 0.90))


func _aim_segment(skeleton: Skeleton3D, bone_idx: int, child_idx: int, target: Vector3, weight: float) -> void:
	var pose: Transform3D = skeleton.get_bone_global_pose(bone_idx)
	var child_pos: Vector3 = skeleton.get_bone_global_pose(child_idx).origin
	var current: Vector3 = child_pos - pose.origin
	var desired: Vector3 = target - pose.origin
	if current.length_squared() < 1e-8 or desired.length_squared() < 1e-8:
		return
	var turn := Quaternion(current.normalized(), desired.normalized())
	var blended: Quaternion = Quaternion.IDENTITY.slerp(turn, clampf(weight, 0.0, 1.0))
	pose.basis = Basis(blended) * pose.basis
	skeleton.set_bone_global_pose(bone_idx, pose)


func _aim_terminal(skeleton: Skeleton3D, parent_idx: int, terminal_idx: int, target_tip: Vector3, weight: float) -> void:
	var parent_pos: Vector3 = skeleton.get_bone_global_pose(parent_idx).origin
	var pose: Transform3D = skeleton.get_bone_global_pose(terminal_idx)
	var current_axis: Vector3 = pose.origin - parent_pos
	var desired: Vector3 = target_tip - pose.origin
	if current_axis.length_squared() < 1e-8 or desired.length_squared() < 1e-8:
		return
	var turn := Quaternion(current_axis.normalized(), desired.normalized())
	var blended: Quaternion = Quaternion.IDENTITY.slerp(turn, clampf(weight, 0.0, 1.0))
	pose.basis = Basis(blended) * pose.basis
	skeleton.set_bone_global_pose(terminal_idx, pose)


static func _frame(primary: Vector3, secondary: Vector3) -> Basis:
	var y: Vector3 = primary.normalized()
	var x: Vector3 = y.cross(secondary)
	if x.length_squared() < 1e-8:
		return Basis()
	x = x.normalized()
	return Basis(x, y, x.cross(y))


func _bone(skeleton: Skeleton3D, bone: StringName) -> int:
	if not _index.has(bone):
		var idx: int = skeleton.find_bone(bone)
		_index[bone] = idx
		if idx < 0 and not _missing_reported.has(bone):
			_missing_reported[bone] = true
			push_warning("TactileHandGrip: missing bone %s" % bone)
	return int(_index[bone])
