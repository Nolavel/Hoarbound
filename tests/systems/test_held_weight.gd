extends SceneTree

## Storage owns every held item and its weight; the hand only shows it. A hammer or
## an unlit flare weighs the same in its pocket, in the hand and after stowing, is never
## duplicated or lost, and the hand drops the prop if storage loses the item.
## Run: godot --headless --script tests/systems/test_held_weight.gd

const EPS: float = 0.0001

var _failures: int = 0
var _player: Player
var _inventory: InventoryComponent
var _equipment: EquipmentComponent
var _hub: PlayerHubComponent
var _quick: QuickAccessComponent
var _hammer: HammerComponent
var _light: HeldLightComponent


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 0.2, 20.0)
	shape.shape = box
	ground.add_child(shape)
	ground.position = Vector3(0.0, -0.1, 0.0)
	root.add_child(ground)
	_player = (load("res://scenes/actors/player/player.tscn") as PackedScene).instantiate() as Player
	root.add_child(_player)
	_player.global_position = Vector3(0.0, 1.0, 0.0)
	_inventory = _player.get_node(^"InventoryComponent") as InventoryComponent
	_equipment = _player.get_node(^"EquipmentComponent") as EquipmentComponent
	_hub = _player.get_node(^"PlayerHubComponent") as PlayerHubComponent
	_quick = _player.get_node(^"QuickAccessComponent") as QuickAccessComponent
	_hammer = _player.get_node(^"HammerComponent") as HammerComponent
	_light = _player.get_node(^"HeldLightComponent") as HeldLightComponent
	await _frames(20)
	await _check_hammer_from_pocket()
	await _check_hammer_from_pack()
	await _check_hammer_lost_while_shown()
	await _check_unlit_flare()
	print("test_held_weight: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)


## Quick Access hammer: weight_before_draw == weight_while_held == weight_after_stow.
func _check_hammer_from_pocket() -> void:
	var zone: StringName = await _pocket(&"hammer")
	var count: int = _total(&"hammer")
	var before: float = _inventory.get_total_weight()
	_select(zone)
	_quick.use_selected()
	await _frames(3)
	_check(_hammer.is_holding() and _hammer.get_source_zone() == zone, "Quick Access did not show the hammer from its pocket")
	var held: float = _inventory.get_total_weight()
	_check(HeldOwnership.zone_item(_equipment, zone) == &"hammer", "the shown hammer left its pocket")
	_check(absf(held - before) < EPS, "the hammer's weight changed in hand: %.3f -> %.3f" % [before, held])
	_quick.use_selected()
	await _frames(3)
	_check(_hammer.is_holding() and HeldOwnership.zone_item(_equipment, zone) == &"hammer" and _total(&"hammer") == count,
		"pressing the shown hammer's slot again moved it")
	_hammer.put_away()
	await _frames(3)
	var after: float = _inventory.get_total_weight()
	_check(absf(after - before) < EPS, "stowing changed the weight: %.3f -> %.3f" % [before, after])
	_check(_total(&"hammer") == count and HeldOwnership.zone_item(_equipment, zone) == &"hammer",
		"stowing duplicated or lost the hammer (%d -> %d)" % [count, _total(&"hammer")])


## Hub / board-up path: the pack keeps the hammer while the hand shows it.
func _check_hammer_from_pack() -> void:
	_inventory.try_add(ItemCatalog.get_item(&"hammer"))
	var pack: int = _inventory.get_count(&"hammer")
	var before: float = _inventory.get_total_weight()
	_check(_hammer.use(&"hammer"), "the pack hammer was not shown")
	await _frames(3)
	var held: float = _inventory.get_total_weight()
	_check(_inventory.get_count(&"hammer") == pack and absf(held - before) < EPS, "showing the pack hammer took it out of the pack")
	_hammer.put_away()
	await _frames(3)
	_check(_inventory.get_count(&"hammer") == pack and absf(_inventory.get_total_weight() - before) < EPS,
		"stowing the pack hammer changed the pack")


## Storage moves the hammer away while shown: the hand lets go, nothing is duplicated.
func _check_hammer_lost_while_shown() -> void:
	var zone: StringName = await _pocket(&"hammer")
	var count: int = _total(&"hammer")
	_check(_hammer.equip_from_zone(&"hammer", zone), "the pocket hammer was not shown")
	_hub.move_to_pack(zone)
	await _frames(3)
	_check(not _hammer.is_holding(), "the hand still shows a hammer its pocket no longer holds")
	_check(_total(&"hammer") == count, "losing the shown hammer duplicated or lost it (%d -> %d)" % [count, _total(&"hammer")])


## Unlit flare: pocket, hand and back weigh the same; the pocket keeps it.
func _check_unlit_flare() -> void:
	var zone: StringName = await _pocket(&"road_flare")
	var count: int = _total(&"road_flare")
	var before: float = _inventory.get_total_weight()
	_check(_light.equip_from_zone(&"road_flare", zone), "the unlit flare was not shown")
	await _frames(3)
	_check(_light.is_holding_unlit() and HeldOwnership.zone_item(_equipment, zone) == &"road_flare", "the unlit flare left its pocket")
	_check(absf(_inventory.get_total_weight() - before) < EPS, "the unlit flare's weight changed in hand")
	_light.put_away_unlit()
	await _frames(3)
	_check(absf(_inventory.get_total_weight() - before) < EPS and _total(&"road_flare") == count,
		"stowing the unlit flare changed weight or count")


## Puts one item_id in a free Quick Access pocket and returns its zone path.
func _pocket(item_id: StringName) -> StringName:
	var zone: StringName = HeldOwnership.pocket_holding(_equipment, item_id)
	if zone != &"":
		return zone
	_inventory.try_add(ItemCatalog.get_item(item_id))
	for entry: Dictionary in _hub.get_quick_access_zones():
		if entry["item_id"] == &"" and _hub.move_to_zone(item_id, entry["path"]) == EquipmentComponent.Refusal.NONE:
			await _frames(2)
			return entry["path"]
	_check(false, "no free Quick Access pocket for %s" % item_id)
	return &""


func _select(zone: StringName) -> void:
	var zones: Array[Dictionary] = _hub.get_quick_access_zones()
	for i: int in range(zones.size()):
		if zones[i]["path"] == zone:
			_quick.select(i)


func _total(item_id: StringName) -> int:
	var count: int = _inventory.get_count(item_id)
	for pocket: Dictionary in _equipment.get_available_pockets():
		if pocket["item_id"] == item_id:
			count += 1
	return count


func _frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("held weight: " + message)
