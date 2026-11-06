extends SceneTree

## The held pack at an open cabinet (3D inventory, ItemContainer) on the real player and Hub. A cabinet built
## like the 727 one stands ahead of Henry with two tins and a stew on its shelves; Tab searches it where he
## stands: he crouches (it is low), the pack opens, and the ring:
## - carries a tin off the shelf into the pack (the shelf loses it, the pack gains it);
## - carries a pack tin back onto the shelf;
## - carries the coat pocket's tin onto the shelf, and a shelf tin into the empty coat pocket;
## - is refused by a full shelf (its reason shows, the tin stays in the pack).
## Closing the pack lets go of the cabinet.
## Run: godot --headless --path . --fixed-fps 30 --script res://tests/systems/test_container_hands.gd

const PLAYER: String = "res://scenes/actors/player/player.tscn"
const PANELS: Array = [
	[Vector3(0.8, 0.9, 0.03), Vector3(0.0, 0.45, -0.21)],
	[Vector3(0.03, 0.9, 0.45), Vector3(-0.385, 0.45, 0.0)],
	[Vector3(0.03, 0.9, 0.45), Vector3(0.385, 0.45, 0.0)],
	[Vector3(0.8, 0.03, 0.45), Vector3(0.0, 0.885, 0.0)],
	[Vector3(0.8, 0.06, 0.45), Vector3(0.0, 0.03, 0.0)],
	[Vector3(0.74, 0.02, 0.4), Vector3(0.0, 0.45, 0.0)],
]

var _failures: int = 0
var _hub: PlayerHubComponent
var _hands: PackHandling
var _box: ItemContainer
var _inventory: InventoryComponent


func _initialize() -> void:
	_run()


func _run() -> void:
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	floor.add_child(shape)
	root.add_child(floor)
	var player := (load(PLAYER) as PackedScene).instantiate() as Player
	root.add_child(player)
	player.global_position = Vector3(0.0, 1.0, 0.0)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.make_current()
	await _frames(30)
	_inventory = player.get_node(^"InventoryComponent") as InventoryComponent
	_hub = player.get_node(^"PlayerHubComponent") as PlayerHubComponent
	var equipment := player.get_node(^"EquipmentComponent") as EquipmentComponent
	for entry: Dictionary in _inventory.get_entries():
		if entry["id"] != &"bedroll":
			for _n: int in int(entry["count"]):
				_inventory.take_instance(entry["id"])
	for _n: int in 3:
		_inventory.try_add(ItemCatalog.get_item(&"spov_can"))
	var coat_left: StringName = &""
	for zone: Dictionary in _hub.get_quick_access_zones():
		if String(zone["path"]).ends_with("coat_left"):
			coat_left = zone["path"]
	var parts: PackedStringArray = String(coat_left).split(EquipmentComponent.POCKET_SEPARATOR)
	equipment.take_from_pocket(StringName(parts[0]), StringName(parts[1]))
	equipment.stow(StringName(parts[0]), StringName(parts[1]), &"spov_can")

	## The cabinet stands ahead of Henry (his forward is the body's -Z), its opening toward him.
	var cabinet := _cabinet()
	root.add_child(cabinet)
	cabinet.global_position = player.global_position * Vector3(1, 0, 1) - player.global_basis.z.slide(Vector3.UP).normalized() * 0.75
	cabinet.look_at(cabinet.global_position + player.global_basis.z.slide(Vector3.UP).normalized(), Vector3.UP, true)
	_box = ItemContainer.new()
	_box.container_id = &"test_hands_cabinet"
	_box.shelves = ItemContainer.shelves_from_furniture(cabinet, null)
	cabinet.add_child(_box)
	for id: StringName in [&"spov_can", &"spov_can", &"tinned_stew"]:
		_box.put(id)
	await _frames(5)

	## Its items are blurs behind frost and not taken by F; the search (an eye over F) is what is offered.
	var search := _box.get_node(^"Search") as ContainerSearch
	_check(search != null and search.can_interact() and search.marker_icon != null, "the open cabinet offers no search with an eye")
	_check(not (_box.items[0]["pickup"] as ItemPickup).can_interact(), "a shelf item is still taken by F")
	await _frames(2)
	var veil := _box.get_node_or_null(^"FrostedVeil") as MeshInstance3D
	_check(veil != null and veil.visible, "the open cabinet's face is not frosted over")
	var stood: Vector3 = player.global_position
	_check(_hub.open() and _hub.is_open(), "Tab at the open cabinet did not search it")
	await _frames(45)
	_check(player.is_crouching(), "Henry did not crouch at the low cabinet")
	_check(Vector2(player.global_position.x - stood.x, player.global_position.z - stood.z).length() < 0.05, "Henry walked to search (he searches where he stands)")
	_check(veil == null or not veil.visible, "the frost stayed over the cabinet during Henry's own search")
	_check(not search.can_interact(), "the search is still offered while Henry is at the cabinet")
	_hands = _hub.get_pack_hands()
	## The working frame comes at the cut, once the pack is off his back: wait for it, not for a frame count.
	for _i: int in 120:
		if _hands == null or _hands.enabled:
			break
		await _frames(1)
	_check(_hands != null and _hands.enabled, "the view never cut to the cabinet's frame")
	_check(_hub.container == _box and _hands != null and _hands.container == _box, "Tab at the open cabinet did not take its shelves in")
	if _hands == null or _hands.container == null:
		_finish()
		return
	var straps: PackStraps = _hands.straps
	var shelf: PackQuickShelf = _hub.get_quick_shelf()

	## A tin off the shelf into the pack.
	var on_shelf: int = _box.items.size()
	var tins: int = _inventory.get_count(&"spov_can")
	await _aim(_shelf_screen(0))
	_check(_hands.hovered_shelf == 0, "the ring over a shelf tin does not hover it")
	await _grab()
	await _glide(_pack_screen(straps))
	_hands.press(PackHandling.GRAB_ACTION, false)
	await _frames(10)
	_check(_box.items.size() == on_shelf - 1 and _inventory.get_count(&"spov_can") == tins + 1, "the shelf tin did not go into the pack")
	print("container hands: shelf -> pack")

	## A pack tin back onto the shelf.
	await _aim(_item_screen(straps, 0))
	await _grab()
	await _glide(_shelves_screen())
	_hands.press(PackHandling.GRAB_ACTION, false)
	await _frames(10)
	_check(_box.items.size() == on_shelf and _inventory.get_count(&"spov_can") == tins, "the pack tin did not go onto the shelf")
	print("container hands: pack -> shelf")

	## The coat pocket's tin onto the shelf, then a shelf tin into the empty pocket.
	var left_card: int = -1
	for k: int in shelf.slots.size():
		if shelf.slots[k]["path"] == coat_left:
			left_card = k
	await _aim(shelf.aim_point(left_card))
	await _grab()
	await _glide(_shelves_screen())
	_hands.press(PackHandling.GRAB_ACTION, false)
	await _frames(10)
	_check(StringName(shelf.slots[left_card]["item_id"]) == &"" and _box.items.size() == on_shelf + 1, "the coat pocket's tin did not go onto the shelf")
	await _aim(_shelf_screen(0))
	await _grab()
	await _glide(shelf.aim_point(left_card))
	_hands.press(PackHandling.GRAB_ACTION, false)
	await _frames(10)
	_check(StringName(shelf.slots[left_card]["item_id"]) != &"" and _box.items.size() == on_shelf, "a shelf item did not go into the coat pocket")
	print("container hands: pocket -> shelf -> pocket")

	## A full shelf refuses: fill it, then try a pack tin.
	while _box.put(&"spov_can") == &"":
		pass
	await _frames(5)
	var full_count: int = _box.items.size()
	var before: int = _inventory.get_count(&"spov_can")
	await _aim(_item_screen(straps, 0))
	await _grab()
	await _glide(_shelves_screen())
	_hands.press(PackHandling.GRAB_ACTION, false)
	await _frames(5)
	_check(_box.items.size() == full_count and _inventory.get_count(&"spov_can") == before, "a full shelf took the tin")
	_check(_hands.cursor.warning == tr(ItemContainer.NO_ROOM), "the full shelf showed no reason")
	print("container hands: a full shelf refused")

	_hub.close()
	await _frames(40)
	_check(_hub.container == null and not _hub.is_open(), "closing the pack kept the cabinet")
	_check(not player.is_work_crouching(), "closing the pack left Henry crouched")
	_finish()


