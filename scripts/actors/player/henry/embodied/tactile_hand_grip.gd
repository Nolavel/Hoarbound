class_name TactileHandGrip
extends SkeletonModifier3D

## Lab-only object-aware grip proof for #198.
##
## DoorHandIK owns arm/wrist reach. This modifier keeps Henry's authored UAL
## closed-hand pose as an anatomical prior, then settles each evaluated finger
## chain onto the real cylinder volume. The prop transform is therefore part of
## the solve, not merely a scalar controlling how closed the fist looks.

@export_range(1.0, 20.0, 0.5) var blend_in_rate: float = 10.0
@export_range(1.0, 20.0, 0.5) var blend_out_rate: float = 7.0
@export_range(0.02, 0.12, 0.005) var fully_closed_radius_m: float = 0.035
@export_range(0.04, 0.20, 0.005) var open_hand_radius_m: float = 0.11
@export_range(0.0, 1.0, 0.05) var hand_orient_weight: float = 0.65
@export_range(0.0, 1.0, 0.05) var contact_settle_weight: float = 0.82
@export_range(1, 6, 1) var contact_iterations: int = 4

const FINGER_WRAP_ANGLE_RAD: float = 1.658063 # 95 degrees
const THUMB_WRAP_ANGLE_RAD: float = 1.134464 # 65 degrees, opposite direction
const FINGER_TIP_EXTENSION_SHARE: float = 0.66
const THUMB_TIP_EXTENSION_SHARE: float = 0.72

var _hand: StringName = &"RIGHT"
var _item_xf_world := Transform3D.IDENTITY
var _radius_m: float = 0.045
var _half_height_m: float = 0.07
var _goal_weight: float = 0.0
var _weight: float = 0.0
var _closed_pose: Dictionary = {}
var _index: Dictionary = {}
var _missing_reported: Dictionary = {}
var _pose_scan_done: bool = false


func set_closed_pose(pose_by_bone: Dictionary) -> void:
	_closed_pose = pose_by_bone.duplicate(true)
	_pose_scan_done = true


func set_goal(hand: StringName, item_xf_world: Transform3D, radius_m: float, half_height_m: float, weight: float = 1.0) -> void:
	_hand = hand
	_item_xf_world = item_xf_world
	_radius_m = maxf(radius_m, 0.01)
	_half_height_m = maxf(half_height_m, 0.02)
	_goal_weight = clampf(weight, 0.0, 1.0)


func release() -> void:
	_goal_weight = 0.0


func get_weight() -> float:
	return _weight


func get_closed_pose_count() -> int:
	return _closed_pose.size()


func _process_modification() -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null:
		return
	if not _pose_scan_done:
		_sample_authored_fist_pose(skeleton)
	if _closed_pose.is_empty():
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
	var orient_weight: float = smoothstep(0.0, 1.0, _weight) * hand_orient_weight
	_orient_hand_to_cylinder(skeleton, hand_idx, middle_idx, index_idx, pinky_idx, center, axis, orient_weight)

	## First use a real authored grip as the anatomical prior. Radius only decides
	## how far we move toward that closed pose; it does not claim contact.
	var radius_close: float = 1.0 - inverse_lerp(fully_closed_radius_m, open_hand_radius_m, _radius_m)
	var grip_weight: float = smoothstep(0.0, 1.0, _weight) * clampf(radius_close, 0.0, 1.0)
	for finger: String in ["thumb", "index", "middle", "ring", "pinky"]:
		for joint: int in [1, 2, 3]:
			var bone_name := StringName("%s_%02d_%s" % [finger, joint, suffix])
			if not _closed_pose.has(bone_name):
				continue
			var bone_idx: int = _bone(skeleton, bone_name)
			if bone_idx < 0:
				continue
			var current: Quaternion = skeleton.get_bone_pose_rotation(bone_idx)
			var closed := _closed_pose[bone_name] as Quaternion
			skeleton.set_bone_pose_rotation(bone_idx, current.slerp(closed, grip_weight))

	## Then use the evaluated bones, not an assumed local flex axis, to settle the
	## fingertips against the measured cylinder. This is intentionally a tiny CCD
	## correction, not a replacement procedural hand animation system.
	var settle: float = smoothstep(0.25, 1.0, _weight) * contact_settle_weight
	if settle > 0.001:
		_settle_finger_to_cylinder(skeleton, suffix, "index", center, axis, settle, false)
		_settle_finger_to_cylinder(skeleton, suffix, "middle", center, axis, settle, false)
		_settle_finger_to_cylinder(skeleton, suffix, "ring", center, axis, settle, false)
		_settle_finger_to_cylinder(skeleton, suffix, "pinky", center, axis, settle, false)
		_settle_finger_to_cylinder(skeleton, suffix, "thumb", center, axis, settle, true)


