class_name CMUUALRetargetLab
extends Node3D

## Direct-Godot CMU BVH -> canonical Henry UAL retarget lab for issue #202.
## Source BVHs are staged only for CI/lab use. UAL translations/bone lengths
## remain canonical; mapped source rotations drive the pose while raw CMU root
## motion is retained separately for motion-matching trajectory features.

const DEFAULT_SOURCE_BVH_PATH := "res://tests/motion_matching/_runtime_cmu/41_02.bvh"
const DEFAULT_CLIP_NAME := &"CMU_41_02"

const TARGET_SOURCE_ALIASES := {
	"pelvis": ["Hips"],
	"spine_01": ["LowerBack"],
	"spine_02": ["Spine"],
	"spine_03": ["Spine1"],
	"neck_01": ["Neck1", "Neck"],
	"Head": ["Head"],
	"clavicle_l": ["LeftShoulder"],
	"upperarm_l": ["LeftArm"],
	"lowerarm_l": ["LeftForeArm"],
	"hand_l": ["LeftHand"],
	"thigh_l": ["LeftUpLeg"],
	"calf_l": ["LeftLeg"],
	"foot_l": ["LeftFoot"],
	"ball_l": ["LeftToeBase"],
	"clavicle_r": ["RightShoulder"],
	"upperarm_r": ["RightArm"],
	"lowerarm_r": ["RightForeArm"],
	"hand_r": ["RightHand"],
	"thigh_r": ["RightUpLeg"],
	"calf_r": ["RightLeg"],
	"foot_r": ["RightFoot"],
	"ball_r": ["RightToeBase"],
}

const REQUIRED_TARGET_BONES: Array[StringName] = [
	&"pelvis",
	&"spine_01", &"spine_02", &"spine_03", &"neck_01", &"Head",
	&"clavicle_l", &"upperarm_l", &"lowerarm_l", &"hand_l",
	&"clavicle_r", &"upperarm_r", &"lowerarm_r", &"hand_r",
	&"thigh_l", &"calf_l", &"foot_l", &"ball_l",
	&"thigh_r", &"calf_r", &"foot_r", &"ball_r",
]

const DIAGNOSTIC_BONES: Array[StringName] = [
	&"pelvis", &"Head", &"foot_l", &"foot_r",
]

@onready var henry_animation: HenryUALAnimation = $Henry/HenryUALVisual as HenryUALAnimation
@onready var readout: Label3D = $Debug/Readout

var _source_bvh_path := DEFAULT_SOURCE_BVH_PATH
var _source_clip_name: StringName = DEFAULT_CLIP_NAME
var _source_trial := "CMU Subject 41 / 41_02"
var _source_description := "navigate: forward, backward, sideways, diagonally"
var _source_role := "multidirectional_reference"

var _source: CMUBVHSource
var _target_skeleton: Skeleton3D
var _proxy_skeleton: Skeleton3D
var _retarget_modifier: RetargetModifier3D
var _motion_database: MotionDatabase
var _setup_ok := false
var _setup_started := false
var _mapped_count := 0
var _mapping: Dictionary = {}
var _mapped_target_indices: Array[int] = []
var _unmapped_required: Array[String] = []
var _report: Dictionary = {}


func configure_source(
		bvh_path: String,
		clip_name: StringName,
		trial: String = "",
		description: String = "",
		role: String = ""
	) -> bool:
	if _setup_started or is_inside_tree():
		push_error("CMUUALRetargetLab: configure_source must run before the lab enters the tree.")
		return false
	_source_bvh_path = bvh_path
	_source_clip_name = clip_name
	if not trial.is_empty():
		_source_trial = trial
	if not description.is_empty():
		_source_description = description
	if not role.is_empty():
		_source_role = role
	return true


func _ready() -> void:
	call_deferred("_setup")


func _setup() -> void:
	_setup_started = true
	if not FileAccess.file_exists(_source_bvh_path):
		_fail("CMU BVH was not staged before capture: %s" % _source_bvh_path)
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

	_source = CMUBVHSource.new()
	_source.name = String(_source_clip_name)
	$SourceData.add_child(_source)
	if not _source.load_bvh(_source_bvh_path):
		_fail(_source.error_message)
		return

	_mapping = _build_mapping()
	for requested in REQUIRED_TARGET_BONES:
		if not _mapping.has(String(requested).to_lower()):
			_unmapped_required.append(String(requested))
	if not _unmapped_required.is_empty():
		_fail("CMU mapping is missing required UAL bones: %s" % ", ".join(_unmapped_required))
		return

	if not _install_runtime_retarget():
		return

	_setup_ok = true
	_report = _source.get_report()
	_report["setup_ok"] = true
	_report["retarget_mode"] = "CMU_BVH_RetargetModifier3D_proxy_rotation_only"
	_report["retarget_position_enabled"] = false
	_report["retarget_rotation_enabled"] = true
	_report["target_copy_mode"] = "mapped_rotation_only_preserve_ual_positions"
	_report["mapped_profile_bones"] = _mapped_count
	_report["target_bone_count"] = _target_skeleton.get_bone_count()
	_report["target_source_mapping"] = _mapping.duplicate(true)
	_report["unmapped_required_bones"] = _unmapped_required
	_report["source_trial"] = _source_trial
	_report["source_description"] = _source_description
	_report["source_role"] = _source_role
	_report["source_clip_name"] = String(_source_clip_name)
	_update_readout()
	seek_capture_time(0.0)


