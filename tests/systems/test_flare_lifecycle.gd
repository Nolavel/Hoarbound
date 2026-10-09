extends SceneTree

## The burn belongs to the flare. Lit in hand it still weighs on Henry; G drops the
## same flare, which keeps its remaining burn, goes out on its original schedule, then
## lingers and is cleaned up. A flare that burns out in hand falls the same way.
## Lighting is a transaction: nothing is taken unless the whole hand-over can finish.
## Run: godot --headless --script tests/systems/test_flare_lifecycle.gd

const EPS: float = 0.0001
const BURN_S: float = 2.0
const TIME_TOLERANCE_S: float = 0.2

var _failures: int = 0
var _player: Player
var _inventory: InventoryComponent
var _equipment: EquipmentComponent
var _hub: PlayerHubComponent
var _light: HeldLightComponent
var _flare_weight: float = 0.0


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
	_light = _player.get_node(^"HeldLightComponent") as HeldLightComponent
	_flare_weight = ItemCatalog.get_item(&"road_flare").weight
	await _frames(20)
	await _check_g_drop_keeps_burn()
	await _check_burn_out_in_hand()
	await _check_ignite_transaction()
	print("test_flare_lifecycle: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)


## Weight chain, then G: same flare, burn not reset, spent on time, linger, cleanup.
func _check_g_drop_keeps_burn() -> void:
	var zone: StringName = await _pocket()
	var flares: int = _total()
	var in_pocket: float = _inventory.get_total_weight()
	_check(_light.equip_from_zone(&"road_flare", zone), "the flare was not drawn")
	var flare := _held_flare()
	flare.burn_duration_s = BURN_S
	var unlit: float = _inventory.get_total_weight()
	_check(_light.ignite_held(), "the drawn flare did not light")
	await _frames(2)
	var burning: float = _inventory.get_total_weight()
	_check(absf(unlit - in_pocket) < EPS and absf(burning - in_pocket) < EPS,
		"weight pocket %.3f / unlit %.3f / burning %.3f differ" % [in_pocket, unlit, burning])
	_check(HeldOwnership.zone_item(_equipment, zone) == &"" and _total() == flares - 1, "lighting did not move the flare out of storage")
	var before: float = flare.get_remaining_seconds()
	_check(flare.ignite() and absf(flare.get_remaining_seconds() - before) < 0.05, "igniting a burning flare reset its burn")
	await _seconds(0.6)
	var remaining: float = flare.get_remaining_seconds()
	var dropped_at: int = Time.get_ticks_msec()
	_press_g()
	await _frames(2)
	_check(not _light.is_holding(), "G left the burning flare in hand")
	_check(is_instance_valid(flare) and flare.get_parent() is RigidBody3D and flare.get_parent().name.begins_with("DroppedFlare"),
		"G did not drop the same flare into the world")
	_check(flare.is_burning(), "the dropped flare went out")
	_check(flare.get_remaining_seconds() <= remaining + 0.01 and flare.get_remaining_seconds() > remaining - 0.3,
		"the drop changed the burn: %.2f -> %.2f s" % [remaining, flare.get_remaining_seconds()])
	_check(absf(_inventory.get_total_weight() - (in_pocket - _flare_weight)) < EPS,
		"after G the weight is %.3f, expected %.3f" % [_inventory.get_total_weight(), in_pocket - _flare_weight])
	var body: Node = flare.get_parent()
	await _until_spent(flare, remaining + 1.0)
	var burned: float = float(Time.get_ticks_msec() - dropped_at) / 1000.0
	_check(absf(burned - remaining) < TIME_TOLERANCE_S, "the flare went out after %.2f s, expected %.2f s" % [burned, remaining])
	_check(flare.is_spent() and not flare.ignite(), "a spent flare lit again")
	_check(_total() == flares - 1, "the burnt flare came back into storage")
	await _seconds(HeldLightComponent.SPENT_LINGER_S - 0.5)
	_check(is_instance_valid(body), "the spent flare was cleaned up before its linger")
	await _seconds(1.0)
	_check(not is_instance_valid(body), "the spent flare was never cleaned up")


## Burn-out in hand: the same spent flare falls into the world, weight drops by it.
func _check_burn_out_in_hand() -> void:
	var zone: StringName = await _pocket()
	_check(_light.equip_from_zone(&"road_flare", zone) and _light.ignite_held(), "the second flare did not light")
	var flare := _held_flare()
	flare.burn_duration_s = 0.4
	var burning: float = _inventory.get_total_weight()
	await _until_spent(flare, 2.0)
	await _frames(3)
	_check(not _light.is_holding(), "the spent flare stayed in hand")
	_check(is_instance_valid(flare) and flare.get_parent() is RigidBody3D, "the burnt-out flare vanished instead of falling")
	_check(absf(_inventory.get_total_weight() - (burning - _flare_weight)) < EPS, "burn-out did not take the flare's weight off Henry")
	var body: Node = flare.get_parent()
	await _seconds(HeldLightComponent.SPENT_LINGER_S + 0.5)
	_check(not is_instance_valid(body), "the burnt-out flare was not cleaned up after its linger")


## Storage lost the flare behind the hand's back: lighting refuses and takes nothing.
func _check_ignite_transaction() -> void:
	var zone: StringName = await _pocket()
	_check(_light.equip_from_zone(&"road_flare", zone), "the third flare was not drawn")
	var parts: PackedStringArray = String(zone).split(EquipmentComponent.POCKET_SEPARATOR)
	_equipment.take_from_pocket(StringName(parts[0]), StringName(parts[1]))
	var count: int = _total()
	var weight: float = _inventory.get_total_weight()
	_check(not _light.ignite_held(), "a flare storage no longer owns was lit")
	_check(not _light.is_holding() and _total() == count and absf(_inventory.get_total_weight() - weight) < EPS,
		"the refused ignition changed the hand or storage")
	_inventory.try_add(ItemCatalog.get_item(&"road_flare"))
	zone = await _pocket()
	count = _total()
	_check(HeldOwnership.take(_inventory, _equipment, &"road_flare", zone) and _total() == count - 1, "rollback fixture: take failed")
	_check(HeldOwnership.restore(_inventory, _equipment, &"road_flare", zone), "rollback did not return the flare")
	_check(HeldOwnership.zone_item(_equipment, zone) == &"road_flare" and _total() == count, "rollback lost the flare or its pocket")


func _held_flare() -> HeldFlare:
	var visual: HenryUALAnimation = _player.get(&"animation_component") as HenryUALAnimation
	var flare := visual.get_held_prop() as HeldFlare if visual != null else null
	if flare == null and visual != null:
		flare = visual.get_offhand_prop() as HeldFlare
	return flare


func _press_g() -> void:
	var down := InputEventAction.new()
	down.action = HeldLightComponent.DROP_ACTION
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventAction.new()
	up.action = HeldLightComponent.DROP_ACTION
	up.pressed = false
	Input.parse_input_event(up)


## One flare in a free Quick Access pocket; returns its zone path.
func _pocket() -> StringName:
	var zone: StringName = HeldOwnership.pocket_holding(_equipment, &"road_flare")
	if zone != &"":
		return zone
	_inventory.try_add(ItemCatalog.get_item(&"road_flare"))
	for entry: Dictionary in _hub.get_quick_access_zones():
		if entry["item_id"] == &"" and _hub.move_to_zone(&"road_flare", entry["path"]) == EquipmentComponent.Refusal.NONE:
			await _frames(2)
			return entry["path"]
	_check(false, "no free Quick Access pocket for a flare")
	return &""


func _total() -> int:
	var count: int = _inventory.get_count(&"road_flare")
	for pocket: Dictionary in _equipment.get_available_pockets():
		if pocket["item_id"] == &"road_flare":
			count += 1
	return count


## Waits for burn-out, but never longer than max_s, so a broken burn fails instead of hanging.
func _until_spent(flare: HeldFlare, max_s: float) -> void:
	var until: int = Time.get_ticks_msec() + int(max_s * 1000.0)
	while is_instance_valid(flare) and not flare.is_spent() and Time.get_ticks_msec() < until:
		await process_frame


func _seconds(seconds: float) -> void:
	var until: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame


func _frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("flare lifecycle: " + message)
