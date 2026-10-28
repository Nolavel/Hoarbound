extends SceneTree

## Shadow look on the shelter edge (#156): Henry inside 727 and outside it, the stylized
## shadow mode switched by the real ShelterGradeBinder, plus the same inside frame forced to
## the outdoor mode for comparison. Clear noon, stove lit.
## Run: xvfb-run godot --path . --rendering-driver vulkan --fixed-fps 30 --script res://tools/runtime/capture_shadow_shelter.gd -- <out dir>

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
const INTERIOR_GLOBAL: StringName = &"stylized_shadow_interior_mode"

var _out: String = "user://shots/shadow_shelter"
var _world: Node3D
var _player: Player


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
	for weather: Node in _world.find_children("*", "WeatherController", true, false):
		weather.call(&"set_weather", &"clear", true)
	for node: Node in _world.find_children("*", "DayNightManager", true, false):
		node.set(&"total_game_time_hours", floorf(float(node.get(&"total_game_time_hours")) / 24.0) * 24.0 + 13.0)
		node.call(&"force_update_lighting")
		node.set_process(false)
	for layer: Node in root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	var stove := _world.find_children("*", "HeatSource", true, false)[0] as HeatSource
	stove.restore_fuel(1.5, true)
	stove.ignite()
	var door := _world.find_children("HouseDoor", "", true, false)[0] as Node3D
	var out: Vector3 = door.global_basis.z
	out.y = 0.0
	out = out.normalized()

	## Inside: Henry by the stove, the binder fades the indoor look in.
	_player.global_position = stove.to_global(Vector3(1.1, 1.0, 0.35))
	await _settle(120)
	print("[shadowcap] inside mode=", RenderingServer.global_shader_parameter_get(INTERIOR_GLOBAL))
	var room_from: Vector3 = stove.to_global(Vector3(3.2, 1.7, 2.6))
	var room_at: Vector3 = stove.to_global(Vector3(1.2, 0.1, 0.3))
	await _shot("1_inside_indoor_look", room_from, room_at)
	RenderingServer.global_shader_parameter_set(INTERIOR_GLOBAL, 0.0)
	await _shot("2_inside_outdoor_look", room_from, room_at)
	## From the room through the open door: the street keeps its outdoor shadows only once Henry is out.
	var door_view_from: Vector3 = door.global_position - out * 2.5 + Vector3.UP * 1.6
	var door_view_at: Vector3 = door.global_position + out * 6.0
	RenderingServer.global_shader_parameter_set(INTERIOR_GLOBAL, 1.0)
	await _shot("3_inside_door_view", door_view_from, door_view_at)

	## Outside: Henry on the street, the binder fades back to the outdoor look.
	_player.global_position = door.global_position + out * 8.0 + Vector3.UP
	await _settle(150)
	print("[shadowcap] outside mode=", RenderingServer.global_shader_parameter_get(INTERIOR_GLOBAL))
	await _shot("4_outside_727", door.global_position + out * 14.0 + Vector3.UP * 1.7, door.global_position + Vector3.UP * 0.8)
	print("[shadowcap] done")
	quit(0)


func _settle(frames: int) -> void:
	for _i: int in range(frames):
		await process_frame


func _shot(shot_name: String, from: Vector3, at: Vector3) -> void:
	var previous := root.get_camera_3d()
	var camera := Camera3D.new()
	camera.fov = 62.0
	root.add_child(camera)
	camera.look_at_from_position(from, at)
	camera.make_current()
	_player.visible = false
	for _i: int in range(30):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out).path_join(shot_name + ".png"))
	print("[shadowcap] ", shot_name, " mode=", RenderingServer.global_shader_parameter_get(INTERIOR_GLOBAL))
	_player.visible = true
	camera.queue_free()
	if previous != null:
		previous.make_current()
