extends SceneTree

## Deterministic Phase 1 capture for issue #201. The lab is scene-authored; this
## driver only feeds movement queries and records what the real viewport renders.

const SCENE_PATH := "res://tests/motion_matching/motion_matching_lab.tscn"
const OUT_DIR := "res://docs/runtime_previews/motion_matching_lab"
const FRAME_DIR := OUT_DIR + "/frames"
const CAPTURE_WIDTH := 1280
const CAPTURE_HEIGHT := 720
const PHYSICS_STEPS_PER_FRAME := 2

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


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
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

	_prepare_output()
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
			await _capture_frame(String(segment["label"]), segment_index, save_keyframe)
		_report_segments.append({
			"label": String(segment["label"]),
			"input": [input_vector.x, input_vector.y],
			"snapshot": _henry.get_debug_snapshot(),
		})

	_henry.set_capture_input(Vector2.ZERO)
	await _write_report()
	print("[MOTION_MATCHING_CAPTURE] %d frames written to %s" % [_frame_index, ProjectSettings.globalize_path(OUT_DIR)])
	quit(0)


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


func _write_report() -> void:
	var report := {
		"issue": 201,
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
	var file := FileAccess.open(OUT_DIR + "/report.json", FileAccess.WRITE)
	if file == null:
		push_error("MotionMatchingCapture: cannot write report.json")
		return
	file.store_string(JSON.stringify(report, "\t"))
