extends SceneTree

## Deterministic Phase 1 capture for issue #201. When CI-only motion sources are
## present, the same harness switches to isolated issue #202 retarget/database
## spikes instead of creating extra workflows.

const SCENE_PATH := "res://tests/motion_matching/motion_matching_lab.tscn"
const ROKOKO_SCENE_PATH := "res://tests/motion_matching/rokoko_ual_retarget_lab.tscn"
const ROKOKO_SOURCE_PATH := "res://tests/motion_matching/_runtime_rokoko/rokoko_unreal_sample.fbx"
const CMU_SCENE_PATH := "res://tests/motion_matching/cmu_ual_retarget_lab.tscn"
const CMU_SOURCE_PATH := "res://tests/motion_matching/_runtime_cmu/41_02.bvh"
const OUT_DIR := "res://docs/runtime_previews/motion_matching_lab"
const FRAME_DIR := OUT_DIR + "/frames"
const CAPTURE_WIDTH := 1280
const CAPTURE_HEIGHT := 720
const PHYSICS_STEPS_PER_FRAME := 2
const ROKOKO_VIDEO_FRAMES := 150
const CMU_VIDEO_FRAMES := 240
const MOTION_DATABASE_RATE_HZ := 30.0

const SEQUENCE: Array[Dictionary] = [
	{"label": "idle", "input": Vector2.ZERO, "frames": 18},
	{"label": "forward", "input": Vector2(0.0, -1.0), "frames": 24},
	{"label": "forward_right", "input": Vector2(0.72, -1.0), "frames": 22},
	{"label": "right", "input": Vector2(1.0, 0.0), "frames": 22},
	{"label": "back_right", "input": Vector2(1.0, 0.72), "frames": 22},
	{"label": "back", "input": Vector2(0.0, 1.0), "frames": 22},
	{"label": "back_left", "input": Vector2(-1.0, 0.72), "frames": 22},
	{"label": "left", "input": Vector2(-1.0, 0.0), "frames": 22},
	{"label": "forward_left", "input": Vector2(-0.72, -1.0), "frames": 22},
	{"label": "forward_again", "input": Vector2(0.0, -1.0), "frames": 22},
	{"label": "snap_right", "input": Vector2(1.0, 0.0), "frames": 14},
	{"label": "snap_back", "input": Vector2(0.0, 1.0), "frames": 14},
	{"label": "snap_left", "input": Vector2(-1.0, 0.0), "frames": 14},
	{"label": "snap_forward", "input": Vector2(0.0, -1.0), "frames": 14},
	{"label": "stop", "input": Vector2.ZERO, "frames": 18},
]

var _scene: Node3D
var _henry: MotionMatchingLab
var _frame_index: int = 0
var _report_segments: Array[Dictionary] = []
var _matcher_probe_report: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_prepare_output()
	if FileAccess.file_exists(CMU_SOURCE_PATH):
		await _run_cmu_capture()
	elif FileAccess.file_exists(ROKOKO_SOURCE_PATH):
		await _run_rokoko_capture()
	else:
		await _run_phase1_capture()


func _run_phase1_capture() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		push_error("MotionMatchingCapture: cannot load %s" % SCENE_PATH)
		quit(2)
		return

	_scene = packed.instantiate() as Node3D
	if _scene == null:
		push_error("MotionMatchingCapture: lab root is not Node3D.")
		quit(3)
		return
	root.add_child(_scene)
	root.size = Vector2i(CAPTURE_WIDTH, CAPTURE_HEIGHT)
	_henry = _scene.get_node_or_null(^"Henry") as MotionMatchingLab
	if _henry == null:
		push_error("MotionMatchingCapture: Henry lab body is missing.")
		quit(4)
		return

	for _index in range(36):
		await process_frame

	for segment_index in range(SEQUENCE.size()):
		var segment: Dictionary = SEQUENCE[segment_index]
		var input_vector: Vector2 = segment["input"]
		_henry.set_capture_input(input_vector)
		var frame_count: int = int(segment["frames"])
		for local_frame in range(frame_count):
			for _step in range(PHYSICS_STEPS_PER_FRAME):
				await physics_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var save_keyframe := local_frame == frame_count / 2
			await _capture_frame(str(segment["label"]), segment_index, save_keyframe)
		_report_segments.append({
			"label": str(segment["label"]),
			"input": [input_vector.x, input_vector.y],
			"snapshot": _henry.get_debug_snapshot(),
		})

	_henry.set_capture_input(Vector2.ZERO)
	_write_phase1_report()
	print("[MOTION_MATCHING_CAPTURE] %d frames written to %s" % [_frame_index, ProjectSettings.globalize_path(OUT_DIR)])
	quit(0)


