extends SceneTree

## Close-up of the authored lighter: upright, tilted as at the stove, flame lit, flame world-up.
## Run: godot --path . --resolution 960x540 --script res://tools/runtime/capture_lighter.gd -- <out dir>


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://shots/lighter"
	DirAccess.make_dir_recursive_absolute(out)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.05, 0.05, 0.06)
	env.environment.ambient_light_color = Color(0.5, 0.5, 0.55)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 0.6
	world.add_child(sun)
	var upright: Node3D = SurvivalItemVisual.make(&"lighter")
	upright.position = Vector3(-0.05, 0, 0)
	world.add_child(upright)
	var lit := LighterStrikeVFX.new()
	world.add_child(lit)
	lit.position = Vector3(0.04, 0.05, 0)
	lit.rotation_degrees = Vector3(0, 0, 70)
	lit.set_flame(true)
	var camera := Camera3D.new()
	camera.fov = 30
	world.add_child(camera)
	camera.look_at_from_position(Vector3(0, 0.07, 0.30), Vector3(0, 0.05, 0))
	for i: int in range(20):
		await process_frame
	root.get_texture().get_image().save_png(out.path_join("lighter_front.png"))
	camera.look_at_from_position(Vector3(0.12, 0.16, 0.12), Vector3(0.01, 0.06, 0))
	for i: int in range(8):
		await process_frame
	root.get_texture().get_image().save_png(out.path_join("lighter_above.png"))
	print("[lighter] nozzle=", lit.get_flame_tip(), " shots=", out)
	quit()
