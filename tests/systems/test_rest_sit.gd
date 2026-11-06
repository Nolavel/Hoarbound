extends SceneTree

## Henry sits only when every hand can let go of what it holds. A holder that
## cannot let go is refused before anything is touched, so a refused sit leaves
## Henry as he was: no hand ends up empty because a sit did not happen.
##
## The real holders are checked as well: a held hammer and a held flare are let
## go for the sit, and a burning flare refuses the sit by itself.
##
## Run: godot --headless --path . --script res://tests/systems/test_rest_sit.gd

var _failures: int = 0


## A holder like HeldItemComponent: it holds something and can let go of it.
class FakeHolder:
	extends Node

	var holding: bool = true
	var releases: bool = true
	var put_away_calls: int = 0

	func is_holding() -> bool:
		return holding

	func can_release_now() -> bool:
		return releases

	func put_away_unlit() -> bool:
		put_away_calls += 1
		if not releases:
			return false
		holding = false
		return true


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_test_a_holder_that_cannot_let_go_refuses_before_anything_is_touched()
	_test_the_sit_empties_the_hands()
	_test_every_holder_publishes_the_hands_protocol()
	await _test_the_real_hammer_lets_go()
	await _test_the_real_flare_lets_go()
	await _test_a_real_holder_that_cannot_let_go_refuses_before_anything_is_touched()
	await _test_the_real_burning_flare_refuses_the_sit_by_itself()
	print("test_rest_sit: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


## Two holders, the second one cannot let go: the first one must not be touched.
func _test_a_holder_that_cannot_let_go_refuses_before_anything_is_touched() -> void:
	var body := _body()
	var rest := RestComponent.new()
	body.add_child(rest)
	var item := _holder(body, true)
	var refuser := _holder(body, false)
	var spot := _spot()

	_check(not rest.sit(spot), "Henry sat down although a holder could not let go")
	_check(item.put_away_calls == 0, "the first holder was emptied although the sit was refused")
	_check(item.holding, "the first holder lost its item although the sit was refused")
	_check(refuser.put_away_calls == 0, "the holder that could not let go was touched")
	_check(refuser.holding, "the holder that could not let go lost its item")
	_check(not rest.is_sitting(), "the refused sit left Henry sitting")
	body.free()


## The ordinary path: Henry sits and his hand is empty.
func _test_the_sit_empties_the_hands() -> void:
	var body := _body()
	var rest := RestComponent.new()
	body.add_child(rest)
	var item := _holder(body, true)
	var spot := _spot()

	_check(rest.sit(spot), "Henry did not sit although every holder could let go")
	_check(item.put_away_calls == 1, "the holder was asked to let go more than once")
	_check(not item.holding, "the hand still holds what it put away")
	_check(rest.is_sitting(), "Henry did not stay sitting")
	body.free()


## Every holder of the player publishes the hands protocol, or the sit does not
## see it.
func _test_every_holder_publishes_the_hands_protocol() -> void:
	var player := _player()
	for path: NodePath in [^"HeldItemComponent", ^"HeldLightComponent", ^"HammerComponent"]:
		var holder: Node = player.get_node_or_null(path)
		_check(holder != null, "%s is missing from the player" % path)
		if holder != null:
			_check(
				CapabilityContract.has(holder, HeldReleaseCapability.ID),
				"%s does not publish the hands protocol" % path
			)
	player.free()


## The real hammer: it lets go for the sit.
func _test_the_real_hammer_lets_go() -> void:
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

	_check(rest.sit(_spot()), "Henry did not sit although the hammer could let go")
	_check(not hammer.is_holding(), "the hammer stayed in the hand after the sit")
	_check(rest.is_sitting(), "Henry did not stay sitting")
	player.free()


## The real flare: it lets go for the sit.
func _test_the_real_flare_lets_go() -> void:
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

	_check(rest.sit(_spot()), "Henry did not sit although the flare could let go")
	_check(not light.is_holding(), "the flare stayed in the hand after the sit")
	_check(rest.is_sitting(), "Henry did not stay sitting")
	player.free()


## A real holder in the hand and a holder that cannot let go: the real holder
## must not be emptied by the refused sit.
func _test_a_real_holder_that_cannot_let_go_refuses_before_anything_is_touched() -> void:
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
	_publish(refuser)

	_check(not rest.sit(_spot()), "Henry sat down although a holder could not let go")
	_check(hammer.is_holding(), "the hammer left the hand although the sit was refused")
	_check(refuser.put_away_calls == 0, "the holder that could not let go was touched")
	_check(not rest.is_sitting(), "the refused sit left Henry sitting")
	player.free()


## The real burning flare: it refuses the sit by itself, and stays in the hand.
func _test_the_real_burning_flare_refuses_the_sit_by_itself() -> void:
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


## A holder on Henry's body, published under the hands protocol.
func _holder(body: Node, releases: bool) -> FakeHolder:
	var holder := FakeHolder.new()
	holder.releases = releases
	body.add_child(holder)
	_publish(holder)
	return holder


## Publishes the hands protocol for a holder.
func _publish(holder: FakeHolder) -> void:
	HeldReleaseCapability.publish(holder, &"is_holding", &"can_release_now", &"put_away_unlit")


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
