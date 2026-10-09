extends SceneTree

## The [F] keycap is a promise: a pickup is actionable only with a body spot Henry
## can walk to in a straight line and stand in, with the item in his arm envelope.
## A committed F takes exactly that item; WASD cancels; a blocked path refuses once.
## Run: godot --headless --script tests/systems/test_pickup_affordance.gd

const AREA_SCENE: String = "res://scenes/environment/interactive/InteractiveArea.tscn"
const PICKUP_SCRIPT: String = "res://scripts/environment/interactive/item_pickup.gd"
## A body walking with move_and_slide like Player._walk_direction; collisions stop it.
const WALKER_SOURCE: String = """extends CharacterBody3D
signal movement_stopped
var attention_yaw: float = 0.0
var walk_target: Vector3 = Vector3.ZERO
var walking: bool = false
func get_attention_origin() -> Vector3:
	return global_position + Vector3.UP * 0.62
func get_attention_direction() -> Vector3:
	return Vector3.FORWARD.rotated(Vector3.UP, attention_yaw)
func move_to_position(point: Vector3) -> void:
	walk_target = point
	walking = true
func stop_moving() -> void:
	if not walking:
		return
	walking = false
	movement_stopped.emit()
func face_work_target(point: Vector3) -> void:
	var at := Vector3(point.x, global_position.y, point.z)
	if global_position.distance_to(at) > 0.01:
		look_at(at, Vector3.UP)
func _physics_process(delta: float) -> void:
	velocity = Vector3.ZERO
	if not walking:
		return
	var offset: Vector3 = walk_target - global_position
	offset.y = 0.0
	if offset.length() < 0.05:
		stop_moving()
		return
	velocity = offset.normalized() * minf(1.5, offset.length() / delta)
	move_and_slide()
"""

var _failures: int = 0
var _player: CharacterBody3D
var _component: InteractComponent
var _inventory: InventoryComponent
var _camera: Camera3D
var _solids: Array[Node] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_build()
	await _frames(2)
	await _check_free_floor()
	await _check_table_edge()
	await _check_blocked_side_uses_other_side()
	await _check_unreachable_promises_nothing()
	await _check_commit_survives_attention_change()
	await _check_wasd_cancels()
	await _check_blocked_path_refuses_once()
	await _check_hand_is_not_a_gate()
	await _check_solve_budget()
	if _failures > 0:
		push_error("pickup affordance: %d check(s) failed" % _failures)
		print("test_pickup_affordance: %d FAILED" % _failures)
		quit(1)
		return
	print("pickup affordance: all checks passed")
	quit(0)


func _build() -> void:
	var walker := GDScript.new()
	walker.source_code = WALKER_SOURCE
	walker.reload()
	_player = CharacterBody3D.new()
	_player.set_script(walker)
	_player.add_to_group("player")
	var body_shape := CollisionShape3D.new()
	body_shape.name = "Main_Collision"
	body_shape.shape = CapsuleShape3D.new()
	(body_shape.shape as CapsuleShape3D).radius = 0.5
	(body_shape.shape as CapsuleShape3D).height = 2.0
	_player.add_child(body_shape)
	_inventory = InventoryComponent.new()
	_inventory.max_carry_weight = 60.0
	_player.add_child(_inventory)
	_component = InteractComponent.new()
	_component.name = "InteractComponent"
	_player.add_child(_component)
	root.add_child(_player)
	_camera = Camera3D.new()
	_camera.current = true
	root.add_child(_camera)
	## Look at the sky so no world mechanism is ever under the view.
	_camera.global_position = Vector3(0.0, 30.0, 0.0)
	_camera.look_at(Vector3(0.0, 60.0, 1.0), Vector3.FORWARD)
	_box(Vector3(0.0, -0.1, 0.0), Vector3(60.0, 0.2, 60.0), true)


## A table 1.2 x 0.75 x 1.0 m centred at x, front edge towards +Z.
func _table(x: float, z: float, size: Vector3 = Vector3(1.2, 0.75, 1.0)) -> StaticBody3D:
	return _box(Vector3(x, size.y * 0.5, z), size)


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


func _spawn(at: Vector3) -> ItemPickup:
	var area: Node = (load(AREA_SCENE) as PackedScene).instantiate()
	area.set_script(load(PICKUP_SCRIPT))
	var pickup := area as ItemPickup
	pickup.item_id = &"nails"
	pickup.position = at
	root.add_child(pickup)
	_solids.append(pickup)
	return pickup


