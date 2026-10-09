class_name WoodWorkComponent
extends Node

## Ground-checked armful drops and axe work preserve loose wood through the save contract.
const DROP_ACTION: StringName = &"drop_carried"
const CHOP_SECONDS: float = 4.0
## Manual drop candidates as (yaw offset degrees, distance metres), in preference order.
const DROP_SEARCH: Array[Vector2] = [Vector2(0.0, 1.35), Vector2(25.0, 1.35), Vector2(-25.0, 1.35),
	Vector2(0.0, 1.0), Vector2(25.0, 1.0), Vector2(-25.0, 1.0), Vector2(50.0, 1.2), Vector2(-50.0, 1.2),
	Vector2(0.0, 1.7)]

@export_group("Work time")
## Game-time cost is independent from the four-second chopping presentation.
@export_range(0.1, 60.0, 0.1) var chop_time_cost_minutes: float = 2.0

var _drops: Array[ItemPickup] = []
var _serial: int = 0
var _restore_generation: int = 0
var _chopping: ItemPickup
var _work_left: float = 0.0
var _action_managed: bool = false
var _action_id: StringName = &""
var _hint: Label
var _message_left: float = 0.0

@onready var _body: CharacterBody3D = get_parent() as CharacterBody3D
@onready var _carry: CarryComponent = get_parent().get_node(^"CarryComponent") as CarryComponent
@onready var _inventory: InventoryComponent = get_parent().get_node(^"InventoryComponent") as InventoryComponent
@onready var _held: HeldItemComponent = get_parent().get_node(^"HeldItemComponent") as HeldItemComponent
@onready var _hub: PlayerHubComponent = get_parent().get_node(^"PlayerHubComponent") as PlayerHubComponent


