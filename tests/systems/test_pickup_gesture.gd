extends SceneTree

## Pickup F gesture on the real player: a quick tap stores by the canonical route,
## holding past the tap window enters hand mode and 1.0 s takes the item into the
## hand. Storage keeps every item and its weight; the old held item is put away
## only inside the commit; cancel and refusal change nothing; a world target acts
## at once. Run: godot --headless --script tests/systems/test_pickup_gesture.gd

const AREA_SCENE: String = "res://scenes/environment/interactive/InteractiveArea.tscn"
const PICKUP_SCRIPT: String = "res://scripts/environment/interactive/item_pickup.gd"
const MECHANISM_SOURCE: String = """extends InteractiveArea
var uses: int = 0
func _on_interaction_performed() -> void:
	uses += 1
"""
const STEP: float = 1.0 / 60.0

var _failures: int = 0
var _player: Player
var _ic: InteractComponent
var _inventory: InventoryComponent
var _equipment: EquipmentComponent
var _held: HeldItemComponent
var _ledger: PickupLedger
var _results: Array[StringName] = []
var _stored: Array = []
var _spawned: Array[Node] = []
var _serial: int = 0


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 0.2, 40.0)
	shape.shape = box
	ground.add_child(shape)
	ground.position = Vector3(0.0, -0.1, 0.0)
	root.add_child(ground)
	_ledger = PickupLedger.new()
	root.add_child(_ledger)
	_player = (load("res://scenes/actors/player/player.tscn") as PackedScene).instantiate() as Player
	root.add_child(_player)
	_player.global_position = Vector3(0.0, 1.0, 0.0)
	_ic = _player.get_node(^"InteractComponent") as InteractComponent
	_inventory = _player.get_node(^"InventoryComponent") as InventoryComponent
	_equipment = _player.get_node(^"EquipmentComponent") as EquipmentComponent
	_held = _player.get_node(^"HeldItemComponent") as HeldItemComponent
	_ic.pickup_gesture_finished.connect(func(_t: InteractiveArea, result: StringName) -> void: _results.append(result))
	_ic.pickup_stored.connect(func(item_id: StringName, destination: StringName) -> void: _stored.append([item_id, destination]))
	await _frames(20)
	await _check_tap_pack_route()
	await _check_tap_pocket_route()
	await _check_hold_threshold_and_hands()
	await _check_hold_cancel()
	await _check_swap_old_held()
	await _check_cancel_keeps_old_held()
	await _check_burning_flare_refuses()
	await _check_target_stability()
	await _check_target_vanishes()
	await _check_overweight()
	await _check_world_priority()
	await _check_armful_is_immediate()
	print("test_pickup_gesture: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)


## 1, 3, 4: a quick tap stores a pack item once: world gone, ledger once, destination pack.
func _check_tap_pack_route() -> void:
	var tin: ItemPickup = await _spawn_ahead(&"tinned_stew")
	var id: StringName = tin.world_id
	var before: int = _inventory.get_count(&"tinned_stew")
	_ic.try_interact()
	_ic.hold_interact(0.1)
	_ic.release_interact(0.12)
	_check(_inventory.get_count(&"tinned_stew") == before + 1, "a quick tap did not store the tin")
	_check(not is_instance_valid(tin) or tin.is_queued_for_deletion(), "the stored tin stayed in the world")
	_check(_ledger.is_taken(id), "the ledger did not record the stored tin")
	_check(_last_stored() == [&"tinned_stew", PlayerHubComponent.PACK_DESTINATION], "the tin's destination was not the pack: %s" % [_last_stored()])
	_check(_results.back() == &"stored", "the tap did not finish as stored")
	_ic.try_interact()
	_ic.release_interact(0.05)
	_check(_inventory.get_count(&"tinned_stew") == before + 1, "a second tap took the gone tin again")
	await _reset()


## 2: a Quick Access item follows the existing route into a pocket.
func _check_tap_pocket_route() -> void:
	var hammer: ItemPickup = await _spawn_ahead(&"hammer")
	_check(not _ic.can_hold_pickup(hammer), "the hammer offered a hand hold its presenter cannot keep in storage")
	_ic.try_interact()
	_ic.release_interact(0.05)
	await _frames(70)
	var destination: StringName = _last_stored()[1] if not _last_stored().is_empty() else &""
	_check(destination != PlayerHubComponent.PACK_DESTINATION and destination != &"", "the hammer was not routed to a pocket")
	_check(_pocket_has(&"hammer"), "the hammer did not land in its pocket")
	await _reset()


## 5–6: hold mode only after the tap window; 1.0 s puts the item in the hand, kept in storage.
func _check_hold_threshold_and_hands() -> void:
	var knife: ItemPickup = await _spawn_ahead(&"knife")
	var weight: float = _inventory.get_total_weight()
	_ic.try_interact()
	_ic.hold_interact(0.2)
	_check(not _ic.is_gesture_holding(), "hold mode began inside the tap window")
	_ic.hold_interact(0.25)
	_check(_ic.is_gesture_holding(), "hold mode did not begin after the tap window")
	_check(is_equal_approx(_inventory.get_total_weight(), weight) and is_instance_valid(knife), "hold mode changed ownership before 1.0 s")
	_ic.hold_interact(1.0)
	_check(_held.get_item_id() == &"knife", "1.0 s of hold did not put the knife in the hand")
	_check(_inventory.has_item(&"knife") or _pocket_has(&"knife"), "the held knife left storage")
	_check(is_equal_approx(_inventory.get_total_weight(), weight + 0.12), "the held knife's weight is not counted (%.3f)" % _inventory.get_total_weight())
	_check(_results.back() == &"hands", "the hold did not finish as hands")
	_ic.release_interact(1.05)
	_check(_held.get_item_id() == &"knife", "releasing F after the commit undid it")
	await _reset()


## 7–9: releasing in hold mode before 1.0 s cancels: no tap, nothing changed.
func _check_hold_cancel() -> void:
	var mug: ItemPickup = await _spawn_ahead(&"mug")
	var id: StringName = mug.world_id
	var mugs: int = _inventory.get_count(&"mug")
	var weight: float = _inventory.get_total_weight()
	_ic.try_interact()
	_ic.hold_interact(0.3)
	_ic.hold_interact(0.6)
	_ic.release_interact(0.6)
	_check(is_instance_valid(mug) and not mug.is_queued_for_deletion(), "a cancelled hold took the mug")
	_check(_inventory.get_count(&"mug") == mugs and not _ledger.is_taken(id), "a cancelled hold changed inventory or ledger")
	_check(is_equal_approx(_inventory.get_total_weight(), weight), "a cancelled hold changed the weight")
	_check(not _held.is_holding(), "a cancelled hold left something in the hand")
	_check(_results.back() == &"cancelled", "an unfinished hold did not finish as cancelled")
	await _reset()


## 10: a held knife is put away into its own storage and the lighter takes the hand.
func _check_swap_old_held() -> void:
	await _hold_in_hand(&"knife")
	var lighter: ItemPickup = await _spawn_ahead(&"lighter")
	var weight: float = _inventory.get_total_weight()
	_ic.try_interact()
	_ic.hold_interact(0.3)
	_ic.hold_interact(1.0)
	_check(_held.get_item_id() == &"lighter", "the swap did not put the lighter in the hand")
	_check(_inventory.has_item(&"knife") or _pocket_has(&"knife"), "the swapped-out knife left storage")
	_check(is_equal_approx(_inventory.get_total_weight(), weight + 0.04), "the swap changed weight wrongly (%.3f)" % _inventory.get_total_weight())
	_check(not is_instance_valid(lighter) or lighter.is_queued_for_deletion(), "the lighter stayed in the world")
	_ic.release_interact(1.0)
	await _reset()


## 11: a cancelled hold leaves the old knife in the hand at full size.
func _check_cancel_keeps_old_held() -> void:
	await _hold_in_hand(&"knife")
	var prop: Node3D = _held.get_held_prop()
	var scale: Vector3 = prop.scale
	var mug: ItemPickup = await _spawn_ahead(&"mug")
	_ic.try_interact()
	_ic.hold_interact(0.3)
	_ic.hold_interact(0.7)
	_check(prop.scale.length() < scale.length(), "the old held prop did not start its stow presentation")
	_ic.release_interact(0.7)
	_check(_held.get_item_id() == &"knife" and _held.get_held_prop() == prop, "cancel did not keep the knife in the hand")
	_check(prop.scale.is_equal_approx(scale), "cancel did not restore the knife's presentation")
	_check(is_instance_valid(mug) and not mug.is_queued_for_deletion(), "cancel took the mug")
	await _reset()


## 12: a burning flare cannot be put away: the hold refuses and nothing moves.
func _check_burning_flare_refuses() -> void:
	_inventory.try_add(ItemCatalog.get_item(&"road_flare"))
	var light := _player.get_node(^"HeldLightComponent") as HeldLightComponent
	_check(light.light(), "the fixture could not light a flare")
	await _frames(2)
	var mug: ItemPickup = await _spawn_ahead(&"mug")
	var weight: float = _inventory.get_total_weight()
	_ic.try_interact()
	_ic.hold_interact(0.3)
	_ic.hold_interact(1.0)
	_ic.release_interact(1.0)
	_check(light.is_burning(), "the burning flare was dropped or put out")
	_check(is_instance_valid(mug) and not mug.is_queued_for_deletion(), "the mug was taken despite busy hands")
	_check(is_equal_approx(_inventory.get_total_weight(), weight), "a refused hold changed the weight")
	_check(_results.has(&"refused_hands"), "busy hands did not refuse the hold")
	light.drop()
	await _reset()


## 13: the gesture stays on A while Henry turns to B.
func _check_target_stability() -> void:
	var a: ItemPickup = await _spawn_ahead(&"knife", Vector3(-0.2, 0.0, -0.6))
	var b: ItemPickup = _spawn(&"mug", Vector3(0.35, 0.0, -0.6))
	_face(a.global_position)
	await _frames(6)
	_check(_ic.get_pickup_target() == a, "the fixture did not attend to A")
	_ic.try_interact()
	_ic.hold_interact(0.3)
	_face(b.global_position)
	await _frames(6)
	_ic.hold_interact(1.0)
	_check(_held.get_item_id() == &"knife", "turning to B during the hold changed the item taken")
	_check(is_instance_valid(b) and not b.is_queued_for_deletion(), "B was taken instead of A")
	_ic.release_interact(1.0)
	await _reset()


## 14: A vanishing mid-hold cancels; B is never substituted.
func _check_target_vanishes() -> void:
	var a: ItemPickup = await _spawn_ahead(&"knife", Vector3(-0.15, 0.0, -0.6))
	var b: ItemPickup = _spawn(&"mug", Vector3(0.15, 0.0, -0.6))
	await _frames(4)
	_ic.try_interact()
	_ic.hold_interact(0.3)
	a.queue_free()
	await _frames(1)
	_ic.hold_interact(0.5)
	_ic.hold_interact(1.0)
	_ic.release_interact(1.0)
	_check(not _held.is_holding(), "something was taken after the gesture target vanished")
	_check(is_instance_valid(b) and not b.is_queued_for_deletion(), "B was substituted for the vanished A")
	_check(_results.back() == &"cancelled", "the vanished target did not cancel the gesture")
	await _reset()


## 15–16: overweight refuses the tap (storage) and the hold alike; nothing is lost.
func _check_overweight() -> void:
	var max_weight: float = _inventory.max_carry_weight
	_inventory.max_carry_weight = _inventory.get_total_weight() + 0.01
	var tin: ItemPickup = await _spawn_ahead(&"tinned_stew")
	_ic.try_interact()
	_ic.release_interact(0.05)
	_check(is_instance_valid(tin) and not tin.is_queued_for_deletion(), "an overweight tap took the tin")
	_check(_results.back() == &"refused_storage", "an overweight tap did not report a storage refusal")
	_ic.try_interact()
	_ic.hold_interact(0.3)
	_ic.hold_interact(1.0)
	_ic.release_interact(1.0)
	_check(is_instance_valid(tin) and not tin.is_queued_for_deletion() and not _held.is_holding(),
		"an overweight hold took the tin")
	_check(_results.back() == &"refused_hands", "an overweight hold did not refuse")
	_inventory.max_carry_weight = max_weight
	await _reset()


## 23: a world mechanism under the view acts on F at once; no pickup gesture starts.
func _check_world_priority() -> void:
	var camera := Camera3D.new()
	camera.current = true
	root.add_child(camera)
	_spawned.append(camera)
	var script := GDScript.new()
	script.source_code = MECHANISM_SOURCE
	script.reload()
	var mechanism := (load(AREA_SCENE) as PackedScene).instantiate() as InteractiveArea
	mechanism.set_script(script)
	root.add_child(mechanism)
	_spawned.append(mechanism)
	mechanism.global_position = _player.global_position + Vector3(0.5, -0.1, -0.5)
	var tin: ItemPickup = await _spawn_ahead(&"tinned_stew")
	camera.global_position = _player.global_position + Vector3(0.0, 0.62, 0.0)
	camera.look_at(mechanism.get_focus_point(_player.global_position), Vector3.UP)
	await _frames(4)
	_check(_ic.get_world_target() == mechanism, "the fixture's mechanism is not the world target")
	_ic.try_interact()
	_check((mechanism.get("uses") as int) == 1, "F did not act on the world mechanism at once")
	_check(_ic.get_gesture_target() == null, "a pickup gesture started under a world target")
	_ic.release_interact(0.05)
	_check(is_instance_valid(tin) and not tin.is_queued_for_deletion(), "the tin was taken under a world target")
	await _reset()


## Armfuls keep the immediate F: no tap/hold wait for boards.
func _check_armful_is_immediate() -> void:
	var boards: ItemPickup = await _spawn_ahead(&"boards")
	_ic.try_interact()
	_check(_ic.get_gesture_target() == null and _inventory.get_count(&"boards") > 0, "boards waited for a gesture")
	while _inventory.get_count(&"boards") > 0:
		_inventory.try_remove(&"boards")
	if is_instance_valid(boards):
		boards.queue_free()
	await _reset()


func _hold_in_hand(item_id: StringName) -> void:
	var pickup: ItemPickup = await _spawn_ahead(item_id)
	_ic.try_interact()
	_ic.hold_interact(0.3)
	_ic.hold_interact(1.0)
	_ic.release_interact(1.0)
	_check(_held.get_item_id() == item_id, "the fixture could not put %s in the hand" % item_id)
	_player.animation_component.abort_action()
	if is_instance_valid(pickup):
		pickup.queue_free()
	await _frames(2)


func _spawn_ahead(item_id: StringName, offset: Vector3 = Vector3(0.0, 0.0, -0.6)) -> ItemPickup:
	var pickup: ItemPickup = _spawn(item_id, offset)
	_face(pickup.global_position)
	await _frames(6)
	return pickup


func _spawn(item_id: StringName, offset: Vector3) -> ItemPickup:
	var area: Node = (load(AREA_SCENE) as PackedScene).instantiate()
	area.set_script(load(PICKUP_SCRIPT))
	var pickup := area as ItemPickup
	pickup.item_id = item_id
	_serial += 1
	pickup.world_id = StringName("gesture_test_%d" % _serial)
	root.add_child(pickup)
	pickup.global_position = Vector3(_player.global_position.x + offset.x, 0.0, _player.global_position.z + offset.z)
	_spawned.append(pickup)
	return pickup


func _face(point: Vector3) -> void:
	_player.face_work_target(point)


## Ends the last pickup clip too: it locks F, as in the real game, until it finishes.
func _reset() -> void:
	_held.put_away()
	var visual: HenryUALAnimation = _player.animation_component
	if visual != null:
		visual.abort_action()
	for node: Node in _spawned:
		if is_instance_valid(node):
			node.queue_free()
	_spawned.clear()
	await _frames(4)


func _pocket_has(item_id: StringName) -> bool:
	for pocket: Dictionary in _equipment.get_available_pockets():
		if pocket["item_id"] == item_id:
			return true
	return false


func _last_stored() -> Array:
	return _stored.back() if not _stored.is_empty() else []


func _frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("pickup gesture: " + message)
