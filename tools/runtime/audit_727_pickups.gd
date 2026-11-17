extends "res://tools/runtime/loop_key_west_727.gd"
## Gameplay audit in the real 727: every pickup taken by a real F tap (InteractComponent), then each
## Quick Access item drawn through QuickAccessComponent. godot --headless --script <this> -- [--out=DIR]


func _run() -> void:
	SaveManager.pending_load_slot = -1
	await _boot()
	await _enter()
	await _audit_pickups()
	await _audit_quick_draw()
	await _audit_hand_card()
	_finish()


func _audit_pickups() -> void:
	var interact := _player.get_node(^"InteractComponent") as InteractComponent
	var pickups: Array[ItemPickup] = []
	for node: Node in _house.find_children("*", "Area3D", true, false):
		if node is ItemPickup and not (node as ItemPickup).item_id in [&"boards", &"firewood"]:
			pickups.append(node as ItemPickup)
	var failed: Array[String] = []
	for pickup: ItemPickup in pickups:
		if not is_instance_valid(pickup):
			continue
		var id: StringName = pickup.item_id
		var before: int = _total(id)
		var away: Vector3 = _player.global_position - pickup.global_position
		away.y = 0.0
		await _aim(_floor_at(pickup.global_position + (away.normalized() if away.length() > 0.1 else Vector3.BACK) * 0.7), pickup.global_position)
		for _i: int in range(20):
			await process_frame
			_point_camera(pickup.global_position)
		var target: Variant = interact.get_active_target()
		interact.try_interact()
		interact.release_interact(0.05)
		for _i: int in range(180):
			await physics_frame
			if _total(id) > before:
				break
		await _settle()
		var got: bool = _total(id) > before
		_step("pickup", {"name": String(pickup.name) if is_instance_valid(pickup) else "(gone)", "item": String(id),
			"focused": str(target), "taken": got, "refusal": String(pickup.get_pickup_refusal()) if is_instance_valid(pickup) else ""})
		if not got:
			failed.append("%s(%s)" % [id, str(target)])
	_step("pickups_summary", {"count": pickups.size(), "failed": failed})
	_verdict["open_floor_pickups_take_by_f"] = failed.filter(func(f: String) -> bool: return not f.ends_with("(<null>)") and not f.contains("Open:")).is_empty()


func _audit_quick_draw() -> void:
	var quick := _player.get_node(^"QuickAccessComponent") as QuickAccessComponent
	var hub := _player.get_node(^"PlayerHubComponent") as PlayerHubComponent
	var drawn: Array = []
	var zones: Array[Dictionary] = hub.get_quick_access_zones()
	for i: int in range(zones.size()):
		var zone: Dictionary = hub.get_quick_access_zones()[i]
		if zone["item_id"] == &"":
			continue
		var ok: bool = quick.draw(i)
		await _settle()
		var holders: Array[Node] = HeldReleaseCapability.holders(_player)
		drawn.append({"zone": String(zone["path"]), "item": String(zone["item_id"]), "draw": ok,
			"held_by": holders.map(func(n: Node) -> String: return String(n.name))})
		HeldReleaseCapability.release_all(_player)
		await _settle()
	_step("quick_draw", {"zones": drawn})


## Owner 2026-11-12: an item dropped on the Tab hand card is in Henry's hand once Tab closes; X empties hands.
func _audit_hand_card() -> void:
	var hub := _player.get_node(^"PlayerHubComponent") as PlayerHubComponent
	var quick := _player.get_node(^"QuickAccessComponent") as QuickAccessComponent
	var result: Dictionary = {}
	_put_player(_plan(-2.0, 6.0, 0.02))
	for _i: int in range(60):
		await physics_frame
	for zone: Dictionary in hub.get_quick_access_zones():
		if zone["item_id"] == &"hammer":
			var visual: HenryUALAnimation = (_player as Player).animation_component
			result["why"] = {"vy": _player.velocity.y, "carrying": visual.is_carrying(), "locking": visual.is_action_locking(),
				"holders": HeldReleaseCapability.holders(_player).map(func(n: Node) -> String: return String(n.name))}
			result["hub_opened"] = hub.open()
			for _i: int in range(30):
				await process_frame
			hub.request_hand(&"hammer", zone["path"])
			result["hub_closed"] = hub.close()
			result["zone"] = String(zone["path"])
			for _i: int in range(60):
				await process_frame
			await _settle()
			result["pocket_hammer_in_hand"] = (_player.get_node(^"HammerComponent") as HammerComponent).is_holding()
			break
	result["x_put_away"] = quick.put_away_held()
	await _settle()
	result["hands_empty_after_x"] = HeldReleaseCapability.holders(_player).is_empty()
	if _inventory.has_item(&"knife"):
		hub.open()
		for _i: int in range(30):
			await process_frame
		hub.request_hand(&"knife")
		hub.close()
		for _i: int in range(60):
			await process_frame
		await _settle()
		var held := _player.get_node(^"HeldItemComponent") as HeldItemComponent
		result["pack_knife_in_hand"] = held.is_holding() and held.get_item_id() == &"knife"
	_step("hand_card", result)
	for key: String in result:
		if result[key] is bool:
			_verdict[key] = result[key]


func _total(id: StringName) -> int:
	var n: int = _inventory.get_count(id)
	var equipment := _player.get_node(^"EquipmentComponent") as EquipmentComponent
	for entry: Dictionary in equipment.get_available_pockets():
		n += 1 if entry["item_id"] == id else 0
	return n
