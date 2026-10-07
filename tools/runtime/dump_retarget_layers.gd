extends SceneTree

## Retarget-only dump of Henry joints and rotations per variant (MM_DUMP_VARIANTS) on the
## 30 Hz grid of one clip window (MM_START, MM_SECONDS), into MM_DUMP_OUT; see tools/motion/.

const HENRY_MODEL := "res://assets/characters/henry/henry_outfit.glb"
const HENRY_IDLE := &"Idle"
const B4 := MotionRetargeter.STAGE_ALL | MotionRetargeter.STAGE_NEUTRAL_POSE \
	| MotionRetargeter.STAGE_TWIST_SPLIT | MotionRetargeter.STAGE_SPINE_CHAIN
## Variant name -> MotionRetargeter.stages, or a RetargetModifier3D mode.
const VARIANTS := {
	"L1_core": 0,
	"L2_swing": MotionRetargeter.STAGE_SEGMENT_SWING,
	"L3_feet": MotionRetargeter.STAGE_SEGMENT_SWING | MotionRetargeter.STAGE_FOOT_PITCH,
	"L4_full": MotionRetargeter.STAGE_ALL,
	"B4_neutral": MotionRetargeter.STAGE_ALL | MotionRetargeter.STAGE_NEUTRAL_POSE,
	"B4_twist": MotionRetargeter.STAGE_ALL | MotionRetargeter.STAGE_TWIST_SPLIT,
	"B4_spine": MotionRetargeter.STAGE_ALL | MotionRetargeter.STAGE_SPINE_CHAIN,
	"B4_full": B4,
	"B2_global": "global",
	"B2_local": "local",
}
const DEFAULT_VARIANTS := "L1_core,L2_swing,L3_feet,L4_full"

var _model := UALSkeletonModel.new()
var _henry_neutral: Array[Quaternion] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var out_path := OS.get_environment("MM_DUMP_OUT")
	var requested: Array = Array(OS.get_cmdline_user_args())
	if out_path.is_empty() or requested.is_empty():
		push_error("RetargetLayerDump: set MM_DUMP_OUT and pass dataset:clip.")
		quit(2)
		return
	var henry := (load(HENRY_MODEL) as PackedScene).instantiate()
	root.add_child(henry)
	await process_frame
	var skeletons := henry.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty() or not _model.load_from_skeleton(skeletons[0] as Skeleton3D):
		push_error("RetargetLayerDump: Henry skeleton unavailable.")
		quit(2)
		return
	var players := henry.find_children("*", "AnimationPlayer", true, false)
	var idle: Animation = (players[0] as AnimationPlayer).get_animation(HENRY_IDLE) if not players.is_empty() else null
	_henry_neutral = _model.mean_pose(idle)
	var rest := PackedFloat32Array()
	for rotation in _model.rest_rotations():
		rest.append_array([rotation.x, rotation.y, rotation.z, rotation.w])
	var names := OS.get_environment("MM_DUMP_VARIANTS")
	var variants := (names if not names.is_empty() else DEFAULT_VARIANTS).split(",", false)
	var result := {"henry_bones": _model.bone_names, "henry_parents": _model.parents, "henry_rest_rotations": rest, "clips": {}}
	for entry in requested:
		var parts := String(entry).split(":")
		result["clips"][String(entry)] = await _dump_clip(parts[0], parts[1], variants, skeletons[0] as Skeleton3D)
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(result))
	file.close()
	print("[RETARGET_LAYER_DUMP] clips=%d variants=%s -> %s" % [requested.size(), ",".join(variants), out_path])
	quit(0)


func _dump_clip(dataset: String, clip_name: String, variants: PackedStringArray, henry_skeleton: Skeleton3D) -> Dictionary:
	var profile := SourceRetargetProfile.for_dataset(dataset)
	var clip := BVHClip.new()
	if profile == null or not clip.load_file(profile.source_dir + clip_name + ".bvh", profile.units_to_meters):
		return {"error": "cannot load"}
	var neutral_clip: BVHClip = null
	if not profile.neutral_clip.is_empty():
		neutral_clip = BVHClip.new()
		if not neutral_clip.load_file(profile.source_dir + profile.neutral_clip + ".bvh", profile.units_to_meters):
			neutral_clip = null
	var start := OS.get_environment("MM_START").to_float()
	var seconds := OS.get_environment("MM_SECONDS").to_float() if not OS.get_environment("MM_SECONDS").is_empty() else 1.0e9
	var layers := {}
	var times: Array[float] = []
	var source_frames: Array[int] = []
	for variant in variants:
		if not VARIANTS.has(variant):
			layers[variant] = {"error": "unknown variant"}
			continue
		var retargeter := MotionRetargeter.new()
		retargeter.stages = int(VARIANTS[variant]) if VARIANTS[variant] is int else MotionRetargeter.STAGE_ALL
		retargeter.target_neutral_local = _henry_neutral
		retargeter.source_neutral_clip = neutral_clip
		if not retargeter.setup(clip, profile, _model):
			return {"error": retargeter.error_message}
		if times.is_empty():
			var end := minf(retargeter.get_duration(), start + seconds)
			var time := start
			while time <= end:
				times.append(time)
				source_frames.append(clip.frame_at_time(time, profile.first_motion_frame))
				time += 1.0 / retargeter.track_rate_hz
		var backend: ModifierRetargetBackend = null
		if VARIANTS[variant] is String:
			backend = ModifierRetargetBackend.new()
			if not backend.setup(clip, profile, henry_skeleton, VARIANTS[variant] == "global", root):
				layers[variant] = {"error": backend.error_message}
				continue
		var frames: Array = []
		var rotations: Array = []
		for time in times:
			var pose := retargeter.retarget_at(time)
			var local_rotations: Array[Quaternion] = pose["rotations"]
			if backend != null:
				local_rotations = await backend.pose_at(clip.frame_at_time(time, profile.first_motion_frame), self, retargeter.root_space_basis(time))
			var globals := _model.forward_kinematics(local_rotations, pose["pelvis_position"])
			frames.append(_flatten(globals))
			var packed := PackedFloat32Array()
			for rotation in local_rotations:
				packed.append_array([rotation.x, rotation.y, rotation.z, rotation.w])
			rotations.append(packed)
		layers[variant] = {"frames": frames, "rotations": rotations, "report": backend.report if backend != null else retargeter.report}
		if backend != null:
			backend.free_nodes()
	var source: Array = []
	for frame in source_frames:
		source.append(_flatten(clip.global_transforms(frame)))
	return {
		"times": times, "source_frames": source_frames, "source_bones": clip.bone_names,
		"source_parents": clip.parents, "source": source, "layers": layers,
		"frame_time": clip.frame_time, "units_to_meters": profile.units_to_meters,
	}


func _flatten(transforms: Array[Transform3D]) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	for transform in transforms:
		values.append(transform.origin.x)
		values.append(transform.origin.y)
		values.append(transform.origin.z)
	return values
