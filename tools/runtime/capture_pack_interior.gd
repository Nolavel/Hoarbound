extends SceneTree

## The slotless compartment (3D inventory stage 0), the pack hanging upright and open as Henry holds it: the
## axe, frying pan, hammer, thermos, SPoV tin and mug go in high one by one and fall to the bottom; then the
## boards are refused. Two views: from above into the open front, and the side wall the heap presses.
## Run: xvfb-run godot --path . --rendering-driver vulkan --fixed-fps 30 --script res://tools/runtime/capture_pack_interior.gd -- <out dir>

const FPS: int = 30
const ITEMS: Array[StringName] = [&"axe", &"frying_pan", &"hammer", &"water_flask", &"spov_can", &"mug"]
const PACK_AT: Vector3 = Vector3(0.0, 0.9, 0.0)

var _out: String = "user://shots/pack_interior"
var _frame: int = 0
var _caption: Label


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_run()


func _run() -> void:
	await process_frame
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.11, 0.11, 0.12)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.57, 0.62)
	env.environment.ambient_light_energy = 0.8
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62.0, -30.0, 0.0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	root.add_child(sun)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(4.0, 4.0)
	floor.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.22, 0.22, 0.23)
	floor.material_override = floor_material
	root.add_child(floor)
	var pack := BackpackModel.new()
	root.add_child(pack)
	pack.build()
	pack.global_position = PACK_AT
	pack.set_open(true)
	var interior := PackInterior.new()
	pack.add_child(interior)
	interior.setup(pack)
	interior.set_open(true)
	## Two views of one run: high in front looking down into the opening, and three-quarter from the left side.
	var row := HBoxContainer.new()
	row.size = Vector2(1920, 1080)
	row.add_theme_constant_override("separation", 0)
	root.add_child(row)
	var focus: Vector3 = PACK_AT + Vector3(0.0, 0.2, 0.11)
	for eye: Vector3 in [PACK_AT + Vector3(0.0, 0.95, 0.62), PACK_AT + Vector3(-0.85, 0.45, 0.55)]:
		var holder := SubViewportContainer.new()
		holder.custom_minimum_size = Vector2(960, 1080)
		holder.stretch = true
		row.add_child(holder)
		var view := SubViewport.new()
		view.size = Vector2i(960, 1080)
		view.world_3d = root.world_3d
		holder.add_child(view)
		var camera := Camera3D.new()
		camera.fov = 38.0
		view.add_child(camera)
		camera.look_at_from_position(eye, focus)
	_caption = Label.new()
	_caption.position = Vector2(24, 20)
	_caption.add_theme_font_size_override("font_size", 30)
	root.add_child(_caption)
	await _record(1.6, "HANGING, OPEN, EMPTY")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for id: StringName in ITEMS:
		var at := Vector3(rng.randf_range(-0.06, 0.06), rng.randf_range(0.34, 0.4), rng.randf_range(0.09, 0.13))
		interior.add(id, at)
		await _record(0.7, "IN: %s" % id)
	await _record(1.5, "SETTLED (room left %.1f l)" % (interior.room_left() * 1000.0))
	interior.add(&"boards")
	TranslationServer.set_locale("ru")
	await _record(1.4, "BOARDS: %s" % TranslationServer.translate(interior.refusal(&"boards")))
	print("[pack interior] frames ", _frame, " settled ", interior.is_settled())
	quit(0)


func _record(seconds: float, caption: String) -> void:
	_caption.text = caption
	for _i: int in range(roundi(seconds * FPS)):
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out).path_join("f_%03d.png" % _frame))
		_frame += 1