func _run_rokoko_capture() -> void:
	if not await _prepare_retarget_scene(ROKOKO_SCENE_PATH, "RokokoRetargetCapture", 10):
		return

	var key_indices := {0: 0, 37: 1, 75: 2, 112: 3, 149: 4}
	for frame in range(ROKOKO_VIDEO_FRAMES):
		var capture_time := float(frame) / 30.0
		_scene.call("seek_capture_time", capture_time)
		await process_frame
		await RenderingServer.frame_post_draw
		var save_keyframe := key_indices.has(frame)
		var key_index: int = int(key_indices.get(frame, 0))
		await _capture_frame("rokoko_%02d" % key_index, key_index, save_keyframe)

	var report: Dictionary = _scene.call("get_retarget_report")
	report["issue"] = 202
	report["mode"] = "rokoko_direct_godot_spike"
	report["resolution"] = [CAPTURE_WIDTH, CAPTURE_HEIGHT]
	report["frame_count"] = _frame_index
	report["video_seconds"] = float(ROKOKO_VIDEO_FRAMES) / 30.0
	_write_json_report(report)
	print("[ROKOKO_RETARGET_CAPTURE] %d frames written to %s" % [_frame_index, ProjectSettings.globalize_path(OUT_DIR)])
	quit(0)


func _run_cmu_capture() -> void:
	if not await _prepare_retarget_scene(CMU_SCENE_PATH, "CMURetargetCapture", 20):
		return

	var cmu_lab := _scene as CMUUALRetargetLab
	if cmu_lab == null:
		push_error("CMURetargetCapture: scene is not CMUUALRetargetLab.")
		quit(23)
		return
	var database: MotionDatabase = await cmu_lab.bake_motion_database(MOTION_DATABASE_RATE_HZ)
	if database == null or not database.is_consistent():
		push_error("CMURetargetCapture: MotionDatabase bake failed.")
		quit(24)
		return
	print("[MOTION_DATABASE_BAKE] %d real samples × %d features @ %.1f Hz" % [
		database.get_sample_count(), database.feature_count, database.sample_rate_hz
	])

	if not await _run_cmu_matcher_probe(cmu_lab, database):
		quit(25)
		return

	var key_indices := {0: 0, 60: 1, 120: 2, 180: 3, 239: 4}
	for frame in range(CMU_VIDEO_FRAMES):
		var capture_time := float(frame) / 30.0
		_scene.call("seek_capture_time", capture_time)
		await process_frame
		await RenderingServer.frame_post_draw
		var save_keyframe := key_indices.has(frame)
		var key_index: int = int(key_indices.get(frame, 0))
		await _capture_frame("cmu_%02d" % key_index, key_index, save_keyframe)

	var report: Dictionary = _scene.call("get_retarget_report")
	report["issue"] = 202
	report["mode"] = "cmu_subject41_direct_godot_spike"
	report["resolution"] = [CAPTURE_WIDTH, CAPTURE_HEIGHT]
	report["frame_count"] = _frame_index
	report["video_seconds"] = float(CMU_VIDEO_FRAMES) / 30.0
	report["motion_matcher_probe"] = _matcher_probe_report
	_write_json_report(report)
	print("[CMU_RETARGET_CAPTURE] %d frames written to %s" % [_frame_index, ProjectSettings.globalize_path(OUT_DIR)])
	quit(0)


