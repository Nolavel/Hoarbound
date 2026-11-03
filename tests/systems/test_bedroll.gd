extends SceneTree

## Bedroll: C (or Use in the Hub) shows its grey ghost, F places it, C puts the ghost away; laying spends it from the inventory into a laid roll with F — Sleep
## (a SleepSpot) and a pack prompt; packing returns it; a save restores it.
## Run: godot --headless --script tests/systems/test_bedroll.gd

var _failures: int = 0
var _frame: int = 0
var _body: CharacterBody3D
var _inventory: InventoryComponent
var _bedroll: BedrollComponent


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		1:
			_build()
			_check(not _bedroll.lay_down(), "a bedroll was laid with none in the inventory")
			_inventory.try_add(load("res://data/items/bedroll.tres") as ItemResource)
			_check(_bedroll.lay_down(), "the carried bedroll was not laid")
			_check(not _inventory.has_item(&"bedroll"), "laying did not take the bedroll out of the inventory")
			var roll: Node3D = _bedroll.get_laid_bedroll()
			_check(roll != null and roll.get_node_or_null(^"Sleep") is SleepSpot, "the laid roll offers no F — Sleep")
			_check(not _bedroll.lay_down(), "a second bedroll was laid on top of the first")
			var saved: Dictionary = _bedroll.get_save_data()
			_check(saved.has("x"), "a laid bedroll is not in the save")
			var pack := roll.get_node(^"Pack") as ItemPickup
			_check(pack != null and pack.pick_up(), "rolling it up failed")
		3:
			_check(not _bedroll.is_laid(), "the roll stayed after packing")
			_check(_inventory.has_item(&"bedroll"), "packing did not return the bedroll")
			_check(_bedroll.get_save_data().is_empty(), "a packed bedroll still saves as laid")
			_bedroll.load_save_data({"x": 1.0, "y": 0.0, "z": 2.0, "yaw": 0.5})
			_check(_bedroll.is_laid(), "loading a save did not restore the laid bedroll")
			_test_use_flow()
			_finish()
	return false


func _build() -> void:
	_body = CharacterBody3D.new()
	_inventory = InventoryComponent.new()
	_body.add_child(_inventory)
	_bedroll = BedrollComponent.new()
	_bedroll.inventory = _inventory
	_body.add_child(_bedroll)
	root.add_child(_body)
	## ItemPickup resolves the player's inventory through the player group.
	_body.add_to_group(&"player")


func _finish() -> void:
	if _failures > 0:
		push_error("bedroll: %d check(s) failed" % _failures)
		quit(1)
		return
	print("bedroll: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("bedroll: %s" % message)


## Hub Use or C → preview in front of Henry → confirm lays it.
func _test_use_flow() -> void:
	var on_c: bool = false
	for event: InputEvent in InputMap.action_get_events(&"lay_bedroll") if InputMap.has_action(&"lay_bedroll") else []:
		on_c = on_c or (event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_C)
	_check(on_c, "C does not lay the bedroll")
	var body := CharacterBody3D.new()
	var inventory := InventoryComponent.new()
	body.add_child(inventory)
	var bedroll := BedrollComponent.new()
	bedroll.inventory = inventory
	body.add_child(bedroll)
	var hub := PlayerHubComponent.new()
	hub.inventory = inventory
	body.add_child(hub)
	root.add_child(body)
	_check(not hub.can_use(&"bedroll"), "Use was offered with no bedroll carried")
	inventory.try_add(load("res://data/items/bedroll.tres") as ItemResource)
	_check(hub.can_use(&"bedroll"), "the carried bedroll offers no Use")
	_check(hub.use_item(&"bedroll"), "Use on the bedroll failed")
	_check(bedroll.is_placing(), "Use did not start the placement preview")
	_check(inventory.has_item(&"bedroll"), "the preview spent the bedroll before it was placed")
	bedroll.cancel_placement()
	_check(not bedroll.is_placing() and inventory.has_item(&"bedroll"), "cancelling lost the bedroll")
	var press := InputEventAction.new()
	press.action = &"lay_bedroll"
	press.pressed = true
	bedroll._input(press)
	_check(bedroll.is_placing(), "C did not show the bedroll's ghost")
	var ghost: Node = body.get_tree().current_scene.find_child("BedrollPreview", true, false) if body.get_tree().current_scene != null else root.find_child("BedrollPreview", true, false)
	_check(ghost != null and ghost.find_children("*", "CollisionObject3D", true, false).is_empty(), "the ghost carries colliders")
	bedroll._input(press)
	_check(not bedroll.is_placing() and inventory.has_item(&"bedroll"), "C again did not put the ghost away")
	hub.use_item(&"bedroll")
	_check(bedroll.confirm_placement(), "F did not lay the previewed bedroll")
	_check(bedroll.is_laid() and not inventory.has_item(&"bedroll"), "the placed bedroll was not laid and spent")
	var ahead: Vector3 = bedroll.get_laid_bedroll().global_position - body.global_position
	_check(ahead.dot(-body.global_transform.basis.z) > 1.0, "the bedroll was laid behind Henry, not in front")
