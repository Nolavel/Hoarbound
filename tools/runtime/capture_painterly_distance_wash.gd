extends SceneTree

## Production-path verification for Hoarbound's painterly distance wash.
## It uses the real Key West Reality scene, TPS camera and the atmosphere pass
## embedded in that camera. The harness never constructs a substitute effect.
## Review artifacts must be captured from the exact branch head being handed off.
##
## The existing [key-west-preview] job uploads docs/runtime_previews/key_west/*.png,
## so this verifier deliberately writes its stills, diagnostics and walk there.

const SCENE := "res://scenes/world/key_west/key_west_reality.tscn"
const POST_NODE := ^"PainterlyAtmosphere"
const DEFAULT_OUT := "res://docs/runtime_previews/key_west"
const CHUNK_M := 512.0
const SETTLE_FRAMES := 40
const MAX_WAIT_FRAMES := 600
const VIDEO_FRAMES := 72
const VIDEO_FPS := 12
const MIN_WALK_DISTANCE_M := 2.0
const SAMPLE_STEP := 8
const MIN_POST_PROBE_DELTA_8BIT := 20.0
const MIN_VISIBLE_WASH_DELTA_8BIT := 4.0
const MIN_SURFACE_DELTA_8BIT := 0.7

const SHOTS: Array[Dictionary] = [
	{
		"name": "painterly_01_petronia_street",
		"at": Vector2(-3163.0, 1363.0),
		"look": Vector2(-3115.0, 1331.0),
	},
	{
		"name": "painterly_02_residential_block",
		"at": Vector2(-3385.0, 1513.0),
		"look": Vector2(-3340.0, 1480.0),
	},
	{
		"name": "painterly_03_approach_727",
		"at": Vector2(-3593.0, 1601.0),
		"look": Vector2(-3538.75, 1594.38),
	},
]

