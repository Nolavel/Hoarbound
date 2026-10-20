extends SceneTree

## Henry walks, turns into a wall's drift and runs on Duval Street while three cameras
## record what the snowpack does to him: the TPS view, a side view at leg height and,
## at the end, a close look down at his boot prints. For the snow-walk CI job.
## Usage: xvfb-run godot --path . --rendering-driver vulkan --fixed-fps 30
##   --script res://tools/runtime/capture_snow_walk.gd -- <out_dir>

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
const STREET_DATA: String = "res://data/world/key_west/reality/routes/dev_street_spawns.json"
const STREET: String = "Duval Street"
## Phases: camera yaw offset from the street (degrees), seconds, sprint.
const ROUTE: Array = [[0.0, 4.0, false], [90.0, 3.5, false], [-90.0, 6.0, false], [180.0, 2.5, true], [180.0, 1.5, null]]
const FPS: int = 30
const CAPTURE_EVERY: int = 2

var _out: String = ""
var _world: Node3D
var _ctx: Variant
var _player: CharacterBody3D
var _camera: Camera3D
var _streaming: StreamingSystem
var _ground: Node
var _legs: Camera3D
var _prints: Camera3D
var _street_at: Vector2 = Vector2.ZERO
var _yaw: float = 0.0
var _side: Vector3 = Vector3.RIGHT
var _frames: Array[Dictionary] = []
## Henry's travel direction, kept when he stops, so the prints camera finds his trail.
var _travel: Vector3 = Vector3.FORWARD


func _initialize() -> void:
	ProjectSettings.set_setting("hfn/graphics/quality", "high")
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		_fail("output directory required")
		return
	_out = args[0]
	for dir: String in ["tps", "legs"]:
		DirAccess.make_dir_recursive_absolute(_out.path_join(dir))
	if _read_street():
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
	var weather := _ctx.get_system(preload("res://scripts/systems/world/WeatherController.gd")) as WeatherController
	var presentation := _ctx.get_system(preload("res://scripts/systems/world/snow/snow_presentation_system.gd")) as SnowPresentationSystem
	_ground = _world.find_child("RealityGround", true, false)
	var shell := SnowShell.active as DeterministicSnowShell
	if _player == null or _camera == null or _ground == null or shell == null or weather == null:
		_fail("scene is missing player, ground, weather or the deterministic snow shell")
		return
	for node: Node in _world.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false
	for node: Node in _world.find_children("*", "Control", true, false):
		(node as Control).visible = false
	root.scaling_3d_scale = 1.0
	weather.set_weather(&"calm", true)
	## Deep cover with a strong storm share: crusted scour on the street, drifts at the walls.
	presentation.load_save_data({"settled": 0.9, "frost": 0.35, "storm": 0.6})
	for node: Node in _world.find_children("*", "DayNightManager", true, false):
		var day := node as DayNightManager
		## Low afternoon sun: relief and prints throw shadows.
		day.total_game_time_hours = floorf(day.total_game_time_hours / 24.0) * 24.0 + 15.5
		day.force_update_lighting()
		day.set_process(false)
	_place()
	await _wait_streamed()
	shell.recentre_to(Vector2(_player.global_position.x, _player.global_position.z))
	await _wait_frames(30)
	_setup_cameras()
	var frame: int = 0
	for phase: Array in ROUTE:
		var yaw: float = _yaw + deg_to_rad(float(phase[0]))
		if _camera.has_method(&"set_look"):
			_camera.call(&"set_look", yaw, -16.0)
		_release()
		if phase[2] != null:
			Input.action_press(&"move_forward", 1.0)
			if bool(phase[2]):
				Input.action_press(&"sprint", 1.0)
		for i: int in range(roundi(float(phase[1]) * FPS)):
			await process_frame
			_follow_legs()
			if frame % CAPTURE_EVERY == 0:
				await _capture(frame, shell)
			frame += 1
	_release()
	await _wait_frames(10)
	await _capture_prints()
	_save_report(shell)
	print("SNOW_WALK_CAPTURE done frames=%d plunges=%d" % [_frames.size(), shell.plunge_count])
	quit(0)


func _capture(frame: int, shell: DeterministicSnowShell) -> void:
	var index: int = _frames.size()
	await RenderingServer.frame_post_draw
	_save(root.get_texture().get_image(), "tps/%04d.png" % index)
	_legs.make_current()
	await process_frame
	_follow_legs()
	await RenderingServer.frame_post_draw
	_save(root.get_texture().get_image(), "legs/%04d.png" % index)
	_camera.make_current()
	var p: Vector3 = _player.global_position
	_frames.append({"frame": frame, "henry": [p.x, p.y, p.z], "sink": [shell.get_foot_sink(0), shell.get_foot_sink(1)],
		"depth": shell.field.get_depth(p.x, p.z), "plunges": shell.plunge_count})


## Side view at leg height, beside Henry's travel, so a leg going through shows.
func _follow_legs() -> void:
	var v: Vector3 = _player.velocity
	if Vector2(v.x, v.z).length() > 0.3:
		_side = Vector3(-v.z, 0.0, v.x).normalized()
		_travel = Vector3(v.x, 0.0, v.z).normalized()
	var at: Vector3 = _player.global_position
	_legs.global_position = at + _side * 2.4 + Vector3.UP * 0.75
	_legs.look_at(at + Vector3.UP * 0.35, Vector3.UP)


## The last metres of the trail while it is still fresh: from the side, then from behind.
func _capture_prints() -> void:
	var trail: Vector3 = _player.global_position - _travel * 1.6
	var eyes: Array[Vector3] = [_side * 1.1 + Vector3.UP * 1.3, -_travel * 1.4 + Vector3.UP * 1.6]
	for i: int in range(eyes.size()):
		_prints.global_position = trail + eyes[i]
		_prints.look_at(trail, Vector3.UP)
		_prints.make_current()
		await process_frame
		await RenderingServer.frame_post_draw
		_save(root.get_texture().get_image(), "prints_%d.png" % i)
	_camera.make_current()


func _setup_cameras() -> void:
	_legs = Camera3D.new()
	_legs.name = "SnowWalkLegs"
	_legs.fov = 50.0
	_legs.cull_mask = _camera.cull_mask
	_world.add_child(_legs)
	_prints = Camera3D.new()
	_prints.name = "SnowWalkPrints"
	_prints.fov = 45.0
	_prints.cull_mask = _camera.cull_mask
	_world.add_child(_prints)


func _release() -> void:
	for action: StringName in [&"move_forward", &"move_backward", &"move_left", &"move_right", &"sprint"]:
		Input.action_release(action)


func _save_report(shell: DeterministicSnowShell) -> void:
	var report := {"scene": SCENE, "street": STREET, "plunges": shell.plunge_count, "frames": _frames}
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
	push_error("SNOW_WALK_CAPTURE FAIL " + message)
	quit(1)