func _orient_hand_to_cylinder(
		skeleton: Skeleton3D,
		hand_idx: int,
		middle_idx: int,
		index_idx: int,
		pinky_idx: int,
		center: Vector3,
		axis: Vector3,
		weight: float) -> void:
	if weight <= 0.001:
		return
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
	var blended: Quaternion = Quaternion.IDENTITY.slerp(turn, clampf(weight, 0.0, 1.0))
	hand_pose.basis = Basis(blended) * hand_pose.basis
	skeleton.set_bone_global_pose(hand_idx, hand_pose)


func _settle_finger_to_cylinder(
		skeleton: Skeleton3D,
		suffix: String,
		finger: String,
		center: Vector3,
		axis: Vector3,
		weight: float,
		is_thumb: bool) -> void:
	var b1: int = _bone(skeleton, StringName("%s_01_%s" % [finger, suffix]))
	var b2: int = _bone(skeleton, StringName("%s_02_%s" % [finger, suffix]))
	var b3: int = _bone(skeleton, StringName("%s_03_%s" % [finger, suffix]))
	if b1 < 0 or b2 < 0 or b3 < 0:
		return

	var p1: Vector3 = skeleton.get_bone_global_pose(b1).origin
	var p2: Vector3 = skeleton.get_bone_global_pose(b2).origin
	var root_radial: Vector3 = p1 - center
	root_radial -= axis * root_radial.dot(axis)
	if root_radial.length_squared() < 1e-8:
		return
	root_radial = root_radial.normalized()
	var tangent: Vector3 = axis.cross(root_radial)
	if tangent.length_squared() < 1e-8:
		return
	tangent = tangent.normalized()
	var first_segment: Vector3 = p2 - p1
	var direction_sign: float = 1.0 if first_segment.dot(tangent) >= 0.0 else -1.0
	if is_thumb:
		direction_sign *= -1.0
	var wrap_angle: float = THUMB_WRAP_ANGLE_RAD if is_thumb else FINGER_WRAP_ANGLE_RAD
	var target_radial: Vector3 = Basis(Quaternion(axis, wrap_angle * direction_sign)) * root_radial
	var axial: float = clampf((p1 - center).dot(axis), -_half_height_m * 0.78, _half_height_m * 0.78)
	var skin_clearance: float = 0.003 if is_thumb else 0.002
	var target: Vector3 = center + axis * axial + target_radial * (_radius_m + skin_clearance)
	var extension_share: float = THUMB_TIP_EXTENSION_SHARE if is_thumb else FINGER_TIP_EXTENSION_SHARE

	var joints: Array[int] = [b2, b1]
	for _iteration: int in range(contact_iterations):
		for joint_idx: int in joints:
			var tip: Vector3 = _finger_tip_proxy(skeleton, b2, b3, extension_share)
			var pose: Transform3D = skeleton.get_bone_global_pose(joint_idx)
			var current_vec: Vector3 = tip - pose.origin
			var desired_vec: Vector3 = target - pose.origin
			if current_vec.length_squared() < 1e-8 or desired_vec.length_squared() < 1e-8:
				continue
			var turn := Quaternion(current_vec.normalized(), desired_vec.normalized())
			var step: Quaternion = Quaternion.IDENTITY.slerp(turn, clampf(weight * 0.62, 0.0, 1.0))
			pose.basis = Basis(step) * pose.basis
			skeleton.set_bone_global_pose(joint_idx, pose)


