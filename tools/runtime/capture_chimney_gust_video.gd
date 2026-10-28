extends SceneTree

## Five seconds of one real gust at the 727 chimney (#252), 30 fps PNG frames for a video.
## The weather's own gust curve is searched for its steepest 5 s rise and the clip starts there;
## Henry, hidden, stands on the roof so the wind streaks and roof drift play around the chimney.
## Run: xvfb-run godot --path . --rendering-driver vulkan --fixed-fps 30 --script res://tools/runtime/capture_chimney_gust_video.gd -- <out dir>

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
const WEATHER_ID: StringName = &"windy"
const HOUR: float = 14.0
const FPS: int = 30
const CLIP_S: float = 5.0
const SEARCH_S: float = 600.0
## The plume's lifetime of smoke history before the clip, run at this game-speed multiple.
const PREROLL_S: float = 7.0
const PREROLL_SPEED: float = 7.0

var _out: String = "user://shots/chimney_gust"


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_run()


func _run() -> void:
	var world := (load(SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(world)
	var ctx: Variant = null
	for _i: int in range(600):
		await process_frame
		ctx = world.call(&"get_context")
		if ctx != null:
			break
	var player := ctx.player as Player
	var weather: WeatherController = null
	for node: Node in world.find_children("*", "WeatherController", true, false):
		if not (node as WeatherController).profiles.is_empty():
			weather = node as WeatherController
	weather.set_weather(WEATHER_ID, true)
	for node: Node in world.find_children("*", "DayNightManager", true, false):
		node.set(&"total_game_time_hours", floorf(float(node.get(&"total_game_time_hours")) / 24.0) * 24.0 + HOUR)
		node.call(&"force_update_lighting")
	for layer: Node in root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	for control: Node in root.find_children("*", "Control", true, false):
		(control as Control).visible = false
	for label: Node in world.find_children("*", "Label3D", true, false):
		(label as Node3D).visible = false
	var smoke := world.find_children("ChimneySmoke", "", true, false)[0] as ChimneySmoke
	smoke.source.restore_fuel(1.5, true)
	smoke.source.ignite()

	var profile: WeatherProfile = weather.get_current_profile()
	var start: float = _steepest_rise(weather, profile)
	var wind_dir: Vector3 = weather.get_wind_direction()
	var across: Vector3 = Vector3.UP.cross(wind_dir).normalized()
	var cap: Vector3 = smoke.global_position
	var camera := Camera3D.new()
	camera.fov = 50.0
	root.add_child(camera)
	## Ground-level view across the wind, the plume's drift running across the frame.
	var from: Vector3 = cap + across * 17.0 - wind_dir * 3.0
	from.y = cap.y - 3.4
	camera.look_at_from_position(from, cap + wind_dir * 3.5 + Vector3.UP * 0.8)
	camera.make_current()
	## Henry, hidden, on the roof between the camera and the chimney: the streaks spawn ahead of him.
	player.global_position = cap + across * 6.0 + Vector3.UP * 0.2
	player.visible = false
	player.set_physics_process(false)  # held on the roof, not dropped through it
	print("[gust] clip from %.1f s, cap %s, camera %s" % [start, cap, from])

	weather.set(&"_elapsed_s", start - PREROLL_S)
	Engine.time_scale = PREROLL_SPEED
	for _i: int in range(int(PREROLL_S * FPS / PREROLL_SPEED)):
		await process_frame
	Engine.time_scale = 1.0
	weather.set(&"_elapsed_s", start)
	for frame: int in range(int(CLIP_S * FPS)):
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out).path_join("f_%03d.png" % frame))
		if frame % 15 == 0:
			print("[gust] frame %d wind %.2f m/s streaks/drift %s" % [frame, weather.get_wind_speed_mps(), _effect_counts(world)])
	print("[gust] done")
	quit(0)


## Clip start (elapsed seconds) where the authored gust curve rises most over CLIP_S.
func _steepest_rise(weather: WeatherController, profile: WeatherProfile) -> float:
	var noise: FastNoiseLite = weather.get(&"_gust_noise")
	var best: float = PREROLL_S
	var best_rise: float = -INF
	var t: float = PREROLL_S
	while t < SEARCH_S:
		var rise: float = noise.get_noise_1d((t + CLIP_S) / profile.gust_period_s) - noise.get_noise_1d(t / profile.gust_period_s)
		if rise > best_rise:
			best_rise = rise
			best = t
		t += 0.25
	print("[gust] steepest rise %.2f m/s over %.0f s" % [best_rise * 0.5 * profile.gust_speed_mps, CLIP_S])
	return best


func _effect_counts(world: Node) -> Vector2i:
	for gusts: Node in world.find_children("*", "WindGusts", true, false):
		return (gusts as WindGusts).get_active_counts()
	return Vector2i(-1, -1)
