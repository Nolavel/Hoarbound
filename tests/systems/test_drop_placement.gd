extends SceneTree

## G drop is forgiving but physical: straight ahead when clear, a nearby side spot
## when a chair blocks the centre, never through a wall, and the load stays in the
## hands when nothing fits. Dropped piles survive save/load.
## Run: godot --headless --script tests/systems/test_drop_placement.gd

var _failures: int = 0
var _player: Player
var _work: WoodWorkComponent
var _carry: CarryComponent
var _inventory: InventoryComponent
var _solids: Array[Node] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_box(Vector3(0.0, -0.1, 0.0), Vector3(40.0, 0.2, 40.0), true)
	_player = (load("res://scenes/actors/player/player.tscn") as PackedScene).instantiate() as Player
	root.add_child(_player)
	_player.global_position = Vector3(0.0, 1.0, 0.0)
	_work = _player.get_node(^"WoodWorkComponent") as WoodWorkComponent
	_carry = _player.get_node(^"CarryComponent") as CarryComponent
	_inventory = _player.get_node(^"InventoryComponent") as InventoryComponent
	await _frames(10)
	await _check_clear_forward()
	await _check_chair_uses_side()
	await _check_all_blocked_keeps_load()
	await _check_never_through_wall()
	await _check_save_reload()
	print("test_drop_placement: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)


func _arm(count: int = 3) -> void:
	for _i: int in range(count):
		_inventory.try_add(ItemCatalog.get_item(&"boards"))
	_player.global_position = Vector3(0.0, 1.0, 0.0)
	_player.rotation = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	await _frames(4)


func _check_clear_forward() -> void:
	await _arm()
	_check(_carry.is_carrying(), "the fixture did not put boards in Henry's hands")
	var dropped: bool = _work.drop_carried()
	var pile: ItemPickup = _last_pile()
	_check(dropped and pile != null and not _carry.is_carrying(), "a clear floor refused the drop")
	if pile != null:
		_check(absf(pile.global_position.x) < 0.05 and absf(pile.global_position.z + 1.35) < 0.05,
			"a clear drop did not land straight ahead (%s)" % pile.global_position)
	await _clear()


func _check_chair_uses_side() -> void:
	await _arm()
	_box(Vector3(0.0, 0.45, -1.35), Vector3(0.5, 0.9, 0.5))
	await _frames(2)
	var dropped: bool = _work.drop_carried()
	var pile: ItemPickup = _last_pile()
	_check(dropped and pile != null, "a chair in front blocked the whole drop although the side was free")
	if pile != null:
		_check(absf(pile.global_position.x) > 0.3, "the pile landed in the chair (%s)" % pile.global_position)
	await _clear()


func _check_all_blocked_keeps_load() -> void:
	await _arm()
	_box(Vector3(0.0, 1.0, -0.75), Vector3(5.0, 2.0, 0.2))
	await _frames(2)
	var piles: int = _work._drops.size()
	var dropped: bool = _work.drop_carried()
	_check(not dropped and _carry.is_carrying() and _inventory.get_count(&"boards") == 3,
		"a blocked drop lost the load")
	_check(_work._drops.size() == piles, "a blocked drop still spawned a pile")
	await _clear()
	_carry_reset()


## A wall across the centre: a side spot is fine, a spot behind the wall never is.
func _check_never_through_wall() -> void:
	await _arm()
	_box(Vector3(0.0, 1.0, -1.0), Vector3(1.6, 2.0, 0.1))
	await _frames(2)
	_work.drop_carried()
	var pile: ItemPickup = _last_pile()
	if pile != null:
		_check(pile.global_position.z > -0.95 or absf(pile.global_position.x) > 0.8,
			"the pile was placed through the wall (%s)" % pile.global_position)
	await _clear()
	_carry_reset()


func _check_save_reload() -> void:
	await _arm()
	_work.drop_carried()
	var pile: ItemPickup = _last_pile()
	_check(pile != null, "the save fixture could not drop a pile")
	if pile == null:
		return
	var at: Vector3 = pile.global_position
	var data: Dictionary = _work.get_save_data()
	_work.load_save_data(data)
	await _frames(4)
	var restored: ItemPickup = _last_pile()
	_check(restored != null and restored.global_position.distance_to(at) < 0.01 and restored.count == 3,
		"the dropped pile did not survive save/load")
	await _clear()


func _last_pile() -> ItemPickup:
	var alive: Array = _work._drops.filter(func(p: Variant) -> bool: return is_instance_valid(p) and not (p as Node).is_queued_for_deletion())
	return alive[-1] if not alive.is_empty() else null


func _carry_reset() -> void:
	while _inventory.get_count(&"boards") > 0:
		_inventory.try_remove(&"boards")


func _box(center: Vector3, size: Vector3, permanent: bool = false) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	root.add_child(body)
	if not permanent:
		_solids.append(body)
	return body


func _clear() -> void:
	for node: Node in _solids:
		if is_instance_valid(node):
			node.queue_free()
	_solids.clear()
	for pile: Variant in _work._drops:
		if is_instance_valid(pile):
			(pile as Node).queue_free()
	_work._drops.clear()
	await _frames(3)


func _frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("drop placement: " + message)
