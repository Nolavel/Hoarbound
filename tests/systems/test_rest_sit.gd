extends SceneTree

## Sitting down empties Henry's hands. When one holder cannot let go of what it
## holds, Henry has to stay as he was: the holder that already let go keeps its
## item, and no hand is left half empty by a sit that did not happen.
##
## The real holders are checked as well: a held hammer and a held flare are
## given back after a refusal, and a burning flare refuses the sit by itself.
##
## Run: godot --headless --path . --script res://tests/systems/test_rest_sit.gd

var _failures: int = 0


## A holder like HeldItemComponent: it shows an item and can be asked to let go.
class FakeHolder:
	extends Node

	var holding: bool = true
	var releases: bool = true
	var show_succeeds: bool = true
	var put_away_calls: int = 0
	var show_calls: int = 0
	var shown_again: bool = false
	var item_id: StringName = &"hammer"
	var zone: StringName = &"coat/pocket_0"
	## The item stays in storage when it is put away; only the hand empties.
	var in_storage: bool = true

	func is_holding() -> bool:
		return holding

	func put_away_unlit() -> bool:
		put_away_calls += 1
		if not releases:
			return false
		holding = false
		return true

	func get_item_id() -> StringName:
		return item_id

	func get_source_zone() -> StringName:
		return zone

	func equip_from_zone(_item_id: StringName, _zone: StringName) -> bool:
		show_calls += 1
		if not show_succeeds:
			return false
		shown_again = true
		holding = true
		return true