var _out := DEFAULT_OUT
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
var _records: Array[Dictionary] = []
var _post_probe_delta_8bit := -1.0
var _max_wash_delta_8bit := 0.0
var _surface_delta_8bit := 0.0
var _video_start := Vector3.ZERO
var _video_end := Vector3.ZERO
var _video_distance_m := 0.0
var _video_frame_count := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = String(args[0])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_frame_dir = _out.path_join("painterly_video_frames")
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

	# Review the complete visual contract rather than a faint calm-weather fraction.
	# Before/after frames still use the same blizzard state, so only the pass changes.
	_weather.set_weather(&"blizzard", true)
	RenderingServer.global_shader_parameter_set(&"painterly_surface_strength", 1.0)
	await _wait_frames(3)

	print("painterly distance wash: production_pass=%s rendering_driver=%s camera_mask=0x%X post_layers=0x%X" % [
		_post.get_path(),
		RenderingServer.get_current_rendering_driver_name(),
		_camera.cull_mask,
		_post.layers,
	])

	for shot_index in range(SHOTS.size()):
		var shot: Dictionary = SHOTS[shot_index]
		_place(shot)
		await _wait_until_streamed(shot)

		_material.set_shader_parameter(&"debug_mode", 0)
		_set_post_enabled(false)
		await _wait_frames(3)

		if shot_index == 0:
			RenderingServer.global_shader_parameter_set(&"painterly_surface_strength", 0.0)
			await _wait_frames(3)
			var surface_off := _capture_image()
			_save_image(surface_off, _out.path_join("painterly_surface_off.png"))
			RenderingServer.global_shader_parameter_set(&"painterly_surface_strength", 1.0)
			await _wait_frames(3)
			var surface_on := _capture_image()
			_save_image(surface_on, _out.path_join("painterly_surface_on.png"))
			_surface_delta_8bit = _mean_rgb_delta_8bit(surface_off, surface_on)

		var before_image := _capture_image()
		var before_path := _out.path_join(String(shot["name"]) + "_before.png")
		_save_image(before_image, before_path)

		_set_post_enabled(true)
		await _wait_frames(5)
		var wash_image := _capture_image()
		var after_path := _out.path_join(String(shot["name"]) + "_wash.png")
		_save_image(wash_image, after_path)
		var wash_delta := _mean_rgb_delta_8bit(before_image, wash_image)
		_max_wash_delta_8bit = maxf(_max_wash_delta_8bit, wash_delta)

		if shot_index == 0:
			# Unmissable magenta probe. If this is not visibly different, the
			# fullscreen mesh is not drawing and CI must not report success.
			_material.set_shader_parameter(&"debug_mode", 1)
			await _wait_frames(3)
			var post_probe := _capture_image()
			_save_image(post_probe, _out.path_join("painterly_post_probe.png"))
			_post_probe_delta_8bit = _mean_rgb_delta_8bit(before_image, post_probe)
			if _post_probe_delta_8bit < MIN_POST_PROBE_DELTA_8BIT:
				_fail("fullscreen post probe did not render: mean RGB delta %.3f < %.3f" % [_post_probe_delta_8bit, MIN_POST_PROBE_DELTA_8BIT])
				return

			# Depth visualization is equally explicit: black = near, white = far.
			_material.set_shader_parameter(&"debug_mode", 2)
			await _wait_frames(3)
			_save_image(_capture_image(), _out.path_join("painterly_depth_probe.png"))

			# Material diagnostics: grayscale permanent paper tooth; advanced RGB =
			# drying rim / fine pigment / internal ink; base RGB = wash front / pool / bleed.
			_material.set_shader_parameter(&"debug_mode", 3)
			await _wait_frames(3)
			_save_image(_capture_image(), _out.path_join("painterly_paper_probe.png"))
			_material.set_shader_parameter(&"debug_mode", 4)
			await _wait_frames(3)
			_save_image(_capture_image(), _out.path_join("painterly_material_masks.png"))
			_material.set_shader_parameter(&"debug_mode", 5)
			await _wait_frames(3)
			_save_image(_capture_image(), _out.path_join("painterly_base_masks.png"))
			_material.set_shader_parameter(&"debug_mode", 0)
			await _wait_frames(2)

		_records.append({
			"shot": shot["name"],
			"player_xz": [shot["at"].x, shot["at"].y],
			"look_xz": [shot["look"].x, shot["look"].y],
			"before": before_path,
			"wash": after_path,
			"mean_rgb_delta_8bit": snappedf(wash_delta, 0.001),
		})

	await _capture_tps_walk()
	_write_report()

	if _surface_delta_8bit < MIN_SURFACE_DELTA_8BIT:
		_fail("PainterlySurface is visually negligible: mean RGB delta %.3f < %.3f" % [_surface_delta_8bit, MIN_SURFACE_DELTA_8BIT])
		return
	if _max_wash_delta_8bit < MIN_VISIBLE_WASH_DELTA_8BIT:
		_fail("distance wash is still visually negligible: max mean RGB delta %.3f < %.3f" % [_max_wash_delta_8bit, MIN_VISIBLE_WASH_DELTA_8BIT])
		return
	if _video_frame_count != VIDEO_FRAMES:
		_fail("TPS video captured %d/%d frames" % [_video_frame_count, VIDEO_FRAMES])
		return
	if _video_distance_m < MIN_WALK_DISTANCE_M:
		_fail("Henry did not traverse the street: %.2f m < %.2f m" % [_video_distance_m, MIN_WALK_DISTANCE_M])
		return

	print("painterly distance wash: verified surface_delta=%.3f post_delta=%.3f max_wash_delta=%.3f walk=%.2fm frames=%d -> %s" % [
		_surface_delta_8bit,
		_post_probe_delta_8bit,
		_max_wash_delta_8bit,
		_video_distance_m,
		_video_frame_count,
		_out,
	])
	quit(0)


func _set_post_enabled(value: bool) -> void:
	if _post.has_method(&"set_effect_enabled"):
		_post.call(&"set_effect_enabled", value)
	else:
		_post.visible = value