## Henry's feet at (x, 0, z), head turned to the given point.
func _stand(x: float, z: float, look_at_point: Vector3) -> void:
	_player.set(&"walking", false)
	_player.global_position = Vector3(x, 1.0, z)
	_player.rotation = Vector3.ZERO
	var flat: Vector3 = look_at_point - _player.global_position
	_player.set(&"attention_yaw", Vector3.FORWARD.signed_angle_to(Vector3(flat.x, 0.0, flat.z).normalized(), Vector3.UP))


func _clear() -> void:
	for node: Node in _solids:
		if is_instance_valid(node):
			node.queue_free()
	_solids.clear()
	await _frames(2)


func _check_free_floor() -> void:
	var item: ItemPickup = _spawn(Vector3(0.0, 0.0, -2.0))
	_stand(0.0, 0.0, item.global_position)
	await _frames(2)
	var affordance: PickupAffordance = _component.get_pickup_affordance()
	_check(_component.get_pickup_target() == item and _component.is_pickup_actionable(), "a free-floor item is not actionable")
	_check(affordance != null and affordance.valid and not affordance.in_place, "a free-floor item 2 m away has no walk-to spot (%s, target %s)" % [affordance.reason if affordance != null else &"none", _component.get_pickup_target()])
	var count: int = _inventory.get_count(&"nails")
	_component.try_interact()
	await _frames(150)
	_check(_inventory.get_count(&"nails") > count, "F on a free-floor item did not walk over and take it")
	await _clear()


## The item lies 0.3 m behind the table edge: the old straight stop point (0.675 m
## from the item) sits inside the table, so the capsule stalled. The solver stands
## Henry at the edge instead.
func _check_table_edge() -> void:
	_table(0.0, 0.0)
	var item: ItemPickup = _spawn(Vector3(0.0, 0.75, 0.2))
	_stand(1.4, 2.0, item.global_position)
	await _frames(2)
	var affordance: PickupAffordance = _component.get_pickup_affordance()
	_check(_component.is_pickup_actionable(), "a tabletop item with a free edge is not actionable (%s)" % (affordance.reason if affordance != null else &"none"))
	if affordance == null or not affordance.valid:
		await _clear()
		return
	_check(affordance.body_position.z >= 0.5 + 0.5 - 0.01, "the body spot lies inside the table")
	var count: int = _inventory.get_count(&"nails")
	_component.try_interact()
	await _frames(240)
	_check(_inventory.get_count(&"nails") > count, "F on a tabletop item did not end in a pickup")
	_check(_player.global_position.z >= 0.99, "Henry's capsule went into the table")
	await _clear()


## Henry's own side of the table is taken by a low crate: the solver picks the free
## side and the straight walk there clears the crate.
func _check_blocked_side_uses_other_side() -> void:
	_table(0.0, 0.0)
	_box(Vector3(1.05, 0.5, 0.9), Vector3(0.8, 1.0, 0.7))
	var item: ItemPickup = _spawn(Vector3(0.3, 0.75, 0.2))
	_stand(0.7, 2.6, item.global_position)
	await _frames(2)
	var affordance: PickupAffordance = _component.get_pickup_affordance()
	_check(affordance != null and affordance.valid, "with Henry's side blocked no other side was found (%s, target %s)"
		% [affordance.reason if affordance != null else &"none", _component.get_pickup_target()])
	if affordance != null and affordance.valid:
		var clear_of_crate: bool = affordance.body_position.x + 0.47 <= 0.65 or affordance.body_position.z - 0.47 >= 1.25
		_check(clear_of_crate, "the chosen body spot %s overlaps the blocking crate" % affordance.body_position)
		var count: int = _inventory.get_count(&"nails")
		_component.try_interact()
		await _frames(240)
		_check(_inventory.get_count(&"nails") > count, "the alternative side did not end in a pickup")
	await _clear()


