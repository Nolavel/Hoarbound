extends SceneTree

## Backpack stage 2 (#260): the canvas pack on Henry in Key West Reality. He stands, sprints off
## and stops (the pack swings from its straps), then the pack opens top-only and fully for the Hub.
## A fixed side camera; 30 fps PNG frames for a video.
## Run: xvfb-run godot --path . --rendering-driver vulkan --fixed-fps 30 --script res://tools/runtime/capture_backpack_worn.gd -- <out dir>

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
const FPS: int = 30

var _out: String = "user://shots/backpack_worn"
var _frame: int = 0
var _camera: Camera3D
var _player: Player
var _caption: Label


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
	_caption = Label.new()
	_caption.position = Vector2(24, 20)
	_caption.add_theme_font_size_override("font_size", 28)
	root.add_child(_caption)
	_camera = Camera3D.new()
	_camera.fov = 45.0
	root.add_child(_camera)
	_camera.make_current()
	var pack: PackRig = _player.animation_component.get_pack_rig()
	print("[packworn] pack visible ", pack.is_visible_in_tree(), " canvas ", pack.use_canvas_model)

	await _record(1.2, "WORN, STANDING", -out)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _record(1.4, "SPRINT OFF: the pack lags and swings", -out)
	Input.action_release(&"sprint")
	Input.action_release(&"move_forward")
	await _record(1.6, "STOP: it swings on and settles", -out)
	pack.set_openness(PackRig.Openness.TOP_ONLY)
	await _record(1.4, "TOP-ONLY (quick stow): the front panel opens a little", -out)
	pack.set_openness(PackRig.Openness.FULL)
	await _record(1.8, "FULL (Hub): the front panel folds down", -out)
	pack.set_openness(PackRig.Openness.CLOSED)
	await _record(1.2, "CLOSED", -out)
	print("[packworn] frames ", _frame)
	quit(0)


## Records seconds of frames from beside and a little behind Henry, following him.
func _record(seconds: float, caption: String, away: Vector3) -> void:
	_caption.text = caption
	for _i: int in range(roundi(seconds * FPS)):
		var henry: Vector3 = _player.global_position
		var facing: Vector3 = -_player.global_basis.z
		facing.y = 0.0
		facing = facing.normalized()
		var right: Vector3 = facing.cross(Vector3.UP)
		_camera.look_at_from_position(henry - right * 2.0 - facing * 1.0 + Vector3.UP * 0.8, henry + Vector3.UP * 0.35 - facing * 0.2)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out).path_join("f_%03d.png" % _frame))
		_frame += 1


func _frames(count: int) -> void:
	for _i: int in range(count):
		await process_frame
