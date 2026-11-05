extends SceneTree

## Furniture that holds items (ItemContainer), on a cabinet built like the 727 waiting-room one:
## - its shelves come from its own panels (walls, back, floor, middle shelf, lid; the door left out);
## - tins stand on the shelves until there is no room, then it refuses (NO_ROOM);
## - taking one gives its id back and its pickup goes; the list survives a save and a load;
## - F (the pickup) takes a tin straight into Henry's pack and it leaves the list;
## - an older save that took a seeded item from the world (PickupLedger) removes it here.
## Run: godot --headless --path . --fixed-fps 30 --script res://tests/systems/test_item_container.gd

const PLAYER: String = "res://scenes/actors/player/player.tscn"
## The 727 cabinet's panels: size and centre (cabinet space), as the First Exit template builds them.
const PANELS: Array = [
	[Vector3(0.8, 0.9, 0.03), Vector3(0.0, 0.45, -0.21)],
	[Vector3(0.03, 0.9, 0.45), Vector3(-0.385, 0.45, 0.0)],
	[Vector3(0.03, 0.9, 0.45), Vector3(0.385, 0.45, 0.0)],
	[Vector3(0.8, 0.03, 0.45), Vector3(0.0, 0.885, 0.0)],
	[Vector3(0.8, 0.06, 0.45), Vector3(0.0, 0.03, 0.0)],
	[Vector3(0.74, 0.02, 0.4), Vector3(0.0, 0.45, 0.0)],
]

var _failures: int = 0


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
	player.global_position = Vector3(5.0, 1.0, 0.0)
	await _frames(20)
	var inventory := player.get_node(^"InventoryComponent") as InventoryComponent

	var cabinet := _cabinet()
	root.add_child(cabinet)
	var shelves: Array[AABB] = ItemContainer.shelves_from_furniture(cabinet, cabinet.get_node(^"DoorHinge"))
	print("container: shelves ", shelves)
	_check(shelves.size() == 2, "the cabinet should have two shelves (floor and middle), got %d" % shelves.size())
	if shelves.size() == 2:
		_check(is_equal_approx(shelves[0].position.y, 0.06) and is_equal_approx(shelves[0].end.y, 0.44), "the lower shelf is not floor-top to shelf-bottom")
		_check(is_equal_approx(shelves[1].position.y, 0.46) and is_equal_approx(shelves[1].end.y, 0.87), "the upper shelf is not shelf-top to lid")
		_check(is_equal_approx(shelves[0].size.x, 0.74) and is_equal_approx(shelves[0].position.z, -0.195), "the shelves are not between the walls, from the back")

	var box := ItemContainer.new()
	box.container_id = &"test_cabinet"
	box.shelves = shelves
	cabinet.add_child(box)
	var stocked: int = 0
	while box.put(&"spov_can") == &"" and stocked < 40:
		stocked += 1
	print("container: %d tins stand on the shelves" % stocked)
	_check(stocked >= 8 and stocked <= 14, "the shelves hold an unlikely number of tins: %d" % stocked)
	_check(box.refusal(&"spov_can") == ItemContainer.NO_ROOM, "a full cabinet does not refuse")
	for item: Dictionary in box.items:
		var pickup: ItemPickup = item["pickup"]
		var at: Vector3 = pickup.position
		_check(at.x > -0.4 and at.x < 0.4 and at.y >= 0.05 and at.y < 0.9, "a tin stands outside the cabinet at %s" % at)

	var taken: Dictionary = box.take(0)
	await _frames(2)
	_check(taken.get("id") == &"spov_can" and box.items.size() == stocked - 1, "taking a tin did not give it back")
	_check(box.refusal(&"spov_can") == &"", "the freed spot is not offered again")

	var saved: Dictionary = box.get_save_data()
	box.load_save_data({"items": []})
	await _frames(2)
	_check(box.items.is_empty(), "loading an empty save left items")
	box.load_save_data(saved)
	await _frames(2)
	_check(box.items.size() == stocked - 1, "the list did not survive a save and a load (%d)" % box.items.size())

	## F: the pickup goes into the pack and leaves the list.
	var before: int = inventory.get_count(&"spov_can")
	var first: ItemPickup = box.items[0]["pickup"]
	_check(first.pick_up(true), "the tin's pickup refused to go into the pack")
	await _frames(2)
	_check(inventory.get_count(&"spov_can") == before + 1 and box.items.size() == stocked - 2, "F did not take the tin out of the cabinet into the pack")

	## Seeded from the world, then an older save says the world's tin was taken already.
	var seeded := ItemPickup.new()
	seeded.item_id = &"spov_can"
	seeded.world_id = &"spov_can_test_seed"
	box.load_save_data({"items": []})
	box.adopt([seeded] as Array[ItemPickup])
	_check(box.items.size() == 1 and box.items[0]["world_id"] == &"spov_can_test_seed", "adopting the world's pickup did not seed it")
	var ledger := PickupLedger.new()
	root.add_child(ledger)
	ledger.record(&"spov_can_test_seed")
	box.drop_taken(ledger)
	_check(box.items.is_empty(), "an item an older save took is still in the cabinet")
	_finish()


## Box panels like the 727 cabinet, its door on a hinge node the shelves leave out.
func _cabinet() -> Node3D:
	var cabinet := Node3D.new()
	for panel: Array in PANELS:
		cabinet.add_child(_panel(panel[0], panel[1]))
	var hinge := Node3D.new()
	hinge.name = "DoorHinge"
	hinge.position = Vector3(-0.39, 0.45, 0.225)
	hinge.add_child(_panel(Vector3(0.78, 0.84, 0.025), Vector3(0.39, 0.0, 0.012)))
	cabinet.add_child(hinge)
	return cabinet


func _panel(size: Vector3, at: Vector3) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	return mesh


func _finish() -> void:
	print("container: %s" % ("all checks passed" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _frames(count: int) -> void:
	for _i: int in count:
		await process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("container: %s" % message)
