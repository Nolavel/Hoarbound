extends SceneTree

## Henry's clothes at rime 0, 0.4 and 0.85, front and back three-quarter, in the same cold light.
## Run: xvfb-run godot --path . --rendering-driver vulkan --resolution 960x540 --script res://tools/runtime/capture_clothing_frost.gd -- <out dir>

const PLAYER: String = "res://scenes/actors/player/player.tscn"
const LEVELS: Array[float] = [0.0, 0.4, 0.85]

var _out: String = "user://shots/clothing_frost"


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
	box.size = Vector3(40.0, 1.0, 40.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	root.add_child(floor_body)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.5, 0.55, 0.62)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.6, 0.7)
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	sun.light_energy = 1.0
	root.add_child(sun)
	var player := (load(PLAYER) as PackedScene).instantiate() as Player
	root.add_child(player)
	player.global_position = Vector3(0.0, 1.0, 0.0)
	var frost := player.get_node(^"ClothingFrostComponent") as ClothingFrostComponent
	frost.set_process(false)
	var camera := Camera3D.new()
	camera.fov = 45.0
	root.add_child(camera)
	camera.make_current()
	for _i: int in range(60):
		await process_frame
	var forward: Vector3 = player.animation_component.get_head_facing()
	forward = Vector3(forward.x, 0.0, forward.z).normalized()
	var side: Vector3 = Vector3.UP.cross(forward)
	var chest: Vector3 = player.global_position + Vector3.UP * 0.45
	for level: float in LEVELS:
		player.animation_component.set_frost(level)
		for view: String in ["front", "back"]:
			var dir: Vector3 = forward if view == "front" else -forward
			camera.look_at_from_position(chest + dir * 1.5 + side * 0.7 + Vector3.UP * 0.45, chest, Vector3.UP)
			for _i: int in range(3):
				await process_frame
			await RenderingServer.frame_post_draw
			var label: String = "frost_%02d_%s" % [int(level * 100.0), view]
			root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(_out.path_join(label + ".png")))
			print("CLOTHING_FROST ", label)
	quit(0)
