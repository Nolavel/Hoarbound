extends SceneTree

## Seam-focused visual proof for the snow clipmap migration.
## Reuses the real Key West Reality scene and existing snow preview workflow.
## A wide chase/overhead camera keeps the local SnowShell and streamed outer snow
## visible while Henry traverses open Duval Street. The capture temporarily doubles
## walk speed so 72 Lavapipe frames cross 5-10 production recenter boundaries without
## doubling render time. Production movement values are restored before exit and
## recorded alongside the capture-only value in report.json.
## Final diagnostic: L0 red, stitch yellow, L1 blue, streamed outer green.

const SCENE := "res://scenes/world/key_west/key_west_reality.tscn"
const STREET_DATA := "res://data/world/key_west/reality/routes/dev_street_spawns.json"
const STREET_NAME := "Duval Street"
const OUT := "res://docs/runtime_previews/key_west/snow_clipmap"
const CHUNK_M := 512.0
const SETTLE_FRAMES := 60
const POST_RECENTER_SETTLE_FRAMES := 12
const MAX_WAIT_FRAMES := 600
const VIDEO_FRAMES := 72
const VIDEO_FPS := 12
const REVIEW_HOUR := 14.0
const SEAM_SETTLED := 0.25
const CAPTURE_WALK_SPEED_MPS := 3.0
const MIN_WALK_DISTANCE_M := 10.0
const MIN_RECENTERS := 5
const MAX_RECENTERS := 10

var _world: Node3D
var _ctx: Variant
var _player: CharacterBody3D
var _camera: Camera3D
var _review_camera: Camera3D
var _ground: Node
var _streaming: StreamingSystem
var _weather: WeatherController
var _day_night: DayNightManager
var _presentation: SnowPresentationSystem
var _shell: SnowShell
var _mover: MovementController
var _production_walk_speed_mps := 0.0
var _street_at := Vector2.ZERO
var _street_yaw := 0.0
var _frame_dir := ""
var _start := Vector3.ZERO
var _last_origin := Vector2(INF, INF)
var _recenter_count := 0


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

	_production_walk_speed_mps = _mover.walk_speed
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
	_build_review_camera()
	await _wait_frames(4)

	_start = _player.global_position
	_last_origin = _shell.get_origin()
	_save_image(_capture_image(), OUT.path_join("start.png"))
	_mover.walk_speed = CAPTURE_WALK_SPEED_MPS
	_press_walk_input()
	for i: int in range(VIDEO_FRAMES):
		await _capture_frame(i)
	_release_motion_input()
	_mover.walk_speed = _production_walk_speed_mps
	await _wait_frames(3)

	var finish := _player.global_position
	var walked := Vector2(_start.x, _start.z).distance_to(Vector2(finish.x, finish.z))
	_update_review_camera()
	_save_image(_capture_image(), OUT.path_join("end.png"))

	_set_lod_debug(surface, true)
	await _wait_frames(2)
	_update_review_camera()
	await RenderingServer.frame_post_draw
	_save_image(_capture_image(), OUT.path_join("lod_ownership.png"))
	_set_lod_debug(surface, false)
	_write_report(surface, walked)

	if walked < MIN_WALK_DISTANCE_M:
		_fail("Henry traversed %.2f m; need %.2f m for seam proof" % [walked, MIN_WALK_DISTANCE_M])
		return
	if _recenter_count < MIN_RECENTERS or _recenter_count > MAX_RECENTERS:
		_fail("seam proof observed %d recenter events; expected %d..%d" % [_recenter_count, MIN_RECENTERS, MAX_RECENTERS])
		return
	print("SNOW_CLIPMAP_SEAM pass frames=%d settled=%.2f traverse=%.2fm recenter=%d production_walk=%.2f capture_walk=%.2f driver=%s" % [
		VIDEO_FRAMES, SEAM_SETTLED, walked, _recenter_count, _production_walk_speed_mps,
		CAPTURE_WALK_SPEED_MPS, RenderingServer.get_current_rendering_driver_name()])
	quit(0)


func _capture_frame(index: int) -> void:
	await process_frame
	var origin: Vector2 = _shell.get_origin()
	if _last_origin.x != INF and not origin.is_equal_approx(_last_origin):
		_recenter_count += 1
	_last_origin = origin
	_update_review_camera()
	await RenderingServer.frame_post_draw
	_save_image(_capture_image(), _frame_dir.path_join("frame_%04d.png" % index))


