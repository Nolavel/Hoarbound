extends SceneTree

## Henry walks Duval Street while a fixed top-down witness records drawn snow height (debug_height)
## for analyze_snow_surface.py; args: <out_dir> [walk_m]. Run with Vulkan and --fixed-fps 30.

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
const STREET_DATA: String = "res://data/world/key_west/reality/routes/dev_street_spawns.json"
const STREET: String = "Duval Street"
## Render layer 21: snow meshes while the witness camera looks; nothing else uses it.
const WITNESS_LAYER: int = 1 << 20
const WITNESS_SIZE_M: float = 40.0
const CAPTURE_EVERY: int = 3

var _out: String = ""
var _walk_m: float = 16.0
var _world: Node3D
var _ctx: Variant
var _player: CharacterBody3D
var _camera: Camera3D
var _streaming: StreamingSystem
var _ground: Node
var _weather: WeatherController
var _presentation: SnowPresentationSystem
var _day_night: DayNightManager
var _witness: Camera3D
var _oblique: Camera3D
## Eye-level views across the street at each side's wall foot, first and last frame only.
var _walls: Array[Camera3D] = []
var _street_at: Vector2 = Vector2.ZERO
var _yaw: float = 0.0
var _start: Vector3 = Vector3.ZERO
var _forward: Vector2 = Vector2.ZERO
var _frames: Array[Dictionary] = []


func _initialize() -> void:
	ProjectSettings.set_setting("hfn/graphics/quality", "high")
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		_fail("output directory required")
		return
	_out = args[0]
	if args.size() > 1:
		_walk_m = args[1].to_float()
	DirAccess.make_dir_recursive_absolute(_out.path_join("witness"))
	DirAccess.make_dir_recursive_absolute(_out.path_join("oblique"))
	DirAccess.make_dir_recursive_absolute(_out.path_join("tps"))
	if not _read_street():
		return
	_run()


func _run() -> void:
	_world = (load(SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_world)
	for i: int in range(600):
		await process_frame
		_ctx = _world.call(&"get_context")
		if _ctx != null:
			break
	if _ctx == null:
		_fail("WorldContext not ready")
		return
	_player = _ctx.player as CharacterBody3D
	_camera = _ctx.camera as Camera3D
	_streaming = _ctx.get_system(preload("res://core/world/streaming_system.gd")) as StreamingSystem
	_weather = _ctx.get_system(preload("res://scripts/systems/world/WeatherController.gd")) as WeatherController
	_presentation = _ctx.get_system(preload("res://scripts/systems/world/snow/snow_presentation_system.gd")) as SnowPresentationSystem
	_ground = _world.find_child("RealityGround", true, false)
	for node: Node in _world.find_children("*", "DayNightManager", true, false):
		_day_night = node as DayNightManager
	if _player == null or _camera == null or _ground == null or SnowShell.active == null or _weather == null:
		_fail("scene is missing player, ground, weather or snow shell")
		return
	for node: Node in _world.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false
	for node: Node in _world.find_children("*", "Control", true, false):
		(node as Control).visible = false
	root.scaling_3d_scale = 1.0
	root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_weather.set_weather(&"calm", true)
	_presentation.load_save_data({"settled": 0.8, "frost": 0.35, "storm": 0.4})
	if _day_night != null:
		_day_night.total_game_time_hours = floorf(_day_night.total_game_time_hours / 24.0) * 24.0 + 14.0
		_day_night.force_update_lighting()
		_day_night.set_process(false)
	_place()
	await _wait_streamed()
	SnowShell.active.recentre_to(Vector2(_player.global_position.x, _player.global_position.z))
	await _wait_frames(30)
	_start = _player.global_position
	var fwd: Vector3 = Basis(Vector3.UP, _yaw) * Vector3.FORWARD
	_forward = Vector2(fwd.x, fwd.z).normalized()
	_setup_cameras()
	if _camera.has_method(&"set_look"):
		_camera.call(&"set_look", _yaw, -18.0)
	await _wait_frames(20)
	await _capture(0)
	await _capture_walls("first")
	Input.action_press(&"move_forward", 1.0)
	var frame: int = 1
	while Vector2(_player.global_position.x - _start.x, _player.global_position.z - _start.z).length() < _walk_m and frame < 2000:
		await process_frame
		if frame % CAPTURE_EVERY == 0:
			await _capture(frame)
		frame += 1
	Input.action_release(&"move_forward")
	for i: int in range(30):
		await process_frame
	await _capture(frame)
	await _capture_walls("last")
	_save_report()
	print("SNOW_SURFACE_CAPTURE done frames=%d walked=%.2f" % [_frames.size(), Vector2(_player.global_position.x - _start.x, _player.global_position.z - _start.z).length()])
	quit(0)


func _capture_walls(tag: String) -> void:
	for i: int in range(_walls.size()):
		_walls[i].make_current()
		await process_frame
		await RenderingServer.frame_post_draw
		_save(root.get_texture().get_image(), "wall_%d_%s.png" % [i, tag])
	_camera.make_current()


func _capture(frame: int) -> void:
	var index: int = _frames.size()
	await RenderingServer.frame_post_draw
	_save(root.get_texture().get_image(), "tps/%04d.png" % index)
	_oblique.make_current()
	await process_frame
	await RenderingServer.frame_post_draw
	_save(root.get_texture().get_image(), "oblique/%04d.png" % index)
	_set_debug(true)
	_witness.make_current()
	await process_frame
	await RenderingServer.frame_post_draw
	_save(root.get_texture().get_image(), "witness/%04d.png" % index)
	_set_debug(false)
	_camera.make_current()
	var p: Vector3 = _player.global_position
	var origin: Vector2 = SnowShell.active.get_origin()
	_frames.append({"frame": frame, "henry": [p.x, p.y, p.z], "window_origin": [origin.x, origin.y]})


## Snow meshes join the witness layer and draw encoded height while it looks.
func _set_debug(on: bool) -> void:
	var shell: SnowShell = SnowShell.active
	for mesh: Node in shell.find_children("*", "MeshInstance3D", true, false):
		if (mesh as MeshInstance3D).material_override == shell._surface:
			(mesh as MeshInstance3D).layers = (mesh as MeshInstance3D).layers | WITNESS_LAYER if on else (mesh as MeshInstance3D).layers & ~WITNESS_LAYER
	shell._surface.set_shader_parameter("debug_height", on)
	for cover: Node in _ground.find_children("Snow_*", "MeshInstance3D", true, false):
		var mi := cover as MeshInstance3D
		mi.layers = mi.layers | WITNESS_LAYER if on else mi.layers & ~WITNESS_LAYER
		if mi.mesh != null and mi.mesh.get_surface_count() > 0:
			var mat := mi.mesh.surface_get_material(0) as ShaderMaterial
			if mat != null:
				mat.set_shader_parameter("debug_height", on)


func _setup_cameras() -> void:
	var centre := Vector3(_start.x, _start.y, _start.z) + Vector3(_forward.x, 0.0, _forward.y) * (_walk_m * 0.5)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var attributes := CameraAttributesPractical.new()
	attributes.auto_exposure_enabled = false
	_witness = Camera3D.new()
	_witness.name = "SnowHeightWitness"
	_witness.projection = Camera3D.PROJECTION_ORTHOGONAL
	_witness.size = WITNESS_SIZE_M
	_witness.keep_aspect = Camera3D.KEEP_WIDTH
	_witness.near = 1.0
	_witness.far = 200.0
	_witness.cull_mask = WITNESS_LAYER
	_witness.environment = env
	_witness.attributes = attributes
	_world.add_child(_witness)
	## Looking straight down with -Z up the image: pixel (u, v) maps to world x, z directly.
	_witness.global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), centre + Vector3.UP * 60.0)
	_oblique = Camera3D.new()
	_oblique.name = "SnowFixedOblique"
	_oblique.fov = 50.0
	_oblique.cull_mask = _camera.cull_mask
	_world.add_child(_oblique)
	var side := Vector3(-_forward.y, 0.0, _forward.x)
	var eye: Vector3 = _start + side * 5.0 + Vector3.UP * 2.2 - Vector3(_forward.x, 0.0, _forward.y) * 3.0
	_oblique.global_position = eye
	_oblique.look_at(centre + Vector3(_forward.x, 0.0, _forward.y) * 6.0 + Vector3.UP * 0.2, Vector3.UP)
	for sign: float in [-1.0, 1.0]:
		var cam := Camera3D.new()
		cam.fov = 55.0
		cam.cull_mask = _camera.cull_mask
		_world.add_child(cam)
		var at: Vector3 = _start + Vector3(_forward.x, 0.0, _forward.y) * 3.0
		cam.global_position = at - side * sign * 1.5 + Vector3.UP * 1.3
		cam.look_at(at + side * sign * 9.0 + Vector3.UP * 0.3, Vector3.UP)
		_walls.append(cam)


