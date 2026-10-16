extends SceneTree

## Dual-LUT blend review videos (5 s shelter + 5 s outdoor LUT chain).

const SCENE: String = "res://tests/scenes/TestScene.tscn"
const OUT_ROOT: String = "res://docs/runtime_previews/color_grade_blend"
const FPS: int = 30
const SHELTER_SECONDS: float = 5.0
const OUTDOOR_SEGMENT_SECONDS: float = 5.0 / 3.0
const PREPARE_FRAMES: int = 40
const OUTDOOR_STEPS: Array[Dictionary] = [
	{"from": &"HFN_ColdAsh_Day", "to": &"HFN_ColdAsh_Dusk"},
	{"from": &"HFN_ColdAsh_Dusk", "to": &"HFN_ColdAsh_Night"},
	{"from": &"HFN_ColdAsh_Night", "to": &"HFN_ColdAsh_Day"},
]

var _scene: Node
var _grade: ColorGradeController
var _manager: DayNightManager
var _player: Node3D
var _frame: int = 0
var _phase: StringName = &"prepare"
var _phase_frame: int = 0
var _outdoor_step: int = 0
var _shelter_dir: String
var _outdoor_dir: String
var _shelter_written: int = 0
var _outdoor_written: int = 0

func _initialize() -> void:
	var packed := load(SCENE) as PackedScene
	if packed == null:
		push_error("color grade blend capture: TestScene missing")
		quit(1)
		return
	_scene = packed.instantiate()
	root.add_child(_scene)
	_shelter_dir = ProjectSettings.globalize_path(OUT_ROOT.path_join("shelter_5s"))
	_outdoor_dir = ProjectSettings.globalize_path(OUT_ROOT.path_join("outdoor_luts_5s"))
	DirAccess.make_dir_recursive_absolute(_shelter_dir)
	DirAccess.make_dir_recursive_absolute(_outdoor_dir)

func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		&"prepare":
			if _frame < PREPARE_FRAMES:
				return false
			if not _wire():
				quit(1)
				return true
			_grade.shelter_blend_s = SHELTER_SECONDS
			_grade.time_blend_s = OUTDOOR_SEGMENT_SECONDS
			_grade.initialize_for_interior(false)
			_manager.total_game_time_hours = 12.0
			_manager._force_update_visuals()
			_grade.use_outdoor_profile()
			_place_outside()
			_phase = &"shelter"
			_phase_frame = 0
			_grade.initialize_for_interior(true)
			return false
		&"shelter":
			_grab(_shelter_dir, _shelter_written)
			_shelter_written += 1
			_phase_frame += 1
			if _phase_frame >= int(SHELTER_SECONDS * FPS):
				_grade.initialize_for_interior(false)
				_phase = &"outdoor"
				_phase_frame = 0
				_outdoor_step = 0
				_start_outdoor_step(0)
			return false
		&"outdoor":
			_grab(_outdoor_dir, _outdoor_written)
			_outdoor_written += 1
			_phase_frame += 1
			var segment_frames: int = maxi(1, int(OUTDOOR_SEGMENT_SECONDS * FPS))
			if _phase_frame >= segment_frames:
				_outdoor_step += 1
				_phase_frame = 0
				if _outdoor_step >= OUTDOOR_STEPS.size():
					_encode_videos()
					print("color grade blend capture: done shelter=%d outdoor=%d" % [_shelter_written, _outdoor_written])
					quit(0)
					return true
				_start_outdoor_step(_outdoor_step)
			return false
	return false

func _wire() -> bool:
	_grade = _scene.find_child("ColorGradeController", true, false) as ColorGradeController
	_manager = _scene.find_child("DayNightManager", true, false) as DayNightManager
	_player = _scene.find_child("Player", true, false) as Node3D
	if _grade == null or _manager == null:
		push_error("color grade blend capture: grade or day/night missing")
		return false
	_manager.set_process(false)
	return true

func _place_outside() -> void:
	if _player != null:
		_player.global_position = Vector3(10.0, 1.0, 0.0)

func _start_outdoor_step(index: int) -> void:
	_place_outside()
	var step: Dictionary = OUTDOOR_STEPS[index]
	_grade.blend_outdoor_profiles(step["from"] as StringName, step["to"] as StringName, OUTDOOR_SEGMENT_SECONDS)

func _grab(directory: String, index: int) -> void:
	var path: String = "%s/frame_%04d.png" % [directory, index]
	var img: Image = get_root().get_viewport().get_texture().get_image()
	if img == null:
		return
	img.save_png(path)

func _encode_videos() -> void:
	_ffmpeg(_shelter_dir, "shelter_outdoor_to_inside_5s.mp4")
	_ffmpeg(_outdoor_dir, "outdoor_day_dusk_night_5s.mp4")

func _ffmpeg(frame_dir: String, filename: String) -> void:
	var out_path: String = ProjectSettings.globalize_path(OUT_ROOT.path_join(filename))
	var args: PackedStringArray = ["-y", "-framerate", str(FPS), "-i", "%s/frame_%%04d.png" % frame_dir, "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "20", out_path]
	var output: Array = []
	var code: int = OS.execute("ffmpeg", args, output, true)
	if code != 0:
		push_warning("ffmpeg failed for %s" % filename)
	else:
		print("wrote %s" % out_path)
