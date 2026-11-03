extends SceneTree

## Forward+ review of the two functional cooktop plates in the real 727 scene.
const SCENE: PackedScene = preload("res://archive/graciosa/scenes/Graciosa_Island_Terrain.tscn")
const OUT: String = "res://docs/runtime_previews/key_west_727/stove_cooktop"


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var scene := SCENE.instantiate()
	root.add_child(scene)
	await create_timer(2.0).timeout
	for node: Node in root.find_children("*", "WorldEnvironment", true, false):
		var environment := (node as WorldEnvironment).environment
		if environment != null:
			environment.volumetric_fog_enabled = false
			environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			environment.ambient_light_color = Color(0.68, 0.74, 0.82)
			environment.ambient_light_energy = 1.2
	var zone := scene.find_child("ShelterZone", true, false)
	var stove := zone.get_node_or_null(^"Stove") as HeatSource if zone != null else null
	if stove == null:
		push_error("The 727 stove was not found")
		quit(1)
		return
	var visual := stove.get_node(^"StoveVisual") as StoveVisual
	var warmer_a := stove.get_node(^"Warmer") as StoveWarmer
	var warmer_b := stove.get_node(^"Warmer2") as StoveWarmer
	if visual.get_node_or_null(^"CookRingA") == null or visual.get_node_or_null(^"CookRingB") == null \
		or warmer_a.get_save_key() == warmer_b.get_save_key():
		push_error("Both cooking plates and distinct warmer states are required")
		quit(1)
		return
	var ring_a := visual.get_node(^"CookRingA") as MeshInstance3D
	var pan := SurvivalItemVisual.make(&"frying_pan")
	pan.name = "ReviewFryingPan"
	ring_a.add_child(pan)
	pan.position.y = (ring_a.mesh as CylinderMesh).height * 0.5
	var pan_max_z := -INF
	for mesh: Node in pan.find_children("*", "MeshInstance3D", true, false):
		var in_stove: AABB = stove.global_transform.affine_inverse() * (mesh as MeshInstance3D).global_transform * (mesh as MeshInstance3D).get_aabb()
		pan_max_z = maxf(pan_max_z, in_stove.end.z)
	var clearance: float = StoveVisual.COOK_RING_Z - StoveVisual.COOK_RING_RADIUS - pan_max_z
	if clearance < 0.01:
		push_error("The pan intrudes into the second cooking plate: %.3f m clearance" % clearance)
		quit(1)
		return
	for player: Node in get_nodes_in_group(&"player"):
		(player as Node3D).visible = false
	for layer: Node in root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	for overlay: Node in root.find_children("*", "Control", true, false):
		(overlay as Control).visible = false
	var camera := Camera3D.new()
	camera.fov = 45.0
	root.add_child(camera)
	camera.make_current()
	## A neutral review bounce makes the dark iron legible without changing the game scene.
	var bounce := OmniLight3D.new()
	bounce.light_color = Color(0.66, 0.75, 0.88)
	bounce.light_energy = 2.2
	bounce.omni_range = 2.2
	bounce.position = stove.to_global(Vector3(0.6, 1.6, 0.1))
	root.add_child(bounce)
	var review_sun := DirectionalLight3D.new()
	review_sun.rotation_degrees = Vector3(-55.0, 25.0, 0.0)
	review_sun.light_energy = 2.0
	review_sun.shadow_enabled = false
	root.add_child(review_sun)
	var focus := stove.to_global(Vector3(0.03, 0.70, 0.0))
	camera.look_at_from_position(stove.to_global(Vector3(0.46, 2.0, 0.02)), focus)
	## The first Forward+ draw can still contain the world's red shader warm-up frame.
	for _i: int in range(8):
		await process_frame
	await _save("02_cooktop.png")
	warmer_b.load_save_data({"state": int(StoveWarmer.State.READY), "item": "warm_water_mug", "progress": StoveWarmer.WARM_HOURS})
	await _save("03_second_occupied.png")
	print("STOVE_COOKTOP pan to second plate clearance=%.3f m; distinct save keys: %s, %s" % [clearance, warmer_a.get_save_key(), warmer_b.get_save_key()])
	quit()


func _save(filename: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT).path_join(filename))