func _save_report() -> void:
	var w: Transform3D = _witness.global_transform
	var report := {
		"scene": SCENE,
		"street": STREET,
		"renderer": RenderingServer.get_current_rendering_driver_name(),
		"witness": {"size_m": WITNESS_SIZE_M, "origin": [w.origin.x, w.origin.y, w.origin.z],
			"right": [w.basis.x.x, w.basis.x.y, w.basis.x.z], "up": [w.basis.y.x, w.basis.y.y, w.basis.y.z]},
		"start": [_start.x, _start.y, _start.z],
		"forward": [_forward.x, _forward.y],
		"frames": _frames,
	}
	var f := FileAccess.open(_out.path_join("report.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t"))
	f.close()


func _place() -> void:
	var y: float = float(_ground.call(&"get_height", _street_at.x, _street_at.y))
	_player.global_position = Vector3(_street_at.x, y + 1.0, _street_at.y)
	_player.velocity = Vector3.ZERO
	_player.rotation.y = _yaw
	_player.reset_physics_interpolation()
	if _streaming != null:
		_streaming.scan(_player.global_position)


func _wait_streamed() -> void:
	if _streaming == null:
		await _wait_frames(60)
		return
	var activated: int = -1
	for i: int in range(900):
		var p: Vector3 = _player.global_position
		var cell := StringName("kw_gen_%d_%d" % [floori(p.x / 512.0), floori(p.z / 512.0)])
		if activated < 0 and _streaming.get_state(cell) == StreamingSystem.CellState.ACTIVE:
			activated = i
			_place()
		if activated >= 0 and i - activated >= 90:
			return
		await process_frame


func _read_street() -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(STREET_DATA))
	if parsed is Dictionary:
		for item: Variant in (parsed as Dictionary).get("streets", []):
			if item is Dictionary and String((item as Dictionary).get("name", "")) == STREET:
				var at: Array = (item as Dictionary)["at"]
				_street_at = Vector2(float(at[0]), float(at[1]))
				_yaw = deg_to_rad(float((item as Dictionary).get("heading_deg", 0.0)))
				return true
	_fail("street spawn missing: " + STREET)
	return false


func _wait_frames(count: int) -> void:
	for i: int in range(count):
		await process_frame


func _save(image: Image, rel: String) -> void:
	image.save_png(_out.path_join(rel))


func _fail(message: String) -> void:
	push_error("SNOW_SURFACE_CAPTURE FAIL " + message)
	quit(1)