func _build_review_camera() -> void:
	_review_camera = Camera3D.new()
	_review_camera.name = "SnowSeamReviewCamera"
	_review_camera.fov = 70.0
	_review_camera.near = 0.1
	_review_camera.far = 400.0
	_world.add_child(_review_camera)
	_review_camera.make_current()
	_update_review_camera()


func _update_review_camera() -> void:
	if _review_camera == null or _player == null:
		return
	var forward: Vector3 = Basis(Vector3.UP, _street_yaw) * Vector3.FORWARD
	var right: Vector3 = forward.cross(Vector3.UP).normalized()
	var target: Vector3 = _player.global_position + forward * 1.5
	_review_camera.global_position = target - forward * 17.0 + right * 5.0 + Vector3.UP * 19.0
	_review_camera.look_at(target, Vector3.UP)


func _press_walk_input() -> void:
	Input.action_release(&"sprint")
	Input.action_release(&"move_left")
	Input.action_release(&"move_right")
	Input.action_release(&"move_backward")
	Input.action_press(&"move_forward", 1.0)


func _set_lod_debug(surface: MeshInstance3D, enabled: bool) -> void:
	var local_mat := surface.material_override as ShaderMaterial
	if local_mat != null:
		local_mat.set_shader_parameter("debug_lod_ownership", enabled)
		local_mat.set_shader_parameter("debug_l0_half_m", float(surface.get_meta(&"snow_l0_half_m", 3.84)))
		local_mat.set_shader_parameter(
			"debug_l1_transition_m",
			float(surface.get_meta(&"snow_l0_half_m", 3.84)) + float(surface.get_meta(&"snow_l1_spacing_m", 0.16))
		)
	for node: Node in _world.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null or mesh_instance.mesh.get_surface_count() == 0:
			continue
		var material := mesh_instance.get_active_material(0) as ShaderMaterial
		if material == null or material.shader == null:
			continue
		if material.shader.resource_path.ends_with("snow_chunk_cover.gdshader"):
			material.set_shader_parameter("debug_lod_ownership", enabled)


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
	push_warning("snow clipmap seam preview: stream wait hit %d-frame safety cap" % MAX_WAIT_FRAMES)


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
		"diagnostic": "snow clipmap seam and recenter proof",
		"scene": SCENE,
		"street": STREET_NAME,
		"renderer": RenderingServer.get_current_rendering_driver_name(),
		"geometry": String(surface.get_meta(&"snow_geometry", "")),
		"l0_half_m": float(surface.get_meta(&"snow_l0_half_m", 0.0)),
		"l0_spacing_m": float(surface.get_meta(&"snow_l0_spacing_m", 0.0)),
		"l1_spacing_m": float(surface.get_meta(&"snow_l1_spacing_m", 0.0)),
		"outer_step_m": SnowChunkCover.STEP_M,
		"vertices": vertices.size(),
		"triangles": indices.size() / 3,
		"traverse_distance_m": walked,
		"locomotion": "capture_only_fast_walk",
		"production_walk_speed_mps": _production_walk_speed_mps,
		"capture_walk_speed_mps": CAPTURE_WALK_SPEED_MPS,
		"recenter_count": _recenter_count,
		"required_recenter_range": [MIN_RECENTERS, MAX_RECENTERS],
		"video_frames": VIDEO_FRAMES,
		"video_fps": VIDEO_FPS,
		"settled_snow": SEAM_SETTLED,
		"review_camera": "wide_follow_keeps_l0_l1_outer_handoff_visible",
		"lod_debug_capture": "lod_ownership.png",
		"lod_debug_legend": {"L0": "red", "transition": "yellow", "L1": "blue", "outer": "green"},
		"foot_pin_reach_m": 0.34,
	}
	var file := FileAccess.open(OUT.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()


func _fail(message: String) -> void:
	_release_motion_input()
	if _mover != null and _production_walk_speed_mps > 0.0:
		_mover.walk_speed = _production_walk_speed_mps
	push_error("SNOW_CLIPMAP_SEAM %s" % message)
	quit(1)
