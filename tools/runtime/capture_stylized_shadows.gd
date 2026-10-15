extends SceneTree

## Production regression for the stylized-shadow contract: matched physical/stylized
## Key West frames. `-- brush` compares spray masks; `-- shimmer` shifts the camera;
## `-- review` takes the author's review angles.

const MAIN_SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
const OUT_DIR: String = "res://docs/runtime_previews/stylized_shadows"
const BRUSH_OUT_DIR: String = "res://docs/runtime_previews/shadow_brush"
const SHIMMER_OUT_DIR: String = "res://docs/runtime_previews/shadow_shimmer"
const REVIEW_OUT_DIR: String = "res://docs/runtime_previews/shadow_review"
## Densest Duval Street block in the city snapshot: seven buildings within 25 m.
const DUVAL := Vector2(-3072.7, 1374.3)
const DUVAL_HEADING_DEG: float = 34.1
## Extra queue steps while a far placement streams its city chunks in.
const STREAM_WAIT_STEPS: int = 6
## About half a pixel on the ground 4-5 m ahead of the TPS camera.
const SHIMMER_SHIFT_M: float = 0.003
const BRUSH_MASKS: Dictionary[String, String] = {
	"dry": "res://assets/textures/shadows/shadow_brush_dry.png",
	"flat": "res://assets/textures/shadows/shadow_brush_flat.png",
}
const FIRST_ACTION_FRAME: int = 20
const SETTLE_FRAMES: int = 6
const GRADES: Array[StringName] = [&"HFN_ColdAsh_Day", &"HFN_ColdAsh_Dusk", &"HFN_ColdAsh_Night"]

var _scene: Node3D
var _player: Player
var _camera: TpsCamera
## Ground height source of the loaded world (Reality ground or legacy IslandTerrain).
var _ground: Node
## The shelter zone centre and the way out through its door, read from the scene.
var _shelter_xz: Vector2
var _outward: Vector2 = Vector2.UP
## Set by a placement: the next settle step stands Henry on the ground once it is live.
var _snap_pending: bool = false
var _settle_tries: int = 0
var _stove: HeatSource
var _grade: ColorGradeController
var _day_night: DayNightManager
var _weather: WeatherController
var _inside_camera: Camera3D
var _frame: int = 0
var _next_frame: int = FIRST_ACTION_FRAME
var _queue: Array[Callable] = []
var _saved: Array[String] = []
var _out_dir: String = OUT_DIR