func _shelf_screen(i: int) -> Vector2:
	var outline: PackedVector2Array = PackHandling.screen_outline(_box.items[i]["pickup"], _hands.camera)
	var middle := Vector2.ZERO
	for point: Vector2 in outline:
		middle += point
	return middle / maxf(outline.size(), 1.0)


func _shelves_screen() -> Vector2:
	return _hands.camera.unproject_position(_box.global_transform * _box.shelves_box().get_center())


func _item_screen(straps: PackStraps, i: int) -> Vector2:
	return _hands.camera.unproject_position(straps.model.global_transform * (straps.items[i]["box"] as AABB).get_center())


func _pack_screen(straps: PackStraps) -> Vector2:
	return _hands.camera.unproject_position(straps.model.global_transform * PackStraps.room().get_center())


func _cabinet() -> Node3D:
	var cabinet := Node3D.new()
	for panel: Array in PANELS:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = panel[0]
		mesh.mesh = box
		mesh.position = panel[1]
		cabinet.add_child(mesh)
	return cabinet


## LMB held until the hand has taken the item (a take costs time, PackHandling.take_seconds).
func _grab() -> void:
	_hands.press(PackHandling.GRAB_ACTION, true)
	for _i: int in 90:
		if not _hands.is_taking():
			break
		await _frames(1)


func _aim(at: Vector2) -> void:
	_hands.set_cursor(at)
	await _frames(3)


func _glide(to: Vector2) -> void:
	var from: Vector2 = _hands.cursor_at
	for f: int in 12:
		_hands.set_cursor(from.lerp(to, float(f + 1) / 12.0))
		await _frames(1)


func _frames(count: int) -> void:
	for _i: int in count:
		await process_frame


func _finish() -> void:
	print("container hands: %s" % ("all checks passed" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("container hands: %s" % message)
