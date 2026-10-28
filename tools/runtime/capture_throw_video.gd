extends SceneTree

## #257 clip: by 727, Henry scoops a handful, aims (the arc and its sway show), throws it at a
## neighbour's window (crack and splat), then throws a stone at it (it breaks). 30 fps PNG frames.
## Run: xvfb-run godot --path . --rendering-driver vulkan --fixed-fps 30 --script res://tools/runtime/capture_throw_video.gd -- <out dir>

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
const THROW_DISTANCE_M: float = 8.0

var _out: String = "user://shots/throw_video"
var _frame: int = 0
var _tps: TpsCamera
var _target: Vector3


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
	var ground := world.find_children("RealityGround", "", true, false)[0] as KeyWestRealityGround
	var breakage := world.find_children("WindowBreakage", "", true, false)[0] as WindowBreakage
	var door := world.find_children("HouseDoor", "", true, false)[0] as Node3D
	await _frames(60)

	## A ground-floor pane of a generated house near 727 with open snow in front of it.
	var pane: Dictionary = {}
	var best: float = INF
	for mesh: Node in world.find_children("*", "MeshInstance3D", true, false):
		var at: Vector3 = (mesh as Node3D).global_position
		if at.distance_to(door.global_position) > 60.0:
			continue
		for candidate: Dictionary in breakage.call(&"_facade_panes", mesh):
			var centre: Vector3 = candidate["centre"]
			var stand: Vector3 = centre + (candidate["normal"] as Vector3) * THROW_DISTANCE_M
			var floor_y: float = ground.get_surface_height(stand.x, stand.z)
			var score: float = centre.distance_to(door.global_position)
			if centre.y - floor_y > 2.6 or ground.has_snow_obstacle_at(Vector2(stand.x, stand.z)) or score >= best:
				continue
			best = score
			pane = candidate
	print("[throwvid] pane ", pane.get("key"), " at ", pane.get("centre"))
	var normal: Vector3 = pane["normal"]
	var target: Vector3 = pane["centre"]
	var stand: Vector3 = target + normal * THROW_DISTANCE_M
	stand.y = ground.get_surface_height(stand.x, stand.z) + 1.0
	player.global_position = stand
	player.look_at(Vector3(target.x, stand.y, target.z), Vector3.UP)
	await _frames(90)

	## The game's own camera, looking at the pane past Henry: the aim push-in is its doing.
	var tps := root.get_camera_3d() as TpsCamera
	_tps = tps
	_target = target
	var look: Vector3 = (target - (stand + Vector3.UP * 0.6)).normalized()
	tps.set_look(atan2(-look.x, -look.z), rad_to_deg(asin(look.y)) - 4.0)
	var inventory := player.get_node(^"InventoryComponent") as InventoryComponent
	var held := player.get_node(^"HeldItemComponent") as HeldItemComponent
	var interact := player.get_node(^"InteractComponent") as InteractComponent
	await _record(20)

	## Scoop a handful (F on the snow), aim, throw.
	interact.try_interact()
	await _record(30)
	print("[throwvid] in hand: ", held.get_item_id())
	await _aim_and_throw(45)
	await _record(40)
	print("[throwvid] after snowball: ", breakage.get_pane_state(pane["key"]))

	## A stone from the pocket: aim, throw.
	inventory.try_add(load("res://data/items/stone.tres") as ItemResource)
	held.present_owned(&"stone")
	await _record(10)
	await _aim_and_throw(40)
	await _record(60)
	print("[throwvid] after stone: ", breakage.get_pane_state(pane["key"]), " frames ", _frame)
	## Looking up hard from deep snow: the lens must stay above the snow top.
	tps.set_look(atan2(-look.x, -look.z), 55.0)
	await _record(45)
	var lens: Vector3 = tps.global_position
	print("[throwvid] look-up: camera %.2f m above the snow top" % (lens.y - SnowShell.active.field.get_snow_top(lens.x, lens.z)))
	quit(0)


func _aim_and_throw(aim_frames: int) -> void:
	_press(&"present_held", true)
	## Like a player, keep the screen centre on the pane while the camera closes in.
	for _i: int in range(aim_frames):
		var from: Vector3 = _tps.global_position
		var look: Vector3 = (_target - from).normalized()
		_tps.set_look(atan2(-look.x, -look.z), rad_to_deg(asin(look.y)))
		await _record(1)
	_press(&"fire", true)
	_press(&"fire", false)
	await _record(2)
	_press(&"present_held", false)


func _press(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)


func _frames(count: int) -> void:
	for _i: int in range(count):
		await process_frame


func _record(count: int) -> void:
	for _i: int in range(count):
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out).path_join("f_%03d.png" % _frame))
		_frame += 1
