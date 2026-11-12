extends "res://tools/runtime/loop_key_west_727.gd"
## Bedroll in the real 727 via its own placement ray: floor spots, the stove top, F on Sleep, F on Pack.
## godot --headless --script <this> -- [--out=DIR]


func _run() -> void:
	SaveManager.pending_load_slot = -1
	await _boot()
	await _enter()
	await _take_kit()
	await _board_windows()
	await _light_stove()
	await _warm_and_dry()
	await _probe_bedroll()
	_finish()


func _probe_bedroll() -> void:
	var bedroll := _player.get_node(^"BedrollComponent") as BedrollComponent
	_step("bedroll_have", {"in_inventory": _inventory.has_item(&"bedroll"), "can_use": bedroll.can_use(&"bedroll")})
	if not _inventory.has_item(&"bedroll"):
		_inventory.add_item(&"bedroll")
	var spots: Array = [[-4.4, 7.6], [-2.0, 6.0], [0.0, 5.0], [2.0, 6.5], [-3.0, 3.0], [4.0, 4.0]]
	var floor_ok: int = 0
	for s: Array in spots:
		var target: Vector3 = _plan(s[0], s[1], 0.0)
		var from: Vector3 = _floor_at(target + (_house.global_basis.z * -1.4))
		await _aim(from, target)
		var d: Dictionary = _diagnose(bedroll)
		d["spot"] = s
		_step("floor_spot", d)
		floor_ok += 1 if d["valid"] else 0
	var stove: Node3D = _house.get_node(^"ShelterZone/Stove") as Node3D
	var top: Dictionary = _ray(stove.global_position + Vector3.UP * 2.0, stove.global_position + Vector3.DOWN)
	var stove_valid: bool = false
	if not top.is_empty():
		await _aim(_floor_at(stove.global_position + Vector3(1.2, 0, 0)), top["position"])
		var d2: Dictionary = _diagnose(bedroll)
		stove_valid = d2["valid"]
		d2["top_y"] = (top["position"] as Vector3).y
		_step("stove_top", d2)
	_verdict["floor_accepts"] = floor_ok > 0
	_verdict["stove_refuses"] = not stove_valid
	await _sleep_and_pack(bedroll)


## Lays the mat on the floor, then presses F on Sleep and on Pack through InteractComponent.
func _sleep_and_pack(bedroll: BedrollComponent) -> void:
	var target: Vector3 = _plan(-4.4, 7.6, 0.0)
	await _aim(_floor_at(target + (_house.global_basis.z * -1.4)), target)
	bedroll.begin_placement()
	await process_frame
	var laid: bool = bedroll.confirm_placement()
	await _settle()
	for _i: int in range(60):
		await process_frame
	_step("lay", {"laid": laid, "is_laid": bedroll.is_laid()})
	_verdict["bedroll_laid"] = bedroll.is_laid()
	if not bedroll.is_laid():
		return
	var roll: Node3D = bedroll.get_laid_bedroll()
	var interact := _player.get_node(^"InteractComponent") as InteractComponent
	var prompt := get_first_node_in_group(SleepPrompt.GROUP) as SleepPrompt
	var spot := roll.get_node(^"Sleep") as InteractiveArea
	await _aim(_floor_at(spot.global_position + roll.global_basis.x * 1.0), spot.global_position)
	var focused: Variant = interact.get_active_target()
	_step("sleep_state", {"world": str(interact.get_world_target()), "spot_can": spot.can_interact(),
		"spot_at": str(spot.global_position), "henry": str(_player.global_position)})
	var refusal: int = prompt.sleep_controller.can_sleep() if prompt != null and prompt.sleep_controller != null else -1
	_step("sleep_gate", {"blocked": interact._is_blocked(), "flat": interact._flat_distance_to(spot), "reach": interact._reach(),
		"lock": str(InteractHostCapability.run(_player, &"action_locked"))})
	interact.try_interact()
	for _i: int in range(240):
		await physics_frame
		if prompt != null and prompt.is_open():
			break
	_step("press_sleep", {"prompt_found": prompt != null, "focused": str(focused), "refusal": refusal,
		"dialog_open": prompt != null and prompt.is_open()})
	_verdict["sleep_dialog_opens"] = prompt != null and prompt.is_open()
	if prompt != null and prompt.is_open():
		prompt.close()
	var pack := roll.get_node(^"Pack") as InteractiveArea
	await _aim(_floor_at(pack.global_position - roll.global_basis.z * 1.0), pack.global_position)
	var before: int = _inventory.get_count(&"bedroll")
	var pick := pack as ItemPickup
	_step("pack_state", {"refusal": String(pick.get_pickup_refusal()) if pick != null else "not ItemPickup",
		"world": str(interact.get_world_target()), "pickup": str(interact.get_pickup_target()),
		"actionable": interact.is_pickup_actionable(), "item_id": String(pick.item_id) if pick != null else ""})
	interact.try_interact()
	for _i: int in range(30):
		await process_frame
	interact.release_interact(0.05)
	for _i: int in range(240):
		await physics_frame
	await _settle()
	_step("press_pack", {"focused": str(interact.get_active_target()), "bedroll_before": before,
		"bedroll_after": _inventory.get_count(&"bedroll"), "still_laid": bedroll.is_laid()})
	_verdict["bedroll_packs_up"] = not bedroll.is_laid() and _inventory.get_count(&"bedroll") > before


func _diagnose(bedroll: BedrollComponent) -> Dictionary:
	var c: Dictionary = bedroll._raycast_placement()
	var out: Dictionary = {"valid": c["valid"], "cold": c.get("cold", false)}
	var xf: Transform3D = c["transform"]
	var cam: Camera3D = get_root().get_viewport().get_camera_3d()
	var from: Vector3 = TpsCamera.aim_origin(cam)
	var hit: Dictionary = _ray(from, from + TpsCamera.aim_direction(cam) * BedrollComponent.RAY_LENGTH)
	if hit.is_empty():
		out["hit"] = "none"
		return out
	var collider: Object = hit["collider"]
	out["hit"] = str(collider.get_path()) if collider is Node else str(collider)
	out["normal_y"] = snappedf((hit["normal"] as Vector3).y, 0.01)
	out["dist"] = snappedf(_player.global_position.distance_to(hit["position"]), 0.01)
	out["dy"] = snappedf((hit["position"] as Vector3).y - _player.global_position.y, 0.01)
	var box := BoxShape3D.new()
	box.size = Vector3(BedrollComponent.BEDROLL_SIZE.x * 0.94, 0.14, BedrollComponent.BEDROLL_SIZE.z * 0.94)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.transform = Transform3D(xf.basis, xf.origin + Vector3.UP * 0.09)
	q.exclude = [_player.get_rid(), (collider as CollisionObject3D).get_rid()]
	var blockers: Array[String] = []
	for r: Dictionary in _world.get_world_3d().direct_space_state.intersect_shape(q, 8):
		blockers.append(str((r["collider"] as Node).get_path()))
	out["blockers"] = blockers
	return out
