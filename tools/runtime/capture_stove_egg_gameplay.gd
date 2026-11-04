extends SceneTree

## Six-second 727 capture: real stove/warmer owns the pan, egg and heat state.
## The fixed camera is a review close-up, not Henry's final work framing.
const SCENE: PackedScene = preload("res://archive/graciosa/scenes/Graciosa_Island_Terrain.tscn")
const OUT: String = "res://docs/runtime_previews/key_west_727/egg_gameplay"
const FPS: int = 12
const FRAMES: int = 72

func _initialize() -> void:
	call_deferred(&"_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.path_join("frames")))
	var scene := SCENE.instantiate()
	root.add_child(scene)
	await create_timer(2.0).timeout
	for node: Node in root.find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (node as WorldEnvironment).environment
		if env != null:
			env.volumetric_fog_enabled = false
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = Color(0.68, 0.74, 0.82)
			env.ambient_light_energy = 1.2
	var zone: Node = scene.find_child("ShelterZone", true, false)
	var stove: HeatSource = zone.get_node_or_null(^"Stove") as HeatSource if zone != null else null
	if stove == null:
		push_error("Cooking review: production 727 stove not found")
		quit(1)
		return
	var first := stove.get_node(^"Warmer") as StoveWarmer
	var second := stove.get_node(^"Warmer2") as StoveWarmer
	if first == null or second == null:
		push_error("Cooking review: both cooking plates required")
		quit(1)
		return
	first.load_save_data({})
	second.load_save_data({})
	stove.restore_fuel(1.0, true)
	var inventory := InventoryComponent.new()
	root.add_child(inventory)
	if not inventory.try_add(ItemCatalog.get_item(&"frying_pan")) or not inventory.try_add(ItemCatalog.get_item(&"egg_raw")):
		push_error("Cooking review: inventory setup failed")
		quit(1)
		return
	for player: Node in get_nodes_in_group(&"player"):
		(player as Node3D).visible = false
	for layer: Node in root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	var camera := Camera3D.new()
	camera.fov = 37.0
	root.add_child(camera)
	camera.make_current()
	var bounce := OmniLight3D.new()
	bounce.light_color = Color(0.74, 0.78, 0.83)
	bounce.light_energy = 1.9
	bounce.omni_range = 2.2
	bounce.position = stove.to_global(Vector3(0.6, 1.8, 0.1))
	root.add_child(bounce)
	var focus: Vector3 = stove.to_global(Vector3(0.14, 0.68, 0.0))
	camera.look_at_from_position(stove.to_global(Vector3(0.48, 1.68, 0.42)), focus)
	for _i: int in range(8):
		await process_frame
	for frame: int in range(FRAMES):
		if frame == 6 and not first.put_pan(inventory):
			push_error("Cooking review: pan failed to transfer")
			quit(1)
			return
		if frame == 16 and not first.crack_egg(inventory):
			push_error("Cooking review: egg failed to transfer")
			quit(1)
			return
		if frame == 35:
			second.load_save_data({"state": int(StoveWarmer.State.READY), "item": "warm_water_mug", "progress": StoveWarmer.WARM_HOURS})
		if frame >= 16 and first.get_egg_state() == StoveWarmer.EggState.COOKING:
			first._egg_intro_seconds = minf(3.0, float(frame - 16) / float(FPS))
			if frame >= 43:
				## Drive the real heat_elapsed event, accelerated only for this review.
				stove.heat_elapsed.emit(StoveWarmer.EGG_COOK_HOURS / 23.0)
			first._sync_egg_visual()
		await process_frame
		await RenderingServer.frame_post_draw
		var path: String = ProjectSettings.globalize_path(OUT.path_join("frames/f_%03d.png" % frame))
		if root.get_texture().get_image().save_png(path) != OK:
			push_error("Cooking review: capture failed " + path)
			quit(1)
			return
	print("COOKING_GAMEPLAY_CAPTURE frames=%d pan=%s egg=%d second=%d" % [
		FRAMES, str(first.has_pan()), first.get_egg_state(), second.get_state()])
	if not first.has_pan() or first.get_egg_state() != StoveWarmer.EggState.READY:
		push_error("Cooking review: egg never reached ready")
		quit(1)
		return
	quit()
