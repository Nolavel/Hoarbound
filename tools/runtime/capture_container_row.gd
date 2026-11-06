extends SceneTree

## Stills of the container test row (ContainerRow): the whole row with every way in open (full ones frosted over),
## then the working frame of each full container, searched where Henry stands.
## Run: xvfb-run godot --path . --rendering-driver vulkan --fixed-fps 30 --resolution 1920x1080 --script res://tools/runtime/capture_container_row.gd -- <out dir>

const PLAYER: String = "res://scenes/actors/player/player.tscn"
const ROW: String = "res://tests/scenes/container_row.tscn"
const SEARCHED: Array = [["floor_cabinet", ["floor_cabinet"]], ["cupboard", ["cupboard_left", "cupboard_right"]],
	["drawer_top", ["drawer_top"]], ["drawer_middle", ["drawer_middle"]]]

var _out: String = "user://shots/container_row"


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_run()


func _run() -> void:
	TranslationServer.set_locale("ru")
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	floor.add_child(shape)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30.0, 30.0)
	ground.mesh = plane
	var floor_paint := StandardMaterial3D.new()
	floor_paint.albedo_color = Color(0.4, 0.38, 0.35)
	ground.material_override = floor_paint
	floor.add_child(ground)
	root.add_child(floor)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, 30.0, 0.0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.72, 0.75, 0.8)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.62, 0.68)
	root.add_child(env)
	var row := (load(ROW) as PackedScene).instantiate() as ContainerRow
	root.add_child(row)
	var player := (load(PLAYER) as PackedScene).instantiate() as Player
	root.add_child(player)
	player.global_position = Vector3(-2.0, 1.0, 3.0)
	var camera := Camera3D.new()
	camera.fov = 50.0
	root.add_child(camera)
	camera.make_current()
	await _frames(30)
	for way: String in ["floor_cabinet", "cupboard_left", "cupboard_right", "drawer_top", "chest"]:
		(row.openers[way] as InteractiveArea).interact()
	await _frames(45)
	## The whole row from in front and above.
	var middle := Vector3(ContainerRow.SPACING_M * 1.5, 0.9, 0.0)
	camera.global_transform = Transform3D(Basis.IDENTITY, middle + Vector3(0.0, 1.3, 4.2)).looking_at(middle, Vector3.UP)
	await _frames(10)
	await _save("row_open.png")
	var hub := player.get_node(^"PlayerHubComponent") as PlayerHubComponent
	## Each searched alone: everything else shut first (an open drawer above hides the one below).
	for way: InteractiveArea in row.openers.values():
		if (way is Cabinet and (way as Cabinet).is_open()) or (way is Drawer and (way as Drawer).is_open()):
			way.interact()
	await _frames(45)
	for entry: Array in SEARCHED:
		var shelves: ItemContainer = row.containers[entry[0]]
		var face: Array = shelves.front()
		var stand: Vector3 = (face[0] as Vector3) + (face[1] as Vector3) * 0.9
		stand.y = 1.0
		player.global_position = stand
		player.velocity = Vector3.ZERO
		for way: String in entry[1]:
			(row.openers[way] as InteractiveArea).interact()
		await _frames(45)
		(shelves.get_node(^"Search") as ContainerSearch).interact()
		for _i: int in 120:
			var hands: PackHandling = hub.get_pack_hands()
			if hands != null and hands.enabled:
				break
			await _frames(1)
		await _frames(45)
		await _save("framed_%s.png" % entry[0])
		print("[row] framed ", entry[0], " crouched ", player.is_crouching())
		hub.close()
		await _frames(45)
		for way: String in entry[1]:
			(row.openers[way] as InteractiveArea).interact()
		await _frames(45)
		camera.make_current()
	quit()


func _save(file: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out).path_join(file))


func _frames(count: int) -> void:
	for _i: int in count:
		await process_frame
