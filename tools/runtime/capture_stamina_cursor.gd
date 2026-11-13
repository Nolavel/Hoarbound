extends SceneTree

## Close-ups of the cursor's stamina arcs in the states a player meets: sprinting full, sprinting low,
## winded after running dry, catching breath walking, and nearly full standing.
## Run: xvfb-run godot --path . --rendering-driver vulkan --fixed-fps 60 --resolution 640x360 --script res://tools/runtime/capture_stamina_cursor.gd -- <out dir>

const PLAYER: String = "res://scenes/actors/player/player.tscn"
const CURSOR: String = "res://scenes/ui/hud/dynamic_cursor/mouse_cursor_ui.tscn"

var _out: String = "user://shots/stamina_cursor"


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_run.call_deferred()


func _run() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	root.add_child(floor_body)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.66, 0.72)
	root.add_child(env)
	var player := (load(PLAYER) as PackedScene).instantiate() as Player
	root.add_child(player)
	player.global_position = Vector3(0.0, 1.0, 0.0)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.make_current()
	camera.look_at_from_position(Vector3(0.0, 2.0, 4.0), Vector3(0.0, 1.0, 0.0))
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var cursor := (load(CURSOR) as PackedScene).instantiate() as MouseCursorUI
	cursor.player = player
	layer.add_child(cursor)
	var stamina: StaminaManager = player.movement.stamina_manager
	await _frames(30)
	## Sprinting: Henry runs in place on the floor with the sprint held.
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _frames(90)
	await _shot("1_sprint_full", stamina)
	stamina.current_stamina = 22.0
	await _frames(30)
	await _shot("2_sprint_low", stamina)
	stamina.current_stamina = 0.4
	await _frames(20)
	await _shot("3_winded", stamina)
	Input.action_release(&"sprint")
	await _frames(240)
	await _shot("4_catching_breath_walking", stamina)
	Input.action_release(&"move_forward")
	stamina.current_stamina = 85.0
	await _frames(40)
	await _shot("5_nearly_full_standing", stamina)
	quit(0)


func _shot(label: String, stamina: StaminaManager) -> void:
	await _frames(2)
	var image: Image = root.get_viewport().get_texture().get_image()
	var size := Vector2i(160, 120)
	var crop: Image = image.get_region(Rect2i(image.get_size() / 2 - size / 2, size))
	crop.resize(size.x * 3, size.y * 3, Image.INTERPOLATE_NEAREST)
	crop.save_png(ProjectSettings.globalize_path(_out.path_join(label + ".png")))
	print("STAMINA_CURSOR %s ratio=%.2f exhausted=%s sprint_ok=%s" % [label, stamina.get_stamina_ratio(), stamina.is_exhausted(), stamina.is_sprint_allowed()])


func _frames(count: int) -> void:
	for _i: int in range(count):
		await process_frame
