class_name RokokoUALRetargetLab
extends Node3D

## Direct-Godot Rokoko -> UAL compatibility spike for issue #202.
## The official sample FBX is downloaded by CI and never committed.
##
## Pass 1 proved that simply rebinding Rokoko UE animation tracks to UAL bone
## names is invalid because the skeletons have very different Bone Rest axes.
## This pass uses Godot's RetargetModifier3D for the rest-space correction. A
## meshless proxy skeleton has Henry/UAL's exact rests and source-compatible bone
## names; the modifier writes the corrected pose there, then that pose is copied
## by bone index to Henry's real skeleton.

const SOURCE_SCENE_PATH := "res://tests/motion_matching/_runtime_rokoko/rokoko_unreal_sample.fbx"
const CORE_BONES: Array[StringName] = [
	&"pelvis",
	&"spine_01", &"spine_02", &"spine_03", &"neck_01", &"head",
	&"clavicle_l", &"upperarm_l", &"lowerarm_l", &"hand_l",
	&"clavicle_r", &"upperarm_r", &"lowerarm_r", &"hand_r",
	&"thigh_l", &"calf_l", &"foot_l", &"ball_l",
	&"thigh_r", &"calf_r", &"foot_r", &"ball_r",
]

@onready var henry_animation: HenryUALAnimation = $Henry/HenryUALVisual as HenryUALAnimation
@onready var readout: Label3D = $Debug/Readout

var _source_scene: Node
var _source_skeleton: Skeleton3D
var _source_player: AnimationPlayer
var _target_skeleton: Skeleton3D
var _proxy_skeleton: Skeleton3D
var _retarget_modifier: RetargetModifier3D
var _clip_name: StringName = &""
var _clip_length: float = 0.0
var _setup_ok: bool = false
var _mapped_bone_count: int = 0
var _unmapped_target_bones: Array[String] = []
var _report: Dictionary = {}


func _ready() -> void:
	call_deferred("_setup")


func _setup() -> void:
	if not FileAccess.file_exists(SOURCE_SCENE_PATH):
		_fail("Official Rokoko sample was not staged before import.")
		return
	if henry_animation == null or henry_animation.skeleton == null:
		_fail("Henry UAL skeleton is unavailable.")
		return

	_target_skeleton = henry_animation.skeleton
	if henry_animation.animation_tree != null:
		henry_animation.animation_tree.active = false
	if henry_animation.animation_player != null:
		henry_animation.animation_player.stop(true)
	_disable_target_modifiers(_target_skeleton)
	_target_skeleton.reset_bone_poses()

	var packed := load(SOURCE_SCENE_PATH) as PackedScene
	if packed == null:
		_fail("Godot could not load the staged Rokoko FBX as PackedScene.")
		return
	_source_scene = packed.instantiate()
	if _source_scene == null:
		_fail("Rokoko FBX instantiated to null.")
		return
	$SourceData.add_child(_source_scene)
	_hide_geometry(_source_scene)
	_source_skeleton = _find_skeleton(_source_scene)
	_source_player = _find_animation_player(_source_scene)
	if _source_skeleton == null or _source_player == null:
		_fail("Imported Rokoko sample is missing Skeleton3D or AnimationPlayer.")
		return
	_source_player.stop(true)

	_clip_name = _select_longest_animation(_source_player)
	if _clip_name.is_empty():
		_fail("Imported Rokoko sample has no non-RESET animation.")
		return
	var source_animation := _source_player.get_animation(_clip_name)
	if source_animation == null:
		_fail("Selected Rokoko animation resource is null.")
		return

	_report = _audit_compatibility()
	if not _install_runtime_retarget():
		return

	_clip_length = source_animation.length
	_source_player.play(_clip_name)
	_source_player.pause()
	_setup_ok = true
	_report["setup_ok"] = true
	_report["retarget_mode"] = "RetargetModifier3D_proxy"
	_report["source_animation"] = String(_clip_name)
	_report["clip_length_seconds"] = _clip_length
	_report["mapped_profile_bones"] = _mapped_bone_count
	_report["unmapped_target_bones"] = _unmapped_target_bones
	_report["source_transform_tracks"] = _count_transform_tracks(source_animation)
	_update_readout()
	seek_capture_time(0.0)


func is_ready_for_capture() -> bool:
	return _setup_ok


func get_clip_length() -> float:
	return _clip_length


func seek_capture_time(seconds: float) -> void:
	if not _setup_ok or _source_player == null:
		return
	var sample_time := 0.0
	if _clip_length > 0.0001:
		sample_time = fposmod(seconds, _clip_length)
	_source_player.seek(sample_time, true, true)
	_report["last_capture_time"] = sample_time


