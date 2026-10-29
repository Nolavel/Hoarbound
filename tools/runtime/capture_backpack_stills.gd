extends SceneTree

## Backpack stills (#260): Henry standing in Key West Reality, close up round him and his pack from
## eight sides, one settled PNG each (no video). Part of the backpack stand (BACKPACK_RIG.md).
## Run: xvfb-run godot --path . --rendering-driver vulkan --fixed-fps 30 --script res://tools/runtime/capture_backpack_stills.gd -- <out dir>

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
const FPS: int = 30

var _out: String = "user://shots/backpack_stills"
var _camera: Camera3D
var _player: Player


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
	_player = ctx.player as Player
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
	## Open snow out from 727, Henry facing along the street so the camera sees him side-on.
	_player.global_position = door.global_position + out * 9.0 + Vector3.UP
	_player.look_at(_player.global_position + side, Vector3.UP)
	await _frames(120)
	_camera = Camera3D.new()
	_camera.fov = 45.0
	root.add_child(_camera)
	_camera.make_current()
	var pack: PackRig = _player.animation_component.get_pack_rig()
	print("[packstills] pack visible ", pack.is_visible_in_tree())

	## Eight sides at chest height, a metre out: front, front-left, left, back-left, back, and round.
	var names: PackedStringArray = ["front", "front_left", "left", "back_left", "back", "back_right", "right", "front_right"]
	for k: int in range(names.size()):
		var henry: Vector3 = _player.global_position
		var facing: Vector3 = -_player.global_basis.z
		facing.y = 0.0
		facing = facing.normalized()
		var around: Vector3 = facing.rotated(Vector3.UP, deg_to_rad(45.0 * k))
		_camera.look_at_from_position(henry + around * 1.05 + Vector3.UP * 0.75, henry + Vector3.UP * 0.42)
		await _frames(25)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out).path_join("%d_%s.png" % [k, names[k]]))
	print("[packstills] done")
	quit(0)


func _frames(count: int) -> void:
	for _i: int in range(count):
		await process_frame
