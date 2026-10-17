extends SceneTree

## Phase 3.1 proof for the production snow clipmap.
## The video uses the real third-person camera. Two fixed-camera stills observe the
## same untouched world patch before/after several recenter events, and two low-Y
## close-ups show a planted boot settling into the deformed surface.

const SCENE := "res://scenes/world/key_west/key_west_reality.tscn"
const STREET_DATA := "res://data/world/key_west/reality/routes/dev_street_spawns.json"
const STREET_NAME := "Duval Street"
const OUT := "res://docs/runtime_previews/key_west/snow_clipmap"
const CHUNK_M := 512.0
const SETTLE_FRAMES := 60
const POST_RECENTER_SETTLE_FRAMES := 6
const MAX_WAIT_FRAMES := 600
const VIDEO_FRAMES := 72
const VIDEO_FPS := 12
const REVIEW_HOUR := 14.0
const SEAM_SETTLED := 0.25
const MIN_WALK_DISTANCE_M := 8.0
const MIN_RECENTERS := 5
const MAX_RECENTERS := 10
const TPS_PITCH_DEG := -12.0

var _world: Node3D
var _ctx: Variant
var _player: CharacterBody3D
var _camera: Camera3D
var _fixed_camera: Camera3D
var _foot_camera: Camera3D
var _ground: Node
var _streaming: StreamingSystem
var _weather: WeatherController
var _day_night: DayNightManager
var _presentation: SnowPresentationSystem
var _shell: SnowShell
var _mover: MovementController
var _street_at := Vector2.ZERO
var _street_yaw := 0.0
var _frame_dir := ""
var _start := Vector3.ZERO
var _last_origin := Vector2(INF, INF)
var _recenter_count := 0
var _foot_sink_samples: Array[float] = []


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
	_mover = _player.get_node_or_null(^"MovementController") as MovementController if _player != null else null
	for node: Node in _world.find_children("*", "DayNightManager", true, false):
		_day_night = node as DayNightManager
		break
	if _player == null or _camera == null or _ground == null or _weather == null or _day_night == null or _presentation == null or _shell == null or _mover == null:
		_fail("missing player/camera/ground/weather/day-night/snow presentation/snow shell/movement")
		return

	var surface := _shell.get_node_or_null("SnowShellMesh") as MeshInstance3D
	if surface == null or String(surface.get_meta(&"snow_geometry", "")) != "clipmap_l0_l1":
		_fail("production SnowShell did not install clipmap_l0_l1 geometry")
		return

	_hide_hud()
	_weather.set_weather(&"calm", true)
	_presentation.load_save_data({"settled": SEAM_SETTLED, "frost": 0.35, "storm": 0.4})
	_day_night.total_game_time_hours = floorf(_day_night.total_game_time_hours / 24.0) * 24.0 + REVIEW_HOUR
	_day_night.force_update_lighting()
	_day_night.set_process(false)
	_place()
	await _wait_until_streamed()
	_shell.recentre_to(Vector2(_player.global_position.x, _player.global_position.z))
	await _wait_frames(POST_RECENTER_SETTLE_FRAMES)

	## Production TPS is the primary acceptance view, not the old overhead seam camera.
	if _camera.has_method(&"set_look"):
		_camera.call(&"set_look", _street_yaw, TPS_PITCH_DEG)
	_camera.make_current()
	await _wait_frames(2)

	_start = _player.global_position
	_last_origin = _shell.get_origin()
	_build_fixed_camera(_start)
	await _capture_with_camera(_fixed_camera, OUT.path_join("handoff_fixed_before.png"))
	_camera.make_current()
	await RenderingServer.frame_post_draw
	_save_image(_capture_image(), OUT.path_join("start.png"))

	_press_walk_input()
	for i: int in range(VIDEO_FRAMES):
		await _capture_tps_frame(i)
	_release_motion_input()
	_player.velocity = Vector3.ZERO
	await _wait_frames(1)

	var finish := _player.global_position
	var walked := Vector2(_start.x, _start.z).distance_to(Vector2(finish.x, finish.z))
	_camera.make_current()
	await RenderingServer.frame_post_draw
	_save_image(_capture_image(), OUT.path_join("end.png"))

	## Same world-space patch, same camera and frozen lighting. It begins inside the
	## local window and ends behind it, so any ownership-induced visual rewrite is obvious.
	await _capture_with_camera(_fixed_camera, OUT.path_join("handoff_fixed_after.png"))

	## Low-Y side view: two real rendered moments while the stopped stance settles.
	_build_foot_camera()
	await _capture_foot_y(OUT.path_join("foot_y_contact.png"))
	await _wait_frames(2)
	await _capture_foot_y(OUT.path_join("foot_y_pressed.png"))
	_camera.make_current()

	_write_report(surface, walked)
	if walked < MIN_WALK_DISTANCE_M:
		_fail("Henry traversed %.2f m; need %.2f m for TPS seam proof" % [walked, MIN_WALK_DISTANCE_M])
		return
	if _recenter_count < MIN_RECENTERS or _recenter_count > MAX_RECENTERS:
		_fail("TPS proof observed %d recenter events; expected %d..%d" % [_recenter_count, MIN_RECENTERS, MAX_RECENTERS])
		return
	print("SNOW_CLIPMAP_PHASE31 pass frames=%d settled=%.2f traverse=%.2fm recenter=%d step=%.2fm walk=%.2f driver=%s" % [
		VIDEO_FRAMES, SEAM_SETTLED, walked, _recenter_count, _shell.recentre_step_m,
		_mover.walk_speed, RenderingServer.get_current_rendering_driver_name()])
	quit(0)


