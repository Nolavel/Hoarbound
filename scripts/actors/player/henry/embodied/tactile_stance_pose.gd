class_name TactileStancePose
extends SkeletonModifier3D

## Lab-only stance prior for issue #198.
##
## No action playback: one authored Fixing_Kneeling frame is sampled and blended
## into the evaluated base pose. CharacterBody3D still owns translation/root.
## CROUCH receives only a partial lower-body/torso contribution; KNEEL receives
## the full static prior. This gives low reaches a real body pose before wrist IK.

@export_range(1.0, 12.0, 0.5) var blend_in_rate: float = 4.0
@export_range(1.0, 12.0, 0.5) var blend_out_rate: float = 4.5
@export_range(0.0, 1.0, 0.05) var pelvis_vertical_weight: float = 0.85
@export_range(0.0, 1.0, 0.05) var crouch_prior_weight: float = 0.48

const KNEEL_SAMPLE_SECONDS: float = 2.6
const KNEEL_ROTATION_BONES: PackedStringArray = [
	"pelvis", "spine_01", "spine_02", "spine_03",
	"thigh_l", "calf_l", "foot_l", "ball_l",
	"thigh_r", "calf_r", "foot_r", "ball_r",
]

var _stance: StringName = &"STAND"
var _goal_weight: float = 0.0
var _weight: float = 0.0
var _player: AnimationPlayer
var _clip_name: StringName = &""
var _sample_time: float = 0.0
var _rotations: Dictionary = {}
var _positions: Dictionary = {}
var _sampled: bool = false


func set_stance(stance: StringName) -> void:
	_stance = stance
	match stance:
		&"KNEEL":
			_goal_weight = 1.0
		&"CROUCH":
			_goal_weight = crouch_prior_weight
		_:
			_goal_weight = 0.0


func get_weight() -> float:
	return _weight


func get_debug() -> Dictionary:
	return {
		"stance": String(_stance),
		"weight": _weight,
		"goal_weight": _goal_weight,
		"clip": String(_clip_name),
		"sample_time": _sample_time,
		"sampled_bones": _rotations.size(),
	}


func _process_modification() -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null:
		return
	if not _sampled:
		_sample_kneel_pose(skeleton)
	var delta: float = clampf(get_process_delta_time(), 0.001, 0.05)
	var rate: float = blend_in_rate if _goal_weight > _weight else blend_out_rate
	_weight = move_toward(_weight, _goal_weight, rate * delta)
	if _weight <= 0.001 or _rotations.is_empty():
		return

	for bone_text: String in KNEEL_ROTATION_BONES:
		if not _rotations.has(bone_text):
			continue
		var bone_idx: int = skeleton.find_bone(StringName(bone_text))
		if bone_idx < 0:
			continue
		var current: Quaternion = skeleton.get_bone_pose_rotation(bone_idx)
		var desired: Quaternion = _rotations[bone_text] as Quaternion
		skeleton.set_bone_pose_rotation(bone_idx, current.slerp(desired.normalized(), _weight))

	## Keep horizontal/root ownership with CharacterBody3D. Only authored pelvis Y
	## is borrowed, and scaled with stance influence.
	if _positions.has("pelvis"):
		var pelvis_idx: int = skeleton.find_bone(&"pelvis")
		if pelvis_idx >= 0:
			var current_pos: Vector3 = skeleton.get_bone_pose_position(pelvis_idx)
			var sampled_pos: Vector3 = _positions["pelvis"] as Vector3
			var desired_pos := Vector3(current_pos.x, sampled_pos.y, current_pos.z)
			skeleton.set_bone_pose_position(
				pelvis_idx,
				current_pos.lerp(desired_pos, clampf(_weight * pelvis_vertical_weight, 0.0, 1.0))
			)


func _sample_kneel_pose(skeleton: Skeleton3D) -> void:
	_sampled = true
	_player = _find_animation_player_near(skeleton)
	if _player == null:
		push_warning("TactileStancePose: no AnimationPlayer near Henry skeleton")
		return
	for candidate: StringName in _player.get_animation_list():
		var text: String = String(candidate)
		if text == "Fixing_Kneeling" or text.ends_with("/Fixing_Kneeling"):
			_clip_name = candidate
			break
	if _clip_name == &"":
		push_warning("TactileStancePose: Fixing_Kneeling unavailable")
		return
	var animation: Animation = _player.get_animation(_clip_name)
	if animation == null or animation.length <= 0.001:
		return
	_sample_time = minf(KNEEL_SAMPLE_SECONDS, maxf(0.0, animation.length - 0.02))
	for track: int in animation.get_track_count():
		var path: NodePath = animation.track_get_path(track)
		var bone_text: String = path.get_concatenated_subnames()
		if bone_text.is_empty() or not KNEEL_ROTATION_BONES.has(bone_text):
			continue
		match animation.track_get_type(track):
			Animation.TYPE_ROTATION_3D:
				_rotations[bone_text] = animation.rotation_track_interpolate(track, _sample_time).normalized()
			Animation.TYPE_POSITION_3D:
				_positions[bone_text] = animation.position_track_interpolate(track, _sample_time)
	print("[TactileStancePose] clip=%s t=%.2f bones=%d static_sample=true crouch_prior=%.2f" % [
		String(_clip_name), _sample_time, _rotations.size(), crouch_prior_weight])


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
