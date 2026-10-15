extends SceneTree

## Experimental reference-matching capture for Hoarbound's painterly distance wash.
## Runs only from CI / codex. It uses the real Key West Reality scene and game
## TPS camera; no production scene or material is modified.
##
## The existing [key-west-preview] job uploads docs/runtime_previews/key_west/*.png,
## so this experiment deliberately writes its stills, diagnostics and orbit there.

const SCENE := "res://scenes/world/key_west/key_west_reality.tscn"
const SHADER_PATH := "res://shaders/experimental/painterly_distance_wash.gdshader"
const DEFAULT_OUT := "res://docs/runtime_previews/key_west"
const CHUNK_M := 512.0
const SETTLE_FRAMES := 40
const MAX_WAIT_FRAMES := 600
const ORBIT_FRAMES := 64
const ORBIT_DEGREES := 34.0
const SAMPLE_STEP := 8
const MIN_POST_PROBE_DELTA_8BIT := 20.0
const MIN_VISIBLE_WASH_DELTA_8BIT := 4.0

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
var _world: Node3D
var _ctx: Variant
var _player: CharacterBody3D
var _camera: Camera3D
var _ground: Node
var _streaming: StreamingSystem
var _post: MeshInstance3D
var _material: ShaderMaterial
var _records: Array[Dictionary] = []
var _post_probe_delta_8bit := -1.0
var _max_wash_delta_8bit := 0.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = String(args[0])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
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
	if _player == null or _camera == null or _ground == null:
		_fail("missing player, TPS camera, or RealityGround")
		return

	_hide_hud()
	_build_post_process()
	if _post == null or _material == null:
		_fail("could not build painterly distance wash post-process")
		return

	print("painterly distance wash: rendering_driver=%s camera_mask=0x%X post_layers=0x%X" % [
		RenderingServer.get_current_rendering_driver_name(),
		_camera.cull_mask,
		_post.layers,
	])

	for shot_index in range(SHOTS.size()):
		var shot: Dictionary = SHOTS[shot_index]
		_place(shot)
		await _wait_until_streamed(shot)

		_material.set_shader_parameter(&"debug_mode", 0)
		_post.visible = false
		await _wait_frames(3)
		var before_image := _capture_image()
		var before_path := _out.path_join(String(shot["name"]) + "_before.png")
		_save_image(before_image, before_path)

		_post.visible = true
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

			# Depth visualization is equally explicit: black = near, white = far.
			_material.set_shader_parameter(&"debug_mode", 2)
			await _wait_frames(3)
			_save_image(_capture_image(), _out.path_join("painterly_depth_probe.png"))
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

	await _capture_orbit()
	_write_report()

	if _post_probe_delta_8bit < MIN_POST_PROBE_DELTA_8BIT:
		_fail("fullscreen post probe did not render: mean RGB delta %.3f < %.3f" % [_post_probe_delta_8bit, MIN_POST_PROBE_DELTA_8BIT])
		return
	if _max_wash_delta_8bit < MIN_VISIBLE_WASH_DELTA_8BIT:
		_fail("distance wash is still visually negligible: max mean RGB delta %.3f < %.3f" % [_max_wash_delta_8bit, MIN_VISIBLE_WASH_DELTA_8BIT])
		return

	print("painterly distance wash: verified post_delta=%.3f max_wash_delta=%.3f -> %s" % [
		_post_probe_delta_8bit,
		_max_wash_delta_8bit,
		_out,
	])
	quit(0)


func _build_post_process() -> void:
	var shader := load(SHADER_PATH) as Shader
	if shader == null:
		return
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.render_priority = 127
	_material.set_shader_parameter(&"viewport_size", root.get_viewport().get_visible_rect().size)

	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	quad.flip_faces = true

	_post = MeshInstance3D.new()
	_post.name = "PainterlyDistanceWash_EXPERIMENT"
	_post.mesh = quad
	_post.material_override = _material
	_post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_post.extra_cull_margin = 100000.0
	_post.ignore_occlusion_culling = true
	_post.layers = 1
	# Keep the CPU-side AABB unambiguously in front of the active camera. The
	# shader still writes clip-space POSITION, so this transform does not move the pass.
	_post.position = Vector3(0.0, 0.0, -1.0)
	_camera.cull_mask |= _post.layers
	_camera.add_child(_post)


func _hide_hud() -> void:
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


func _capture_orbit() -> void:
	var shot: Dictionary = SHOTS[1]
	_place(shot)
	_material.set_shader_parameter(&"debug_mode", 0)
	_post.visible = true
	await _wait_until_streamed(shot)

	var at: Vector2 = shot["at"]
	var look: Vector2 = shot["look"]
	var direction := Vector3(look.x - at.x, 0.0, look.y - at.y).normalized()
	var base_yaw := atan2(-direction.x, -direction.z)

	for i in range(ORBIT_FRAMES):
		var t := float(i) / float(maxi(ORBIT_FRAMES - 1, 1))
		var yaw_offset := deg_to_rad(ORBIT_DEGREES) * sin(t * TAU)
		_camera.call(&"set_look", base_yaw + yaw_offset, -8.0)
		await process_frame
		_save_image(_capture_image(), _out.path_join("painterly_frame_%04d.png" % i))


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
		"experiment": "Painterly Distance Wash",
		"status": "experimental; codex only; not connected to production path",
		"scene": SCENE,
		"reference_contract": [
			"0-18 m foreground remains effectively untouched",
			"18-32 m mid-ground visibly loses local contrast/chroma and collapses into broader values",
			"32-70+ m background lifts decisively toward a pale cold paper/snow mass",
			"dark buildings become charcoal before dissolving into the wash",
			"blur stays secondary and is suppressed at depth discontinuities",
			"CI fails if the fullscreen post probe is not clearly visible",
			"CI fails if before/wash mean RGB delta stays visually negligible",
		],
		"parameters": {
			"mid_start_m": 18.0,
			"mid_full_m": 32.0,
			"far_start_m": 32.0,
			"far_full_m": 70.0,
			"wash_color_srgb": [0.90, 0.92, 0.94],
			"mid_desaturation": 0.45,
			"far_desaturation": 0.45,
			"mid_contrast_compression": 0.36,
			"far_contrast_compression": 0.38,
			"mid_dark_value_lift": 0.32,
			"far_dark_value_lift": 0.34,
			"mid_paper_mix": 0.38,
			"far_paper_mix": 0.42,
			"blur_start_m": 26.0,
			"blur_end_m": 70.0,
			"blur_strength": 0.18,
			"blur_radius_px": 2.4,
			"horizon_band": 0.16,
			"horizon_paper_boost": 0.08,
		},
		"verification": {
			"post_probe_mean_rgb_delta_8bit": snappedf(_post_probe_delta_8bit, 0.001),
			"max_wash_mean_rgb_delta_8bit": snappedf(_max_wash_delta_8bit, 0.001),
			"required_post_probe_delta_8bit": MIN_POST_PROBE_DELTA_8BIT,
			"required_visible_wash_delta_8bit": MIN_VISIBLE_WASH_DELTA_8BIT,
		},
		"capture": {
			"settle_frames_after_active": SETTLE_FRAMES,
			"max_stream_wait_frames": MAX_WAIT_FRAMES,
			"orbit_frames": ORBIT_FRAMES,
			"orbit_degrees": ORBIT_DEGREES,
		},
		"static_shots": _records,
	}
	var file := FileAccess.open(_out.path_join("source_report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))


func _fail(message: String) -> void:
	push_error("painterly distance wash: %s" % message)
	quit(1)