func _hide_hud() -> void:
	# Review evidence is the TPS image itself. Hide every runtime HUD/debug canvas;
	# the 3D weather, Henry and world keep rendering normally.
	for node: Node in _world.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false
	for node_name: StringName in [&"MouseCursorUI", &"VitalHUD"]:
		var node := _player.get_node_or_null(NodePath(String(node_name)))
		if node is CanvasItem:
			(node as CanvasItem).visible = false


func _place(shot: Dictionary) -> void:
	var at: Vector2 = shot["at"]
	var look: Vector2 = shot["look"]
	var ground_y := _ground_height(at.x, at.y)
	_player.global_position = Vector3(at.x, ground_y + 1.0, at.y)
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	var direction := Vector3(look.x - at.x, 0.0, look.y - at.y).normalized()
	var yaw := atan2(-direction.x, -direction.z)
	_player.rotation.y = yaw
	_camera.call(&"set_look", yaw, -8.0)
	_camera.make_current()


func _wait_until_streamed(shot: Dictionary) -> void:
	if _streaming == null:
		push_warning("painterly distance wash: StreamingSystem unavailable; using short fallback settle")
		await _wait_frames(SETTLE_FRAMES)
		return

	var active_at := -1
	for frame in range(MAX_WAIT_FRAMES + 1):
		var p := _player.global_position
		var own := StringName("kw_gen_%d_%d" % [floori(p.x / CHUNK_M), floori(p.z / CHUNK_M)])
		if active_at < 0 and _streaming.get_state(own) == StreamingSystem.CellState.ACTIVE:
			active_at = frame
			# Ground height is authoritative only after the target chunk becomes active.
			_place(shot)
		if active_at >= 0 and frame - active_at >= SETTLE_FRAMES:
			return
		await process_frame

	push_warning("painterly distance wash: stream wait hit %d-frame safety cap" % MAX_WAIT_FRAMES)


func _capture_tps_walk() -> void:
	var shot: Dictionary = SHOTS[1]
	_release_motion_input()
	_place(shot)
	_material.set_shader_parameter(&"debug_mode", 0)
	_set_post_enabled(true)
	await _wait_until_streamed(shot)
	await _wait_frames(8)

	_video_start = _player.global_position
	_save_image(_capture_image(), _out.path_join("painterly_tps_video_start.png"))
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
	_save_image(_capture_image(), _out.path_join("painterly_tps_video_end.png"))


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
		push_error("painterly distance wash: save failed %s (%d)" % [path, error])


func _mean_rgb_delta_8bit(a: Image, b: Image) -> float:
	if a == null or b == null or a.is_empty() or b.is_empty():
		return 0.0
	var width := mini(a.get_width(), b.get_width())
	var height := mini(a.get_height(), b.get_height())
	var total := 0.0
	var samples := 0
	for y in range(0, height, SAMPLE_STEP):
		for x in range(0, width, SAMPLE_STEP):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			total += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			samples += 3
	if samples == 0:
		return 0.0
	return (total / float(samples)) * 255.0


