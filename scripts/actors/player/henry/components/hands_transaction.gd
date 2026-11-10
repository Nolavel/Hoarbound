class_name HandsTransaction
extends RefCounted

## Hold-F takes a world pickup into Henry's hand, whole or not at all. Storage owns the new item and its weight;
## the hand only shows it. Holders let go through HeldReleaseCapability, after every check passed.

enum Refusal { NONE, NO_PRESENTER, HANDS_BUSY, STORAGE, GONE }

## How far the old hand prop shrinks toward the holster while F is held.
const STOW_SHRINK: float = 0.85

var _player: Node
var _target: ItemPickup
var _old_prop: Node3D = null
var _old_scale: Vector3 = Vector3.ONE


func _init(player: Node, target: ItemPickup) -> void:
	_player = player
	_target = target
	for holder: Node in _holders():
		var prop: Node3D = _prop_of(holder)
		if is_instance_valid(prop):
			_old_prop = prop
			_old_scale = prop.scale


## Whether this item can be shown in a hand at all; hammer, flare and armfuls cannot.
static func can_hold(player: Node, target: InteractiveArea) -> bool:
	var pickup := target as ItemPickup
	var presenter := player.get_node_or_null(^"HeldItemComponent") as HeldItemComponent if player != null else null
	return pickup != null and presenter != null and presenter.supports_item(pickup.item_id)


## Every condition for the swap, checked without changing anything.
func check() -> Refusal:
	if not is_instance_valid(_target) or _target.is_queued_for_deletion() or not _target.can_interact():
		return Refusal.GONE
	if not can_hold(_player, _target):
		return Refusal.NO_PRESENTER
	var carry := _player.get_node_or_null(^"CarryComponent") as CarryComponent
	if carry != null and carry.is_carrying():
		return Refusal.HANDS_BUSY
	## Every holder must be able to let go now (a burning flare cannot); asked, never tried.
	for holder: Node in _holders():
		if not HeldReleaseCapability.can_release(holder):
			return Refusal.HANDS_BUSY
	if _target.get_pickup_refusal() != &"":
		return Refusal.STORAGE
	return Refusal.NONE


## Presentation only: the old prop sinks toward the holster with the hold progress.
func present_stow(progress: float) -> void:
	if is_instance_valid(_old_prop):
		_old_prop.scale = _old_scale * (1.0 - STOW_SHRINK * clampf(progress, 0.0, 1.0))


## Undoes the presentation; the old item never left Henry's hand in gameplay terms.
func restore() -> void:
	if is_instance_valid(_old_prop):
		_old_prop.scale = _old_scale


## Revalidates, then swaps whole or not at all (ARCHITECTURE §16, rule 3). Storage taking the new item is the
## one step that may still refuse, so it goes first; the holders let go after it, which cannot fail once asked.
func commit() -> Refusal:
	var refusal: Refusal = check()
	restore()
	if refusal != Refusal.NONE:
		return refusal
	var holders: Array[Node] = _holders()
	var item_id: StringName = _target.item_id
	if not _target.pick_up(true):
		return Refusal.STORAGE
	for holder: Node in holders:
		if not HeldReleaseCapability.release(holder):
			push_error("HandsTransaction: %s refused to let go after it said it could" % holder.name)
	var hub := _player.get_node_or_null(^"PlayerHubComponent") as PlayerHubComponent
	if hub != null:
		hub.route_now(item_id)
	var presenter := _player.get_node_or_null(^"HeldItemComponent") as HeldItemComponent
	if presenter != null:
		presenter.present_owned(item_id)
	return Refusal.NONE


func _holders() -> Array[Node]:
	return HeldReleaseCapability.holders(_player)


## The shown prop of a held item (the hammer and a flare have none to shrink).
static func _prop_of(holder: Node) -> Node3D:
	var held := holder as HeldItemComponent
	return held.get_held_prop() if held != null else null
