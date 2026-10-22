extends SceneTree

## The stove ritual in the 727 Fort St shelter (Key West Reality), driven by real input through the
## production TPS camera: eight named frames and a continuous frame run for a video.
## Run: xvfb-run godot --path . --rendering-driver vulkan --fixed-fps 30 --script res://tools/runtime/capture_stove.gd -- <out dir>
## Frames: 1 before F, 2 crouched with the empty ring, 3 one log, 4 three logs, 5 tinder laid,
## 6 holding the lighter, 7 the fire growing, 8 the door closed and Henry up. video/ holds every
## other frame of the whole run.

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
## Evening, so the stove's light on the room reads against the interior.
const HOUR: float = 18.6
const VIDEO_EVERY: int = 2

var _out: String = "user://shots/stove"
var _world: Node3D
var _player: Player
var _feed: HeatSourceFeed
var _source: HeatSource
var _control: StoveInteractionController
var _frame: int = 0
var _video: int = 0
var _recording: bool = false


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out).path_join("video"))
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
	for node: Node in _world.find_children("*", "CanvasLayer", true, false):
		node.set(&"visible", false)
	var weather: Node = ctx.get_system(preload("res://scripts/systems/world/WeatherController.gd"))
	weather.call(&"set_weather", &"calm", true, 9999.0)
	for node: Node in _world.find_children("*", "DayNightManager", true, false):
		node.set(&"total_game_time_hours", floorf(float(node.get(&"total_game_time_hours")) / 24.0) * 24.0 + HOUR)
		node.call(&"force_update_lighting")
		node.set_process(false)
	for _i: int in range(90):
		await process_frame
	var shelter: Node = _world.find_children("*", "", true, false).filter(func(n: Node) -> bool: return n is KeyWest727Shelter)[0]
	_feed = shelter.find_child("Feed", true, false) as HeatSourceFeed
	_source = _feed.heat_source
	_control = _feed.controller
	_source.restore_fuel(0.0, false)
	_source.set_tinder_prepared(false)
	var inventory: InventoryComponent = InventoryComponent.find_in(_player)
	for _i: int in range(3):
		inventory.try_add(ItemCatalog.get_item(&"firewood"))
	inventory.try_add(ItemCatalog.get_item(&"tinder"))
	inventory.try_add(ItemCatalog.get_item(&"lighter"))
	## Henry two metres before the door, inside the heated room, looking at the stove.
	var stand: Vector3 = _floor_point(_source.to_global(Vector3(2.0, 0.0, 0.35)))
	_player.global_position = stand + Vector3.UP * 1.0
	_player.velocity = Vector3.ZERO
	_player.look_at(Vector3(_source.global_position.x, _player.global_position.y, _source.global_position.z), Vector3.UP)
	## The player's mouse: the TPS aim on the firebox, so F names the stove.
	for _i: int in range(3):
		_aim_camera(_feed.focus_anchor.global_position)
		for _f: int in range(15):
			await process_frame
	_recording = true
	await _shot("1_before_f")
	_press_interact()
	await _until(func() -> bool: return _control.is_working(), 12.0)
	await _hold(0.6)
	await _shot("2_crouched_empty_ring")
	_mouse(MOUSE_BUTTON_RIGHT, true)
	_mouse(MOUSE_BUTTON_RIGHT, false)
	await _until(func() -> bool: return not _feed.is_acting(), 5.0)
	await _hold(0.3)
	await _shot("3_one_log")
	for _log: int in range(2):
		_mouse(MOUSE_BUTTON_RIGHT, true)
		_mouse(MOUSE_BUTTON_RIGHT, false)
		await _until(func() -> bool: return not _feed.is_acting(), 5.0)
	await _hold(0.3)
	await _shot("4_three_logs")
	_mouse(MOUSE_BUTTON_LEFT, true)
	await _until(func() -> bool: return _source.is_tinder_prepared(), 5.0)
	await _hold(0.4)
	_mouse(MOUSE_BUTTON_LEFT, false)
	await _hold(0.2)
	await _shot("5_tinder_laid")
	await _until(func() -> bool: return _feed.get_stage() == HeatSourceFeed.Stage.READY, 8.0)
	_mouse(MOUSE_BUTTON_LEFT, true)
	await _hold(HeatSourceFeed.LIGHT_SECONDS * 0.55)
	await _shot("6_lighter_hold")
	await _until(func() -> bool: return _source.is_burning(), 5.0)
	_mouse(MOUSE_BUTTON_LEFT, false)
	await _hold(5.0)
	await _shot("7_fire_growing")
	_press_interact()
	await _until(func() -> bool: return not _control.is_active(), 5.0)
	await _hold(1.2)
	await _shot("8_door_closed_up")
	_recording = false
	print("[stove] logs=%d tinder=%s burning=%s intensity=%.2f video_frames=%d" % [_source.get_loaded_log_count(),
		_source.is_tinder_prepared(), _source.is_burning(), _source.get_intensity(), _video])
	quit(0)


func _process(_delta: float) -> bool:
	## Debug HUD layers come and go; only the stove ring stays on the frames.
	if _frame % 15 == 0 and _world != null:
		for node: Node in _world.find_children("*", "CanvasLayer", true, false):
			if node.name != &"StoveRingLayer":
				node.set(&"visible", false)
	if _recording:
		_frame += 1
		if _frame % VIDEO_EVERY == 0:
			_video += 1
			_save(ProjectSettings.globalize_path(_out).path_join("video/%05d.png" % _video))
	return false


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	_save(ProjectSettings.globalize_path(_out).path_join(name + ".png"))
	print("[stove] shot ", name, " phase=", _control.get_phase(), " logs=", _source.get_loaded_log_count(),
		" tinder=", _source.is_tinder_prepared(), " stage=", _feed.get_stage(), " burning=", _source.is_burning())


func _save(path: String) -> void:
	root.get_texture().get_image().save_png(path)


func _until(done: Callable, seconds: float) -> void:
	var frames: int = int(seconds * 30.0)
	for _i: int in range(frames):
		if done.call():
			return
		await process_frame


func _hold(seconds: float) -> void:
	for _i: int in range(int(seconds * 30.0)):
		await process_frame


func _press_interact() -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = &"interact"
		event.pressed = pressed
		root.push_input(event)


func _mouse(button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	root.push_input(event)


## The production TPS camera turned so its aim passes through the point.
func _aim_camera(point: Vector3) -> void:
	var camera := root.get_camera_3d()
	if camera == null or not camera.has_method(&"set_look"):
		return
	var dir: Vector3 = (point - camera.global_position).normalized()
	camera.call(&"set_look", atan2(-dir.x, -dir.z), rad_to_deg(asin(clampf(dir.y, -1.0, 1.0))))


func _floor_point(at: Vector3) -> Vector3:
	var space: PhysicsDirectSpaceState3D = _world.get_world_3d().direct_space_state
	var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.6, at + Vector3.DOWN * 2.0))
	return hit["position"] if not hit.is_empty() else at
