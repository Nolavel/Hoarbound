extends SceneTree

## Isolated three-quarter view of the same procedural StoveVisual used by 727.
const OUT: String = "res://docs/asset_previews/stove/dual_cooktop_studio.png"


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT).get_base_dir())
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.12, 0.15, 0.19)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.76, 0.82, 0.9)
	environment.ambient_light_energy = 1.5
	world.environment = environment
	root.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 2.5
	sun.shadow_enabled = true
	root.add_child(sun)
	var stove := HeatSource.new()
	stove.starts_burning = false
	var visual := StoveVisual.new()
	visual.flue_length = 0.9
	stove.add_child(visual)
	root.add_child(stove)
	var camera := Camera3D.new()
	camera.fov = 37.0
	root.add_child(camera)
	camera.look_at_from_position(Vector3(1.35, 1.45, 1.25), Vector3(0.0, 0.68, 0.0))
	camera.make_current()
	for _i: int in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT))
	print("STOVE_STUDIO cook rings: ", visual.get_node_or_null(^"CookRingA") != null, ", ",
		visual.get_node_or_null(^"CookRingB") != null)
	quit()
