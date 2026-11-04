extends SceneTree

## The 3D inventory's Tab ritual with the real HUD: Henry takes the pack off into his hands and opens it toward
## the camera, which faces him; the Quick Access cards stand pinned on their live anchors. Nine SPoV tins go
## into the pack one by one: each stands into its place and its tier's strap pulls in. Tab again puts the pack
## back on. 30 fps PNG frames.
## Run: xvfb-run godot --path . --rendering-driver vulkan --fixed-fps 30 --resolution 1280x720 --script res://tools/runtime/capture_pack_view.gd -- <out dir>

const PLAYER: String = "res://scenes/actors/player/player.tscn"
const UI: String = "res://scenes/ui/hud/gameplay_ui.tscn"
const FPS: int = 30

var _out: String = "user://shots/pack_view"
var _frame: int = 0


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
	plane.size = Vector2(40.0, 40.0)
	ground.mesh = plane
	ground.material_override = StylizedEnvironmentMaterial.make(Color(0.78, 0.8, 0.84), 0.9)
	floor.add_child(ground)
	root.add_child(floor)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.72, 0.75, 0.8)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.72, 0.78)
	env.environment.ambient_light_energy = 0.8
	root.add_child(env)
	var player := (load(PLAYER) as PackedScene).instantiate() as Player
	root.add_child(player)
	player.global_position = Vector3(0.0, 1.0, 0.0)
	var ui: Node = (load(UI) as PackedScene).instantiate()
	ui.call(&"bind_player", player)
	root.add_child(ui)
	var game_camera := Camera3D.new()
	root.add_child(game_camera)
	game_camera.look_at_from_position(player.global_position + Vector3(0.0, 1.0, 3.0), player.global_position + Vector3.UP * 0.4)
	game_camera.make_current()
	var visual := player.get_node(^"HenryUALVisual") as HenryUALAnimation
	visual.head_look_idle_speed = 0.0
	for _i: int in 40:
		await process_frame
	await _record(0.6)
	## The pack starts half full of SPoV tins (the bedroll stays strapped on top); a tin waits in the left coat
	## pocket.
	var inventory := player.get_node(^"InventoryComponent") as InventoryComponent
	for entry: Dictionary in inventory.get_entries():
		if entry["id"] != &"bedroll":
			for _n: int in int(entry["count"]):
				inventory.take_instance(entry["id"])
	var tin: ItemResource = ItemCatalog.get_item(&"spov_can")
	for _n: int in 5:
		inventory.try_add(tin)
	var hub := player.get_node(^"PlayerHubComponent") as PlayerHubComponent
	var equipment := player.get_node(^"EquipmentComponent") as EquipmentComponent
	for zone: Dictionary in hub.get_quick_access_zones():
		if String(zone["path"]).ends_with("coat_left") and zone["item_id"] == &"":
			var parts: PackedStringArray = String(zone["path"]).split(EquipmentComponent.POCKET_SEPARATOR)
			equipment.stow(StringName(parts[0]), StringName(parts[1]), &"spov_can")
	await _record(0.3)
	hub.open()
	await _record(1.6)
	## From the quick pockets into the pack, one by one.
	var shelf: PackQuickShelf = hub.get_quick_shelf()
	var rig: PackRig = visual.get_pack_rig()
	for wanted: String in ["coat_left", "coat_right", "thigh_left"]:
		for k: int in shelf.slots.size():
			if String(shelf.slots[k]["path"]).ends_with(wanted) and StringName(shelf.slots[k]["item_id"]) != &"":
				print("[pack view] sending ", shelf.slots[k]["item_id"], " from ", wanted)
				shelf.send_to_pack(k, rig.global_position)
				break
		await _record(1.1)
	await _record(1.0)
	hub.close()
	await _record(1.4)
	print("[pack view] frames ", _frame)
	quit()


func _record(seconds: float) -> void:
	for _i: int in range(roundi(seconds * FPS)):
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out).path_join("f_%03d.png" % _frame))
		_frame += 1
