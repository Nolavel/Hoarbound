extends SceneTree

## G puts the item in Henry's hand down: a pickup lands on the ground ahead, the item leaves the pocket it was
## shown from, and picking it up brings it back with its runtime state (a searchlight's charge).
## Run: godot --headless --path . --script res://tests/systems/test_drop_held.gd

var _failures: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	floor.add_child(shape)
	root.add_child(floor)
	var player := (load("res://scenes/actors/player/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	root.add_child(player)
	player.global_position = Vector3(0.0, 1.0, 0.0)
	for _i: int in range(30):
		await physics_frame
	var held := player.get_node(^"HeldItemComponent") as HeldItemComponent
	var equipment := player.get_node(^"EquipmentComponent") as EquipmentComponent
	var inventory := player.get_node(^"InventoryComponent") as InventoryComponent
	## The lighter in the coat pocket: shown in the hand, then put down.
	_check(held.present_owned(&"lighter"), "the pocketed lighter could not be held")
	var zone: StringName = held.get_source_zone()
	_check(held.drop_held(), "G did not put the lighter down")
	_check(not held.is_holding(), "the lighter is still in the hand")
	_check(HeldOwnership.zone_item(equipment, zone) != &"lighter", "the lighter is still in its pocket")
	var pickups: Array = root.find_children("*", "ItemPickup", true, false).filter(func(n: Node) -> bool: return (n as ItemPickup).item_id == &"lighter")
	_check(pickups.size() == 1, "no lighter pickup on the ground")
	if pickups.size() == 1:
		var dropped := pickups[0] as ItemPickup
		_check(dropped.global_position.y < 0.05 and dropped.global_position.distance_to(player.global_position) < 2.0, "the lighter did not land on the ground ahead")
		_check(dropped.pick_up(), "the dropped lighter could not be picked up again")
		_check(inventory.has_item(&"lighter"), "picking it up did not bring the lighter back")
	## A searchlight keeps its charge through the drop.
	inventory.try_add_instance(load("res://data/items/searchlight.tres") as ItemResource, {"searchlight_runtime_hours": 30.0})
	_check(held.present_owned(&"searchlight"), "the searchlight could not be held")
	await process_frame
	_check(held.drop_held(), "G did not put the searchlight down")
	var lights: Array = root.find_children("*", "ItemPickup", true, false).filter(func(n: Node) -> bool: return (n as ItemPickup).item_id == &"searchlight")
	_check(lights.size() == 1 and float((lights[0] as ItemPickup).instance_state.get("searchlight_runtime_hours", -1.0)) == 30.0, "the dropped searchlight lost its charge")
	if lights.size() == 1:
		(lights[0] as ItemPickup).pick_up()
		_check(float(inventory.get_first_instance_state(&"searchlight").get("searchlight_runtime_hours", -1.0)) == 30.0, "the picked-up searchlight lost its charge")
	print("drop held: %s" % ("all checks passed" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("drop held: %s" % message)
