class_name RokokoUALRetargetLab
extends Node3D

## Isolated direct-Godot Rokoko -> UAL compatibility spike for issue #202.
## The official sample FBX is downloaded by CI and never committed. We first
## measure whether Rokoko's Unreal export and UAL share enough bone/rest data to
## bind the imported animation directly. The visual playback deliberately keeps
## this test independent from the production locomotion AnimationTree.

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
var _playback: AnimationPlayer
var _clip_name: StringName = &""
var _clip_length: float = 0.0
var _mapped_tracks: int = 0
var _setup_ok: bool = false
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
	if not _install_direct_binding(source_animation):
		return
	_clip_length = source_animation.length
	_setup_ok = true
	_report["setup_ok"] = true
	_report["source_animation"] = String(_clip_name)
	_report["clip_length_seconds"] = _clip_length
	_report["mapped_tracks"] = _mapped_tracks
	_update_readout()
	seek_capture_time(0.0)


func is_ready_for_capture() -> bool:
	return _setup_ok


func get_clip_length() -> float:
	return _clip_length


func seek_capture_time(seconds: float) -> void:
	if not _setup_ok or _playback == null:
		return
	var sample_time := 0.0
	if _clip_length > 0.0001:
		sample_time = fposmod(seconds, _clip_length)
	_playback.seek(sample_time, true, true)
	_report["last_capture_time"] = sample_time


func get_retarget_report() -> Dictionary:
	var result := _report.duplicate(true)
	result["setup_ok"] = _setup_ok
	result["source_scene"] = SOURCE_SCENE_PATH
	return result


func _install_direct_binding(source_animation: Animation) -> bool:
	var remapped := source_animation.duplicate(true) as Animation
	if remapped == null:
		_fail("Could not duplicate Rokoko animation for track rebinding.")
		return false
	var target_path := get_path_to(_target_skeleton)
	_mapped_tracks = 0
	for track_index in range(remapped.get_track_count() - 1, -1, -1):
		var track_type := remapped.track_get_type(track_index)
		if track_type != Animation.TYPE_POSITION_3D \
				and track_type != Animation.TYPE_ROTATION_3D \
				and track_type != Animation.TYPE_SCALE_3D:
			remapped.remove_track(track_index)
			continue
		var source_path := remapped.track_get_path(track_index)
		if source_path.get_subname_count() < 1:
			remapped.remove_track(track_index)
			continue
		var bone_name := StringName(source_path.get_subname(source_path.get_subname_count() - 1))
		if _target_skeleton.find_bone(String(bone_name)) < 0:
			remapped.remove_track(track_index)
			continue
		remapped.track_set_path(track_index, NodePath("%s:%s" % [String(target_path), String(bone_name)]))
		_mapped_tracks += 1

	if _mapped_tracks == 0:
		_fail("Rokoko animation contained no transform tracks matching UAL bone names.")
		return false
	remapped.loop_mode = Animation.LOOP_LINEAR

	_playback = AnimationPlayer.new()
	_playback.name = "RokokoDirectPlayback"
	_playback.root_node = NodePath("..")
	add_child(_playback)
	var library := AnimationLibrary.new()
	library.add_animation(&"sample", remapped)
	_playback.add_animation_library(&"rokoko", library)
	_playback.play(&"rokoko/sample")
	_playback.pause()
	return true


func _audit_compatibility() -> Dictionary:
	var missing_source: Array[String] = []
	var missing_target: Array[String] = []
	var hierarchy_mismatches: Array[String] = []
	var rest_rotation_max_deg := 0.0
	var rest_rotation_sum_deg := 0.0
	var rest_rotation_samples := 0
	var length_ratio_sum := 0.0
	var length_ratio_samples := 0

	for bone_name in CORE_BONES:
		var source_index := _source_skeleton.find_bone(String(bone_name))
		var target_index := _target_skeleton.find_bone(String(bone_name))
		if source_index < 0:
			missing_source.append(String(bone_name))
			continue
		if target_index < 0:
			missing_target.append(String(bone_name))
			continue

		var source_parent := _source_skeleton.get_bone_parent(source_index)
		var target_parent := _target_skeleton.get_bone_parent(target_index)
		var source_parent_name := "" if source_parent < 0 else _source_skeleton.get_bone_name(source_parent)
		var target_parent_name := "" if target_parent < 0 else _target_skeleton.get_bone_name(target_parent)
		if source_parent_name != target_parent_name:
			hierarchy_mismatches.append("%s: %s != %s" % [bone_name, source_parent_name, target_parent_name])

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


func _update_readout() -> void:
	if readout == null:
		return
	readout.text = "ROKOKO → UAL (direct Godot)\n%s  %.2fs\ntracks %d  rest max %.2f°\nmissing %d/%d  hierarchy %d\ndirect candidate: %s" % [
		String(_clip_name),
		_clip_length,
		_mapped_tracks,
		float(_report.get("rest_rotation_max_deg", 0.0)),
		(_report.get("missing_source", []) as Array).size(),
		(_report.get("missing_target", []) as Array).size(),
		(_report.get("hierarchy_mismatches", []) as Array).size(),
		"YES" if bool(_report.get("direct_bind_candidate", false)) else "NO — inspect pose",
	]


func _fail(message: String) -> void:
	push_error("RokokoUALRetargetLab: %s" % message)
	_report = {"setup_ok": false, "error": message}
	if readout != null:
		readout.text = "ROKOKO → UAL\nFAILED\n%s" % message