func _capture_tps_frame(index: int) -> void:
	await process_frame
	var origin: Vector2 = _shell.get_origin()
	if _last_origin.x != INF and not origin.is_equal_approx(_last_origin):
		_recenter_count += 1
	_last_origin = origin
	_camera.make_current()
	await RenderingServer.frame_post_draw
	_save_image(_capture_image(), _frame_dir.path_join("frame_%04d.png" % index))


func _build_fixed_camera(start: Vector3) -> void:
	_fixed_camera = Camera3D.new()
	_fixed_camera.name = "SnowHandoffFixedCamera"
	_fixed_camera.fov = 58.0
	_fixed_camera.near = 0.08
	_fixed_camera.far = 180.0
	_world.add_child(_fixed_camera)
	var forward: Vector3 = Basis(Vector3.UP, _street_yaw) * Vector3.FORWARD
	var right: Vector3 = forward.cross(Vector3.UP).normalized()
	## Untouched patch: local at the start, outer cover after the traversal.
	var patch := start - forward * 5.0 + right * 4.0
	var ground_y := _ground_height(patch.x, patch.z)
	var target := Vector3(patch.x, ground_y + 0.08, patch.z)
	_fixed_camera.global_position = target - forward * 5.0 - right * 5.5 + Vector3.UP * 5.0
	_fixed_camera.look_at(target, Vector3.UP)


func _build_foot_camera() -> void:
	_foot_camera = Camera3D.new()
	_foot_camera.name = "SnowFootYCamera"
	_foot_camera.fov = 34.0
	_foot_camera.near = 0.03
	_foot_camera.far = 20.0
	_world.add_child(_foot_camera)
	_update_foot_camera()


func _update_foot_camera() -> void:
	if _foot_camera == null or _player == null:
		return
	var forward: Vector3 = Basis(Vector3.UP, _street_yaw) * Vector3.FORWARD
	var right: Vector3 = forward.cross(Vector3.UP).normalized()
	var p := _player.global_position
	var ground_y := _ground_height(p.x, p.z)
	var target := Vector3(p.x, ground_y + 0.16, p.z)
	_foot_camera.global_position = target + right * 1.15 - forward * 0.18 + Vector3.UP * 0.08
	_foot_camera.look_at(target, Vector3.UP)


func _capture_foot_y(path: String) -> void:
	_update_foot_camera()
	_foot_camera.make_current()
	await process_frame
	await RenderingServer.frame_post_draw
	_save_image(_capture_image(), path)
	_foot_sink_samples.append(maxf(_shell.get_foot_sink(0), _shell.get_foot_sink(1)))


func _capture_with_camera(camera: Camera3D, path: String) -> void:
	camera.make_current()
	await process_frame
	await RenderingServer.frame_post_draw
	_save_image(_capture_image(), path)


func _press_walk_input() -> void:
	Input.action_release(&"sprint")
	Input.action_release(&"move_left")
	Input.action_release(&"move_right")
	Input.action_release(&"move_backward")
	Input.action_press(&"move_forward", 1.0)


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
	push_warning("snow Phase 3.1 preview: stream wait hit %d-frame safety cap" % MAX_WAIT_FRAMES)


func _release_motion_input() -> void:
	for action: StringName in [&"move_forward", &"move_backward", &"move_left", &"move_right", &"sprint"]:
		Input.action_release(action)


func _ground_height(x: float, z: float) -> float:
	if _ground != null and _ground.has_method(&"get_height"):
		return float(_ground.call(&"get_height", x, z))
	return 0.0


func _wait_frames(count: int) -> void:
	for _i in range(count):
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
		"diagnostic": "snow Phase 3.1 TPS recenter and Y-foot proof",
		"scene": SCENE,
		"street": STREET_NAME,
		"renderer": RenderingServer.get_current_rendering_driver_name(),
		"geometry": String(surface.get_meta(&"snow_geometry", "")),
		"l0_half_m": float(surface.get_meta(&"snow_l0_half_m", 0.0)),
		"l0_spacing_m": float(surface.get_meta(&"snow_l0_spacing_m", 0.0)),
		"l1_spacing_m": float(surface.get_meta(&"snow_l1_spacing_m", 0.0)),
		"recentre_step_m": _shell.recentre_step_m,
		"outer_step_m": SnowChunkCover.STEP_M,
		"vertices": vertices.size(),
		"triangles": indices.size() / 3,
		"traverse_distance_m": walked,
		"locomotion": "production_walk",
		"walk_speed_mps": _mover.walk_speed,
		"recenter_count": _recenter_count,
		"required_recenter_range": [MIN_RECENTERS, MAX_RECENTERS],
		"video_frames": VIDEO_FRAMES,
		"video_fps": VIDEO_FPS,
		"video_camera": "production_tps",
		"settled_snow": SEAM_SETTLED,
		"fixed_handoff_pair": ["handoff_fixed_before.png", "handoff_fixed_after.png"],
		"foot_y_captures": ["foot_y_contact.png", "foot_y_pressed.png"],
		"foot_sink_samples_m": _foot_sink_samples,
	}
	var file := FileAccess.open(OUT.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()


func _fail(message: String) -> void:
	_release_motion_input()
	push_error("SNOW_CLIPMAP_PHASE31 %s" % message)
	quit(1)