func get_retarget_report() -> Dictionary:
	var result := _report.duplicate(true)
	result["setup_ok"] = _setup_ok
	result["source_scene"] = SOURCE_SCENE_PATH
	return result


func _install_runtime_retarget() -> bool:
	## RetargetModifier3D maps by exact profile bone names. Build a proxy with
	## Henry's rests/hierarchy but use the matching Rokoko source spelling for
	## each bone (e.g. Rokoko `head` can drive UAL `Head`).
	var source_names_by_lower: Dictionary = {}
	for source_index in range(_source_skeleton.get_bone_count()):
		var source_name := StringName(_source_skeleton.get_bone_name(source_index))
		source_names_by_lower[String(source_name).to_lower()] = source_name

	_proxy_skeleton = Skeleton3D.new()
	_proxy_skeleton.name = "UALRestProxy"
	var proxy_names: Array[StringName] = []
	var mapped_source_names: Array[StringName] = []
	var mapped_target_indices: Array[int] = []
	var used_proxy_names: Dictionary = {}

	for target_index in range(_target_skeleton.get_bone_count()):
		var target_name := StringName(_target_skeleton.get_bone_name(target_index))
		var source_name: StringName = &""
		if _source_skeleton.find_bone(String(target_name)) >= 0:
			source_name = target_name
		else:
			source_name = StringName(source_names_by_lower.get(String(target_name).to_lower(), &""))

		var proxy_name := source_name if not source_name.is_empty() else target_name
		if used_proxy_names.has(String(proxy_name)):
			## A proxy bone must be unique. Keep the target rest/hierarchy but leave
			## the duplicate unmapped rather than creating an ambiguous profile key.
			proxy_name = StringName("__unmapped_%d_%s" % [target_index, String(target_name)])
			source_name = &""
		used_proxy_names[String(proxy_name)] = true
		proxy_names.append(proxy_name)
		_proxy_skeleton.add_bone(String(proxy_name))
		_proxy_skeleton.set_bone_parent(target_index, _target_skeleton.get_bone_parent(target_index))
		_proxy_skeleton.set_bone_rest(target_index, _target_skeleton.get_bone_rest(target_index))

		if source_name.is_empty():
			_unmapped_target_bones.append(String(target_name))
		else:
			mapped_source_names.append(source_name)
			mapped_target_indices.append(target_index)

	if mapped_source_names.size() < 16:
		_fail("Too few common Rokoko/UAL bones for runtime retarget: %d" % mapped_source_names.size())
		return false

	var profile := SkeletonProfile.new()
	profile.bone_size = mapped_source_names.size()
	for profile_index in range(mapped_source_names.size()):
		var source_name := mapped_source_names[profile_index]
		var target_index := mapped_target_indices[profile_index]
		profile.set_bone_name(profile_index, source_name)
		profile.set_reference_pose(profile_index, _target_skeleton.get_bone_rest(target_index))

	_retarget_modifier = RetargetModifier3D.new()
	_retarget_modifier.name = "RokokoToUALRetarget"
	_source_skeleton.add_child(_retarget_modifier)
	_retarget_modifier.profile = profile
	_retarget_modifier.use_global_pose = false
	_retarget_modifier.copy_bone_skin_scale = false
	_retarget_modifier.set_position_enabled(true)
	_retarget_modifier.set_rotation_enabled(true)
	_retarget_modifier.set_scale_enabled(false)
	_retarget_modifier.add_child(_proxy_skeleton)
	_retarget_modifier.modification_processed.connect(_copy_proxy_pose_to_henry)
	_mapped_bone_count = mapped_source_names.size()
	return true


func _copy_proxy_pose_to_henry() -> void:
	if _proxy_skeleton == null or _target_skeleton == null:
		return
	var count := mini(_proxy_skeleton.get_bone_count(), _target_skeleton.get_bone_count())
	for bone_index in range(count):
		_target_skeleton.set_bone_pose(bone_index, _proxy_skeleton.get_bone_pose(bone_index))