## In the middle of a 2.4 m table nothing can reach it: noticed, never promised.
func _check_unreachable_promises_nothing() -> void:
	_table(0.0, 0.0, Vector3(2.4, 0.75, 2.4))
	var item: ItemPickup = _spawn(Vector3(0.0, 0.75, 0.0))
	_stand(0.0, 2.0, item.global_position)
	await _frames(2)
	_check(_component.get_pickup_target() == item, "the unreachable item is not even noticed")
	_check(not _component.is_pickup_actionable() and _component.get_active_target() == null,
		"an unreachable item promised [F]")
	var count: int = _inventory.get_count(&"nails")
	var start: Vector3 = _player.global_position
	_component.try_interact()
	await _frames(30)
	_check(_inventory.get_count(&"nails") == count and _player.global_position.distance_to(start) < 0.01,
		"F on an unpromised item still did something")
	await _clear()


## F on A, then the head turns to B mid-walk: A is still the one taken.
func _check_commit_survives_attention_change() -> void:
	var a: ItemPickup = _spawn(Vector3(-0.15, 0.0, -2.0))
	var b: ItemPickup = _spawn(Vector3(0.15, 0.0, -2.0))
	_stand(0.0, 0.0, a.global_position)
	_player.set(&"attention_yaw", deg_to_rad(6.0))
	await _frames(2)
	_check(_component.get_pickup_target() == a, "the head did not pick A")
	_component.try_interact()
	await _frames(10)
	_player.set(&"attention_yaw", deg_to_rad(-8.0))
	await _frames(150)
	_check(not is_instance_valid(a) or a.is_queued_for_deletion(), "the committed item A was not taken")
	_check(is_instance_valid(b) and not b.is_queued_for_deletion(), "the neighbour B was taken instead of or with A")
	await _clear()


func _check_wasd_cancels() -> void:
	var item: ItemPickup = _spawn(Vector3(0.0, 0.0, -2.2))
	_stand(0.0, 0.0, item.global_position)
	await _frames(2)
	_component.try_interact()
	await _frames(10)
	_check(_component.get_committed_target() == item, "F did not commit to the item")
	_player.call(&"stop_moving")
	await _frames(60)
	_check(_component.get_committed_target() == null, "WASD did not cancel the committed approach")
	_check(is_instance_valid(item) and not item.is_queued_for_deletion(), "a cancelled approach still took the item")
	await _clear()


## A wall drops across the path after F: one re-solve, then an honest refusal.
func _check_blocked_path_refuses_once() -> void:
	var item: ItemPickup = _spawn(Vector3(0.0, 0.0, -2.4))
	_stand(0.0, 0.0, item.global_position)
	await _frames(2)
	_component.try_interact()
	await _frames(5)
	_check(_component.get_committed_target() == item, "F did not commit to the item before the wall dropped")
	_box(Vector3(0.0, 1.0, -1.2), Vector3(8.0, 2.0, 0.2))
	await _frames(240)
	_check(_component.get_committed_target() == null, "the walk into a new wall never ended")
	_check(is_instance_valid(item) and not item.is_queued_for_deletion(), "an item behind a wall was taken")
	_check(item._feedback_text == tr(&"INTERACT_UNREACHABLE"), "the refusal did not say the item cannot be reached")
	await _clear()


## Items mirrored left and right of Henry: both valid, only the hand hint differs.
func _check_hand_is_not_a_gate() -> void:
	var left: ItemPickup = _spawn(Vector3(-0.35, 0.0, -0.45))
	var right: ItemPickup = _spawn(Vector3(0.35, 0.0, -0.45))
	_stand(0.0, 0.0, left.global_position)
	await _frames(2)
	var left_affordance: PickupAffordance = _component.get_pickup_affordance(left)
	var right_affordance: PickupAffordance = _component.get_pickup_affordance(right)
	_check(left_affordance.valid and right_affordance.valid, "a mirrored item lost validity with the other hand")
	_check(left_affordance.preferred_hand != right_affordance.preferred_hand, "mirrored items got the same hand hint")
	await _clear()


## Standing still before one item, solves stay cached instead of running every frame.
func _check_solve_budget() -> void:
	var item: ItemPickup = _spawn(Vector3(0.0, 0.0, -1.5))
	_stand(0.0, 0.0, item.global_position)
	await _frames(2)
	var before: int = _component.affordance_solves
	await _frames(60)
	var solves: int = _component.affordance_solves - before
	_check(solves <= 4, "one still target was solved %d times in 60 frames" % solves)
	await _clear()


func _frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("pickup affordance: %s" % message)
