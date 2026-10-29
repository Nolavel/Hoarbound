extends SceneTree

## Backpack lab (#260): an empty pack slumps closed, the front panel unzips and folds down,
## items go into their slots one by one, the panel closes on them. 30 fps PNG frames, two views.
## Run: xvfb-run godot --path . --rendering-driver vulkan --fixed-fps 30 --script res://tools/runtime/capture_backpack_lab.gd -- <out dir>

const FPS: int = 30
const LOAD: Array = [
	[&"tinned_stew", &"low_left"],
	[&"water_flask", &"low_mid"],
	[&"spov_can", &"low_right"],
	[&"work_gloves", &"shelf"],
	[&"water_flask", &"side_left"],
]

var _out: String = "user://shots/backpack_lab"
var _frame: int = 0
var _pack: BackpackModel
var _caption: Label
var _views: Array[SubViewport] = []


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_run()


func _run() -> void:
	await process_frame
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.11, 0.11, 0.12)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.57, 0.62)
	env.environment.ambient_light_energy = 0.7
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	world.add_child(sun)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(4.0, 4.0)
	floor.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.2, 0.2, 0.21)
	floor.material_override = floor_material
	floor.position.y = -0.135
	world.add_child(floor)
	_pack = BackpackModel.new()
	world.add_child(_pack)

	## Two views of one run, side by side: three-quarter front, and the left side for the pocket.
	var row := HBoxContainer.new()
	row.size = Vector2(1920, 1080)
	row.add_theme_constant_override("separation", 0)
	root.add_child(row)
	for pose: Array in [[Vector3(0.62, 0.62, 1.05), Vector3(0.0, 0.22, 0.12)], [Vector3(-1.15, 0.4, 0.25), Vector3(0.0, 0.2, 0.1)]]:
		var holder := SubViewportContainer.new()
		holder.custom_minimum_size = Vector2(960, 1080)
		holder.stretch = true
		row.add_child(holder)
		var view := SubViewport.new()
		view.size = Vector2i(960, 1080)
		view.world_3d = root.world_3d
		holder.add_child(view)
		var camera := Camera3D.new()
		camera.fov = 40.0
		view.add_child(camera)
		camera.look_at_from_position(pose[0], pose[1])
		_views.append(view)
	_caption = Label.new()
	_caption.position = Vector2(24, 20)
	_caption.add_theme_font_size_override("font_size", 30)
	root.add_child(_caption)

	await _record(1.5, "EMPTY, CLOSED: the canvas slumps")
	_pack.set_open(true)
	await _record(1.6, "FRONT PANEL UNZIPS AND FOLDS DOWN")
	for entry: Array in LOAD:
		_pack.add_item(entry[0], entry[1])
		await _record(0.45, "PACKING: %s -> %s" % [entry[0], entry[1]])
	await _record(0.6, "PACKED (fill %.2f)" % _pack.get_fill_target())
	_pack.set_open(false)
	await _record(1.8, "PANEL CLOSES ON THE LOAD")
	await _record(1.2, "FULL, CLOSED: the canvas takes the shape of the load")
	print("[backpack] frames ", _frame, " fill ", _pack.get_fill_target())
	quit(0)


func _record(seconds: float, caption: String) -> void:
	_caption.text = caption
	for _i: int in range(roundi(seconds * FPS)):
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out).path_join("f_%03d.png" % _frame))
		_frame += 1
