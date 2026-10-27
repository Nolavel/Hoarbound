extends SceneTree

## The 727 wall thermometer in Key West Reality through the production TPS camera: close in the
## cold room, close in the warmed room, and from 4 m where the reading has faded out.
## Run: xvfb-run godot --path . --rendering-driver vulkan --fixed-fps 30 --script res://tools/runtime/capture_thermometer.gd -- <out dir>

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"

var _out: String = "user://shots/thermometer"
var _world: Node3D
var _player: Player
var _thermometer: WallThermometer


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
	for node: Node in _world.find_children("*", "DayNightManager", true, false):
		node.set(&"total_game_time_hours", floorf(float(node.get(&"total_game_time_hours")) / 24.0) * 24.0 + 13.0)
		node.call(&"force_update_lighting")
	for _i: int in range(120):
		await process_frame
	_thermometer = _world.find_children("WallThermometer", "", true, false)[0] as WallThermometer
	await _shot("1_cold_close", 1.4, 0.0)
	_thermometer.zone.restore_heated_offset(_thermometer.zone.max_heated_offset_c)
	await _shot("2_warm_close", 1.4, 0.0)
	await _shot("3_far_faded", 4.0, 0.0)
	print("[thermometer] done")
	quit(0)


## Stands Henry `distance` m in front of the dial, aims the camera at it and saves a frame.
func _shot(shot_name: String, distance: float, side: float) -> void:
	var forward: Vector3 = _thermometer.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var spot: Vector3 = _thermometer.global_position + forward * distance + _thermometer.global_basis.x * side
	_player.global_position = Vector3(spot.x, _thermometer.global_position.y - 1.5 + 0.05, spot.z)
	_player.velocity = Vector3.ZERO
	for _i: int in range(45):
		var camera := root.get_camera_3d()
		var dir: Vector3 = (_thermometer.global_position - camera.global_position).normalized()
		camera.call(&"set_look", atan2(-dir.x, -dir.z), rad_to_deg(asin(dir.y)))
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out).path_join(shot_name + ".png"))
	print("[thermometer] ", shot_name, " air=%.1f alpha=%.2f" % [_thermometer.get_air_c(), _thermometer.get_reading_alpha()])
