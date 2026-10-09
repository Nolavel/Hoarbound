class_name HeldLightComponent
extends Node

## Road flare in hand: storage owns it until lit; the burning flare is a physical object
## that weighs on Henry until G or Use drops that same flare.

signal flare_drawn(flare: HeldFlare)
signal flare_lit(flare: HeldFlare)
signal flare_dropped(flare: HeldFlare)

const SPENT_LINGER_S: float = 3.0
const DROP_ACTION: StringName = &"drop_carried"

@export var inventory: InventoryComponent
@export var flare_item_id: StringName = &"road_flare"

var _flare: HeldFlare
var _source_zone: StringName = &""
## True once the lit flare left storage: Henry holds a physical object, not an item.
var _physical: bool = false
var _context: WorldContext


func on_world_ready(context: WorldContext) -> void:
	_context = context


func _ready() -> void:
	if inventory == null:
		inventory = InventoryComponent.find_in(get_parent())
	if inventory != null:
		inventory.weight_changed.connect(func(_a: float, _b: float) -> void: _queue_sync())
	var equipment: EquipmentComponent = _equipment()
	if equipment != null:
		equipment.slot_changed.connect(func(_a: StringName, _b: StringName) -> void: _queue_sync())


## G drops a burning flare where an armful would be dropped.
func _unhandled_input(event: InputEvent) -> void:
	if not is_burning() or not InputMap.has_action(DROP_ACTION) or not event.is_action_pressed(DROP_ACTION) or event.is_echo():
		return
	var hub := get_parent().get_node_or_null(^"PlayerHubComponent") as PlayerHubComponent
	if hub != null and hub.is_open():
		return
	drop()
	get_viewport().set_input_as_handled()


func can_use(item_id: StringName) -> bool:
	return (
		item_id == flare_item_id
		and not is_holding()
		and inventory != null
		and inventory.has_item(item_id)
		and _other_hands_clear()
	)


func use(item_id: StringName) -> bool:
	return can_use(item_id) and light()


## Number-key Quick Access draw: shows the unlit flare from its pocket, which keeps
## the flare and its weight; nothing is consumed or lit.
func equip_from_zone(item_id: StringName, zone_path: StringName) -> bool:
	if item_id != flare_item_id or is_holding() or not _other_hands_clear():
		return false
	var animation: HenryUALAnimation = _animation()
	if animation == null or String(zone_path).split(EquipmentComponent.POCKET_SEPARATOR).size() != 2:
		return false
	if HeldOwnership.zone_item(_equipment(), zone_path) != item_id:
		return false
	_flare = _make_held_flare(animation)
	if _flare == null:
		return false
	_source_zone = zone_path
	flare_drawn.emit(_flare)
	return true


## Existing Use Selected Item grammar while something is already in hand:
## unlit -> ignite; burning -> drop.
func use_held() -> bool:
	if not is_holding():
		return false
	if not _flare.is_burning():
		return ignite_held()
	drop()
	return true


## Changing Quick Access selection hides an unlit flare; storage never let go of it.
func put_away_unlit() -> bool:
	if not is_holding_unlit():
		return false
	var animation: HenryUALAnimation = _animation()
	var flare: HeldFlare = _flare
	_flare = null
	_source_zone = &""
	if animation != null:
		_release_prop(animation, flare)
	if is_instance_valid(flare):
		flare.queue_free()
	return true


## Compatibility seam for callers that ask a held component to release itself.
func release_held() -> bool:
	if not is_holding():
		return false
	if is_holding_unlit():
		return put_away_unlit()
	_drop_physical()
	return true


func toggle() -> void:
	if is_holding():
		use_held()
	else:
		light()


func is_holding() -> bool:
	return is_instance_valid(_flare)


## A fresh flare in hand that storage still owns.
func is_holding_unlit() -> bool:
	return is_holding() and not _physical and not _flare.is_burning() and not _flare.is_spent()


func is_burning() -> bool:
	return is_holding() and _flare.is_burning()


func get_source_zone() -> StringName:
	return _source_zone


## The physical flare's weight while it is in hand outside storage; storage counts the rest.
func get_held_physical_weight() -> float:
	if not _physical or not is_holding():
		return 0.0
	var item: ItemResource = ItemCatalog.get_item(flare_item_id)
	return item.weight if item != null else 0.0


## Lighting is the ownership hand-over, done as one transaction: check everything,
## take the flare out of storage, ignite; any failure puts it back where it was.
func ignite_held() -> bool:
	if not is_holding_unlit():
		return false
	var equipment: EquipmentComponent = _equipment()
	var source: StringName = _source_zone
	if not HeldOwnership.owns(inventory, equipment, flare_item_id, source):
		put_away_unlit()
		return false
	if not HeldOwnership.take(inventory, equipment, flare_item_id, source):
		return false
	if not _flare.ignite():
		HeldOwnership.restore(inventory, equipment, flare_item_id, source)
		return false
	_source_zone = &""
	_physical = true
	if inventory != null:
		inventory.notify_weight_changed()
	flare_lit.emit(_flare)
	return true


