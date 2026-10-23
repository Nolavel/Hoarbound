extends SceneTree

## The production vitals HUD in Key West Reality: blizzard outdoors, a critical night and the
## 727 stove room. Vitals, body temperature and extremity cold are set through their systems.
## Run: xvfb-run godot --path . --rendering-driver vulkan --fixed-fps 30 --script res://tools/runtime/capture_vitals_hud.gd -- <out dir>

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"

var _out: String = "user://shots/vitals_hud"
var _world: Node3D
var _player: Player
var _bio: BioMonitorManager
var _thermal: ThermalManager
var _weather: Node


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
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
	_bio = _player.get_node(^"BioMonitorManager") as BioMonitorManager
	_thermal = ctx.get_system(preload("res://scripts/systems/survival/thermal_manager.gd")) as ThermalManager
	_weather = ctx.get_system(preload("res://scripts/systems/world/WeatherController.gd"))
	for node: Node in _world.find_children("*", "DayNightManager", true, false):
		node.set(&"total_game_time_hours", floorf(float(node.get(&"total_game_time_hours")) / 24.0) * 24.0 + 13.0)
		node.call(&"force_update_lighting")
	_weather.call(&"set_weather", &"blizzard", true, 9999.0)
	for _i: int in range(200):
		await process_frame
	await _state("1_blizzard_face", [0.72, 0.70, 0.82], 34.9, {"head": 0.55, "hands": 0.3, "feet": 0.0}, -0.004)
	await _state("2_night_critical", [0.55, 0.42, 0.30], 30.6, {"head": 0.8, "hands": 0.9, "feet": 1.0}, -0.012)
	_weather.call(&"set_weather", &"calm", true, 9999.0)
	var shelter: Node = _world.find_children("*", "", true, false).filter(func(n: Node) -> bool: return n is KeyWest727Shelter)[0]
	var feed: HeatSourceFeed = shelter.find_child("Feed", true, false) as HeatSourceFeed
	feed.heat_source.restore_fuel(0.8, true)
	_player.global_position = feed.heat_source.to_global(Vector3(2.1, 0.0, 1.0)) + Vector3.UP * 1.1
	_player.velocity = Vector3.ZERO
	for _i: int in range(30):
		await process_frame
	var camera := root.get_camera_3d()
	var dir: Vector3 = (feed.focus_anchor.global_position - camera.global_position).normalized()
	camera.call(&"set_look", atan2(-dir.x, -dir.z), rad_to_deg(asin(dir.y)))
	await _state("3_thawing_at_stove", [0.24, 0.62, 0.72], 33.4, {"head": 0.0, "hands": 0.35, "feet": 0.25}, 0.012)
	print("[vitals_hud] done")
	quit(0)


## Sets thirst, hunger and sleep, body temperature and extremity cold, then drifts the body
## temperature by `drift` per frame for two seconds so the trend chevrons show.
func _state(name: String, vitals: Array, body_c: float, extremities: Dictionary, drift: float) -> void:
	_bio.current_hydration = _bio.max_hydration * float(vitals[0])
	_bio.current_calories = _bio.max_calories * float(vitals[1])
	_bio.current_energy = _bio.max_energy * float(vitals[2])
	_bio.update_ui_signals()
	_thermal.load_save_data({"body_temp_c": body_c, "extremities": extremities})
	for _i: int in range(60):
		_thermal.apply_body_temperature_delta(drift)
		_bio.current_hydration -= 0.02
		_bio.update_ui_signals()
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out).path_join(name + ".png"))
	print("[vitals_hud] ", name, " body=%.1f felt=%.0f" % [_thermal.get_body_temperature_c(), _thermal.get_felt_temperature_c()])
