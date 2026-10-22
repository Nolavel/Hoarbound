extends SceneTree

## Native main-scene proof: physical held lighter, filtered SFX output and door snow snapshots.
const OUT: String = "res://.godot/codex-checks/live-stove-final"
const SCENE: String = "res://archive/graciosa/scenes/Graciosa_Island_Terrain.tscn"
var _camera: Camera3D
var _record: AudioEffectRecord
var _bus: int = -1
var _peak: float = -200.0
var _recording: bool = false
var _frame_left: float = 0.0
var _frame_index: int = 0
var _frames: Array[Dictionary] = []
var _started_ms: int = 0


func _initialize() -> void:
	call_deferred(&"_run")


func _process(delta: float) -> bool:
	if _recording:
		_peak = maxf(_peak, AudioServer.get_bus_peak_volume_left_db(_bus, 0))
		_frame_left -= delta
		if _frame_left <= 0.0:
			_frame_left = 0.2
			_capture_frame.call_deferred()
	return false


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1280, 720)
	var scene := (load(SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	await create_timer(3.0).timeout
	var stove := root.find_child("ShelterZone", true, false).get_node(^"Stove") as HeatSource
	var feed := stove.get_node(^"Feed") as HeatSourceFeed
	var player := get_first_node_in_group(&"player") as Player
	player.set_physics_process(false)
	player.global_position = stove.to_global(Vector3(0.95, 0.9, 0.0))
	player.rotation.y = stove.global_rotation.y + PI * 0.5
	var inventory: InventoryComponent = InventoryComponent.find_in(player)
	for entry: Dictionary in inventory.get_entries():
		var item: ItemResource = ItemCatalog.get_item(entry["id"])
		if item.carried_in_hands:
			for _i: int in range(int(entry["count"])):
				inventory.try_remove(item.id)
	inventory.try_add(ItemCatalog.get_item(&"lighter"))
	inventory.try_add(ItemCatalog.get_item(&"tinder"))
	stove.restore_fuel(0.0, false)
	stove.add_logs(2)
	feed.toggle_door()
	_camera = Camera3D.new()
	root.add_child(_camera)
	_camera.global_position = stove.to_global(Vector3(2.2, 1.35, 1.05))
	_camera.look_at(feed.focus_anchor.global_position)
	_camera.fov = 52.0
	_camera.make_current()
	var listener := AudioListener3D.new()
	player.add_child(listener)
	listener.make_current()
	await create_timer(1.0).timeout
	var sound: Node = root.get_node(^"SoundSystem")
	sound.call(&"set_parameter", &"interior", 1.0)
	await create_timer(0.8).timeout
	_bus = AudioServer.get_bus_index(&"SFX")
	_record = AudioEffectRecord.new()
	AudioServer.add_bus_effect(_bus, _record)
	_record.set_recording_active(true)
	_started_ms = Time.get_ticks_msec()
	_recording = true
	feed.strike_success_chance = 0.0
	## The ritual's state at the lighter: Henry working the stove, logs and tinder laid.
	feed.session_active = true
	stove.set_tinder_prepared(true)
	print("[live stove] prepare=", feed.prepare_lighter(), " audio=", AudioServer.get_driver_name(), " interior=", sound.call(&"get_parameter", &"interior"))
	feed.attempt_lighter_strike()
	await _shot("01_sparks")
	await create_timer(0.7).timeout
	feed.strike_success_chance = 1.0
	feed.attempt_lighter_strike()
	print("[live stove] held flame=", feed._flame_held, " visual=", feed._lighter.is_flame_visible())
	await create_timer(0.2).timeout
	await _shot("02_held_lighter")
	await create_timer(1.0).timeout
	feed.release_lighter()
	print("[live stove] session=", feed._ignition_session, " strike_count=", feed._strike_count, " released flame=", feed._flame_held, " burning=", stove.is_burning())
	await _shot("03_released")
	await create_timer(0.4).timeout
	feed.attempt_lighter_strike()
	await create_timer(3.2).timeout
	print("[live stove] caught=", stove.is_burning(), " intensity=", stove.get_intensity())
	await _shot("04_kindling")
	await create_timer(20.5).timeout
	print("[live stove] developed intensity=", stove.get_intensity(), " remaining_ramp=", stove._warmup_remaining_h, " socket distance=", feed._animation.get_hand_socket().global_position.distance_to(player.global_position))
	await _shot("05_developed")
	var door := stove.get_parent().get_parent().get_node(^"HouseDoor") as HingedDoor
	var weather := root.find_child("Weather", true, false) as WeatherController
	if weather == null:
		for node: Node in root.find_children("*", "", true, false):
			if node is WeatherController:
				weather = node as WeatherController
	var blizzard: WeatherProfile = load("res://resources/weather/blizzard.tres").duplicate() as WeatherProfile
	blizzard.wind_direction_deg = rad_to_deg(atan2(breach_wind(door).x * -1.0, breach_wind(door).z * -1.0))
	blizzard.wind_direction_jitter_deg = 0.0
	blizzard.snowfall_density = 1.0
	blizzard.wind_speed_mps = 17.0
	blizzard.gust_speed_mps = 11.0
	weather.profiles.append(blizzard)
	weather._current = blizzard
	weather._previous = null
	weather._blend = 1.0
	player.visible = false
	_camera.global_position = door.to_global(Vector3(0.0, 0.0, -1.7))
	_camera.look_at(door.global_position)
	_camera.fov = 60.0
	player.global_position = door.to_global(Vector3(0.0, -0.05, -1.2))
	await create_timer(2.0).timeout
	print("[live door] closed strength=", (door.breach.get_node(^"Draft") as BreachDraft).get_strength(), " snowfall=", weather.get_snowfall_density(), " wind=", weather.get_wind_direction())
	await _shot("06_door_closed_blizzard")
	_camera.global_position = door.to_global(Vector3(0.63, 0.0, -0.8))
	_camera.look_at(door.to_global(Vector3(0.73, -0.1, 0.0)))
	await create_timer(1.2).timeout
	await _shot("06b_door_gap_detail")
	_camera.global_position = door.to_global(Vector3(0.0, 0.0, -1.7))
	_camera.look_at(door.global_position)
	door.interact()
	await create_timer(0.35).timeout
	await _shot("07_door_moving")
	await create_timer(1.0).timeout
	print("[live door] open strength=", (door.breach.get_node(^"Draft") as BreachDraft).get_strength())
	await _shot("08_door_open_blizzard")
	door.interact()
	await create_timer(1.0).timeout
	blizzard.snowfall_density = 0.0
	await create_timer(2.0).timeout
	await _shot("09_door_without_snow")
	_recording = false
	_record.set_recording_active(false)
	var audio: AudioStreamWAV = _record.get_recording()
	audio.save_to_wav(OUT + "/lighter-indoor.wav")
	var report: Dictionary = {"driver": AudioServer.get_driver_name(), "sfx_peak_db": _peak, "audio_bytes": audio.data.size(), "frames": _frames}
	var file := FileAccess.open(OUT + "/capture.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("[live stove] output=", ProjectSettings.globalize_path(OUT), " peak_db=", _peak, " bytes=", audio.data.size())
	quit()


func breach_wind(door: HingedDoor) -> Vector3:
	return -door.breach.get_facing()


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "/" + label + ".png")


func _capture_frame() -> void:
	await RenderingServer.frame_post_draw
	var name: String = "frame_%05d.png" % _frame_index
	root.get_texture().get_image().save_png(OUT + "/" + name)
	_frames.append({"file": name, "seconds": float(Time.get_ticks_msec() - _started_ms) / 1000.0})
	_frame_index += 1