func _ready() -> void:
	add_to_group(&"saveable")
	_carry.carry_changed.connect(func(_item: ItemResource, count: int) -> void:
		if count > 0:
			_message_left = 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if _hub.is_open() or not event.is_action_pressed(DROP_ACTION) or event.is_echo() or not _carry.is_carrying():
		return
	drop_carried()
	get_viewport().set_input_as_handled()


func drop_carried() -> bool:
	if not _carry.is_carrying() or _work_left > 0.0 or _body.call(&"is_holding_still"):
		return false
	var placement: Dictionary = find_drop_placement()
	if not bool(placement.get("valid", false)):
		_message(tr("WOOD_DROP_BLOCKED"))
		return false
	_drop_at(placement)
	_message(tr("WOOD_DROPPED"))
	return true


## Stove overflow uses the same saved piles and collision checks as a manual drop.
func drop_carried_nearby() -> bool:
	if not _carry.is_carrying() or _work_left > 0.0:
		return false
	var forward: Vector3 = -_body.global_basis.z
	var right: Vector3 = _body.global_basis.x
	for direction: Vector3 in [forward, -right, right]:
		var placement: Dictionary = get_drop_placement(direction, 0.85)
		if bool(placement.get("valid", false)):
			_drop_at(placement)
			return true
	return false


func _drop_at(placement: Dictionary) -> void:
	var id: StringName = _carry.get_carried_item().id
	var count: int = _carry.get_carried_count()
	spawn_load(id, count, placement["transform"])
	for _i: int in range(count):
		_inventory.try_remove(id)


## The first physically valid spot from a short bounded list: straight ahead, then
## slightly to either side, nearer, wider and farther; at each, the pile across Henry,
## then along his facing. All fail: the load stays carried.
func find_drop_placement() -> Dictionary:
	var forward: Vector3 = -_body.global_basis.z
	for spot: Vector2 in DROP_SEARCH:
		for turn: float in [0.0, PI * 0.5]:
			var placement: Dictionary = get_drop_placement(forward.rotated(Vector3.UP, deg_to_rad(spot.x)), spot.y, turn)
			if bool(placement.get("valid", false)):
				return placement
	return {"valid": false}


## A floor ray plus path/volume checks ignore interaction trigger Areas.
func get_drop_placement(direction: Vector3 = Vector3.ZERO, distance: float = 1.35, turn: float = 0.0) -> Dictionary:
	if not _carry.is_carrying():
		return {"valid": false}
	if direction == Vector3.ZERO:
		direction = -_body.global_basis.z
	direction.y = 0.0
	direction = direction.normalized()
	var at: Vector3 = _body.global_position + direction * distance
	var space: PhysicsDirectSpaceState3D = _body.get_world_3d().direct_space_state
	var floor_ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.75, at + Vector3.DOWN * 3.0)
	floor_ray.exclude = [_body.get_rid()]
	var hit: Dictionary = space.intersect_ray(floor_ray)
	if hit.is_empty() or (hit["normal"] as Vector3).dot(Vector3.UP) < 0.75:
		return {"valid": false}
	var floor_at: Vector3 = hit["position"]
	var collision := _body.get_node(^"Main_Collision") as CollisionShape3D
	var feet_y: float = collision.global_position.y - float(collision.shape.get("height")) * 0.5
	if absf(floor_at.y - feet_y) > 0.65:
		return {"valid": false}
	var path := PhysicsRayQueryParameters3D.create(_body.global_position + Vector3.DOWN * 0.5, floor_at + Vector3.UP * 0.35)
	path.exclude = [_body.get_rid()]
	if not space.intersect_ray(path).is_empty():
		return {"valid": false}
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.82, 0.28, 0.30) if _carry.get_carried_item().id == &"boards" else Vector3(0.72, 0.34, 0.56)
	var basis := Basis(Vector3.UP, atan2(-direction.x, -direction.z) + turn)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(basis, floor_at + Vector3.UP * (shape.size.y * 0.5 + 0.03))
	query.exclude = [_body.get_rid(), (hit["collider"] as CollisionObject3D).get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return {"valid": space.intersect_shape(query, 8).is_empty(),
		"transform": Transform3D(basis, floor_at + Vector3.UP * 0.015)}


func axe_is_held() -> bool:
	return _held.get_item_id() == &"axe"


func is_chopping(pickup: ItemPickup) -> bool:
	return _work_left > 0.0 and _chopping == pickup


func begin_chop(pickup: ItemPickup) -> bool:
	if not axe_is_held() or _work_left > 0.0 or pickup.item_id != &"boards":
		return false
	var rest := _body.get_node(^"RestComponent") as RestComponent
	if rest.is_sitting():
		return false
	_chopping = pickup
	_work_left = CHOP_SECONDS
	_body.call(&"hold_still", CHOP_SECONDS)
	_body.call(&"play_action_animation", &"fix")
	_message(tr("WOOD_CHOP_WORK"))

	var actions: TimeCostedActionSystem = _actions()
	if actions != null:
		var request := TimeActionRequest.new()
		_action_id = StringName("chop:%d" % get_instance_id())
		request.action_id = _action_id
		request.duration_hours = chop_time_cost_minutes / 60.0
		request.presentation_seconds = CHOP_SECONDS
		request.reason = &"chop"
		request.actor = _body
		request.target = pickup
		request.stop_check = _chop_stop_reason
		request.on_complete = _chop_action_completed
		request.on_cancel = _chop_action_cancelled
		_action_managed = actions.start_action(request)
		if not _action_managed:
			_chopping = null
			_work_left = 0.0
			return false
	return true


func _chop_stop_reason() -> StringName:
	if not is_instance_valid(_chopping) or _chopping.is_queued_for_deletion():
		return &"target_lost"
	if not axe_is_held():
		return &"tool_lost"
	return &""


func _chop_action_completed(_elapsed_h: float) -> void:
	_action_managed = false
	_work_left = 0.0
	_finish_chop()


func _chop_action_cancelled(_elapsed_h: float, _reason: StringName) -> void:
	_action_managed = false
	_work_left = 0.0
	_chopping = null


func _actions() -> TimeCostedActionSystem:
	return TimeCostedActionSystem.find(get_tree()) if is_inside_tree() else null


func _finish_chop() -> void:
	if not is_instance_valid(_chopping) or _chopping.is_queued_for_deletion() or not axe_is_held():
		_chopping = null
		return
	var source: ItemPickup = _chopping
	_chopping = null
	spawn_load(&"firewood", source.count, source.global_transform)
	var ledger: PickupLedger = PickupLedger.find(get_tree())
	if ledger != null:
		ledger.record(source.world_id)
	source.queue_free()
	_message(tr("WOOD_CHOP_DONE"))


func spawn_load(item_id: StringName, count: int, transform: Transform3D, saved_id: StringName = &"") -> ItemPickup:
	_serial += 1
	var pickup := ItemPickup.new()
	pickup.item_id = item_id
	pickup.count = count
	pickup.world_id = saved_id if saved_id != &"" else StringName("wood:%d:%d:%d" % [get_instance_id(), Time.get_ticks_msec(), _serial])
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.55
	collision.shape = shape
	pickup.add_child(collision)
	var world: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	world.add_child(pickup)
	pickup.global_transform = transform
	_drops.append(pickup)
	return pickup


func get_save_key() -> StringName:
	return &"loose_wood"


func get_save_data() -> Dictionary:
	var piles: Array = []
	for pickup: ItemPickup in _drops:
		if not is_instance_valid(pickup) or pickup.is_queued_for_deletion():
			continue
		var at: Vector3 = pickup.global_position
		piles.append({"id": String(pickup.item_id), "count": pickup.count, "world_id": String(pickup.world_id),
			"position": [at.x, at.y, at.z], "yaw": pickup.global_rotation.y})
	return {"piles": piles}


func load_save_data(data: Dictionary) -> void:
	if _action_managed:
		var actions: TimeCostedActionSystem = _actions()
		if actions != null and actions.get_active_action_id() == _action_id:
			actions.cancel(&"load")
	_restore_generation += 1
	_action_managed = false
	_work_left = 0.0
	_chopping = null
	for pickup: ItemPickup in _drops:
		if is_instance_valid(pickup) and not pickup.is_queued_for_deletion():
			pickup.queue_free()
	_drops.clear()
	call_deferred(&"_restore_piles", data.get("piles", []), _restore_generation)


func _restore_piles(piles: Array, generation: int) -> void:
	if generation != _restore_generation:
		return
	var ledger: PickupLedger = PickupLedger.find(get_tree())
	for raw: Variant in piles:
		if not raw is Dictionary:
			continue
		var id := StringName(raw.get("id", ""))
		var item: ItemResource = ItemCatalog.get_item(id)
		var world_id := StringName(raw.get("world_id", ""))
		var at: Array = raw.get("position", [])
		if item == null or not item.carried_in_hands or at.size() != 3 or world_id == &"" \
			or (ledger != null and ledger.is_taken(world_id)):
			continue
		spawn_load(id, clampi(int(raw.get("count", 1)), 1, item.hand_carry_limit),
			Transform3D(Basis(Vector3.UP, float(raw.get("yaw", 0))), Vector3(float(at[0]), float(at[1]), float(at[2]))), world_id)


func _message(text: String) -> void:
	_ensure_hint()
	_hint.text = text
	_message_left = 3.0
	_hint.visible = true


func _ensure_hint() -> void:
	if is_instance_valid(_hint):
		return
	var layer := CanvasLayer.new()
	layer.layer = 15
	add_child(layer)
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 20)
	_hint.add_theme_constant_override("outline_size", 4)
	layer.add_child(_hint)


func _process(delta: float) -> void:
	if _work_left > 0.0:
		if _action_managed:
			var actions: TimeCostedActionSystem = _actions()
			if actions != null and actions.get_active_action_id() == _action_id:
				_work_left = CHOP_SECONDS * (1.0 - actions.get_progress())
			else:
				_action_managed = false
		else:
			_work_left -= delta
			if _work_left <= 0.0:
				_finish_chop()
	if _carry.is_carrying():
		_ensure_hint()
		if _message_left <= 0.0:
			_hint.text = tr("WOOD_DROP_HINT") % [_carry.get_carried_count(), tr(_carry.get_carried_item().display_name)]
		_hint.visible = true
	if is_instance_valid(_hint):
		_message_left -= delta
		_hint.visible = _carry.is_carrying() or _message_left > 0.0
		var view_size: Vector2 = get_viewport().get_visible_rect().size
		_hint.position = Vector2((view_size.x - _hint.size.x) * 0.5, view_size.y * 0.73)
