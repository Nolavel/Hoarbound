extends SceneTree

## Retarget-only layer dump: Henry joint positions per retarget stage set for one
## clip on the 30 Hz track grid, plus the raw source FK; read by tools/motion/.

const SOURCE_ROOT := "res://tests/motion_matching/_runtime_cmu/"
const HENRY_MODEL := "res://assets/characters/henry/henry_outfit.glb"
## Layer name -> MotionRetargeter.stages.
const LAYERS := {
	"L1_core": 0,
	"L2_swing": MotionRetargeter.STAGE_SEGMENT_SWING,
	"L3_feet": MotionRetargeter.STAGE_SEGMENT_SWING | MotionRetargeter.STAGE_FOOT_PITCH,
	"L4_full": MotionRetargeter.STAGE_ALL,
}


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
	var model := UALSkeletonModel.new()
	var skeletons := henry.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty() or not model.load_from_skeleton(skeletons[0] as Skeleton3D):
		push_error("RetargetLayerDump: Henry skeleton unavailable.")
		quit(2)
		return
	var rest := PackedFloat32Array()
	for rotation in model.rest_rotations():
		rest.append_array([rotation.x, rotation.y, rotation.z, rotation.w])
	var result := {"henry_bones": model.bone_names, "henry_parents": model.parents, "henry_rest_rotations": rest, "clips": {}}
	for entry in requested:
		var parts := String(entry).split(":")
		result["clips"][String(entry)] = _dump_clip(parts[0], parts[1], model)
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(result))
	file.close()
	print("[RETARGET_LAYER_DUMP] clips=%d -> %s" % [requested.size(), out_path])
	quit(0)


func _dump_clip(dataset: String, clip_name: String, model: UALSkeletonModel) -> Dictionary:
	var profile := SourceRetargetProfile.for_dataset(dataset)
	var clip := BVHClip.new()
	if profile == null or not clip.load_file(SOURCE_ROOT + clip_name + ".bvh", profile.units_to_meters):
		return {"error": "cannot load"}
	var layers := {}
	var times: Array[float] = []
	var source_frames: Array[int] = []
	for layer_name in LAYERS.keys():
		var retargeter := MotionRetargeter.new()
		retargeter.stages = int(LAYERS[layer_name])
		if not retargeter.setup(clip, profile, model):
			return {"error": retargeter.error_message}
		var frames: Array = []
		var rotations: Array = []
		if times.is_empty():
			for sample in range(retargeter.root_positions.size()):
				times.append(float(sample) / retargeter.track_rate_hz)
				source_frames.append(clip.frame_at_time(times[-1], profile.first_motion_frame))
		for time in times:
			var pose := retargeter.retarget_at(time)
			var globals := model.forward_kinematics(pose["rotations"], pose["pelvis_position"])
			frames.append(_flatten(globals))
			var local := PackedFloat32Array()
			for rotation: Quaternion in pose["rotations"]:
				local.append_array([rotation.x, rotation.y, rotation.z, rotation.w])
			rotations.append(local)
		layers[layer_name] = {"frames": frames, "rotations": rotations, "report": retargeter.report}
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
