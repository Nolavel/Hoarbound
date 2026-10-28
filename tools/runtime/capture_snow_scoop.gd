extends SceneTree

## Snow by hand (#257 stage 1): Henry on the snow by 727 presses F with a mug in hand, then
## with a free hand. Frames before, mid-stoop and after each scoop, from one steady camera.
## Run: xvfb-run godot --path . --rendering-driver vulkan --fixed-fps 30 --script res://tools/runtime/capture_snow_scoop.gd -- <out dir>

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"

var _out: String = "user://shots/snow_scoop"
var _camera: Camera3D


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
	for weather: Node in world.find_children("*", "WeatherController", true, false):
		weather.call(&"set_weather", &"clear", true)
	for node: Node in world.find_children("*", "DayNightManager", true, false):
		node.set(&"total_game_time_hours", floorf(float(node.get(&"total_game_time_hours")) / 24.0) * 24.0 + 13.0)
		node.call(&"force_update_lighting")
	for layer: Node in root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	for label: Node in world.find_children("*", "Label3D", true, false):
		(label as Node3D).visible = false
	var door := world.find_children("HouseDoor", "", true, false)[0] as Node3D
	var out: Vector3 = door.global_basis.z
	out.y = 0.0
	out = out.normalized()
	var side: Vector3 = Vector3.UP.cross(out).normalized()
	player.global_position = door.global_position + out * 8.0 + Vector3.UP
	player.look_at(player.global_position + side, Vector3.UP)
	await _frames(120)

	var inventory := player.get_node(^"InventoryComponent") as InventoryComponent
	var held := player.get_node(^"HeldItemComponent") as HeldItemComponent
	var scoop := player.get_node(^"SnowScoopComponent") as SnowScoopComponent
	var interact := player.get_node(^"InteractComponent") as InteractComponent
	inventory.try_add(load("res://data/items/mug.tres") as ItemResource)
	print("[scoop] mug in hand: ", held.present_owned(&"mug"), " depth underfoot %.3f m" % scoop.snow_depth_underfoot())
	var henry: Vector3 = player.global_position
	_camera = Camera3D.new()
	_camera.fov = 45.0
	root.add_child(_camera)
	_camera.look_at_from_position(henry + side * 2.2 + out * 1.4 + Vector3.UP * 0.6, henry + Vector3.UP * 0.1)
	_camera.make_current()
	await _frames(30)
	await _save("1_mug_before")
	interact.try_interact()
	await _frames(12)
	await _save("2_mug_stoop")
	await _frames(60)
	await _save("3_mug_snow")
	print("[scoop] mug now: ", held.get_item_id())

	held.put_away()
	await _frames(20)
	interact.try_interact()
	await _frames(12)
	await _save("4_hand_stoop")
	await _frames(60)
	await _save("5_handful")
	print("[scoop] hand now: ", held.get_item_id(), " pack has handful: ", inventory.has_item(&"snow_handful"))
	print("[scoop] done")
	quit(0)


func _frames(count: int) -> void:
	for _i: int in range(count):
		await process_frame


func _save(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out).path_join(shot_name + ".png"))
	print("[scoop] ", shot_name)
