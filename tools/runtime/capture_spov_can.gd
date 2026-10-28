extends SceneTree

## SPoV canned meat in Key West Reality: on the 727 cabinet's bottom shelf with the door open,
## through the production TPS camera, then close-ups of the label, the sealed and the open can.
## Run: xvfb-run godot --path . --rendering-driver vulkan --fixed-fps 30 --script res://tools/runtime/capture_spov_can.gd -- <out dir>

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"

var _out: String = "user://shots/spov_can"
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
	for node: Node in _world.find_children("*", "DayNightManager", true, false):
		node.set(&"total_game_time_hours", floorf(float(node.get(&"total_game_time_hours")) / 24.0) * 24.0 + 13.0)
		node.call(&"force_update_lighting")
	for _i: int in range(120):
		await process_frame
	var can := _world.find_children("SPoVCanShelter", "", true, false)[0] as Node3D
	var cabinet: Cabinet = _world.find_children("*", "", true, false).filter(func(n: Node) -> bool: return n is Cabinet)[0]
	print("[spov] cabinet ", cabinet.get_path(), " open=", cabinet.is_open(), " can at ", can.global_position)
	if not cabinet.is_open():
		cabinet.interact()
	var cab: Node3D = cabinet.get_parent() as Node3D
	var out: Vector3 = cab.global_basis.z
	out.y = 0.0
	out = out.normalized()
	var label: Vector3 = can.global_position + Vector3.UP * 0.035
	## Henry's eye height in front of the open cabinet: the room, the cabinet and the can.
	## From the side away from the open door, which hides the hinge side of the shelf.
	var right: Vector3 = (-out).cross(Vector3.UP).normalized()
	_player.global_position = can.global_position + out * 1.8 - right * 0.8
	await _close_up("1_cabinet_in_727", can.global_position + out * 1.15 + right * 0.45 + Vector3.UP * 0.8, label + Vector3.UP * 0.2, 55.0)
	await _close_up("2_shelf", label + out * 0.75 + Vector3.UP * 0.22, label)
	await _close_up("3_label", label + out * 0.28 + Vector3.UP * 0.06, label)
	var open: Node3D = SurvivalItemVisual.make(&"spov_can_open")
	cab.add_child(open)
	open.global_transform = can.global_transform.translated(can.global_basis.x * 0.0 + out * 0.0 + Vector3.UP * 0.0)
	open.global_position = can.global_position + can.global_basis.x * -0.14
	await _close_up("4_open_beside", label + out * 0.45 + Vector3.UP * 0.25 + can.global_basis.x * -0.07, label + can.global_basis.x * -0.07)
	print("[spov] done")
	quit(0)


## A capture-only camera at `from` looking at `at`; the gameplay camera is restored after.
func _close_up(shot_name: String, from: Vector3, at: Vector3, fov: float = 40.0) -> void:
	var previous := root.get_camera_3d()
	var camera := Camera3D.new()
	camera.fov = fov
	root.add_child(camera)
	camera.look_at_from_position(from, at)
	camera.make_current()
	for _i: int in range(20):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out).path_join(shot_name + ".png"))
	print("[spov] ", shot_name)
	camera.queue_free()
	if previous != null:
		previous.make_current()
