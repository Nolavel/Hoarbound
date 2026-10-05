extends SceneTree

## Captures issue #198's vertical tactile-grasp lab through the production TPS
## camera. The renderer may run slower than the requested movie rate on CI, so
## frame output is time-quantized: slow rendered frames are duplicated as needed
## and the ffmpeg 10 fps encode keeps the intended simulation duration.

const SCENE: String = "res://scenes/debug/embodied_interaction_lab.tscn"
const OUT_DIR: String = "res://docs/runtime_previews/embodied_interaction"
const FRAME_DIR: String = OUT_DIR + "/frames"
const WARMUP_SECONDS: float = 1.0
const CAPTURE_SECONDS: float = 27.0
const CAPTURE_FPS: int = 10

var _scene: Node
var _actor: EmbodiedInteractionLabActor
var _time: float = 0.0
var _capture_time: float = 0.0
var _frame_index: int = 0
var _frame_credit: float = 0.0
var _capturing: bool = false
var _hero_saved: bool = false
var _saved_pickup_cases: Dictionary = {}
var _handoff_saved: bool = false


func _initialize() -> void:
	Engine.max_fps = CAPTURE_FPS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FRAME_DIR))
	_scene = (load(SCENE) as PackedScene).instantiate()
	root.add_child(_scene)
	_actor = _scene.get_node("Henry") as EmbodiedInteractionLabActor
	_scene.process_mode = Node.PROCESS_MODE_DISABLED
	print("[EmbodiedCapture] warmup started")


func _process(delta: float) -> bool:
	_time += delta
	if not _capturing:
		if _time < WARMUP_SECONDS:
			return false
		_scene.process_mode = Node.PROCESS_MODE_INHERIT
		_capturing = true
		_capture_time = 0.0
		print("[EmbodiedCapture] capture started")
		return false

	_capture_time += delta
	_capture_time_quantized(delta)
	if not _hero_saved and _capture_time >= 2.0:
		root.get_texture().get_image().save_png(OUT_DIR + "/alignment_action.png")
		_hero_saved = true
	_capture_pickup_keyframe()
	_capture_handoff_keyframe()

	if _capture_time >= CAPTURE_SECONDS:
		_write_report()
		print("[EmbodiedCapture] frames=%d seconds=%.2f movie_seconds=%.2f" % [
			_frame_index, _capture_time, float(_frame_index) / float(CAPTURE_FPS)])
		quit()
	return false


func _capture_time_quantized(delta: float) -> void:
	_frame_credit += delta * float(CAPTURE_FPS)
	var copies: int = int(floor(_frame_credit))
	if copies <= 0:
		return
	_frame_credit -= float(copies)
	var image: Image = root.get_texture().get_image()
	for _copy: int in range(copies):
		image.save_png("%s/frame_%04d.png" % [FRAME_DIR, _frame_index])
		_frame_index += 1


func _capture_pickup_keyframe() -> void:
	if _actor == null or _actor.get_pickup_phase() != "CONTACT":
		return
	var case_index: int = _actor.get_pickup_case_index()
	if case_index < 0 or _saved_pickup_cases.has(case_index):
		return
	_saved_pickup_cases[case_index] = true
	root.get_texture().get_image().save_png("%s/pickup_case_%02d.png" % [OUT_DIR, case_index + 1])


func _capture_handoff_keyframe() -> void:
	if _actor == null or _handoff_saved or _actor.get_handoff_phase() != "CONTACT":
		return
	_handoff_saved = true
	root.get_texture().get_image().save_png(OUT_DIR + "/handoff_right_to_left.png")


func _write_report() -> void:
	var report: Dictionary = {
		"scene": SCENE,
		"frame_count": _frame_index,
		"capture_seconds": _capture_time,
		"movie_seconds": float(_frame_index) / float(CAPTURE_FPS),
		"requested_fps": CAPTURE_FPS,
		"pickup_keyframes": _saved_pickup_cases.size(),
		"handoff_keyframe": _handoff_saved,
		"proof": _actor.get_capture_report() if _actor != null else {},
	}
	var file := FileAccess.open(OUT_DIR + "/report.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
