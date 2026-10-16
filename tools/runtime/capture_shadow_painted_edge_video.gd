extends SceneTree

## Six-second moving A/B for the stock-Godot stylized-shadow experiment.
## Baseline keeps the shipped dry-brush three-tone path. Painted removes the hard
## tone cut, uses one coarse lookup displacement layer, and lets the authored brush
## reshape only the continuous penumbra. Both arms run as separate processes on the
## same open Duval Street spawn, weather, clock, camera and movement input.

const SCENE := "res://scenes/world/key_west/key_west_reality.tscn"
const STREET_DATA := "res://data/world/key_west/reality/routes/dev_street_spawns.json"
const STREET_NAME := "Duval Street"
const DEFAULT_OUT := "res://docs/runtime_previews/key_west/shadow_painted_ab/painted"
const CHUNK_M := 512.0
const SETTLE_FRAMES := 40
const MAX_WAIT_FRAMES := 600
const VIDEO_FRAMES := 72
const VIDEO_FPS := 12
const REVIEW_PITCH_DEG := -7.0
const REVIEW_HOUR := 15.0
const MIN_WALK_DISTANCE_M := 2.0

var _out := DEFAULT_OUT
var _arm := "painted"
var _frame_dir := ""
var _world: Node3D
var _ctx: Variant
var _player: CharacterBody3D
var _camera: Camera3D
var _ground: Node
var _streaming: StreamingSystem
var _weather: WeatherController
var _day_night: DayNightManager
var _video_start := Vector3.ZERO
var _video_end := Vector3.ZERO
var _video_distance_m := 0.0
var _video_frame_count := 0
var _street_at := Vector2.ZERO
var _street_yaw := 0.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_out = String(args[0])
	if args.size() >= 2:
		_arm = String(args[1]).to_lower()
	if _arm != "baseline" and _arm != "painted":
		_fail("invalid arm '%s' (expected baseline or painted)" % _arm)
		return
	if not _load_street():
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_frame_dir = _out.path_join("frames")
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
	_weather = get_first_node_in_group(PainterlyAtmospherePass.WEATHER_GROUP) as WeatherController
	for node: Node in _world.find_children("*", "DayNightManager", true, false):
		_day_night = node as DayNightManager
		break
	if _player == null or _camera == null or _ground == null or _weather == null or _day_night == null:
		_fail("missing player, TPS camera, RealityGround, WeatherController, or DayNightManager")
		return

	_hide_hud()
	_weather.set_weather(&"calm", true)
	_day_night.total_game_time_hours = floorf(_day_night.total_game_time_hours / 24.0) * 24.0 + REVIEW_HOUR
	_day_night.force_update_lighting()
	_day_night.set_process(false)
	RenderingServer.global_shader_parameter_set(&"stylized_shadow_strength", 1.0)
	RenderingServer.global_shader_parameter_set(&"stylized_shadow_brush_mix", 2.0 if _arm == "painted" else 1.0)
	await _wait_frames(8)

	_place()
	await _wait_until_streamed()
	_camera.call(&"set_look", _street_yaw, REVIEW_PITCH_DEG)
	_camera.make_current()
	await _wait_frames(8)

	print("SHADOW_PAINTED_AB start arm=%s street=%s hour=%.1f driver=%s" % [
		_arm,
		STREET_NAME,
		REVIEW_HOUR,
		RenderingServer.get_current_rendering_driver_name(),
	])

	_video_start = _player.global_position
	_save_image(_capture_image(), _out.path_join("start.png"))
	Input.action_press(&"move_forward", 0.82)

	for i in range(VIDEO_FRAMES):
		await process_frame
		await RenderingServer.frame_post_draw
		_save_image(_capture_image(), _frame_dir.path_join("frame_%04d.png" % i))
		_video_frame_count += 1

	_release_motion_input()
	await _wait_frames(3)
	_video_end = _player.global_position
	_video_distance_m = Vector2(_video_start.x, _video_start.z).distance_to(Vector2(_video_end.x, _video_end.z))
	_save_image(_capture_image(), _out.path_join("end.png"))
	_write_report("pass", "")

	if _video_frame_count != VIDEO_FRAMES:
		_fail("captured %d/%d frames" % [_video_frame_count, VIDEO_FRAMES])
		return
	if _video_distance_m < MIN_WALK_DISTANCE_M:
		_fail("Henry did not traverse the street: %.2f m < %.2f m" % [_video_distance_m, MIN_WALK_DISTANCE_M])
		return

	print("SHADOW_PAINTED_AB pass arm=%s frames=%d walk=%.2fm out=%s" % [
		_arm,
		_video_frame_count,
		_video_distance_m,
		_out,
	])
	quit(0)


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
	for node_name: StringName in [&"MouseCursorUI", &"VitalHUD"]:
		var node := _player.get_node_or_null(NodePath(String(node_name)))
		if node is CanvasItem:
			(node as CanvasItem).visible = false


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
	for frame in range(MAX_WAIT_FRAMES + 1):
		var p := _player.global_position
		var own := StringName("kw_gen_%d_%d" % [floori(p.x / CHUNK_M), floori(p.z / CHUNK_M)])
		if active_at < 0 and _streaming.get_state(own) == StreamingSystem.CellState.ACTIVE:
			active_at = frame
			_place()
		if active_at >= 0 and frame - active_at >= SETTLE_FRAMES:
			return
		await process_frame
	push_warning("shadow painted A/B: stream wait hit %d-frame safety cap" % MAX_WAIT_FRAMES)


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
	return root.get_viewport().get_texture().get_image()


func _save_image(image: Image, path: String) -> void:
	var error := image.save_png(path)
	if error != OK:
		push_error("shadow painted A/B: save failed %s (%d)" % [path, error])


func _write_report(status: String, failure: String) -> void:
	var report := {
		"diagnostic": "stylized shadow painted-edge independent-process A/B",
		"arm": _arm,
		"status": status,
		"failure": failure,
		"scene": SCENE,
		"street": STREET_NAME,
		"street_at": [_street_at.x, _street_at.y],
		"weather": "calm",
		"hour": REVIEW_HOUR,
		"shadow_mode": "painted_edge_continuous" if _arm == "painted" else "production_three_tone",
		"brush_mix_runtime": 2.0 if _arm == "painted" else 1.0,
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"video_fps": VIDEO_FPS,
		"video_frames": _video_frame_count,
		"expected_frames": VIDEO_FRAMES,
		"video_pitch_deg": REVIEW_PITCH_DEG,
		"henry_travel_m": snappedf(_video_distance_m, 0.01),
	}
	var file := FileAccess.open(_out.path_join("arm_report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))


func _fail(message: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_release_motion_input()
	_write_report("fail", message)
	push_error("SHADOW_PAINTED_AB fail arm=%s reason=%s" % [_arm, message])
	quit(1)
