extends SceneTree

## One-shot diagnostic A/B for the painterly Key West preview.
## Each arm is launched by CI in a separate Godot process so an early crash in
## one arm cannot hide the other arm. Both arms use the real Key West scene,
## the production TPS camera, and the live full-blizzard weather binding.
##
## CONTROL: PainterlySurface strength = 0, PainterlyAtmosphere disabled.
## TEST:    PainterlySurface strength = 1, PainterlyAtmosphere enabled.

const SCENE := "res://scenes/world/key_west/key_west_reality.tscn"
const POST_NODE := ^"PainterlyAtmosphere"
const DEFAULT_OUT := "res://docs/runtime_previews/key_west/painterly_ab/test"
const CHUNK_M := 512.0
const SETTLE_FRAMES := 40
const MAX_WAIT_FRAMES := 600
const VIDEO_FRAMES := 72
const VIDEO_FPS := 12
const REVIEW_PITCH_DEG := 8.0
const MIN_WALK_DISTANCE_M := 2.0
const SHOT := {
	"at": Vector2(-3385.0, 1513.0),
	"look": Vector2(-3340.0, 1480.0),
}

var _out := DEFAULT_OUT
var _arm := "test"
var _frame_dir := ""
var _world: Node3D
var _ctx: Variant
var _player: CharacterBody3D
var _camera: Camera3D
var _ground: Node
var _streaming: StreamingSystem
var _weather: WeatherController
var _post: MeshInstance3D
var _material: ShaderMaterial
var _video_start := Vector3.ZERO
var _video_end := Vector3.ZERO
var _video_distance_m := 0.0
var _video_frame_count := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_out = String(args[0])
	if args.size() >= 2:
		_arm = String(args[1]).to_lower()
	if _arm != "control" and _arm != "test":
		_fail("invalid arm '%s' (expected control or test)" % _arm)
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
	if _player == null or _camera == null or _ground == null or _weather == null:
		_fail("missing player, TPS camera, RealityGround, or WeatherController")
		return

	_hide_hud()
	_post = _camera.get_node_or_null(POST_NODE) as MeshInstance3D
	if _post != null:
		_material = _post.material_override as ShaderMaterial
	if _post == null or _material == null:
		_fail("production TPS camera is missing PainterlyAtmosphere or its material")
		return

	_weather.set_weather(&"blizzard", true)
	_material.set_shader_parameter(&"debug_mode", 0)
	var painterly_enabled := _arm == "test"
	_set_post_enabled(painterly_enabled)
	RenderingServer.global_shader_parameter_set(&"painterly_surface_strength", 1.0 if painterly_enabled else 0.0)
	await _wait_frames(8)

	_place()
	await _wait_until_streamed()
	_camera.call(&"set_look", _player.rotation.y, REVIEW_PITCH_DEG)
	_camera.make_current()
	await _wait_frames(8)

	print("PAINTERLY_AB_ARM start arm=%s weather=blizzard driver=%s post=%s surface_strength=%.1f" % [
		_arm,
		RenderingServer.get_current_rendering_driver_name(),
		str(painterly_enabled),
		1.0 if painterly_enabled else 0.0,
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

	print("PAINTERLY_AB_ARM pass arm=%s frames=%d walk=%.2fm out=%s" % [
		_arm,
		_video_frame_count,
		_video_distance_m,
		_out,
	])
	quit(0)


func _set_post_enabled(value: bool) -> void:
	if _post.has_method(&"set_effect_enabled"):
		_post.call(&"set_effect_enabled", value)
	else:
		_post.visible = value


func _hide_hud() -> void:
	for node: Node in _world.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false
	for node_name: StringName in [&"MouseCursorUI", &"VitalHUD"]:
		var node := _player.get_node_or_null(NodePath(String(node_name)))
		if node is CanvasItem:
			(node as CanvasItem).visible = false


func _place() -> void:
	var at: Vector2 = SHOT["at"]
	var look: Vector2 = SHOT["look"]
	var ground_y := _ground_height(at.x, at.y)
	_player.global_position = Vector3(at.x, ground_y + 1.0, at.y)
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	var direction := Vector3(look.x - at.x, 0.0, look.y - at.y).normalized()
	var yaw := atan2(-direction.x, -direction.z)
	_player.rotation.y = yaw
	_camera.call(&"set_look", yaw, -8.0)
	_camera.make_current()


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
	push_warning("painterly A/B: stream wait hit %d-frame safety cap" % MAX_WAIT_FRAMES)


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
		push_error("painterly A/B: save failed %s (%d)" % [path, error])


func _write_report(status: String, failure: String) -> void:
	var report := {
		"diagnostic": "painterly independent-process A/B",
		"arm": _arm,
		"status": status,
		"failure": failure,
		"scene": SCENE,
		"weather": "blizzard",
		"post_enabled": _arm == "test",
		"painterly_surface_strength": 1.0 if _arm == "test" else 0.0,
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
	_write_report("fail", message)
	push_error("PAINTERLY_AB_ARM fail arm=%s reason=%s" % [_arm, message])
	quit(1)