func is_ready_for_capture() -> bool:
	return _setup_ok


func get_clip_length() -> float:
	return 0.0 if _source == null else _source.clip_length


func get_source_clip_name() -> String:
	return String(_source_clip_name)


func get_target_skeleton() -> Skeleton3D:
	return _target_skeleton


func set_retarget_active(enabled: bool) -> void:
	if _retarget_modifier != null:
		_retarget_modifier.active = enabled


func bake_motion_database(
		sample_rate_hz: float = 30.0,
		start_time: float = 0.0,
		end_time: float = -1.0,
		role: String = "",
		source_id: String = ""
	) -> MotionDatabase:
	if not _setup_ok or _source == null or _target_skeleton == null:
		return null
	var baker := MotionDatabaseBaker.new()
	var effective_role := _source_role if role.is_empty() else role
	var effective_source := _source_bvh_path if source_id.is_empty() else source_id
	var database: MotionDatabase = await baker.bake_seekable_skeleton(
		_target_skeleton,
		_source_clip_name,
		_source.clip_length,
		Callable(self, "seek_capture_time"),
		Callable(_source, "get_raw_root_position"),
		Callable(_source, "get_raw_root_facing"),
		sample_rate_hz,
		start_time,
		end_time,
		effective_role,
		effective_source
	)
	if database == null or not database.is_consistent():
		push_error("CMUUALRetargetLab: MotionDatabase bake failed for %s." % String(_source_clip_name))
		return null
	_motion_database = database
	_report["motion_database_baker"] = "post_retarget_ual_exact_time_with_canonical_pose"
	_report["motion_database"] = _motion_database.get_report()
	return _motion_database


func seek_capture_time(seconds: float) -> void:
	if not _setup_ok or _source == null:
		return
	var sample_time := seconds
	if _source.clip_length > 0.0001:
		sample_time = fposmod(seconds, _source.clip_length)
	_source.seek_seconds(sample_time)
	_report["last_capture_time"] = sample_time
	var root := _source.get_raw_root_position(sample_time)
	_report["last_raw_root_m"] = [root.x, root.y, root.z]


func get_retarget_report() -> Dictionary:
	var result := _report.duplicate(true)
	result["setup_ok"] = _setup_ok
	result["source_scene"] = _source_bvh_path
	if _setup_ok:
		result["target_diagnostics"] = _collect_target_diagnostics()
	return result


func _build_mapping() -> Dictionary:
	var source_by_lower: Dictionary = {}
	for source_index in range(_source.get_bone_count()):
		var source_name := _source.get_bone_name(source_index)
		source_by_lower[source_name.to_lower()] = source_name

	var result: Dictionary = {}
	for target_index in range(_target_skeleton.get_bone_count()):
		var target_name := _target_skeleton.get_bone_name(target_index)
		var target_key := target_name.to_lower()
		var aliases: Array = TARGET_SOURCE_ALIASES.get(target_name, [])
		if aliases.is_empty():
			aliases = TARGET_SOURCE_ALIASES.get(target_key, [])
		for alias_value in aliases:
			var alias := String(alias_value)
			var source_name: String = String(source_by_lower.get(alias.to_lower(), ""))
			if not source_name.is_empty():
				result[target_key] = source_name
				break
	return result