## Hub/direct Use: show a carried flare (pack first) and light it at once.
func light() -> bool:
	var animation: HenryUALAnimation = _animation()
	if is_holding() or animation == null or inventory == null or not _other_hands_clear():
		return false
	var source: StringName = &"" if inventory.has_item(flare_item_id) else HeldOwnership.pocket_holding(_equipment(), flare_item_id)
	if not HeldOwnership.owns(inventory, _equipment(), flare_item_id, source):
		return false
	_flare = _make_held_flare(animation)
	if _flare == null:
		return false
	_source_zone = source
	if ignite_held():
		return true
	put_away_unlit()
	return false


## Drops the burning flare; the same object keeps its remaining burn on the ground.
func drop() -> void:
	if is_burning():
		_drop_physical()


func _make_held_flare(animation: HenryUALAnimation) -> HeldFlare:
	if animation == null:
		return null
	var item: ItemResource = ItemCatalog.get_item(flare_item_id)
	if item == null or item.held_fit == null:
		push_error("HeldLightComponent: road flare requires an authored HeldFit.")
		return null
	var flare := HeldPropFactory.make(flare_item_id, item) as HeldFlare
	if flare == null or not _attach_fitted(animation, flare, item.held_fit):
		if is_instance_valid(flare):
			flare.queue_free()
		return null
	if _context != null:
		flare.on_world_ready(_context)
	flare.spent.connect(_on_spent.bind(flare))
	return flare


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


## The one way a flare leaves Henry's hand: the same node falls into the world in
## a small body that lingers SPENT_LINGER_S after burn-out, then frees itself.
func _drop_physical() -> void:
	var flare: HeldFlare = _flare
	if not is_instance_valid(flare):
		return
	var animation: HenryUALAnimation = _animation()
	_flare = null
	_source_zone = &""
	_physical = false
	var hand_xf: Transform3D = flare.global_transform
	if animation != null:
		_release_prop(animation, flare)
	var world: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	var dropped := RigidBody3D.new()
	dropped.name = "DroppedFlare"
	dropped.mass = 0.15
	dropped.continuous_cd = true
	dropped.linear_damp = 0.3
	dropped.angular_damp = 1.5
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.025
	shape.height = 0.24
	collision.shape = shape
	dropped.add_child(collision)
	world.add_child(dropped)
	dropped.global_transform = hand_xf.orthonormalized()
	dropped.add_child(flare)
	flare.transform = Transform3D.IDENTITY
	var player := get_parent() as PhysicsBody3D
	if player != null:
		dropped.add_collision_exception_with(player)
		dropped.linear_velocity = player.get("velocity") as Vector3
	if flare.is_spent():
		_linger(dropped)
	else:
		flare.spent.connect(_linger.bind(dropped), CONNECT_ONE_SHOT)
	if inventory != null:
		inventory.notify_weight_changed()
	flare_dropped.emit(flare)


func _linger(dropped: RigidBody3D) -> void:
	get_tree().create_timer(SPENT_LINGER_S, false).timeout.connect(func() -> void:
		if is_instance_valid(dropped):
			dropped.queue_free())


## Burn-out in hand: Henry lets the same spent flare fall. Deferred, because the
## flare is still inside its own spent.emit() and cannot be reparented there.
func _on_spent(flare: HeldFlare) -> void:
	if flare == _flare:
		call_deferred(&"_drop_spent", flare)


func _drop_spent(flare: HeldFlare) -> void:
	if flare == _flare and is_instance_valid(flare):
		_drop_physical()


func _queue_sync() -> void:
	call_deferred(&"_sync_owned")


## The hand never shows an unlit flare storage no longer has.
func _sync_owned() -> void:
	if is_holding_unlit() and not HeldOwnership.owns(inventory, _equipment(), flare_item_id, _source_zone):
		put_away_unlit()


func _equipment() -> EquipmentComponent:
	var player: Node = get_parent()
	return player.get_node_or_null(^"EquipmentComponent") as EquipmentComponent if player != null else null


func _animation() -> HenryUALAnimation:
	var player: Node = get_parent()
	return player.get(&"animation_component") as HenryUALAnimation if player != null else null


func _other_hands_clear() -> bool:
	var player: Node = get_parent()
	if player == null:
		return false
	var carry := player.get_node_or_null(^"CarryComponent") as CarryComponent
	if carry != null and carry.is_carrying():
		return false
	var hammer := player.get_node_or_null(^"HammerComponent") as HammerComponent
	var held := player.get_node_or_null(^"HeldItemComponent") as HeldItemComponent
	return (hammer == null or not hammer.is_holding()) and (held == null or not held.is_holding())
