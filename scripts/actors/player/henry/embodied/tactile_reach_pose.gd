class_name TactileReachPose
extends SkeletonModifier3D

## Lab-only authored-pose layer for issue #198.
##
## Important: this NEVER plays a full-body action. It samples a short window from
## an existing UAL clip and applies only a small upper-body/active-arm subset.
## Locomotion/crouch stay authoritative; TactileArmReach then solves the wrist and
## TactileHandGrip settles the fingers on the prop.

@export_range(1.0, 20.0, 0.5) var blend_in_rate: float = 8.0
@export_range(1.0, 20.0, 0.5) var blend_out_rate: float = 10.0

var _hand: StringName = &"RIGHT"
var _profile: StringName = &"PICKUP"
var _phase: float = 0.0
var _goal_weight: float = 0.0
var _weight: float = 0.0
var _player: AnimationPlayer
var _resolved: Dictionary = {}


func set_pose(hand: StringName, profile: StringName, phase: float, weight: float = 1.0) -> void:
	_hand = hand
	_profile = profile
	_phase = clampf(phase, 0.0, 1.0)
	_goal_weight = clampf(weight, 0.0, 1.0)


func release() -> void:
	_goal_weight = 0.0


func get_weight() -> float:
	return _weight


func _process_modification() -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null:
		return
	if _player == null:
		_player = _find_animation_player_near(skeleton)
	if _player == null:
		return
	var delta: float = clampf(get_process_delta_time(), 0.001, 0.05)
	var rate: float = blend_in_rate if _goal_weight > _weight else blend_out_rate
	_weight = move_toward(_weight, _goal_weight, rate * delta)
	if _weight <= 0.001:
		return
	var clip_name: StringName = _resolve_clip(_profile)
	if clip_name == &"":
		return
	var animation: Animation = _player.get_animation(clip_name)
	if animation == null or animation.length <= 0.001:
		return

	## We intentionally use only the useful contact-preparation window. The rest of
	## the imported clip (legs, root, long enter/exit) is never evaluated here.
	var start_share: float = 0.18 if _profile == &"PICKUP" else 0.24
	var end_share: float = 0.54 if _profile == &"PICKUP" else 0.58
	var sample_time: float = lerpf(animation.length * start_share, animation.length * end_share, _phase)
	var sampled: Dictionary = _sample_rotations(animation, sample_time)
	var suffix: String = "l" if _hand == &"LEFT" else "r"
	var opposite: String = "r" if suffix == "l" else "l"
	var targets := {
		"spine_02": 0.16,
		"spine_03": 0.24,
		"clavicle_" + suffix: 0.42,
		"upperarm_" + suffix: 0.72,
		"lowerarm_" + suffix: 0.80,
		"hand_" + suffix: 0.58,
	}
	for bone_text: String in targets:
		var bone_idx: int = skeleton.find_bone(StringName(bone_text))
		if bone_idx < 0:
			continue
		var desired: Quaternion
		if sampled.has(bone_text):
			desired = sampled[bone_text] as Quaternion
		else:
			var opposite_name: String = bone_text.trim_suffix("_" + suffix) + "_" + opposite
			if not sampled.has(opposite_name):
				continue
			desired = _mirror_quaternion_x(sampled[opposite_name] as Quaternion)
		var current: Quaternion = skeleton.get_bone_pose_rotation(bone_idx)
		var bone_weight: float = float(targets[bone_text]) * _weight
		skeleton.set_bone_pose_rotation(bone_idx, current.slerp(desired.normalized(), clampf(bone_weight, 0.0, 1.0)))


func _sample_rotations(animation: Animation, sample_time: float) -> Dictionary:
	var result: Dictionary = {}
	for track: int in animation.get_track_count():
		if animation.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		var path: NodePath = animation.track_get_path(track)
		var bone_text: String = path.get_concatenated_subnames()
		if bone_text.is_empty():
			continue
		result[bone_text] = animation.rotation_track_interpolate(track, sample_time).normalized()
	return result


func _resolve_clip(profile: StringName) -> StringName:
	if _resolved.has(profile):
		return StringName(_resolved[profile])
	var aliases: Array[String] = ["PickUp_Table", "Pickup_Table"] if profile == &"PICKUP" else ["Fixing_Kneeling"]
	for candidate: StringName in _player.get_animation_list():
		var text: String = String(candidate)
		for alias: String in aliases:
			if text == alias or text.ends_with("/" + alias):
				_resolved[profile] = candidate
				print("[TactileReachPose] profile=%s clip=%s partial_upper_body=true" % [String(profile), text])
				return candidate
	_resolved[profile] = &""
	push_warning("TactileReachPose: no clip for profile %s" % String(profile))
	return &""


static func _mirror_quaternion_x(q: Quaternion) -> Quaternion:
	return Quaternion(q.x, -q.y, -q.z, q.w)


func _find_animation_player_near(skeleton: Skeleton3D) -> AnimationPlayer:
	var root: Node = skeleton
	for _step: int in range(5):
		if root.get_parent() == null:
			break
		root = root.get_parent()
	return _find_animation_player_recursive(root)


func _find_animation_player_recursive(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child: Node in node.get_children():
		var found: AnimationPlayer = _find_animation_player_recursive(child)
		if found != null:
			return found
	return null