## A holder that cannot be shown again: once it lets go, there is no way back.
class BlindHolder:
	extends Node

	var holding: bool = true
	var put_away_calls: int = 0

	func is_holding() -> bool:
		return holding

	func put_away_unlit() -> bool:
		put_away_calls += 1
		holding = false
		return true

	func get_item_id() -> StringName:
		return &"hammer"

	func get_source_zone() -> StringName:
		return &"coat/pocket_0"


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_test_two_holders_second_refuses()
	_test_holder_without_a_way_back_refuses_before_anything_is_touched()
	_test_a_failed_give_back_is_reported()
	_test_sit_empties_the_hands()
	await _test_real_hammer_is_given_back()
	await _test_real_flare_is_given_back()
	await _test_real_burning_flare_refuses_by_itself()
	print("test_rest_sit: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


## Two holders, the second one refuses: the first one must be given back.
func _test_two_holders_second_refuses() -> void:
	var body := _body()
	var rest := RestComponent.new()
	body.add_child(rest)
	var item := FakeHolder.new()
	body.add_child(item)
	var refuser := FakeHolder.new()
	refuser.releases = false
	body.add_child(refuser)
	var spot := _spot()

	_check(not rest.sit(spot), "Henry sat down although a holder refused")
	_check(item.put_away_calls == 1, "the first holder was not asked to let go once")
	_check(item.shown_again, "the first holder was not given its item back")
	_check(item.holding, "the first holder stayed empty after the refused sit")
	_check(refuser.holding, "the refusing holder lost its item")
	_check(not rest.is_sitting(), "the refused sit left Henry sitting")
	body.free()


## A holder that cannot be shown again refuses the sit before anything is touched.
func _test_holder_without_a_way_back_refuses_before_anything_is_touched() -> void:
	var body := _body()
	var rest := RestComponent.new()
	body.add_child(rest)
	var item := FakeHolder.new()
	body.add_child(item)
	var blind := BlindHolder.new()
	body.add_child(blind)
	var spot := _spot()

	_check(not rest.sit(spot), "Henry sat down although a holder had no way back")
	_check(item.put_away_calls == 0, "the first holder was emptied although the sit was refused")
	_check(item.holding, "the first holder lost its item although the sit was refused")
	_check(blind.put_away_calls == 0, "the holder without a way back was touched")
	_check(blind.holding, "the holder without a way back lost its item")
	_check(not rest.is_sitting(), "the refused sit left Henry sitting")
	body.free()


## A give-back that fails is attempted and reported; the item is not lost.
func _test_a_failed_give_back_is_reported() -> void:
	var body := _body()
	var rest := RestComponent.new()
	body.add_child(rest)
	var item := FakeHolder.new()
	item.show_succeeds = false
	body.add_child(item)
	var refuser := FakeHolder.new()
	refuser.releases = false
	body.add_child(refuser)
	var spot := _spot()

	_check(not rest.sit(spot), "Henry sat down although a holder refused")
	_check(item.show_calls == 1, "the first holder was not given back")
	_check(not item.shown_again, "the first holder was shown again although it could not be")
	_check(not item.holding, "the first holder still holds what it put away")
	_check(item.in_storage, "the item was lost when it could not be given back")
	_check(not rest.is_sitting(), "the refused sit left Henry sitting")
	body.free()


## The ordinary path: Henry sits and his hand is empty.
func _test_sit_empties_the_hands() -> void:
	var body := _body()
	var rest := RestComponent.new()
	body.add_child(rest)
	var item := FakeHolder.new()
	body.add_child(item)
	var spot := _spot()

	_check(rest.sit(spot), "Henry did not sit although every holder could let go")
	_check(item.put_away_calls == 1, "the holder was asked to let go more than once")
	_check(not item.holding, "the hand still holds what it put away")
	_check(rest.is_sitting(), "Henry did not stay sitting")
	body.free()


## The real hammer: a held item is given back when another holder refuses.
func _test_real_hammer_is_given_back() -> void:
	var player := _player()
	var hub := player.get_node(^"PlayerHubComponent") as PlayerHubComponent
	var inventory := player.get_node(^"InventoryComponent") as InventoryComponent
	var hammer := player.get_node(^"HammerComponent") as HammerComponent
	var rest := player.get_node(^"RestComponent") as RestComponent
	var zone: StringName = await _pocket(hub, inventory, &"hammer")
	_check(zone != &"", "no pocket took the hammer")
	if zone == &"":
		player.free()
		return
	_check(hammer.equip_from_zone(&"hammer", zone), "the hammer did not come into the hand")
	_check(hammer.is_holding(), "the hammer is not in the hand")
	var refuser := FakeHolder.new()
	refuser.releases = false
	player.add_child(refuser)

	_check(not rest.sit(_spot()), "Henry sat down although a holder refused")
	_check(hammer.is_holding(), "the real holder lost the hammer although the sit was refused")
	_check(refuser.holding, "the refusing holder lost its item")
	_check(not rest.is_sitting(), "the refused sit left Henry sitting")
	player.free()


## The real flare: a held flare is given back when another holder refuses.
func _test_real_flare_is_given_back() -> void:
	var player := _player()
	var hub := player.get_node(^"PlayerHubComponent") as PlayerHubComponent
	var inventory := player.get_node(^"InventoryComponent") as InventoryComponent
	var light := player.get_node(^"HeldLightComponent") as HeldLightComponent
	var rest := player.get_node(^"RestComponent") as RestComponent
	var zone: StringName = await _pocket(hub, inventory, &"road_flare")
	_check(zone != &"", "no pocket took the flare")
	if zone == &"":
		player.free()
		return
	_check(light.equip_from_zone(&"road_flare", zone), "the flare did not come into the hand")
	_check(light.is_holding(), "the flare is not in the hand")
	var refuser := FakeHolder.new()
	refuser.releases = false
	player.add_child(refuser)

	_check(not rest.sit(_spot()), "Henry sat down although a holder refused")
	_check(light.is_holding(), "the real holder lost the flare although the sit was refused")
	_check(refuser.holding, "the refusing holder lost its item")
	_check(not rest.is_sitting(), "the refused sit left Henry sitting")
	player.free()


## The real burning flare: it refuses the sit by itself, and stays in the hand.
func _test_real_burning_flare_refuses_by_itself() -> void:
	var player := _player()
	var hub := player.get_node(^"PlayerHubComponent") as PlayerHubComponent
	var inventory := player.get_node(^"InventoryComponent") as InventoryComponent
	var light := player.get_node(^"HeldLightComponent") as HeldLightComponent
	var rest := player.get_node(^"RestComponent") as RestComponent
	inventory.try_add(ItemCatalog.get_item(&"road_flare"))
	await _frames(2)
	_check(light.light(), "the flare could not be lit")
	_check(light.is_burning(), "the flare is not burning")
	_check(not light.put_away_unlit(), "a burning flare could be put away")

	_check(not rest.sit(_spot()), "Henry sat down with a burning flare in hand")
	_check(light.is_holding(), "the burning flare left the hand although the sit was refused")
	_check(not rest.is_sitting(), "the refused sit left Henry sitting")
	player.free()


## Henry's body, in the tree so the spot's global transform is real.
func _body() -> CharacterBody3D:
	var body := CharacterBody3D.new()
	root.add_child(body)
	return body


## The seat, in the tree as well.
func _spot() -> Node3D:
	var spot := Node3D.new()
	root.add_child(spot)
	return spot


## Henry himself, as the game builds him.
func _player() -> Player:
	var player := (load("res://scenes/actors/player/player.tscn") as PackedScene).instantiate() as Player
	root.add_child(player)
	player.global_position = Vector3(0.0, 1.0, 0.0)
	return player


## Puts one item_id in a free Quick Access pocket and returns its zone path.
func _pocket(hub: PlayerHubComponent, inventory: InventoryComponent, item_id: StringName) -> StringName:
	hub.move_to_pack(&"pack/pack_lid")  # the starter mug; these checks need two free pockets
	inventory.try_add(ItemCatalog.get_item(item_id))
	for entry: Dictionary in hub.get_quick_access_zones():
		if entry["item_id"] == &"" and hub.move_to_zone(item_id, entry["path"]) == EquipmentComponent.Refusal.NONE:
			await _frames(2)
			return entry["path"]
	return &""


func _frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("test_rest_sit: " + message)
