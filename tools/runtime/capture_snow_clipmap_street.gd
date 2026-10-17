extends SceneTree

## Six-second visual proof for the current snow migration slice.
## Runs in the real Key West Reality world on open Duval Street. Henry only walks:
## the first three seconds use shallow settled snow and show deterministic sole
## prints; capture pauses off-camera, deepens the snow, then records three seconds
## of the continuous deep-wade/body-plough path. No sprint input is used.
##
## The exact snow depth changes along Duval while Henry walks. The shallow half uses
## the untouched production wade threshold. After the cover transition the harness
## measures the actual shallow/deep depths and, only for the recorded deep half,
## selects a threshold between them. report.json records that capture-only threshold
## alongside the production value so this cannot be mistaken for gameplay tuning.

const SCENE := "res://scenes/world/key_west/key_west_reality.tscn"
const STREET_DATA := "res://data/world/key_west/reality/routes/dev_street_spawns.json"
const STREET_NAME := "Duval Street"
const OUT := "res://docs/runtime_previews/key_west/snow_clipmap"
const CHUNK_M := 512.0
const SETTLE_FRAMES := 60
const POST_RECENTER_SETTLE_FRAMES := 12
const PHASE_SETTLE_FRAMES := 20
const MAX_WAIT_FRAMES := 600
const VIDEO_FRAMES := 72
const PHASE_FRAMES := VIDEO_FRAMES / 2
const VIDEO_FPS := 12
const SHALLOW_SETTLED := 0.25
const DEEP_SETTLED := 1.0
const MIN_PHASE_DEPTH_DELTA_M := 0.025
const REVIEW_PITCH_DEG := -13.0
const REVIEW_HOUR := 14.0
const MIN_WALK_DISTANCE_M := 1.5

var _world: Node3D
var _ctx: Variant
var _player: CharacterBody3D
var _camera: Camera3D
var _ground: Node
var _streaming: StreamingSystem
var _weather: WeatherController
var _day_night: DayNightManager
var _presentation: SnowPresentationSystem
var _shell: SnowShell
var _street_at := Vector2.ZERO
var _street_yaw := 0.0
var _frame_dir := ""
var _start := Vector3.ZERO
var _last_origin := Vector2(INF, INF)
var _recenter_count := 0
var _shallow_depth_m := 0.0
var _deep_depth_m := 0.0
var _capture_wade_depth_m := 0.0
var _production_wade_depth_m := 0.0


func _initialize() -> void:
	ProjectSettings.set_setting("hfn/graphics/quality", "high")
	ProjectSettings.set_setting("hfn/snow/quality", "high")
	ProjectSettings.set_setting("hfn/snow/clipmap_geometry", true)
	if not _load_street():
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_frame_dir = OUT.path_join("frames")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_frame_dir))
	_run()


