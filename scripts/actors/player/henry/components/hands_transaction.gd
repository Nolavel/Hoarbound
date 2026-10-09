class_name HandsTransaction
extends RefCounted

## Hold-F takes a world pickup into Henry's hand. Storage owns the new item and its
## weight like any pickup; the hand only shows it. Whatever he held is put away first,
## and only after every check passed; nothing is ever dropped.

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
	for child: Node in _player.get_children():
		if child.has_method(&"is_burning") and bool(child.call(&"is_burning")):
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


## Revalidates, then swaps in one step: old item put away into its own storage,
## new item picked up into storage and shown in the hand.
func commit() -> Refusal:
	var refusal: Refusal = check()
	restore()
	if refusal != Refusal.NONE:
		return refusal
	for holder: Node in _holders():
		var put: bool = bool(holder.call(&"put_away_unlit")) if holder.has_method(&"put_away_unlit") else false
		if not put and holder.has_method(&"put_away"):
			put = bool(holder.call(&"put_away"))
		if not put:
			return Refusal.HANDS_BUSY
	var item_id: StringName = _target.item_id
	if not _target.pick_up(true):
		return Refusal.STORAGE
	var hub := _player.get_node_or_null(^"PlayerHubComponent") as PlayerHubComponent
	if hub != null:
		hub.route_now(item_id)
	var presenter := _player.get_node_or_null(^"HeldItemComponent") as HeldItemComponent
	if presenter != null:
		presenter.present_owned(item_id)
	return Refusal.NONE


func _holders() -> Array[Node]:
	var out: Array[Node] = []
	if _player == null:
		return out
	for child: Node in _player.get_children():
		if child.has_method(&"is_holding") and bool(child.call(&"is_holding")):
			out.append(child)
	return out


static func _prop_of(holder: Node) -> Node3D:
	if holder.has_method(&"get_held_prop"):
		return holder.call(&"get_held_prop") as Node3D
	return null
