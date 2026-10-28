extends SceneTree

## Work gloves in Key West Reality: on the 727 cabinet shelf with the door open, then worn by
## Henry, framed through the production TPS camera.
## Run: xvfb-run godot --path . --rendering-driver vulkan --fixed-fps 30 --script res://tools/runtime/capture_gloves.gd -- <out dir>

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"

var _out: String = "user://shots/gloves"
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
	var gloves := _world.find_children("GlovesShelter", "", true, false)[0] as Node3D
	var cabinet: Cabinet = _world.find_children("*", "", true, false).filter(func(n: Node) -> bool: return n is Cabinet)[0]
	print("[gloves] cabinet ", cabinet.get_path(), " open=", cabinet.is_open())
	if not cabinet.is_open():
		cabinet.interact()
	var out: Vector3 = -gloves.global_basis.z
	out.y = 0.0
	await _shot("1_cabinet_open", gloves.global_position + out.normalized() * 1.3, gloves.global_position)
	var equipment := _player.get_node(^"EquipmentComponent") as EquipmentComponent
	print("[gloves] equip refusal=", equipment.equip(&"hands_outer", &"work_gloves"))
	await _shot("2_worn", gloves.global_position + out.normalized() * 1.6, gloves.global_position + Vector3.DOWN * 0.3)
	print("[gloves] hand cover=", equipment.get_region_protection(&"hands"))
	await _close_up("3_shelf_close", gloves.global_position + out.normalized() * 0.55 + Vector3.UP * 0.25, gloves.global_position)
	_player.global_position = gloves.global_position + out.normalized() * 1.2 + Vector3.DOWN * 0.375
	var hands: Vector3 = _player.global_position + Vector3.UP * 0.95
	var front: Vector3 = -_player.global_basis.z
	front.y = 0.0
	await _close_up("4_hands_close", hands + front.normalized() * 1.1 + Vector3.UP * 0.2, hands)
	print("[gloves] done")
	quit(0)


## A capture-only camera at `from` looking at `at`; the gameplay camera is restored after.
func _close_up(shot_name: String, from: Vector3, at: Vector3) -> void:
	var previous := root.get_camera_3d()
	var camera := Camera3D.new()
	camera.fov = 40.0
	root.add_child(camera)
	camera.look_at_from_position(from, at)
	camera.make_current()
	for _i: int in range(20):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out).path_join(shot_name + ".png"))
	print("[gloves] ", shot_name)
	camera.queue_free()
	if previous != null:
		previous.make_current()


## Stands Henry at `stand`, aims the camera at `look` for a moment and saves a frame.
func _shot(shot_name: String, stand: Vector3, look: Vector3) -> void:
	_player.global_position = Vector3(stand.x, look.y, stand.z)
	_player.velocity = Vector3.ZERO
	for _i: int in range(60):
		var camera := root.get_camera_3d()
		var dir: Vector3 = (look - camera.global_position).normalized()
		camera.call(&"set_look", atan2(-dir.x, -dir.z), rad_to_deg(asin(dir.y)))
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out).path_join(shot_name + ".png"))
	print("[gloves] ", shot_name)
