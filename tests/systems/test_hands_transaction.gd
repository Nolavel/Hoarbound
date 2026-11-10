extends SceneTree

## HandsTransaction on the real player (ARCHITECTURE §16, rule 3): taking a world item into the hand either
## happens whole or changes nothing.
## - two holders, the first able to let go and the second not: the take is refused, and neither holder, storage
##   nor the world item is changed (it used to put the first one away before the second refused);
## - storage refusing the item: nothing is changed;
## - one holder able to let go: it lets go, the item lands in storage and shows in the hand.
## Run: godot --headless --path . --script res://tests/systems/test_hands_transaction.gd

const AREA_SCENE: String = "res://scenes/environment/interactive/InteractiveArea.tscn"
const PICKUP_SCRIPT: String = "res://scripts/environment/interactive/item_pickup.gd"

var _failures: int = 0
var _player: Player
var _inventory: InventoryComponent
var _held: HeldItemComponent
var _serial: int = 0


## A stand-in for something held in a hand (the flare, the hammer): it publishes the held-release contract under
## the same method names the real holders use, and may refuse to let go.
class StubHolder:
	extends Node

	var holding: bool = true
	var willing: bool = true
	var released: int = 0

	func _ready() -> void:
		HeldReleaseCapability.publish(self, &"is_holding", &"can_let_go", &"put_away_unlit")

	func is_holding() -> bool:
		return holding

	func can_let_go() -> bool:
		return holding and willing

	func put_away_unlit() -> bool:
		if not can_let_go():
			return false
		holding = false
		released += 1
		return true


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	ground.add_child(shape)
	root.add_child(ground)
	root.add_child(PickupLedger.new())
	_player = (load("res://scenes/actors/player/player.tscn") as PackedScene).instantiate() as Player
	root.add_child(_player)
	_player.global_position = Vector3(0.0, 1.0, 0.0)
	_inventory = _player.get_node(^"InventoryComponent") as InventoryComponent
	_held = _player.get_node(^"HeldItemComponent") as HeldItemComponent
	await _frames(20)
	await _refused_by_second_holder()
	await _refused_by_storage()
	await _taken_whole()
	if _failures > 0:
		push_error("hands transaction: %d check(s) failed" % _failures)
		quit(1)
		return
	print("hands transaction: all checks passed")
	quit(0)


func _refused_by_second_holder() -> void:
	var first := _holder(true)
	var second := _holder(false)
	var knife: ItemPickup = _spawn(&"knife")
	await _frames(3)
	var before: int = _inventory.get_count(&"knife")
	var refusal: HandsTransaction.Refusal = HandsTransaction.new(_player, knife).commit()
	await _frames(2)
	_check(refusal == HandsTransaction.Refusal.HANDS_BUSY, "a holder that cannot let go did not refuse the take (%d)" % refusal)
	_check(first.holding and first.released == 0, "the first holder was emptied although the take was refused")
	_check(second.holding and second.released == 0, "the refusing holder was touched")
	_check(_inventory.get_count(&"knife") == before, "storage changed although the take was refused")
	_check(is_instance_valid(knife) and not knife.is_queued_for_deletion(), "the world item went although the take was refused")
	_check(not _held.is_holding(), "the hand shows an item although the take was refused")
	print("hands transaction: refused by the second holder, nothing changed (released %d, %d)" % [first.released, second.released])
	_free_all([first, second, knife])


func _refused_by_storage() -> void:
	var first := _holder(true)
	var knife: ItemPickup = _spawn(&"knife")
	knife.count = 9999  # far past what Henry can carry
	await _frames(3)
	var before: int = _inventory.get_count(&"knife")
	var refusal: HandsTransaction.Refusal = HandsTransaction.new(_player, knife).commit()
	await _frames(2)
	_check(refusal == HandsTransaction.Refusal.STORAGE, "storage that cannot take it did not refuse the take (%d)" % refusal)
	_check(first.holding and first.released == 0, "the holder was emptied although storage refused")
	_check(_inventory.get_count(&"knife") == before, "storage changed although it refused")
	print("hands transaction: refused by storage, nothing changed")
	_free_all([first, knife])


func _taken_whole() -> void:
	var first := _holder(true)
	var knife: ItemPickup = _spawn(&"knife")
	await _frames(3)
	var before: int = _inventory.get_count(&"knife")
	var refusal: HandsTransaction.Refusal = HandsTransaction.new(_player, knife).commit()
	await _frames(2)
	_check(refusal == HandsTransaction.Refusal.NONE, "a free take was refused (%d)" % refusal)
	_check(not first.holding and first.released == 1, "the holder did not let go for the take")
	_check(_inventory.get_count(&"knife") + _pocketed(&"knife") > before, "the taken item is not in storage")
	_check(_held.get_item_id() == &"knife", "the taken item does not show in the hand")
	print("hands transaction: taken whole (holder released %d, hand %s)" % [first.released, _held.get_item_id()])
	_held.put_away()
	_free_all([first])


func _holder(willing: bool) -> StubHolder:
	var holder := StubHolder.new()
	holder.willing = willing
	_player.add_child(holder)
	return holder


func _spawn(item_id: StringName) -> ItemPickup:
	var area: Node = (load(AREA_SCENE) as PackedScene).instantiate()
	area.set_script(load(PICKUP_SCRIPT))
	var pickup := area as ItemPickup
	pickup.item_id = item_id
	_serial += 1
	pickup.world_id = StringName("hands_tx_%d" % _serial)
	root.add_child(pickup)
	pickup.global_position = _player.global_position + Vector3(0.0, -1.0, -0.6)
	return pickup


func _pocketed(item_id: StringName) -> int:
	var equipment := _player.get_node(^"EquipmentComponent") as EquipmentComponent
	return 1 if HeldOwnership.pocket_holding(equipment, item_id) != &"" else 0


func _free_all(nodes: Array) -> void:
	for node: Variant in nodes:
		if is_instance_valid(node) and not (node as Node).is_queued_for_deletion():
			(node as Node).queue_free()


func _frames(count: int) -> void:
	for _i: int in count:
		await process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("hands transaction: %s" % message)
