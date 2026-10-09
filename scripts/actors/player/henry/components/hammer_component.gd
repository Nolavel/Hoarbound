class_name HammerComponent
extends Node

## One-hand hammer used by breach boarding. Quick Access shows it from its pocket,
## the Hub from the pack; storage keeps the hammer and its weight the whole time.

signal hammer_drawn
signal hammer_stowed

@export var inventory: InventoryComponent
@export var hammer_item_id: StringName = &"hammer"

var _hammer: Node3D
var _source_zone: StringName = &""


func _ready() -> void:
	if inventory == null:
		inventory = InventoryComponent.find_in(get_parent())
	if inventory != null:
		inventory.weight_changed.connect(func(_a: float, _b: float) -> void: _queue_sync())
	var equipment: EquipmentComponent = _equipment()
	if equipment != null:
		equipment.slot_changed.connect(func(_a: StringName, _b: StringName) -> void: _queue_sync())


func can_use(item_id: StringName) -> bool:
	return (
		item_id == hammer_item_id
		and not is_holding()
		and inventory != null
		and inventory.has_item(item_id)
		and _other_hands_clear()
	)


## Shows the pack's hammer in hand; the pack keeps it.
func use(item_id: StringName) -> bool:
	if not can_use(item_id):
		return false
	_source_zone = &""
	return _draw()


func equip_from_zone(item_id: StringName, zone_path: StringName) -> bool:
	if item_id != hammer_item_id or is_holding() or not _other_hands_clear():
		return false
	var equipment: EquipmentComponent = _equipment()
	var parts: PackedStringArray = String(zone_path).split(EquipmentComponent.POCKET_SEPARATOR)
	if equipment == null or parts.size() != 2:
		return false
	var body_slot := StringName(parts[0])
	var pocket := StringName(parts[1])
	if equipment.get_pocket_item(body_slot, pocket) != item_id:
		return false
	_source_zone = zone_path
	if _draw():
		return true
	_source_zone = &""
	return false


func is_holding() -> bool:
	return is_instance_valid(_hammer)


## The pocket the shown hammer belongs to, or "" for the pack.
func get_source_zone() -> StringName:
	return _source_zone if is_holding() else &""


## QuickAccess already calls this name when selection changes.
func put_away_unlit() -> bool:
	return put_away()


func put_away() -> bool:
	if not is_holding():
		return false
	var animation: HenryUALAnimation = _animation()
	var prop: Node3D = _hammer
	_hammer = null
	if animation != null:
		_release_prop(animation, prop)
	if is_instance_valid(prop):
		prop.queue_free()
	_source_zone = &""
	hammer_stowed.emit()
	return true


func release_held() -> bool:
	return put_away()


## Small visible hit. Board placement owns the actual resource transaction.
func swing() -> void:
	if not is_holding():
		return
	var start: Vector3 = _hammer.rotation
	var hit: Vector3 = start + Vector3(-0.65, 0.0, 0.0)
	var tween := _hammer.create_tween().set_trans(Tween.TRANS_SINE)
	tween.tween_property(_hammer, ^"rotation", hit, 0.10).set_ease(Tween.EASE_IN)
	tween.tween_property(_hammer, ^"rotation", start, 0.16).set_ease(Tween.EASE_OUT)


func _draw() -> bool:
	var animation: HenryUALAnimation = _animation()
	var item: ItemResource = ItemCatalog.get_item(hammer_item_id)
	if animation == null or item == null or item.held_fit == null:
		push_error("HammerComponent: hammer requires an authored HeldFit.")
		return false
	_hammer = HeldPropFactory.make(hammer_item_id, item)
	if _hammer == null or not _attach_fitted(animation, _hammer, item.held_fit):
		if is_instance_valid(_hammer):
			_hammer.queue_free()
		_hammer = null
		return false
	hammer_drawn.emit()
	return true


func _attach_fitted(animation: HenryUALAnimation, prop: Node3D, fit: HeldFit) -> bool:
	if fit.hand == HeldFit.Hand.RIGHT:
		if animation.get_offhand_socket() == null or animation.get_offhand_prop() != null:
			return false
		animation.hold_in_offhand(prop)
	else:
		if animation.get_hand_socket() == null or animation.get_held_prop() != null:
			return false
		animation.hold_in_hand(prop)
	fit.apply_to(prop)
	return true


func _release_prop(animation: HenryUALAnimation, prop: Node3D) -> void:
	if animation.get_held_prop() == prop:
		animation.release_hand()
	elif animation.get_offhand_prop() == prop:
		animation.release_offhand()


func _other_hands_clear() -> bool:
	var player: Node = get_parent()
	if player == null:
		return false
	var carry := player.get_node_or_null(^"CarryComponent") as CarryComponent
	if carry != null and carry.is_carrying():
		return false
	var light := player.get_node_or_null(^"HeldLightComponent") as HeldLightComponent
	var held := player.get_node_or_null(^"HeldItemComponent") as HeldItemComponent
	return (light == null or not light.is_holding()) and (held == null or not held.is_holding())


func _queue_sync() -> void:
	call_deferred(&"_sync_owned")


## The hand never shows a hammer storage no longer has.
func _sync_owned() -> void:
	if is_holding() and not HeldOwnership.owns(inventory, _equipment(), hammer_item_id, _source_zone):
		put_away()


func _equipment() -> EquipmentComponent:
	var player: Node = get_parent()
	return player.get_node_or_null(^"EquipmentComponent") as EquipmentComponent if player != null else null


func _animation() -> HenryUALAnimation:
	var player: Node = get_parent()
	return player.get(&"animation_component") as HenryUALAnimation if player != null else null