func _initialize() -> void:
	var brush: bool = OS.get_cmdline_user_args().has("brush")
	var shimmer: bool = OS.get_cmdline_user_args().has("shimmer")
	var review: bool = OS.get_cmdline_user_args().has("review")
	if brush:
		_out_dir = BRUSH_OUT_DIR
	elif shimmer:
		_out_dir = SHIMMER_OUT_DIR
	elif review:
		_out_dir = REVIEW_OUT_DIR
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	RenderingServer.global_shader_parameter_set(&"stylized_shadow_strength", 1.0)
	_scene = (load(MAIN_SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	if brush:
		_queue = [
			_set_hour.bind(12.0),
			_place_outside,
			_brush_set.bind("01_outside_noon"),
			_frame_close.bind(Vector3(1.4, 0.5, 1.2)),
			_brush_set.bind("01b_outside_noon_close"),
			_place_inside,
			_brush_set.bind("02_inside_noon"),
		]
		return
	if shimmer:
		_queue = [_set_hour.bind(12.0), _place_outside, _freeze_motion, _shimmer_set]
		return
	if review:
		_queue = [
			_freeze_clock,
			_review.bind("05_normal_daylight", &"calm", 12.0, _place_outside),
			_review.bind("06_heavy_snow", &"blizzard", 12.0, _place_outside),
			_review.bind("07_city_street", &"calm", 12.0, _place_street),
			_review.bind("08_shelter_exterior", &"calm", 12.0, _place_outside.bind(11.0)),
			_review.bind("09_low_sun_1630", &"calm", 16.5, _place_outside),
		]
		return
	_queue = [
		_set_hour.bind(12.0),
		_place_outside,
		_pair.bind("01_outside_noon"),
		_frame_close.bind(Vector3(1.4, 0.5, 1.2)),
		_pair.bind("01b_outside_noon_close"),
		_place_inside,
		_pair.bind("02_inside_noon"),
		_set_hour.bind(23.0),
		_light_stove,
		_pair.bind("03_inside_stove_night"),
		_frame_close_stove,
		_pair.bind("03b_inside_stove_close"),
		_place_inside,
	]
	for grade: StringName in GRADES:
		_queue.append(_use_grade.bind(grade))
		_queue.append(_capture.bind("04_inside_stove_lut_%s" % String(grade).trim_prefix("HFN_ColdAsh_")))


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 8:
		_bind()
	if _frame > 80 and (_player == null or _ground == null or _stove == null):
		push_error("stylized shadow capture: production scene did not bind")
		quit(1)
		return true
	if _player == null or _ground == null or _stove == null or _frame < _next_frame:
		return false
	if _queue.is_empty():
		RenderingServer.global_shader_parameter_set(&"stylized_shadow_strength", 1.0)
		_write_report()
		print("[stylized-shadows] production regression capture complete")
		quit()
		return true
	var step: Callable = _queue.pop_front()
	step.call()
	_next_frame = _frame + SETTLE_FRAMES
	return false


func _bind() -> void:
	_player = get_first_node_in_group(&"player") as Player
	_camera = _scene.get_node_or_null(^"PlayerCamera") as TpsCamera
	_ground = CaptureWorldSupport.ground_of(_scene)
	var zone := _scene.find_child("ShelterZone", true, false) as Node3D
	if zone != null:
		_stove = zone.find_child("Stove", true, false) as HeatSource
		_shelter_xz = Vector2(zone.global_position.x, zone.global_position.z)
		var door := zone.find_child("Door", true, false) as Node3D
		if door != null:
			_outward = (Vector2(door.global_position.x, door.global_position.z) - _shelter_xz).normalized()
	for node: Node in _scene.find_children("*", "ColorGradeController", true, false):
		_grade = node as ColorGradeController
	for node: Node in _scene.find_children("*", "DayNightManager", true, false):
		_day_night = node as DayNightManager
	for node: Node in _scene.find_children("*", "WeatherController", true, false):
		_weather = node as WeatherController
	var splash := _scene.get_node_or_null(^"StartupTitleCard")
	if splash != null:
		splash.queue_free()
	if _player != null:
		_player.set_physics_process(false)


## Physical then stylized frame of the same view; the pair shares every other input.
func _pair(name: String) -> void:
	RenderingServer.global_shader_parameter_set(&"stylized_shadow_strength", 0.0)
	_queue.push_front(_capture.bind("%s_stylized" % name))
	_queue.push_front(RenderingServer.global_shader_parameter_set.bind(&"stylized_shadow_strength", 1.0))
	_queue.push_front(_capture.bind("%s_physical" % name))


## Physical, noise twice (frame-to-frame floor), then each brush mask, same view.
func _brush_set(name: String) -> void:
	var steps: Array[Callable] = [
		_set_spray.bind(0.0, "", 0.0),
		_capture.bind("%s_physical" % name),
		_set_spray.bind(1.0, "", 0.0),
		_capture.bind("%s_noise" % name),
		_capture.bind("%s_noise_repeat" % name),
	]
	for mask: String in BRUSH_MASKS:
		steps.append(_set_spray.bind(1.0, mask, 1.0))
		steps.append(_capture.bind("%s_%s" % [name, mask]))
	steps.append(_restore_spray)
	steps.reverse()
	for step: Callable in steps:
		_queue.push_front(step)


## Each spray from the TPS pose, then the same pose shifted sideways by SHIMMER_SHIFT_M.
func _shimmer_set() -> void:
	var camera := _capture_camera()
	camera.fov = _camera.fov
	camera.global_transform = _camera.global_transform
	camera.make_current()
	var base: Transform3D = camera.global_transform
	var shifted := base.translated(base.basis.x * SHIMMER_SHIFT_M)
	var steps: Array[Callable] = []
	for variant: Array in [["physical", 0.0, "", 0.0], ["noise", 1.0, "", 0.0], ["dry", 1.0, "dry", 1.0], ["flat", 1.0, "flat", 1.0]]:
		steps.append(_set_spray.bind(variant[1], variant[2], variant[3]))
		steps.append(camera.set_global_transform.bind(base))
		steps.append(_capture.bind("shimmer_%s_base" % variant[0]))
		steps.append(camera.set_global_transform.bind(shifted))
		steps.append(_capture.bind("shimmer_%s_shift" % variant[0]))
	steps.append(_restore_spray)
	steps.reverse()
	for step: Callable in steps:
		_queue.push_front(step)


## Only the camera may change between shimmer frames: clock, snowfall and Henry stop.
func _freeze_motion() -> void:
	if _day_night != null:
		_day_night.set_process(false)
	for node: Node in _scene.find_children("*", "SnowfallVFX", true, false):
		(node as Node3D).visible = false
	_player.process_mode = Node.PROCESS_MODE_DISABLED


## Back to the project's shipped spray: Shader Globals in project.godot.
func _restore_spray() -> void:
	for global_name: String in ["stylized_shadow_brush_mix", "stylized_shadow_brush_mask"]:
		var value: Variant = (ProjectSettings.get_setting("shader_globals/" + global_name) as Dictionary)["value"]
		RenderingServer.global_shader_parameter_set(global_name, load(value) if value is String else value)


func _set_spray(strength: float, mask: String, brush_mix: float) -> void:
	RenderingServer.global_shader_parameter_set(&"stylized_shadow_strength", strength)
	RenderingServer.global_shader_parameter_set(&"stylized_shadow_brush_mix", brush_mix)
	if not mask.is_empty():
		RenderingServer.global_shader_parameter_set(&"stylized_shadow_brush_mask", load(BRUSH_MASKS[mask]))


func _set_hour(hour: float) -> void:
	if _day_night != null:
		_day_night.total_game_time_hours = floorf(_day_night.total_game_time_hours / 24.0) * 24.0 + hour


func _place_outside(distance: float = 26.0) -> void:
	var at: Vector2 = _shelter_xz + _outward * distance
	_player.global_position = Vector3(at.x, CaptureWorldSupport.height(_scene, at.x, at.y) + 1.0, at.y)
	_snap_pending = true
	_queue.push_front(_stream_settle)
	var direction := (_shelter_xz - at).normalized()
	var yaw: float = atan2(direction.x, direction.y) + PI
	_player.global_rotation.y = yaw
	if _camera != null:
		_camera.set_look(yaw, _camera.start_pitch_deg)
	var streaming := _find_streaming()
	if streaming != null:
		streaming.scan(_player.global_position)


## Henry walks up Duval Street, the camera looking along it.
func _place_street() -> void:
	_player.global_position = Vector3(DUVAL.x, CaptureWorldSupport.height(_scene, DUVAL.x, DUVAL.y) + 1.0, DUVAL.y)
	_snap_pending = true
	_queue.push_front(_stream_settle)
	var yaw: float = deg_to_rad(DUVAL_HEADING_DEG) + PI
	_player.global_rotation.y = yaw
	if _camera != null:
		_camera.set_look(yaw, _camera.start_pitch_deg)
	var streaming := _find_streaming()
	if streaming != null:
		streaming.scan(_player.global_position)


## Weather, hour and place for one review angle, then a physical/stylized pair once the
## city has streamed in. The clock is frozen, so both frames share one sun.
func _review(name: String, weather: StringName, hour: float, place: Callable) -> void:
	if _weather != null:
		_weather.set_weather(weather, true)
	_set_hour(hour)
	if _day_night != null:
		_day_night.force_update_lighting()
	place.call()
	_queue.push_front(_pair.bind(name))
	_queue.push_front(_stream_settle)
	for i: int in STREAM_WAIT_STEPS:
		_queue.push_front(func() -> void: pass)


func _freeze_clock() -> void:
	if _day_night != null:
		_day_night.set_process(false)
	_player.process_mode = Node.PROCESS_MODE_DISABLED


## Henry stands at the stove door (stove local +X); a fixed camera across the room
## frames him and the floor his stove shadow falls on.
func _place_inside() -> void:
	_player.global_position = _stove.to_global(Vector3(1.1, 1.0, 0.35))
	_player.global_rotation.y = _stove.global_rotation.y + PI * 0.5
	_capture_camera()
	_inside_camera.global_position = _stove.to_global(Vector3(4.6, 1.7, 4.5))
	_inside_camera.look_at(_stove.to_global(Vector3(1.6, 0.2, 0.2)), Vector3.UP)
	_inside_camera.make_current()
	_queue.push_front(_stream_settle)


## Holds the queue until Henry's chunk is live and the streamer quiet, then stands him on the ground if a
## placement asked for it (Reality streams; on the legacy island this passes at once).
func _stream_settle() -> void:
	var xz := Vector2(_player.global_position.x, _player.global_position.z)
	if not CaptureWorldSupport.is_settled(_scene, xz) and _settle_tries < 1000:
		_settle_tries += 1
		_queue.push_front(_stream_settle)
		return
	if _settle_tries >= 1000:
		push_warning("stylized shadow capture: Henry's chunk did not stream in")
	_settle_tries = 0
	if _snap_pending:
		_snap_pending = false
		_player.global_position.y = CaptureWorldSupport.height(_scene, xz.x, xz.y) + 1.0


## Close camera on Henry's torso from an offset in his own frame (x right, z behind).
func _frame_close(offset: Vector3) -> void:
	var camera := _capture_camera()
	camera.global_position = _player.global_transform * offset
	camera.look_at(_player.global_position + Vector3(0.0, 0.25, 0.0), Vector3.UP)
	camera.make_current()


## Henry between the camera and the stove: the stove light rims his silhouette.
func _frame_close_stove() -> void:
	var camera := _capture_camera()
	camera.global_position = _stove.to_global(Vector3(2.7, 1.45, 0.75))
	camera.look_at(_player.global_position + Vector3(0.0, 0.2, 0.0), Vector3.UP)
	camera.make_current()


func _capture_camera() -> Camera3D:
	if _inside_camera == null:
		_inside_camera = Camera3D.new()
		_inside_camera.fov = 62.0
		if _camera != null:
			_inside_camera.cull_mask = _camera.cull_mask
		_scene.add_child(_inside_camera)
	return _inside_camera


func _light_stove() -> void:
	_stove.restore_fuel(1.5, true)
	_stove.ignite()


func _use_grade(grade: StringName) -> void:
	## Presentation-only swap of the LUT while Henry stays inside.
	if _grade == null:
		return
	var profile: ColorGradeProfile = _grade.get(StringName(String(grade).trim_prefix("HFN_ColdAsh_").to_lower() + "_profile"))
	var environment: Environment = _grade.world_environment.environment
	environment.adjustment_color_correction = profile.lut
	environment.adjustment_brightness = profile.brightness
	environment.adjustment_contrast = profile.contrast
	environment.adjustment_saturation = profile.saturation


func _find_streaming() -> StreamingSystem:
	for node: Node in _scene.get_children():
		if node is StreamingSystem:
			return node as StreamingSystem
	return null


func _capture(name: String) -> void:
	var image := root.get_texture().get_image()
	if image == null:
		push_error("stylized shadow capture: viewport image is null")
		quit(1)
		return
	var path := "%s/%s.png" % [_out_dir, name]
	var error := image.save_png(path)
	if error != OK:
		push_error("stylized shadow capture: save failed %s" % error)
		quit(1)
		return
	_saved.append(name)
	print("[stylized-shadows] saved ", path, " grade=", _grade.get_current_profile_id() if _grade != null else &"")


func _write_report() -> void:
	var report := {
		"scene": MAIN_SCENE,
		"frames": _saved,
		"contract": "torn shadow lookup for all lights + three-tone directional shadow",
	}
	var file := FileAccess.open("%s/report.json" % _out_dir, FileAccess.WRITE)
	if file == null:
		push_error("stylized shadow capture: cannot write report (%s)" % FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