func _run_cmu_matcher_probe(cmu_lab: CMUUALRetargetLab, database: MotionDatabase) -> bool:
	var henry_animation := cmu_lab.get_node_or_null(^"Henry/HenryUALVisual") as HenryUALAnimation
	var source := cmu_lab.get_node_or_null(^"SourceData/CMU_41_02") as CMUBVHSource
	if henry_animation == null or henry_animation.skeleton == null or source == null:
		push_error("CMURetargetCapture: runtime query dependencies are missing.")
		return false

	var builder := MotionRuntimeQueryBuilder.new()
	var matcher := MotionMatcher.new()
	var sample_dt := 1.0 / database.sample_rate_hz
	var probe_time := minf(12.0, maxf(sample_dt, cmu_lab.get_clip_length() * 0.33))
	var previous_time := maxf(0.0, probe_time - sample_dt)

	cmu_lab.seek_capture_time(previous_time)
	await process_frame
	var previous_pose := builder.capture_pose(henry_animation.skeleton)
	cmu_lab.seek_capture_time(probe_time)
	await process_frame
	var current_pose := builder.capture_pose(henry_animation.skeleton)
	if previous_pose.is_empty() or current_pose.is_empty():
		push_error("CMURetargetCapture: could not capture Henry query pose.")
		return false

	var previous_root := source.get_raw_root_position(previous_time)
	var current_root := source.get_raw_root_position(probe_time)
	var root_velocity := (current_root - previous_root) / maxf(probe_time - previous_time, 0.000001)
	var previous_facing_3d := source.get_raw_root_facing(previous_time)
	var current_facing_3d := source.get_raw_root_facing(probe_time)
	var previous_facing := Vector2(previous_facing_3d.x, previous_facing_3d.z).normalized()
	var current_facing := Vector2(current_facing_3d.x, current_facing_3d.z).normalized()
	var root_angular_velocity := previous_facing.angle_to(current_facing) / maxf(probe_time - previous_time, 0.000001)
	var command_speed := clampf(Vector2(root_velocity.x, root_velocity.z).length(), 0.9, 2.2)

	var commands: Array[Dictionary] = [
		{"label": "forward", "direction": Vector2(0.0, 1.0)},
		{"label": "forward_right", "direction": Vector2(1.0, 1.0).normalized()},
		{"label": "right", "direction": Vector2(1.0, 0.0)},
		{"label": "back", "direction": Vector2(0.0, -1.0)},
		{"label": "left", "direction": Vector2(-1.0, 0.0)},
	]
	var matches: Array[Dictionary] = []
	var unique_samples: Dictionary = {}
	for command in commands:
		var direction: Vector2 = command["direction"]
		var desired_velocity := direction * command_speed
		var query := builder.build_query(
			previous_pose,
			current_pose,
			maxf(probe_time - previous_time, 0.000001),
			root_velocity,
			root_angular_velocity,
			current_facing,
			desired_velocity
		)
		if query.size() != database.feature_count:
			push_error("CMURetargetCapture: runtime query schema mismatch (%d != %d)." % [query.size(), database.feature_count])
			return false
		var best_match := matcher.find_best(database, query)
		if best_match.is_empty():
			push_error("CMURetargetCapture: brute-force matcher returned no frame.")
			return false
		best_match["query_label"] = str(command["label"])
		best_match["desired_local_velocity"] = [desired_velocity.x, desired_velocity.y]
		matches.append(best_match)
		unique_samples[str(best_match["sample_index"])] = true
		print("[MOTION_MATCH] %-13s -> %s @ %.3fs sample=%d total=%.3f pose=%.3f velocity=%.3f traj=%.3f facing=%.3f" % [
			str(command["label"]),
			str(best_match["clip"]),
			float(best_match["time"]),
			int(best_match["sample_index"]),
			float(best_match["total_cost"]),
			float(best_match["pose_cost"]),
			float(best_match["velocity_cost"]),
			float(best_match["trajectory_cost"]),
			float(best_match["facing_cost"]),
		])

	_matcher_probe_report = {
		"query_source": "live Henry UAL skeleton + current CMU motion + desired future trajectory",
		"probe_time": probe_time,
		"command_speed_mps": command_speed,
		"current_root_velocity": [root_velocity.x, root_velocity.y, root_velocity.z],
		"current_root_angular_velocity": root_angular_velocity,
		"current_facing": [current_facing.x, current_facing.y],
		"query_feature_count": database.feature_count,
		"search": "brute_force_all_frames",
		"searched_samples_per_query": database.get_sample_count(),
		"unique_best_samples": unique_samples.size(),
		"queries": matches,
	}
	cmu_lab.seek_capture_time(probe_time)
	await process_frame
	return matches.size() == commands.size()


func _prepare_retarget_scene(scene_path: String, label: String, error_base: int) -> bool:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("%s: cannot load %s" % [label, scene_path])
		quit(error_base)
		return false
	_scene = packed.instantiate() as Node3D
	if _scene == null or not _scene.has_method("is_ready_for_capture"):
		push_error("%s: lab root is invalid." % label)
		quit(error_base + 1)
		return false
	root.add_child(_scene)
	root.size = Vector2i(CAPTURE_WIDTH, CAPTURE_HEIGHT)

	for _index in range(48):
		await process_frame
	if not bool(_scene.call("is_ready_for_capture")):
		push_error("%s: lab setup failed: %s" % [label, JSON.stringify(_scene.call("get_retarget_report"))])
		quit(error_base + 2)
		return false
	return true


func _prepare_output() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FRAME_DIR))


func _capture_frame(label: String, segment_index: int, save_keyframe: bool) -> void:
	var image: Image = root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("MotionMatchingCapture: empty viewport frame %d" % _frame_index)
		return

	var frame_path := "%s/%04d.png" % [FRAME_DIR, _frame_index]
	var err := image.save_png(ProjectSettings.globalize_path(frame_path))
	if err != OK:
		push_error("MotionMatchingCapture: failed frame %d (%d)" % [_frame_index, err])
	if save_keyframe:
		var key_path := "%s/%02d_%s.png" % [OUT_DIR, segment_index, label]
		var key_err := image.save_png(ProjectSettings.globalize_path(key_path))
		if key_err != OK:
			push_error("MotionMatchingCapture: failed keyframe %s (%d)" % [label, key_err])
	_frame_index += 1


func _write_phase1_report() -> void:
	var report := {
		"issue": 201,
		"mode": "directional_search_phase1",
		"scene": SCENE_PATH,
		"resolution": [CAPTURE_WIDTH, CAPTURE_HEIGHT],
		"physics_steps_per_video_frame": PHYSICS_STEPS_PER_FRAME,
		"frame_count": _frame_index,
		"segments": _report_segments,
		"debug": {
			"desired_arrow": "green",
			"selected_sample_arrow": "blue",
			"facing_arrow": "amber",
		},
	}
	_write_json_report(report)


func _write_json_report(report: Dictionary) -> void:
	var file := FileAccess.open(OUT_DIR + "/report.json", FileAccess.WRITE)
	if file == null:
		push_error("MotionMatchingCapture: cannot write report.json")
		return
	file.store_string(JSON.stringify(report, "\t"))
