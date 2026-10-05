class_name TactileHandGrip
extends SkeletonModifier3D

## Lab-only object-aware grip proof for #198.
##
## DoorHandIK owns arm/wrist reach. This modifier owns only finger local poses.
## Its closed pose is sampled from Henry's authored UAL Idle_Torch fist, then
## mirrored to the opposite hand. The prop radius controls how far each local
## phalanx moves toward that authored closed pose.

@export_range(1.0, 20.0, 0.5) var blend_in_rate: float = 10.0
@export_range(1.0, 20.0, 0.5) var blend_out_rate: float = 7.0
@export_range(0.02, 0.12, 0.005) var fully_closed_radius_m: float = 0.035
@export_range(0.04, 0.20, 0.005) var open_hand_radius_m: float = 0.11

var _hand: StringName = &"RIGHT"
var _radius_m: float = 0.045
var _goal_weight: float = 0.0
var _weight: float = 0.0
var _closed_pose: Dictionary = {}
var _index: Dictionary = {}
var _missing_reported: Dictionary = {}


func set_closed_pose(pose_by_bone: Dictionary) -> void:
	_closed_pose = pose_by_bone.duplicate(true)


func set_goal(hand: StringName, _item_xf_world: Transform3D, radius_m: float, _half_height_m: float, weight: float = 1.0) -> void:
	_hand = hand
	_radius_m = maxf(radius_m, 0.01)
	_goal_weight = clampf(weight, 0.0, 1.0)


func release() -> void:
	_goal_weight = 0.0


func get_weight() -> float:
	return _weight


func get_closed_pose_count() -> int:
	return _closed_pose.size()


func _process_modification() -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null or _closed_pose.is_empty():
		return
	var delta: float = clampf(get_process_delta_time(), 0.001, 0.05)
	var rate: float = blend_in_rate if _goal_weight > _weight else blend_out_rate
	_weight = move_toward(_weight, _goal_weight, rate * delta)
	if _weight <= 0.001:
		return

	## A 7 cm diameter tin should be nearly closed; a large bottle/box keeps a
	## visibly wider grip. This is the volume-aware part of the pose.
	var radius_close: float = 1.0 - inverse_lerp(fully_closed_radius_m, open_hand_radius_m, _radius_m)
	var grip_weight: float = smoothstep(0.0, 1.0, _weight) * clampf(radius_close, 0.0, 1.0)
	var suffix: String = "l" if _hand == &"LEFT" else "r"

	for finger: String in ["thumb", "index", "middle", "ring", "pinky"]:
		for joint: int in [1, 2, 3]:
			var bone_name := StringName("%s_%02d_%s" % [finger, joint, suffix])
			if not _closed_pose.has(bone_name):
				continue
			var bone_idx: int = _bone(skeleton, bone_name)
			if bone_idx < 0:
				continue
			## AnimationMixer + PickUp_Table have already populated the local pose.
			## Blend from that current authored state into the UAL closed-hand local
			## rotation. set_bone_pose_rotation propagates through the finger chain.
			var current: Quaternion = skeleton.get_bone_pose_rotation(bone_idx)
			var closed := _closed_pose[bone_name] as Quaternion
			skeleton.set_bone_pose_rotation(bone_idx, current.slerp(closed, grip_weight))


func _bone(skeleton: Skeleton3D, bone: StringName) -> int:
	if not _index.has(bone):
		var idx: int = skeleton.find_bone(bone)
		_index[bone] = idx
		if idx < 0 and not _missing_reported.has(bone):
			_missing_reported[bone] = true
			push_warning("TactileHandGrip: missing bone %s" % bone)
	return int(_index[bone])
