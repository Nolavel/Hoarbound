extends SceneTree

## Regression suite for the current id catalog and the state-preserving Hub
## transfer. Run locally when a Godot binary is available:
## godot --headless --path . --script res://tests/systems/test_item_integrity.gd
## Deliberately NOT wired to an Actions workflow.

const LAYOUT: String = "res://data/equipment/player_layout.tres"
var _failures: int = 0


var _frame: int = 0


## Runs on the first frame, as test_quick_access does: nodes added in _initialize
## are not ready yet, so the coat's pockets would not exist.
func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_run()
	return false


func _run() -> void:
	_test_catalog_identity()
	_test_stateful_stacks_rejected()
	_test_stateful_pocket_round_trip()
	print("test_item_integrity: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("test_item_integrity: " + message)


func _test_catalog_identity() -> void:
	var production: ItemCatalog = ItemCatalog.shared()
	_check(production != null, "production item catalog missing")
	if production != null:
		_check(production.validate_entries().is_empty(), "duplicate/invalid IDs in production catalog")
	var a := ItemResource.new()
	var b := ItemResource.new()
	a.id = &"same"
	b.id = &"same"
	var duplicate := ItemCatalog.new()
	duplicate.items.append(a)
	duplicate.items.append(b)
	var errors: PackedStringArray = duplicate.validate_entries()
	_check(errors.size() == 1 and errors[0].contains("duplicate"), "duplicate IDs not detected")


func _test_stateful_stacks_rejected() -> void:
	var inventory := InventoryComponent.new()
	var stew: ItemResource = ItemCatalog.get_item(&"tinned_stew")
	_check(stew != null and stew.max_stack > 1, "missing stackable stew fixture")
	if stew != null:
		_check(not inventory.try_add_instance(stew, {"quality": 0.25}), "stateful stack silently accepted")
		_check(inventory.get_count(&"tinned_stew") == 0, "rejected stack changed inventory")
	inventory.free()


func _test_stateful_pocket_round_trip() -> void:
	var player := CharacterBody3D.new()
	var equipment := EquipmentComponent.new()
	equipment.name = "EquipmentComponent"
	equipment.layout = load(LAYOUT) as EquipmentLayout
	equipment.starter_garment_ids = [&"worn_coat"]
	player.add_child(equipment)
	var inventory := InventoryComponent.new()
	inventory.equipment = equipment
	player.add_child(inventory)
	var hub := PlayerHubComponent.new()
	player.add_child(hub)
	root.add_child(player)
	var lighter: ItemResource = ItemCatalog.get_item(&"lighter")
	_check(lighter != null and lighter.max_stack == 1, "missing non-stackable lighter")
	if lighter == null:
		player.free()
		return
	_check(inventory.try_add_instance(lighter, {"fuel": 0.15}), "first lighter rejected")
	_check(inventory.try_add_instance(lighter, {"fuel": 0.80}), "second lighter rejected")
	var zones: Array[Dictionary] = hub.get_quick_access_zones()
	_check(not zones.is_empty(), "no coat pocket available")
	if zones.is_empty():
		player.free()
		return
	var zone: StringName = zones[0]["path"]
	var parts: PackedStringArray = String(zone).split(EquipmentComponent.POCKET_SEPARATOR)
	var slot := StringName(parts[0])
	var pocket := StringName(parts[1])
	var initial_weight: float = inventory.get_total_weight()
	_check(hub.move_to_zone(&"lighter", zone) == EquipmentComponent.Refusal.NONE, "pack -> pocket failed")
	_check(inventory.get_count(&"lighter") == 1, "pack retained both lighters")
	_check(is_equal_approx(float(equipment.get_pocket_instance_state(slot, pocket).get("fuel", -1.0)), 0.15), "pocket lost first lighter fuel")
	_check(is_equal_approx(inventory.get_total_weight(), initial_weight), "transfer changed carried weight")
	var inv_save: Dictionary = inventory.get_save_data()
	var eq_save: Dictionary = equipment.get_save_data()
	var restored_equipment := EquipmentComponent.new()
	restored_equipment.layout = load(LAYOUT) as EquipmentLayout
	restored_equipment.load_save_data(eq_save)
	_check(is_equal_approx(float(restored_equipment.get_pocket_instance_state(slot, pocket).get("fuel", -1.0)), 0.15), "equipment save lost pocket state")
	var restored_inventory := InventoryComponent.new()
	restored_inventory.load_save_data(inv_save)
	_check(is_equal_approx(float(restored_inventory.get_entries()[0].get("instance_state", {}).get("fuel", -1.0)), 0.80), "inventory save lost second lighter state")
	var legacy: Dictionary = eq_save.duplicate(true)
	legacy.erase("pocket_states")
	restored_equipment.load_save_data(legacy)
	_check(restored_equipment.get_pocket_item(slot, pocket) == &"lighter", "legacy equipment save lost ID")
	_check(restored_equipment.get_pocket_instance_state(slot, pocket).is_empty(), "legacy save invented instance state")
	inventory.max_carry_weight = 0.01
	_check(hub.move_to_pack(zone) == PlayerHubComponent.OVERWEIGHT, "overweight transfer not rejected")
	_check(equipment.get_pocket_item(slot, pocket) == &"lighter", "overweight rollback lost pocket item")
	_check(is_equal_approx(float(equipment.get_pocket_instance_state(slot, pocket).get("fuel", -1.0)), 0.15), "overweight rollback lost fuel")
	inventory.max_carry_weight = 30.0
	_check(hub.move_to_pack(zone) == &"", "pocket -> pack failed")
	_check(equipment.get_pocket_item(slot, pocket) == &"", "pocket duplicated item after transfer")
	_check(inventory.get_count(&"lighter") == 2, "not all lighters returned")
	var fuels: Array[float] = []
	for entry: Dictionary in inventory.get_entries():
		if entry["id"] == &"lighter":
			fuels.append(float(entry.get("instance_state", {}).get("fuel", -1.0)))
	fuels.sort()
	_check(fuels.size() == 2 and is_equal_approx(fuels[0], 0.15) and is_equal_approx(fuels[1], 0.80), "two distinct lighter states merged/lost")
	_check(is_equal_approx(inventory.get_total_weight(), initial_weight), "return transfer changed carried weight")
	player.free()
	restored_equipment.free()
	restored_inventory.free()
