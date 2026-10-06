extends SceneTree

## Motion Matching capture harness: Phase 1 lab without staged mocap, otherwise
## curated database bake and the continuous analog proof (CI: both markers).

const SCENE_PATH := "res://tests/motion_matching/motion_matching_lab.tscn"
const ROKOKO_SCENE_PATH := "res://tests/motion_matching/rokoko_ual_retarget_lab.tscn"
const ROKOKO_SOURCE_PATH := "res://tests/motion_matching/_runtime_rokoko/rokoko_unreal_sample.fbx"
const LAB_SCENE_PATH := "res://tests/motion_matching/motion_matching_playback_lab.tscn"
const SOURCE_MANIFEST_PATH := "res://tests/motion_matching/_runtime_cmu/source_manifest.tsv"
const OUT_DIR := "res://docs/runtime_previews/motion_matching_lab"
const FRAME_DIR := OUT_DIR + "/frames"
const CAPTURE_WIDTH := 1280
const CAPTURE_HEIGHT := 720
const PHYSICS_STEPS_PER_FRAME := 2
const ROKOKO_VIDEO_FRAMES := 150
const MOTION_DATABASE_RATE_HZ := 30.0
const PROOF_SECONDS := 26.5

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
var _walk_speed := 1.0
var _strafe_speed := 0.8
var _henry: MotionMatchingLab
var _frame_index := 0
var _report_segments: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_prepare_output()
	if FileAccess.file_exists(SOURCE_MANIFEST_PATH):
		await _run_motion_matching_capture()
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


func _run_motion_matching_capture() -> void:
	root.size = Vector2i(CAPTURE_WIDTH, CAPTURE_HEIGHT)
	var build: Dictionary = MotionMatchingDatabaseBuilder.new().build(MOTION_DATABASE_RATE_HZ)
	if not bool(build.get("ok", false)):
		push_error("MotionMatchingCapture: %s" % String(build.get("error", "database build failed")))
		quit(21)
		return
	var database := build["database"] as MotionDatabase
	var lab := (load(LAB_SCENE_PATH) as PackedScene).instantiate() as MotionMatchingPlaybackLab
	root.add_child(lab)
	for _frame in range(8):
		await process_frame
	if not lab.is_ready_for_capture():
		push_error("MotionMatchingCapture: playback lab is not ready.")
		quit(22)
		return
	print("[MOTION_DATABASE] %d real samples x %d features x %d ranges @ %.0f Hz" % [
		database.get_sample_count(), database.feature_count, database.clip_names.size(), database.sample_rate_hz,
	])
	var controller := MotionMatchingDatabasePlaybackController.new()
	if not controller.setup(database, lab.skeleton, lab.body, lab.visual, lab.debug_view, _first_idle_sample(database)):
		push_error("MotionMatchingCapture: playback setup failed.")
		quit(23)
		return

	# The intent label goes to the report only, never to the matcher.
	var dt := 1.0 / 30.0
	var frame_count := int(PROOF_SECONDS * 30.0)
	# MM_HEADLESS_PROOF=1 runs the identical simulation without frames.
	var headless_proof := OS.get_environment("MM_HEADLESS_PROOF") == "1"
	_walk_speed = _median_speed(database, 0.0)
	_strafe_speed = _median_speed(database, PI * 0.5)
	var facing := Vector3.FORWARD
	var timeline: Array[Dictionary] = []
	for frame in range(frame_count):
		var t := float(frame) * dt
		var intent := _proof_intent(t, facing)
		facing = intent["facing"]
		var state := controller.step(dt, intent["velocity"], facing, intent["label"])
		lab.follow_camera(dt)
		await process_frame
		if not headless_proof:
			await RenderingServer.frame_post_draw
			await _capture_frame("mm_%05.2fs" % t, frame / 60, frame % 60 == 0)
		if frame % 5 == 0:
			timeline.append({
				"t": t, "label": intent["label"],
				"desired_velocity": [intent["velocity"].x, intent["velocity"].z],
				"desired_facing": [facing.x, facing.z],
				"clip": state["current_clip"], "time": state["current_time"],
				"speed": state["root_speed"], "decision": state["decision"],
				"velocity": [state["root_velocity_world"][0], state["root_velocity_world"][2]],
				"actual_facing": _flat_forward(lab.skeleton),
				"desired_local": _to_model_xz(lab.skeleton, intent["velocity"]),
				"frame_root_motion": state["frame_root_motion"],
				"clamp_events": state["clamp_events"],
			})

	var report := {
		"issue": 202,
		"mode": "live_root_space_motion_matching_proof",
		"proof": "continuous_analog_intent_independent_facing",
		"resolution": [CAPTURE_WIDTH, CAPTURE_HEIGHT],
		"frame_count": _frame_index,
		"simulated_seconds": PROOF_SECONDS,
		"proof_speeds_from_database": {"walk": _walk_speed, "strafe": _strafe_speed},
		"database": database.get_report(),
		"database_build": build.get("report", {}),
		"playback": controller.get_report(),
		"timeline": timeline,
	}
	_write_json_report(report)
	var playback := controller.get_report()
	print("[MM_CAPTURE] %d frames / %d switches (%d forced) / slide %.3f m/s -> %s" % [
		_frame_index, int(playback["switch_count"]), int(playback["forced_switch_count"]),
		float(playback["mean_contact_foot_slide_m_s"]), ProjectSettings.globalize_path(OUT_DIR),
	])
	quit(0)


