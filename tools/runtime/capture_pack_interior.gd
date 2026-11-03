extends SceneTree

## The slotless compartment (3D inventory stage 0): the pack lies open face up, a dozen items drop in through
## the mouth one by one and settle on the back wall; then a plank is refused. 30 fps PNG frames from above.
## Run: xvfb-run godot --path . --rendering-driver vulkan --fixed-fps 30 --resolution 960x720 --script res://tools/runtime/capture_pack_interior.gd -- <out dir>

const FPS: int = 30
const ITEMS: Array[StringName] = [&"tinned_stew", &"tinned_stew", &"spov_can", &"water_flask", &"lighter", &"knife",
	&"stone", &"stone", &"tinned_pineapple", &"work_gloves", &"mug", &"tinder"]

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
	## Face up on the floor: the back wall is the floor of the compartment.
	pack.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, 0.0, 0.26))
	pack.set_open(true)
	var interior := PackInterior.new()
	pack.add_child(interior)
	interior.setup(pack)
	interior.set_open(true)
	var camera := Camera3D.new()
	camera.fov = 42.0
	root.add_child(camera)
	camera.look_at_from_position(Vector3(0.0, 1.05, 0.62), Vector3(0.0, 0.08, 0.0))
	camera.make_current()
	_caption = Label.new()
	_caption.position = Vector2(20, 16)
	_caption.add_theme_font_size_override("font_size", 24)
	root.add_child(_caption)
	await _record(0.8, "OPEN, EMPTY")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for id: StringName in ITEMS:
		var at := Vector3(rng.randf_range(-0.1, 0.1), rng.randf_range(0.1, 0.42), BackpackModel.BODY.z + 0.08)
		interior.add(id, at)
		await _record(0.25, "DROP: %s" % id)
	await _record(1.5, "SETTLING (room left %.1f l)" % (interior.room_left() * 1000.0))
	var why: StringName = interior.refusal(&"boards")
	await _record(1.0, "BOARDS: %s" % TranslationServer.translate(why))
	print("[pack interior] frames ", _frame, " settled ", interior.is_settled())
	quit(0)


func _record(seconds: float, caption: String) -> void:
	_caption.text = caption
	for _i: int in range(roundi(seconds * FPS)):
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out).path_join("f_%03d.png" % _frame))
		_frame += 1