func _run() -> void:
	var packed := load(SCENE) as PackedScene
	if packed == null:
		_fail("cannot load real Key West scene")
		return
	_world = packed.instantiate() as Node3D
	root.add_child(_world)

	for _i in range(360):
		await process_frame
		if _world.has_method(&"get_context"):
			_ctx = _world.call(&"get_context")
			if _ctx != null:
				break
	if _ctx == null:
		_fail("WorldContext did not become ready")
		return

	_player = _ctx.player as CharacterBody3D
	_camera = _ctx.camera as Camera3D
	_ground = _world.find_child("RealityGround", true, false)
	_streaming = _ctx.get_system(preload("res://core/world/streaming_system.gd")) as StreamingSystem
	_weather = _ctx.get_system(preload("res://scripts/systems/world/WeatherController.gd")) as WeatherController
	_presentation = _ctx.get_system(preload("res://scripts/systems/world/snow/snow_presentation_system.gd")) as SnowPresentationSystem
	_shell = SnowShell.active
	for node: Node in _world.find_children("*", "DayNightManager", true, false):
		_day_night = node as DayNightManager
		break
	if _player == null or _camera == null or _ground == null or _weather == null or _day_night == null or _presentation == null or _shell == null:
		_fail("missing player/camera/ground/weather/day-night/snow presentation/snow shell")
		return

	var surface := _shell.get_node_or_null("SnowShellMesh") as MeshInstance3D
	if surface == null or String(surface.get_meta(&"snow_geometry", "")) != "clipmap_l0_l1":
		_fail("production SnowShell did not install clipmap_l0_l1 geometry")
		return

	_production_wade_depth_m = _shell.wade_depth_m
	_capture_wade_depth_m = _production_wade_depth_m
	_hide_hud()
	_weather.set_weather(&"calm", true)
	_presentation.load_save_data({"settled": SHALLOW_SETTLED, "frost": 0.35, "storm": 0.4})
	_day_night.total_game_time_hours = floorf(_day_night.total_game_time_hours / 24.0) * 24.0 + REVIEW_HOUR
	_day_night.force_update_lighting()
	_day_night.set_process(false)
	_place()
	await _wait_until_streamed()
	_shell.recentre_to(Vector2(_player.global_position.x, _player.global_position.z))
	## Streaming already waited a full settle window. After the explicit recenter we
	## only need a short visual stabilization, otherwise lavapipe burns most of the
	## capture timeout rendering frames that never enter the six-second proof.
	await _wait_frames(POST_RECENTER_SETTLE_FRAMES)
	_camera.call(&"set_look", _street_yaw, REVIEW_PITCH_DEG)
	_camera.make_current()
	await _wait_frames(8)

	_shallow_depth_m = _depth_here()
	if _shallow_depth_m >= _production_wade_depth_m:
		_fail("shallow phase depth %.3f m reached production wade threshold %.3f m" % [_shallow_depth_m, _production_wade_depth_m])
		return

	_start = _player.global_position
	_last_origin = _shell.get_origin()
	_save_image(_capture_image(), OUT.path_join("start.png"))
	_press_walk_input()
	for i: int in range(PHASE_FRAMES):
		await _capture_frame(i)
	_release_motion_input()

	## Do not record the cover transition. Measure the actual depth at the point
	## reached by ordinary walking, then choose a capture-only threshold that cleanly
	## separates the already-recorded shallow half from the deep half.
	_presentation.load_save_data({"settled": DEEP_SETTLED, "frost": 0.35, "storm": 0.4})
	await _wait_frames(PHASE_SETTLE_FRAMES)
	_deep_depth_m = _depth_here()
	if _deep_depth_m <= _shallow_depth_m + MIN_PHASE_DEPTH_DELTA_M:
		_fail("deep phase %.3f m did not separate from shallow %.3f m by %.3f m" % [_deep_depth_m, _shallow_depth_m, MIN_PHASE_DEPTH_DELTA_M])
		return
	_capture_wade_depth_m = minf(_production_wade_depth_m, (_shallow_depth_m + _deep_depth_m) * 0.5)
	if not (_shallow_depth_m < _capture_wade_depth_m and _deep_depth_m > _capture_wade_depth_m):
		_fail("measured depths do not bracket capture threshold %.3f m (shallow %.3f, deep %.3f)" % [_capture_wade_depth_m, _shallow_depth_m, _deep_depth_m])
		return
	_shell.wade_depth_m = _capture_wade_depth_m
	await _wait_frames(4)

	_press_walk_input()
	for i: int in range(PHASE_FRAMES, VIDEO_FRAMES):
		await _capture_frame(i)
	_release_motion_input()
	await _wait_frames(3)

	var finish := _player.global_position
	var walked := Vector2(_start.x, _start.z).distance_to(Vector2(finish.x, finish.z))
	_save_image(_capture_image(), OUT.path_join("end.png"))
	_write_report(surface, walked)
	if walked < MIN_WALK_DISTANCE_M:
		_fail("Henry walked %.2f m; need %.2f m to prove ordinary gait motion" % [walked, MIN_WALK_DISTANCE_M])
		return
	## Recenter count is informational here. The clipmap topology/recenter contract is
	## covered elsewhere; this visual proof is specifically about gait and snow marks.
	print("SNOW_CLIPMAP_PREVIEW pass mode=walk frames=%d shallow=%.3fm deep=%.3fm capture_threshold=%.3fm production_threshold=%.3fm walk=%.2fm recenter=%d driver=%s" % [
		VIDEO_FRAMES, _shallow_depth_m, _deep_depth_m, _capture_wade_depth_m,
		_production_wade_depth_m, walked, _recenter_count,
		RenderingServer.get_current_rendering_driver_name()])
	quit(0)


func _capture_frame(index: int) -> void:
	await process_frame
	var origin: Vector2 = _shell.get_origin()
	if _last_origin.x != INF and not origin.is_equal_approx(_last_origin):
		_recenter_count += 1
	_last_origin = origin
	await RenderingServer.frame_post_draw
	_save_image(_capture_image(), _frame_dir.path_join("frame_%04d.png" % index))