## Analog stress program (world space). Facing either follows the velocity or
## is held, independently of the trajectory.
func _proof_intent(t: float, previous_facing: Vector3) -> Dictionary:
	var start_facing := Vector3.FORWARD
	var bent := start_facing.rotated(Vector3.UP, PI * 0.5)
	var reversed := -bent
	var pivoted := reversed.rotated(Vector3.UP, -PI * 0.5)
	var label := ""
	var velocity := Vector3.ZERO
	var facing := previous_facing
	var follow := true
	if t < 2.0:
		label = "idle"
	elif t < 4.0:
		label = "gradual acceleration"
		velocity = start_facing * _walk_speed * _smooth((t - 2.0) / 2.0)
	elif t < 6.0:
		label = "straight walk"
		velocity = start_facing * _walk_speed
	elif t < 9.0:
		label = "smooth bend left"
		velocity = start_facing.rotated(Vector3.UP, PI * 0.5 * _smooth((t - 6.0) / 3.0)) * _walk_speed
	elif t < 11.5:
		label = "lateral intent (strafe right, facing held)"
		follow = false
		facing = bent
		velocity = bent.rotated(Vector3.UP, -PI * 0.5) * _strafe_speed
	elif t < 13.5:
		label = "diagonal back-left (facing held)"
		follow = false
		facing = bent
		velocity = bent.rotated(Vector3.UP, PI * 0.75) * _strafe_speed
	elif t < 15.5:
		label = "sharp reversal (facing follows)"
		velocity = reversed * _walk_speed
	elif t < 17.5:
		label = "walk"
		velocity = reversed * _walk_speed
	elif t < 19.0:
		label = "deceleration"
		velocity = reversed * _walk_speed * (1.0 - _smooth((t - 17.5) / 1.5))
	elif t < 20.5:
		label = "stop"
	elif t < 21.5:
		label = "pivot 90 right in place"
		follow = false
		facing = pivoted
	elif t < 23.5:
		label = "restart"
		velocity = pivoted * _walk_speed * _smooth((t - 21.5) / 1.0)
	elif t < 25.0:
		label = "backward walk (facing held)"
		follow = false
		facing = pivoted
		velocity = -pivoted * _strafe_speed
	else:
		label = "stop"
	if follow and velocity.length() > 0.1:
		facing = velocity.normalized()
	return {"label": label, "velocity": velocity, "facing": facing}


func _to_model_xz(skeleton: Skeleton3D, world: Vector3) -> Array:
	var local := skeleton.global_transform.basis.orthonormalized().inverse() * world
	return [local.x, local.z]


func _flat_forward(skeleton: Skeleton3D) -> Array:
	var forward := skeleton.global_transform.basis * Vector3.BACK
	return [forward.x, forward.z]


func _smooth(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


## Median database speed within 30 degrees of a local direction (0 forward,
## PI/2 sideways); the proof asks only for speeds the real material contains.
func _median_speed(database: MotionDatabase, local_angle: float) -> float:
	var speeds: Array[float] = []
	for sample in range(database.get_sample_count()):
		var row := database.get_feature_row(sample)
		var velocity := Vector2(row[0], row[1])
		if velocity.length() < 0.45:
			continue
		var angle := absf(atan2(velocity.x, velocity.y))
		if absf(angle - local_angle) < deg_to_rad(30.0):
			speeds.append(velocity.length())
	if speeds.is_empty():
		return 0.8
	speeds.sort()
	return speeds[int(speeds.size() * 0.5)]


func _first_idle_sample(database: MotionDatabase) -> int:
	var best := 0
	var best_speed := INF
	for sample in range(database.get_sample_count()):
		if database.get_samples_to_range_end(sample) < 60:
			continue
		var row := database.get_feature_row(sample)
		var speed := Vector2(row[0], row[1]).length() + absf(row[2])
		if speed < best_speed:
			best_speed = speed
			best = sample
	return best


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
	# Keep the editor importer away from thousands of capture PNGs.
	FileAccess.open(OUT_DIR + "/.gdignore", FileAccess.WRITE)


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