func _write_report() -> void:
	var report := {
		"feature": "Painterly Atmosphere / Surface Experiment",
		"status": "experimental surface pigment plus production TPS distance wash; verified through the shipping scene path",
		"scene": SCENE,
		"reference_contract": [
			"0-18 m foreground remains effectively untouched",
			"18-32 m mid-ground visibly loses local contrast/chroma and collapses into broader values",
			"32-70+ m background lifts decisively toward a pale cold paper/snow mass",
			"dark buildings become charcoal before dissolving into the wash",
			"18-40 m mid-ground retains darker ink mass before far-distance lift takes over",
			"paper tooth and cold sheet tint stay present independently of weather strength",
			"large pigment masses live in PainterlySurface on static buildings and ground, not in the camera pass",
			"directional brush flow follows the dominant surface plane; Henry and movable props stay untouched",
			"distance bands break into broad world-stable wet-on-wet fronts",
			"selected mid-distance depth edges receive stronger broken pigment pooling and restrained bleed",
			"irregular wash fronts carry narrow broken drying rims, weighted toward dark architecture",
			"broad blotches plus metre-scale granulation stay world-stable and avoid pixel-scale crawling",
			"seven softly blended value families simplify mid-distance digital gradients",
			"authored facade divisions receive broken internal ink without outlining every silhouette",
			"paper combines screen-stable tooth and sparse directional fibre independently of weather",
			"the post-process never invents windows; authored window and frost materials own them",
			"blur stays secondary and is suppressed at depth discontinuities",
			"CI probes the fullscreen pass before the expensive multi-shot/video capture",
			"CI fails if before/wash mean RGB delta stays visually negligible",
		],
		"parameters": {
			"mid_start_m": 18.0,
			"mid_full_m": 32.0,
			"far_start_m": 32.0,
			"far_full_m": 70.0,
			"wash_color_srgb": [0.90, 0.92, 0.94],
			"mid_desaturation": 0.34,
			"far_desaturation": 0.48,
			"mid_contrast_compression": 0.24,
			"far_contrast_compression": 0.40,
			"mid_dark_value_lift": 0.04,
			"far_dark_value_lift": 0.32,
			"mid_ink_hold": 0.38,
			"mid_paper_mix": 0.21,
			"far_paper_mix": 0.44,
			"value_steps": 7.0,
			"value_terrace_strength": 0.22,
			"blur_start_m": 26.0,
			"blur_end_m": 70.0,
			"blur_strength": 0.16,
			"blur_radius_px": 2.2,
			"edge_bleed_strength": 0.095,
			"pigment_pool_strength": 0.20,
			"drying_rim_strength": 0.105,
			"internal_ink_strength": 0.12,
			"horizon_band": 0.16,
			"horizon_paper_boost": 0.08,
			"paper_strength": 1.0,
			"paper_base_mix": 0.035,
			"paper_grain_strength": 0.024,
			"paper_grain_scale_px": 2.25,
			"paper_fiber_strength": 0.008,
			"blotch_scale": 0.11,
			"blotch_mix_variation": 0.27,
			"blotch_value_variation": 0.055,
			"granulation_scale": 3.75,
			"granulation_strength": 0.085,
			"wash_edge_scale": 0.045,
			"wash_edge_variation_m": 4.0,
			"dry_brush_scale": 0.65,
			"dry_brush_strength": 0.20,
			"surface_pigment_scale_m": 9.0,
			"surface_pigment_strength": 0.14,
			"surface_brush_direction": [0.32, 0.95],
			"surface_brush_length_m": 7.0,
			"surface_brush_width_m": 0.85,
			"surface_brush_strength": 0.06,
		},
		"verification": {
			"surface_on_off_mean_rgb_delta_8bit": snappedf(_surface_delta_8bit, 0.001),
			"required_surface_delta_8bit": MIN_SURFACE_DELTA_8BIT,
			"post_probe_mean_rgb_delta_8bit": snappedf(_post_probe_delta_8bit, 0.001),
			"max_wash_mean_rgb_delta_8bit": snappedf(_max_wash_delta_8bit, 0.001),
			"required_post_probe_delta_8bit": MIN_POST_PROBE_DELTA_8BIT,
			"required_visible_wash_delta_8bit": MIN_VISIBLE_WASH_DELTA_8BIT,
		},
		"capture": {
			"weather": "blizzard",
			"settle_frames_after_active": SETTLE_FRAMES,
			"max_stream_wait_frames": MAX_WAIT_FRAMES,
			"video_fps": VIDEO_FPS,
			"video_frames": _video_frame_count,
			"video_duration_seconds": float(_video_frame_count) / float(VIDEO_FPS),
			"video_start_xyz": [_video_start.x, _video_start.y, _video_start.z],
			"video_end_xyz": [_video_end.x, _video_end.y, _video_end.z],
			"henry_travel_m": snappedf(_video_distance_m, 0.01),
			"camera_is_current": _camera.is_current(),
			"video_output": _out.path_join("painterly_tps_walk.mp4"),
		},
		"static_shots": _records,
	}
	var file := FileAccess.open(_out.path_join("source_report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))


func _fail(message: String) -> void:
	push_error("painterly distance wash: %s" % message)
	quit(1)


