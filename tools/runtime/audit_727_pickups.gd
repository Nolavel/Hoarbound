extends "res://tools/runtime/loop_key_west_727.gd"
## Gameplay audit in the real 727: every pickup taken by a real F tap (InteractComponent), then each
## Quick Access item drawn through QuickAccessComponent. godot --headless --script <this> -- [--out=DIR]


func _run() -> void:
	SaveManager.pending_load_slot = -1
	await _boot()
	await _enter()
	await _audit_pickups()
	await _audit_quick_draw()
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
	_verdict["every_pickup_takes_by_f"] = failed.is_empty()


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


func _total(id: StringName) -> int:
	var n: int = _inventory.get_count(id)
	var equipment := _player.get_node(^"EquipmentComponent") as EquipmentComponent
	for entry: Dictionary in equipment.get_available_pockets():
		n += 1 if entry["item_id"] == id else 0
	return n
