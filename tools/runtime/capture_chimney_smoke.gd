extends SceneTree

## 727 chimney (#252): the street view from 25 m with the stove cold, then lit in gusty wind
## (several frames apart, the wind printed per frame), and the room view of the whole flue.
## Run: xvfb-run godot --path . --rendering-driver vulkan --fixed-fps 30 --script res://tools/runtime/capture_chimney_smoke.gd -- <out dir> [weather id]

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
const HOUR: float = 14.0
const GUST_FRAMES: int = 4
## Particle time runs this many times faster while the plume builds, so it fills in few frames.
const WARM_SPEED: float = 8.0

var _out: String = "user://shots/chimney_smoke"
var _weather_id: StringName = &"snowfall"
var _world: Node3D
var _player: Player


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_weather_id = StringName(args[1])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_run()


func _run() -> void:
	_world = (load(SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_world)
	var ctx: Variant = null
	for _i: int in range(600):
		await process_frame
		ctx = _world.call(&"get_context")
		if ctx != null:
			break
	_player = ctx.player as Player
	var weather: WeatherController = null
	for node: Node in _world.find_children("*", "WeatherController", true, false):
		if not (node as WeatherController).profiles.is_empty():
			weather = node as WeatherController
			weather.set_weather(_weather_id, true)
	for node: Node in _world.find_children("*", "DayNightManager", true, false):
		node.set(&"total_game_time_hours", floorf(float(node.get(&"total_game_time_hours")) / 24.0) * 24.0 + HOUR)
		node.call(&"force_update_lighting")
		node.set_process(false)
	for layer: Node in root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	for label: Node in _world.find_children("*", "Label3D", true, false):
		(label as Node3D).visible = false
	var stove := _world.find_children("*", "HeatSource", true, false)[0] as HeatSource
	var smoke := _world.find_children("ChimneySmoke", "", true, false)[0] as ChimneySmoke
	var door := _world.find_children("HouseDoor", "", true, false)[0] as Node3D
	var out: Vector3 = door.global_basis.z
	out.y = 0.0
	out = out.normalized()
	var side: Vector3 = Vector3.UP.cross(out).normalized()
	var cap: Vector3 = smoke.global_position
	var street: Vector3 = door.global_position + out * 24.0 - side * 7.0 + Vector3.UP * 2.0
	var aim: Vector3 = cap + Vector3.UP * 1.2

	## Henry stays out of the street frame, down the road behind the camera.
	_player.global_position = street - out * 6.0 + Vector3.UP
	await _frames(120)
	await _shot("1_cold", street, aim, weather, smoke)
	stove.restore_fuel(1.5, true)
	stove.ignite()
	smoke.speed_scale = WARM_SPEED
	await _frames(30)
	smoke.speed_scale = 1.0
	for i: int in range(GUST_FRAMES):
		await _shot("2_lit_%d" % i, street, aim, weather, smoke)
		await _frames(20)

	## The room: the stove's flue runs unbroken into the ceiling.
	var house := stove.get_parent().get_parent() as Node3D
	var ceiling: float = house.global_position.y + float(house.get_parent().get(&"interior")["ceiling_y"])
	_player.global_position = stove.to_global(Vector3(1.4, 1.0, 0.6))
	await _frames(60)
	_player.visible = false
	var flue: Vector3 = (stove.get_node(^"StoveVisual") as Node3D).to_global(StoveVisual.flue_base())
	await _shot("3_inside_flue", stove.to_global(Vector3(3.0, 1.5, 1.6)), Vector3(flue.x, (flue.y + ceiling) * 0.5, flue.z), weather, smoke)
	print("[chimney] done")
	quit(0)


func _frames(count: int) -> void:
	for _i: int in range(count):
		await process_frame


func _shot(shot_name: String, from: Vector3, at: Vector3, weather: WeatherController, smoke: ChimneySmoke) -> void:
	var previous := root.get_camera_3d()
	var camera := Camera3D.new()
	camera.fov = 55.0
	root.add_child(camera)
	camera.look_at_from_position(from, at)
	camera.make_current()
	await _frames(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out).path_join(shot_name + ".png"))
	var wind: Vector3 = weather.get_wind_direction() * weather.get_wind_speed_mps() if weather != null else Vector3.ZERO
	print("[chimney] %s emitting=%s ratio=%.2f wind=%.2f m/s (%.2f, %.2f)" % [shot_name, smoke.emitting,
		smoke.amount_ratio, wind.length(), wind.x, wind.z])
	camera.queue_free()
	if previous != null:
		previous.make_current()