func _install_runtime_retarget() -> bool:
	_proxy_skeleton = Skeleton3D.new()
	_proxy_skeleton.name = "UALRestProxy"

	var mapped_source_names: Array[StringName] = []
	var used_source_names: Dictionary = {}
	_mapped_target_indices.clear()

	for target_index in range(_target_skeleton.get_bone_count()):
		var target_name := _target_skeleton.get_bone_name(target_index)
		var target_key := target_name.to_lower()
		var source_name := String(_mapping.get(target_key, ""))
		var proxy_name := target_name
		if not source_name.is_empty() and not used_source_names.has(source_name):
			proxy_name = source_name
			used_source_names[source_name] = true
			mapped_source_names.append(StringName(source_name))
			_mapped_target_indices.append(target_index)
		elif not source_name.is_empty():
			source_name = ""

		_proxy_skeleton.add_bone(proxy_name)
		_proxy_skeleton.set_bone_parent(target_index, _target_skeleton.get_bone_parent(target_index))
		_proxy_skeleton.set_bone_rest(target_index, _target_skeleton.get_bone_rest(target_index))

	if mapped_source_names.size() < REQUIRED_TARGET_BONES.size():
		_fail("Too few CMU/UAL mapped bones: %d" % mapped_source_names.size())
		return false

	var profile := SkeletonProfile.new()
	profile.bone_size = mapped_source_names.size()
	for profile_index in range(mapped_source_names.size()):
		var source_name := mapped_source_names[profile_index]
		var target_index := _mapped_target_indices[profile_index]
		profile.set_bone_name(profile_index, source_name)
		profile.set_reference_pose(profile_index, _target_skeleton.get_bone_rest(target_index))

	_retarget_modifier = RetargetModifier3D.new()
	_retarget_modifier.name = "CMUToUALRetarget"
	_source.add_child(_retarget_modifier)
	_retarget_modifier.profile = profile
	_retarget_modifier.use_global_pose = false
	_retarget_modifier.copy_bone_skin_scale = false
	_retarget_modifier.set_position_enabled(false)
	_retarget_modifier.set_rotation_enabled(true)
	_retarget_modifier.set_scale_enabled(false)
	_retarget_modifier.add_child(_proxy_skeleton)
	_retarget_modifier.modification_processed.connect(_copy_proxy_pose_to_henry)
	_mapped_count = mapped_source_names.size()
	return true


func _copy_proxy_pose_to_henry() -> void:
	if _proxy_skeleton == null or _target_skeleton == null:
		return
	for bone_index in _mapped_target_indices:
		_target_skeleton.set_bone_pose_rotation(
			bone_index,
			_proxy_skeleton.get_bone_pose_rotation(bone_index)
		)


func _disable_target_modifiers(node: Node) -> void:
	for child in node.get_children():
		if child is SkeletonModifier3D:
			(child as SkeletonModifier3D).active = false
		_disable_target_modifiers(child)


func _collect_target_diagnostics() -> Dictionary:
	var result: Dictionary = {}
	result["henry_global_position"] = _vec3_to_array($Henry.global_position)
	result["visual_global_position"] = _vec3_to_array(henry_animation.global_position)
	result["skeleton_global_position"] = _vec3_to_array(_target_skeleton.global_position)

	var bone_positions: Dictionary = {}
	for bone_name in DIAGNOSTIC_BONES:
		var bone_index := _target_skeleton.find_bone(String(bone_name))
		if bone_index < 0:
			bone_positions[String(bone_name)] = "missing"
			continue
		var bone_world := _target_skeleton.global_transform * _target_skeleton.get_bone_global_pose(bone_index).origin
		bone_positions[String(bone_name)] = _vec3_to_array(bone_world)
	result["bone_world_positions"] = bone_positions

	var bounds := _collect_visual_world_bounds(henry_animation)
	result["mesh_instance_count"] = int(bounds["count"])
	result["mesh_world_aabb_min"] = bounds["min"]
	result["mesh_world_aabb_max"] = bounds["max"]
	return result


func _collect_visual_world_bounds(node: Node) -> Dictionary:
	var found := false
	var min_point := Vector3.ZERO
	var max_point := Vector3.ZERO
	var mesh_count := 0
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back() as Node
		for child in current.get_children():
			stack.append(child)
		if current is MeshInstance3D:
			var mesh_instance := current as MeshInstance3D
			if mesh_instance.mesh == null or not mesh_instance.visible:
				continue
			mesh_count += 1
			var local_aabb := mesh_instance.get_aabb()
			for x_index in range(2):
				for y_index in range(2):
					for z_index in range(2):
						var corner := local_aabb.position + Vector3(
							local_aabb.size.x * float(x_index),
							local_aabb.size.y * float(y_index),
							local_aabb.size.z * float(z_index)
						)
						var world_corner := mesh_instance.global_transform * corner
						if not found:
							min_point = world_corner
							max_point = world_corner
							found = true
						else:
							min_point = min_point.min(world_corner)
							max_point = max_point.max(world_corner)
	return {
		"count": mesh_count,
		"min": _vec3_to_array(min_point) if found else [],
		"max": _vec3_to_array(max_point) if found else [],
	}


func _vec3_to_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _update_readout() -> void:
	if readout == null or _source == null:
		return
	readout.text = "%s → GODOT → UAL\n%.1f FPS  %d motion frames  %.1fs\nRetargetModifier3D  rotation-only  mapped %d/%d\nrole: %s\nBlender: NONE  synthetic direction: NONE" % [
		String(_source_clip_name),
		0.0 if _source.frame_time <= 0.0 else 1.0 / _source.frame_time,
		_source.motion_frame_count,
		_source.clip_length,
		_mapped_count,
		_target_skeleton.get_bone_count(),
		_source_role,
	]


func _fail(message: String) -> void:
	push_error("CMUUALRetargetLab: %s" % message)
	_report = {"setup_ok": false, "error": message}
	if readout != null:
		readout.text = "CMU → UAL FAILED\n%s" % message