func _press_walk_input() -> void:
	Input.action_release(&"sprint")
	Input.action_press(&"move_forward", 1.0)


func _depth_here() -> float:
	return _shell.field.get_depth(_player.global_position.x, _player.global_position.z)


func _load_street() -> bool:
	var file := FileAccess.open(STREET_DATA, FileAccess.READ)
	if file == null:
		_fail("cannot open %s" % STREET_DATA)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_fail("invalid street data JSON")
		return false
	for row: Variant in (parsed as Dictionary).get("streets", []):
		if row is Dictionary and String((row as Dictionary).get("name", "")) == STREET_NAME:
			var at: Array = (row as Dictionary).get("at", [])
			if at.size() < 2:
				break
			_street_at = Vector2(float(at[0]), float(at[1]))
			_street_yaw = deg_to_rad(float((row as Dictionary).get("heading_deg", 0.0)))
			return true
	_fail("street '%s' missing from %s" % [STREET_NAME, STREET_DATA])
	return false


func _hide_hud() -> void:
	for node: Node in _world.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false


func _place() -> void:
	var ground_y := _ground_height(_street_at.x, _street_at.y)
	_player.global_position = Vector3(_street_at.x, ground_y + 1.0, _street_at.y)
	_player.velocity = Vector3.ZERO
	_player.rotation.y = _street_yaw
	_player.reset_physics_interpolation()
	_camera.call(&"set_look", _street_yaw, REVIEW_PITCH_DEG)
	_camera.make_current()
	if _streaming != null:
		_streaming.scan(_player.global_position)


func _wait_until_streamed() -> void:
	if _streaming == null:
		await _wait_frames(SETTLE_FRAMES)
		return
	var active_at := -1
	for frame: int in range(MAX_WAIT_FRAMES + 1):
		var p := _player.global_position
		var own := StringName("kw_gen_%d_%d" % [floori(p.x / CHUNK_M), floori(p.z / CHUNK_M)])
		if active_at < 0 and _streaming.get_state(own) == StreamingSystem.CellState.ACTIVE:
			active_at = frame
			_place()
		if active_at >= 0 and frame - active_at >= SETTLE_FRAMES:
			return
		await process_frame
	push_warning("snow clipmap preview: stream wait hit %d-frame safety cap" % MAX_WAIT_FRAMES)


func _release_motion_input() -> void:
	for action: StringName in [&"move_forward", &"move_backward", &"move_left", &"move_right", &"sprint"]:
		Input.action_release(action)


func _ground_height(x: float, z: float) -> float:
	if _ground != null and _ground.has_method(&"get_height"):
		return float(_ground.call(&"get_height", x, z))
	return 0.0


func _wait_frames(count: int) -> void:
	for _i: int in range(count):
		await process_frame


func _capture_image() -> Image:
	return root.get_texture().get_image()


func _save_image(image: Image, path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	image.save_png(absolute)


func _write_report(surface: MeshInstance3D, walked: float) -> void:
	var arrays: Array = surface.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var report := {
		"scene": SCENE,
		"street": STREET_NAME,
		"renderer": RenderingServer.get_current_rendering_driver_name(),
		"geometry": String(surface.get_meta(&"snow_geometry", "")),
		"l0_half_m": float(surface.get_meta(&"snow_l0_half_m", 0.0)),
		"l0_spacing_m": float(surface.get_meta(&"snow_l0_spacing_m", 0.0)),
		"l1_spacing_m": float(surface.get_meta(&"snow_l1_spacing_m", 0.0)),
		"vertices": vertices.size(),
		"triangles": indices.size() / 3,
		"walk_distance_m": walked,
		"locomotion": "walk",
		"recenter_count": _recenter_count,
		"video_frames": VIDEO_FRAMES,
		"video_fps": VIDEO_FPS,
		"phase_frames": PHASE_FRAMES,
		"shallow_settled_snow": SHALLOW_SETTLED,
		"deep_settled_snow": DEEP_SETTLED,
		"shallow_depth_m": _shallow_depth_m,
		"deep_depth_m": _deep_depth_m,
		"capture_wade_depth_m": _capture_wade_depth_m,
		"production_wade_depth_m": _production_wade_depth_m,
		"settled_snow": _presentation.get_settled_snow(),
	}
	var file := FileAccess.open(OUT.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()


func _fail(message: String) -> void:
	_release_motion_input()
	push_error("SNOW_CLIPMAP_PREVIEW %s" % message)
	quit(1)
