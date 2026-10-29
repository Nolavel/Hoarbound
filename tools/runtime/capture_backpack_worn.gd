extends SceneTree

## Backpack on Henry (#260) in Key West Reality: round him for the shoulder straps, a sprint and stop
## (pack and carabiners swing), then the zip for a quick stow and for the Hub. 30 fps PNG frames.
## Run: xvfb-run godot --path . --rendering-driver vulkan --fixed-fps 30 --script res://tools/runtime/capture_backpack_worn.gd -- <out dir>

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
const FPS: int = 30

var _out: String = "user://shots/backpack_worn"
var _frame: int = 0
var _camera: Camera3D
var _player: Player
var _caption: Label
var _pack_spot: Vector3 = Vector3.ZERO


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

	await _record(3.0, "SHOULDER STRAPS: round Henry", &"orbit")
	await _record(1.0, "WORN, STANDING", &"side")
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _record(1.4, "SPRINT OFF: the pack and its carabiners swing", &"side")
	Input.action_release(&"sprint")
	Input.action_release(&"move_forward")
	await _record(1.6, "STOP: they swing on and settle", &"side")
	await _record(0.6, "ZIP CLOSED: two sliders meet at the top", &"behind")
	pack.set_openness(PackRig.Openness.TOP_ONLY)
	await _record(1.8, "QUICK STOW: sliders part a little, the top folds out", &"behind")
	pack.set_openness(PackRig.Openness.CLOSED)
	await _record(1.2, "CLOSED AGAIN", &"behind")
	pack.set_openness(PackRig.Openness.FULL)
	await _record(2.4, "HUB: sliders run down, the panel opens behind them", &"behind")
	pack.set_openness(PackRig.Openness.CLOSED)
	await _record(2.4, "CLOSING: the panel folds up, the sliders zip it shut", &"behind")
	## Off his back the straps go limp on the snow by the pack.
	var spot: Vector3 = _player.global_position - _player.global_basis.z * 0.8
	spot.y = SnowShell.active.field.get_snow_top(spot.x, spot.z)
	var floor := Transform3D(_player.global_basis, spot)
	_player.animation_component.call(&"set_pack_down", floor, floor.translated(_player.global_basis.x * 0.6))
	_pack_spot = spot
	await _record(2.4, "PACK OFF: the straps lie limp", &"pack")
	print("[packworn] frames ", _frame)
	quit(0)


## Records seconds of frames following Henry: from the side, round him, or close behind the pack.
func _record(seconds: float, caption: String, view: StringName) -> void:
	_caption.text = caption
	var count: int = roundi(seconds * FPS)
	for i: int in range(count):
		var henry: Vector3 = _player.global_position
		var facing: Vector3 = -_player.global_basis.z
		facing.y = 0.0
		facing = facing.normalized()
		var right: Vector3 = facing.cross(Vector3.UP)
		match view:
			&"orbit":
				var turn: float = TAU * float(i) / count
				var around: Vector3 = facing.rotated(Vector3.UP, turn + PI * 0.25)
				_camera.look_at_from_position(henry + around * 1.5 + Vector3.UP * 0.75, henry + Vector3.UP * 0.55)
			&"pack":
				var round_pack: Vector3 = facing.rotated(Vector3.UP, PI * 0.6 + TAU * 0.3 * float(i) / count)
				_camera.look_at_from_position(_pack_spot + round_pack * 1.0 + Vector3.UP * 0.7, _pack_spot + Vector3.UP * 0.2)
			&"behind":
				_camera.look_at_from_position(henry - facing * 1.05 + right * 0.35 + Vector3.UP * 0.85, henry + Vector3.UP * 0.6 - facing * 0.25)
			_:
				_camera.look_at_from_position(henry - right * 2.0 - facing * 1.0 + Vector3.UP * 0.8, henry + Vector3.UP * 0.35 - facing * 0.2)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out).path_join("f_%03d.png" % _frame))
		_frame += 1


func _frames(count: int) -> void:
	for _i: int in range(count):
		await process_frame
