extends SceneTree

## The held pack at the 727 cabinet in Key West Reality (3D inventory, ItemContainer): Henry stands before the
## shut cabinet, F opens it, he walks to its side, crouches and the pack opens beside it; the ring carries the
## stew off the shelf into the pack, then a tin from the pack back onto the shelf. Tab again puts the pack on.
## 30 fps PNG frames; with --write-movie the sound is recorded too.
## Run: xvfb-run godot --path . --rendering-driver vulkan --fixed-fps 30 --resolution 1920x1080 --script res://tools/runtime/capture_container_view.gd -- <out dir>

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
const FPS: int = 30

var _out: String = "user://shots/container_view"
var _frame: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_run()


func _run() -> void:
	TranslationServer.set_locale("ru")
	var world := (load(SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(world)
	var ctx: Variant = null
	for _i: int in range(600):
		await process_frame
		ctx = world.call(&"get_context")
		if ctx != null:
			break
	var player := ctx.player as Player
	for node: Node in world.find_children("*", "DayNightManager", true, false):
		node.set(&"total_game_time_hours", floorf(float(node.get(&"total_game_time_hours")) / 24.0) * 24.0 + 13.0)
		node.call(&"force_update_lighting")
	for _i: int in range(120):
		await process_frame
	var shelves := world.find_children("Shelves", "ItemContainer", true, false)[0] as ItemContainer
	if shelves.door != null and shelves.door.is_open():
		shelves.door.interact()
	## Henry stands out before the cabinet, a little off to its left (as one looks in), facing it.
	var face: Array = shelves.front()
	var stand: Vector3 = (face[0] as Vector3) + (face[1] as Vector3) * 1.3 - (face[2] as Vector3) * 0.35
	stand.y = player.global_position.y
	player.global_position = stand
	player.velocity = Vector3.ZERO
	player.look_at(face[0] as Vector3 * Vector3(1, 0, 1) + Vector3.UP * stand.y, Vector3.UP)
	var inventory := player.get_node(^"InventoryComponent") as InventoryComponent
	for _n: int in 3:
		inventory.try_add(ItemCatalog.get_item(&"spov_can"))
	for _i: int in range(60):
		await physics_frame
	var hub := player.get_node(^"PlayerHubComponent") as PlayerHubComponent
	await _record(0.5)
	shelves.door.interact()
	for _i: int in range(240):
		await _record(1.0 / FPS)
		if hub.is_open():
			break
	await _record(1.5)
	var hands: PackHandling = hub.get_pack_hands()
	var hinge: Vector3 = shelves.global_transform.affine_inverse() * shelves.door.door_hinge.global_position
	print("[container] door hinge x ", snappedf(hinge.x, 0.01), " shelves middle x ", snappedf(shelves.shelves_box().get_center().x, 0.01), " pack side ", hub.get("_front_hold").container_side if hub.get("_front_hold") != null else 0.0)
	print("[container] at the cabinet: ", hands != null and hands.container == shelves, " holds ", shelves.items.map(func(item: Dictionary) -> StringName: return item["id"]))
	if hands == null or hands.container == null:
		quit(1)
		return
	var straps: PackStraps = hands.straps
	## The stew off the shelf into the pack.
	var stew: int = -1
	for i: int in shelves.items.size():
		if shelves.items[i]["id"] == &"tinned_stew":
			stew = i
	if stew >= 0:
		await _glide(hands, _outline_middle(shelves.items[stew]["pickup"], hands.camera), 0.6)
		await _record(0.8)
		hands.press(PackHandling.GRAB_ACTION, true)
		await _glide(hands, hands.camera.unproject_position(straps.model.global_transform * PackStraps.room().get_center()), 0.7)
		hands.press(PackHandling.GRAB_ACTION, false)
		await _record(1.0)
	## A tin from the pack onto the shelf.
	await _glide(hands, hands.camera.unproject_position(straps.model.global_transform * (straps.items[0]["box"] as AABB).get_center()), 0.6)
	await _record(0.5)
	hands.press(PackHandling.GRAB_ACTION, true)
	await _glide(hands, hands.camera.unproject_position(shelves.global_transform * shelves.shelves_box().get_center()), 0.7)
	hands.press(PackHandling.GRAB_ACTION, false)
	await _record(1.2)
	print("[container] after: ", shelves.items.map(func(item: Dictionary) -> StringName: return item["id"]))
	hub.close()
	await _record(1.2)
	print("[container] frames ", _frame)
	quit()


func _outline_middle(visual: Node3D, camera: Camera3D) -> Vector2:
	var outline: PackedVector2Array = PackHandling.screen_outline(visual, camera)
	var middle := Vector2.ZERO
	for point: Vector2 in outline:
		middle += point
	return middle / maxf(outline.size(), 1.0)


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
