extends SceneTree

## Every caller that frees Henry's hands does it whole or not at all (ARCHITECTURE §16, rule 3), on the real player:
## sitting down (RestComponent.sit), laying the bedroll (BedrollComponent.begin_placement), opening the pack
## (PlayerHubComponent.open) and taking an armful (ItemPickup.pick_up). With two holders, the first able to let go
## and the second not, each is refused and neither holder is changed; with one willing holder each goes ahead and
## it lets go. Changing the Quick Access pocket hides what can go back and leaves what cannot (a burning flare).
## Run: godot --headless --path . --script res://tests/systems/test_held_release_callers.gd

const AREA_SCENE: String = "res://scenes/environment/interactive/InteractiveArea.tscn"
const PICKUP_SCRIPT: String = "res://scripts/environment/interactive/item_pickup.gd"

var _failures: int = 0
var _player: Player
var _serial: int = 0


## A stand-in for something held (the flare, the hammer), under the real holders' method names; it may refuse.
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
	_player.global_position = Vector3(0.0, 0.05, 0.0)
	await _frames(30)
	var rest := _player.get_node(^"RestComponent") as RestComponent
	var bedroll := _player.get_node(^"BedrollComponent") as BedrollComponent
	var hub := _player.get_node(^"PlayerHubComponent") as PlayerHubComponent
	var inventory := _player.get_node(^"InventoryComponent") as InventoryComponent
	if not inventory.has_item(BedrollComponent.ITEM_ID):
		inventory.try_add(ItemCatalog.get_item(BedrollComponent.ITEM_ID))
	var seat := Node3D.new()
	root.add_child(seat)
	seat.global_position = Vector3(0.0, 0.0, 0.0)

	await _case("sit", func() -> bool: return rest.sit(seat), func() -> void: rest.stand())
	await _case("lay the bedroll", func() -> bool: return bedroll.begin_placement(), func() -> void: bedroll.cancel_placement())
	await _case("open the pack", func() -> bool: return hub.open(), func() -> void: hub.close())
	await _case("take an armful", func() -> bool: return _spawn(&"boards").pick_up(), func() -> void: pass)
	await _quick_access()
	if _failures > 0:
		push_error("held release callers: %d check(s) failed" % _failures)
		quit(1)
		return
	print("held release callers: all checks passed")
	quit(0)


## `act` refused with a holder that cannot let go, nothing changed; then done with a willing one, which let go.
func _case(label: String, act: Callable, undo: Callable) -> void:
	var first := _holder(true)
	var second := _holder(false)
	await _frames(2)
	var done: bool = act.call()
	await _frames(2)
	_check(not done, "%s went ahead although a hand could not be freed" % label)
	_check(first.holding and first.released == 0, "%s emptied the first hand although it was refused" % label)
	_check(second.holding and second.released == 0, "%s touched the hand that could not let go" % label)
	if done:
		undo.call()
		await _frames(30)
	print("held release callers: %s refused, hands kept (released %d, %d)" % [label, first.released, second.released])
	second.free()
	await _frames(2)
	done = act.call()
	await _frames(2)
	_check(done, "%s was refused with every hand free to let go" % label)
	_check(not first.holding and first.released == 1, "%s did not free the willing hand" % label)
	print("held release callers: %s done, willing hand released %d" % [label, first.released])
	if done:
		undo.call()
	await _frames(40)
	first.free()
	await _frames(2)


## Changing the selected pocket hides what can go back to storage and leaves what cannot.
func _quick_access() -> void:
	var quick := _player.get_node(^"QuickAccessComponent") as QuickAccessComponent
	var keeps := _holder(false)
	var hides := _holder(true)
	await _frames(2)
	quick.select(quick.get_selected_index() + 1)
	await _frames(2)
	_check(not hides.holding, "a pocket change left showing what could go back")
	_check(keeps.holding and keeps.released == 0, "a pocket change touched what could not go back")
	print("held release callers: pocket change hid %d, kept %d" % [hides.released, 1 if keeps.holding else 0])
	keeps.free()
	hides.free()


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
	pickup.world_id = StringName("held_release_%d" % _serial)
	root.add_child(pickup)
	pickup.global_position = _player.global_position + Vector3(0.0, 0.0, -0.6)
	return pickup


func _frames(count: int) -> void:
	for _i: int in count:
		await process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("held release callers: %s" % message)