func _audit_compatibility() -> Dictionary:
	var missing_source: Array[String] = []
	var missing_target: Array[String] = []
	var hierarchy_mismatches: Array[String] = []
	var rest_rotation_max_deg := 0.0
	var rest_rotation_sum_deg := 0.0
	var rest_rotation_samples := 0
	var length_ratio_sum := 0.0
	var length_ratio_samples := 0
	var target_names_by_lower: Dictionary = {}
	for target_index in range(_target_skeleton.get_bone_count()):
		target_names_by_lower[String(_target_skeleton.get_bone_name(target_index)).to_lower()] = target_index

	for requested_name in CORE_BONES:
		var source_index := _find_bone_case_insensitive(_source_skeleton, requested_name)
		var target_index := int(target_names_by_lower.get(String(requested_name).to_lower(), -1))
		if source_index < 0:
			missing_source.append(String(requested_name))
			continue
		if target_index < 0:
			missing_target.append(String(requested_name))
			continue

		var source_parent := _source_skeleton.get_bone_parent(source_index)
		var target_parent := _target_skeleton.get_bone_parent(target_index)
		var source_parent_name := "" if source_parent < 0 else _source_skeleton.get_bone_name(source_parent).to_lower()
		var target_parent_name := "" if target_parent < 0 else _target_skeleton.get_bone_name(target_parent).to_lower()
		if source_parent_name != target_parent_name:
			hierarchy_mismatches.append("%s: %s != %s" % [requested_name, source_parent_name, target_parent_name])

		var source_rest := _source_skeleton.get_bone_rest(source_index)
		var target_rest := _target_skeleton.get_bone_rest(target_index)
		var angle_deg := rad_to_deg(source_rest.basis.get_rotation_quaternion().angle_to(
			target_rest.basis.get_rotation_quaternion()
		))
		rest_rotation_max_deg = maxf(rest_rotation_max_deg, angle_deg)
		rest_rotation_sum_deg += angle_deg
		rest_rotation_samples += 1
		var source_length := source_rest.origin.length()
		var target_length := target_rest.origin.length()
		if source_length > 0.0001 and target_length > 0.0001:
			length_ratio_sum += target_length / source_length
			length_ratio_samples += 1

	var rest_rotation_mean := 0.0
	if rest_rotation_samples > 0:
		rest_rotation_mean = rest_rotation_sum_deg / float(rest_rotation_samples)
	var mean_length_ratio := 0.0
	if length_ratio_samples > 0:
		mean_length_ratio = length_ratio_sum / float(length_ratio_samples)
	var direct_bind_candidate := (
		missing_source.is_empty()
		and missing_target.is_empty()
		and hierarchy_mismatches.is_empty()
		and rest_rotation_max_deg <= 5.0
	)
	return {
		"core_bone_count": CORE_BONES.size(),
		"source_bone_count": _source_skeleton.get_bone_count(),
		"target_bone_count": _target_skeleton.get_bone_count(),
		"missing_source": missing_source,
		"missing_target": missing_target,
		"hierarchy_mismatches": hierarchy_mismatches,
		"rest_rotation_max_deg": rest_rotation_max_deg,
		"rest_rotation_mean_deg": rest_rotation_mean,
		"mean_local_bone_length_ratio": mean_length_ratio,
		"direct_bind_candidate": direct_bind_candidate,
	}


func _find_bone_case_insensitive(skeleton: Skeleton3D, requested_name: StringName) -> int:
	var exact := skeleton.find_bone(String(requested_name))
	if exact >= 0:
		return exact
	var lower := String(requested_name).to_lower()
	for bone_index in range(skeleton.get_bone_count()):
		if skeleton.get_bone_name(bone_index).to_lower() == lower:
			return bone_index
	return -1


func _select_longest_animation(player: AnimationPlayer) -> StringName:
	var best_name: StringName = &""
	var best_length := -1.0
	for animation_name in player.get_animation_list():
		if String(animation_name).to_lower().contains("reset"):
			continue
		var animation := player.get_animation(animation_name)
		if animation != null and animation.length > best_length:
			best_length = animation.length
			best_name = animation_name
	return best_name


func _count_transform_tracks(animation: Animation) -> int:
	var count := 0
	for track_index in range(animation.get_track_count()):
		var track_type := animation.track_get_type(track_index)
		if track_type == Animation.TYPE_POSITION_3D \
				or track_type == Animation.TYPE_ROTATION_3D \
				or track_type == Animation.TYPE_SCALE_3D:
			count += 1
	return count


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _hide_geometry(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).visible = false
	for child in node.get_children():
		_hide_geometry(child)


func _disable_target_modifiers(node: Node) -> void:
	for child in node.get_children():
		if child is SkeletonModifier3D:
			(child as SkeletonModifier3D).active = false
		_disable_target_modifiers(child)


func _update_readout() -> void:
	if readout == null:
		return
	readout.text = "ROKOKO → GODOT → UAL\n%s  %.2fs\nRetargetModifier3D  mapped %d/%d\nraw rest mismatch: max %.1f°  mean %.1f°\nBlender: NONE" % [
		String(_clip_name),
		_clip_length,
		_mapped_bone_count,
		_target_skeleton.get_bone_count(),
		float(_report.get("rest_rotation_max_deg", 0.0)),
		float(_report.get("rest_rotation_mean_deg", 0.0)),
	]


func _fail(message: String) -> void:
	push_error("RokokoUALRetargetLab: %s" % message)
	_report = {"setup_ok": false, "error": message}
	if readout != null:
		readout.text = "ROKOKO → UAL\nFAILED\n%s" % message