func _finger_tip_proxy(skeleton: Skeleton3D, b2: int, b3: int, extension_share: float) -> Vector3:
	var p2: Vector3 = skeleton.get_bone_global_pose(b2).origin
	var p3: Vector3 = skeleton.get_bone_global_pose(b3).origin
	return p3 + (p3 - p2) * extension_share


func _sample_authored_fist_pose(skeleton: Skeleton3D) -> void:
	_pose_scan_done = true
	var player: AnimationPlayer = _find_animation_player_near(skeleton)
	if player == null:
		push_warning("TactileHandGrip: no AnimationPlayer near Henry skeleton; authored fist unavailable")
		return
	var clip_name: StringName = &""
	for candidate: StringName in player.get_animation_list():
		var text: String = String(candidate)
		if text == "Idle_Torch" or text.ends_with("/Idle_Torch") or text == "Idle_Torch_Loop" or text.ends_with("/Idle_Torch_Loop"):
			clip_name = candidate
			break
	if clip_name == &"":
		push_warning("TactileHandGrip: Idle_Torch clip unavailable; authored fist unavailable")
		return
	var animation: Animation = player.get_animation(clip_name)
	if animation == null:
		return
	var sample_time: float = animation.length * 0.5
	var left_tracks: int = 0
	for track: int in animation.get_track_count():
		if animation.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		var path: NodePath = animation.track_get_path(track)
		var bone_text: String = path.get_concatenated_subnames()
		if not _is_left_finger_bone(bone_text):
			continue
		var left_name := StringName(bone_text)
		var left_rotation: Quaternion = animation.rotation_track_interpolate(track, sample_time)
		_closed_pose[left_name] = left_rotation.normalized()
		var right_name := StringName(bone_text.trim_suffix("_l") + "_r")
		_closed_pose[right_name] = _mirror_quaternion_x(left_rotation).normalized()
		left_tracks += 1
	print("[TactileHandGrip] authored_fist=%s left_tracks=%d bilateral_tracks=%d sample=%.3f" % [
		clip_name, left_tracks, _closed_pose.size(), sample_time])


func _is_left_finger_bone(bone: String) -> bool:
	if not bone.ends_with("_l"):
		return false
	for finger: String in ["thumb_", "index_", "middle_", "ring_", "pinky_"]:
		if bone.begins_with(finger):
			return bone.contains("_01_") or bone.contains("_02_") or bone.contains("_03_")
	return false


static func _mirror_quaternion_x(q: Quaternion) -> Quaternion:
	return Quaternion(q.x, -q.y, -q.z, q.w)


static func _frame(primary: Vector3, secondary: Vector3) -> Basis:
	var y: Vector3 = primary.normalized()
	var x: Vector3 = y.cross(secondary)
	if x.length_squared() < 1e-8:
		return Basis()
	x = x.normalized()
	return Basis(x, y, x.cross(y))


func _find_animation_player_near(skeleton: Skeleton3D) -> AnimationPlayer:
	var root: Node = skeleton
	for _step: int in range(5):
		if root.get_parent() == null:
			break
		root = root.get_parent()
	var found: AnimationPlayer = _find_animation_player_recursive(root)
	return found


func _find_animation_player_recursive(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child: Node in node.get_children():
		var found: AnimationPlayer = _find_animation_player_recursive(child)
		if found != null:
			return found
	return null


func _bone(skeleton: Skeleton3D, bone: StringName) -> int:
	if not _index.has(bone):
		var idx: int = skeleton.find_bone(bone)
		_index[bone] = idx
		if idx < 0 and not _missing_reported.has(bone):
			_missing_reported[bone] = true
			push_warning("TactileHandGrip: missing bone %s" % bone)
	return int(_index[bone])
