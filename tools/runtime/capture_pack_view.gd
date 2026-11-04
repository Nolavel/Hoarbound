extends SceneTree

## The 3D inventory's Tab ritual with the real HUD: Henry takes the pack off into his hands and opens it toward
## the camera, which faces him; hidden quick pockets stand as cards at the sides, the thermos (the pick) is amber,
## and the ring flows into the outline of the mug, the pan and a tin. The ring
## cursor carries a tin, the lighter and the tinder from the pockets into the pack (under the straps), a tin
## back out to a pocket, and the axe is refused by the pack. Tab again puts the pack back on. 30 fps PNG frames.
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
	## The thermos is the Quick Access pick (what Henry last held): amber on the pack.
	var quick := player.get_node(^"QuickAccessComponent") as QuickAccessComponent
	var zones: Array[Dictionary] = hub.get_quick_access_zones()
	for k: int in zones.size():
		if zones[k]["item_id"] == &"water_flask":
			quick.select(k)
	await _record(0.3)
	hub.open()
	await _record(1.6)
	## The ring flows into the outline of what it is over: the mug, the pan, a strapped tin.
	var look_hands: PackHandling = hub.get_pack_hands()
	var look_shelf: PackQuickShelf = hub.get_quick_shelf()
	for wanted: String in ["pack_carabiner", "pack_carabiner_left"]:
		var k: int = _slot_ending(look_shelf, wanted)
		if k >= 0 and look_shelf.visual_of(k) != null:
			await _glide(look_hands, look_hands.camera.unproject_position(look_shelf.visual_of(k).global_position), 0.5)
			await _record(0.6)
	var strapped: PackStraps = look_hands.straps
	await _glide(look_hands, look_hands.camera.unproject_position(strapped.model.global_transform * (strapped.items[0]["box"] as AABB).get_center()), 0.5)
	await _record(0.6)
	## The ring and LMB, as a player: pockets into the pack, a tin out to a pocket, the axe refused.
	var hands: PackHandling = hub.get_pack_hands()
	var shelf: PackQuickShelf = hub.get_quick_shelf()
	var straps: PackStraps = hands.straps
	var into: Vector2 = hands.camera.unproject_position(straps.model.global_transform * PackStraps.room().get_center())
	for wanted: String in ["coat_left", "coat_right", "thigh_left"]:
		var k: int = _slot_ending(shelf, wanted)
		if k < 0 or StringName(shelf.slots[k]["item_id"]) == &"":
			continue
		await _glide(hands, _card_at(hands, shelf, k), 0.45)
		await _record(0.2)
		hands.press(PackHandling.GRAB_ACTION, true)
		await _glide(hands, into, 0.6)
		hands.press(PackHandling.GRAB_ACTION, false)
		await _record(0.7)
	## A tin out of the pack into the emptied left coat pocket.
	await _glide(hands, hands.camera.unproject_position(straps.model.global_transform * (straps.items[0]["box"] as AABB).get_center()), 0.5)
	await _record(0.2)
	hands.press(PackHandling.GRAB_ACTION, true)
	await _glide(hands, _card_at(hands, shelf, _slot_ending(shelf, "coat_left")), 0.6)
	hands.press(PackHandling.GRAB_ACTION, false)
	await _record(0.7)
	## The axe: too big for the pack (red, reason), back to its sleeve.
	var axe: int = -1
	for k: int in shelf.slots.size():
		if shelf.slots[k]["item_id"] == &"axe":
			axe = k
	if axe >= 0:
		await _glide(hands, _card_at(hands, shelf, axe), 0.5)
		hands.press(PackHandling.GRAB_ACTION, true)
		await _glide(hands, into, 0.6)
		await _record(0.5)
		hands.press(PackHandling.GRAB_ACTION, false)
		await _record(1.4)
	hub.close()
	await _record(1.4)
	print("[pack view] frames ", _frame)
	quit()


func _slot_ending(shelf: PackQuickShelf, pocket: String) -> int:
	for k: int in shelf.slots.size():
		if String(shelf.slots[k]["path"]).ends_with(pocket):
			return k
	return -1


func _card_at(hands: PackHandling, shelf: PackQuickShelf, k: int) -> Vector2:
	return hands.camera.unproject_position((shelf.slots[k]["card"] as Node3D).global_position)


func _glide(hands: PackHandling, to: Vector2, seconds: float) -> void:
	var from: Vector2 = hands.cursor_at
	var frames: int = maxi(roundi(seconds * FPS), 1)
	for f: int in frames:
		hands.set_cursor(from.lerp(to, smoothstep(0.0, 1.0, float(f + 1) / float(frames))))
		await _record(1.0 / FPS)


func _record(seconds: float) -> void:
	for _i: int in range(roundi(seconds * FPS)):
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out).path_join("f_%03d.png" % _frame))
		_frame += 1
