class_name TactileHandGrip
extends SkeletonModifier3D

## Lab-only object-aware grip proof for #198.
##
## DoorHandIK gets the wrist to the prop. This modifier runs after it and turns
## the hand/finger chains around the actual cylinder volume. It deliberately
## does not change HeldFit or production pickup ownership until the proof is
## visually accepted.

@export_range(1.0, 20.0, 0.5) var blend_in_rate: float = 8.0
@export_range(1.0, 20.0, 0.5) var blend_out_rate: float = 6.0
@export_range(0.0, 1.0, 0.05) var hand_orient_weight: float = 0.85

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

	## Smaller diameters demand a deeper curl; large props deliberately retain a
	## more open hand. The value therefore comes from object volume, not a fixed fist.
	var size_curl: float = clampf(0.060 / _radius_m, 0.58, 1.0)
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
	## Keep the authored hand's nearest tangent so left/right mirror without a
	## special-case Euler pose.
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
	var root: Vector3 = skeleton.get_bone_global_pose(b1).origin
	var radial: Vector3 = root - center
	radial -= axis * radial.dot(axis)
	if radial.length_squared() < 1e-8:
		var hand_idx: int = _bone(skeleton, StringName("hand_" + suffix))
		if hand_idx < 0:
			return
		radial = skeleton.get_bone_global_pose(hand_idx).origin - center
		radial -= axis * radial.dot(axis)
	if radial.length_squared() < 1e-8:
		return
	radial = radial.normalized()
	var axial: float = clampf((root - center).dot(axis), -_half_height_m * 0.82, _half_height_m * 0.82)

	var current_dir: Vector3 = skeleton.get_bone_global_pose(b2).origin - root
	var tangent: Vector3 = axis.cross(radial).normalized()
	var direction_sign: float = 1.0
	if current_dir.length_squared() > 1e-8 and current_dir.dot(tangent) < 0.0:
		direction_sign = -1.0
	if is_thumb:
		direction_sign *= -1.0

	var first_angle: float = deg_to_rad(28.0 if is_thumb else 36.0) * direction_sign
	var second_angle: float = deg_to_rad(66.0 if is_thumb else 82.0) * direction_sign
	var radial_1: Vector3 = Basis(Quaternion(axis, first_angle)) * radial
	var radial_2: Vector3 = Basis(Quaternion(axis, second_angle)) * radial
	var surface_1: Vector3 = center + axis * axial + radial_1 * (_radius_m + 0.006)
	var surface_2: Vector3 = center + axis * axial + radial_2 * (_radius_m + 0.004)
	_aim_segment(skeleton, b1, b2, surface_1, weight * (0.92 if is_thumb else 0.82))
	_aim_segment(skeleton, b2, b3, surface_2, weight)


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
