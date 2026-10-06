extends SceneTree

## Deterministic motion-matching capture harness.
## Issue #201 Phase 1 remains available without staged mocap. Issue #202 reuses
## this same workflow for direct retarget, merged multi-clip database bake and
## canonical-pose playback; no parallel render pipeline is created.
## CI proof commits use both [motion-matching-preview] and [cmu-retarget-preview]
## so import_gate.sh stages the public CMU BVH pool before this script runs.

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
const CMU_VIDEO_FRAMES := 300
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
var _frame_index := 0
var _report_segments: Array[Dictionary] = []


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
		var frame_count := int(segment["frames"])
		for local_frame in range(frame_count):
			for _step in range(PHYSICS_STEPS_PER_FRAME):
				await physics_frame
			await process_frame
			await RenderingServer.frame_post_draw
			await _capture_frame(str(segment["label"]), segment_index, local_frame == frame_count / 2)
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
	var packed := load(CMU_SCENE_PATH) as PackedScene
	if packed == null:
		push_error("CMUMultiClipCapture: cannot load %s" % CMU_SCENE_PATH)
		quit(20)
		return
	root.size = Vector2i(CAPTURE_WIDTH, CAPTURE_HEIGHT)

	var multi_builder := CMUMultiClipDatabaseBuilder.new()
	var build_result: Dictionary = await multi_builder.build(packed, root, MOTION_DATABASE_RATE_HZ)
	if not bool(build_result.get("ok", false)):
		push_error("CMUMultiClipCapture: %s" % String(build_result.get("error", "unknown build error")))
		quit(21)
		return
	var curation: Dictionary = build_result.get("curation_report", {})
	if not bool(curation.get("steady_direction_gate_passed", false)):
		push_error("CMUMultiClipCapture: steady directional coverage regressed: %s" % JSON.stringify(
			curation.get("missing_steady_direction_roles", [])
		))
		quit(26)
		return

	var database := build_result.get("database") as MotionDatabase
	var cmu_lab := build_result.get("lab") as CMUUALRetargetLab
	if database == null or cmu_lab == null or not database.is_consistent():
		push_error("CMUMultiClipCapture: merged database/presentation lab invalid.")
		quit(22)
		return
	_scene = cmu_lab
	print("[MOTION_DATABASE_MULTI] %d real samples × %d features × %d clips @ %.1f Hz pose_bones=%d" % [
		database.get_sample_count(),
		database.feature_count,
		database.clip_names.size(),
		database.sample_rate_hz,
		database.pose_bone_names.size(),
	])

	var initial_sample := _find_first_role(database, "idle_neutral")
	if initial_sample < 0:
		initial_sample = 0
	var command_speed := _estimate_command_speed(database)
	var controller := MotionMatchingDatabasePlaybackController.new()
	if not await controller.setup(cmu_lab, database, initial_sample):
		push_error("CMUMultiClipCapture: database playback setup failed.")
		quit(23)
		return

	# This proof intentionally avoids a scripted F/R/B/L state list. Every video
	# frame supplies a continuous analog command; the debug label is constant and
	# cannot influence matching. The path contains a full directional sweep,
	# a hard reversal, a diagonal bend, stop/deceleration and a restart curve.
	var proof_samples: Array[Dictionary] = []
	for frame in range(CMU_VIDEO_FRAMES):
		var desired_velocity := _analog_command_for_frame(frame, command_speed)
		var state := await controller.step(
			1.0 / 30.0,
			desired_velocity,
			"LIVE ANALOG",
			Vector2(0.0, 1.0)
		)
		if state.is_empty():
			push_error("CMUMultiClipCapture: live unconstrained playback step failed.")
			quit(24)
			return
		await process_frame
		await RenderingServer.frame_post_draw
		var save_keyframe := frame % 50 == 0 or frame == CMU_VIDEO_FRAMES - 1
		await _capture_frame("mm_live_%03d" % frame, frame / 50, save_keyframe)
		if save_keyframe:
			proof_samples.append({
				"frame": frame,
				"desired_velocity": [desired_velocity.x, desired_velocity.y],
				"state": state,
			})

	if _frame_index != CMU_VIDEO_FRAMES:
		push_error("CMUMultiClipCapture: expected %d frames, captured %d." % [CMU_VIDEO_FRAMES, _frame_index])
		quit(25)
		return

	var report := cmu_lab.get_retarget_report()
	report["issue"] = 202
	report["mode"] = "cmu_unconstrained_live_runtime_motion_matching"
	report["proof_mode"] = "continuous_analog_no_direction_labels"
	report["resolution"] = [CAPTURE_WIDTH, CAPTURE_HEIGHT]
	report["frame_count"] = _frame_index
	report["video_seconds"] = float(_frame_index) / 30.0
	report["command_speed_mps"] = command_speed
	report["proof_source_count"] = int(build_result.get("proof_source_count", 0))
	report["source_reports"] = build_result.get("source_reports", [])
	report["curation"] = curation
	report["motion_database"] = database.get_report()
	report["motion_matching_playback"] = controller.get_report()
	report["proof_samples"] = proof_samples
	_write_json_report(report)
	var playback_report := controller.get_report()
	print("[MM_LIVE_CAPTURE] %d frames / %d switches / %d cross-clip / search=%s written to %s" % [
		_frame_index,
		int(playback_report["switch_count"]),
		int(playback_report["cross_clip_switch_count"]),
		String(playback_report["search_scope"]),
		ProjectSettings.globalize_path(OUT_DIR),
	])
	quit(0)


func _analog_command_for_frame(frame: int, speed: float) -> Vector2:
	if frame < 24:
		var ramp := float(frame) / 23.0
		return Vector2(0.0, speed * ramp)
	if frame < 144:
		var phase := float(frame - 24) / 120.0 * TAU
		return Vector2(sin(phase), cos(phase)) * speed
	if frame < 174:
		# Intent flips in one frame after the completed sweep.
		return Vector2(0.0, -speed)
	if frame < 224:
		var bend := float(frame - 174) / 50.0
		var angle := lerpf(PI, PI * 0.25, bend)
		return Vector2(sin(angle), cos(angle)) * speed
	if frame < 254:
		var decel := 1.0 - float(frame - 224) / 29.0
		return Vector2(0.70710678, 0.70710678) * speed * maxf(0.0, decel)
	var restart := clampf(float(frame - 254) / 20.0, 0.0, 1.0)
	var restart_phase := float(frame - 254) / 46.0 * PI * 0.75
	return Vector2(sin(restart_phase), cos(restart_phase)) * speed * restart


func _find_first_role(database: MotionDatabase, role: String) -> int:
	for sample_index in range(database.get_sample_count()):
		if database.get_sample_role(sample_index) == role:
			return sample_index
	return -1


func _estimate_command_speed(database: MotionDatabase) -> float:
	var speed_sum := 0.0
	var count := 0
	for sample_index in range(database.get_sample_count()):
		var row := database.get_feature_row(sample_index)
		if row.size() < 2:
			continue
		var speed := Vector2(row[0], row[1]).length()
		if speed > 0.35 and speed < 3.5:
			speed_sum += speed
			count += 1
	if count <= 0:
		return 1.35
	return clampf(speed_sum / float(count), 0.8, 2.2)


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
