extends SceneTree

## Sitting down empties Henry's hands. When one holder cannot let go of what it
## holds, Henry has to stay as he was: the holder that already let go keeps its
## item, and no hand is left half empty by a sit that did not happen.
## Run: godot --headless --path . --script res://tests/systems/test_rest_sit.gd
##
## The spot holds no meal table, so the check stays about the hands alone.

var _failures: int = 0


## A holder like HeldItemComponent: it shows an item and can always put it away.
class ItemHolder:
	extends Node

	var holding: bool = true
	var put_away_calls: int = 0
	var given_back: bool = false

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

	func equip_from_zone(_item_id: StringName, _zone: StringName) -> bool:
		given_back = true
		holding = true
		return true


## A holder like HeldLightComponent: a burning flare cannot be stowed.
class LightHolder:
	extends Node

	var holding: bool = true
	var burning: bool = true
	var put_away_calls: int = 0

	func is_holding() -> bool:
		return holding

	func is_holding_unlit() -> bool:
		return holding and not burning

	func put_away_unlit() -> bool:
		put_away_calls += 1
		if burning:
			return false
		holding = false
		return true


## A holder that says it can let go and then refuses anyway.
class LyingHolder:
	extends Node

	var put_away_calls: int = 0

	func is_holding() -> bool:
		return true

	func is_holding_unlit() -> bool:
		return true

	func put_away_unlit() -> bool:
		put_away_calls += 1
		return false


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_test_two_holders_second_refuses()
	_test_single_refusing_holder()
	_test_holder_that_refuses_after_the_prepare()
	_test_sit_empties_the_hands()
	print("test_rest_sit: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


## Two holders, the second one refuses: the first one must not have been touched.
func _test_two_holders_second_refuses() -> void:
	var body := _body()
	var rest := RestComponent.new()
	body.add_child(rest)
	var item := ItemHolder.new()
	body.add_child(item)
	var light := LightHolder.new()
	body.add_child(light)
	var spot := _spot()

	_check(not rest.sit(spot), "Henry sat down although a holder refused")
	_check(item.put_away_calls == 0, "the first holder was emptied although the sit was refused")
	_check(item.holding, "the first holder lost its item although the sit was refused")
	_check(light.put_away_calls == 0, "the refusing holder was touched")
	_check(light.holding, "the refusing holder lost its item")
	_check(not rest.is_sitting(), "the refused sit left Henry sitting")
	body.free()


## One holder that refuses: nothing of his changes.
func _test_single_refusing_holder() -> void:
	var body := _body()
	var rest := RestComponent.new()
	body.add_child(rest)
	var light := LightHolder.new()
	body.add_child(light)
	var spot := _spot()

	_check(not rest.sit(spot), "Henry sat down with a flare he cannot put away")
	_check(light.put_away_calls == 0, "the refusing holder was touched")
	_check(light.holding, "the refusing holder lost its item")
	_check(not rest.is_sitting(), "the refused sit left Henry sitting")
	body.free()


## A holder that refuses only in the commit: what was already let go is given back.
func _test_holder_that_refuses_after_the_prepare() -> void:
	var body := _body()
	var rest := RestComponent.new()
	body.add_child(rest)
	var item := ItemHolder.new()
	body.add_child(item)
	var liar := LyingHolder.new()
	body.add_child(liar)
	var spot := _spot()

	_check(not rest.sit(spot), "Henry sat down although a holder refused")
	_check(item.given_back, "the holder that let go did not get its item back")
	_check(item.holding, "the holder that let go stayed empty after the refused sit")
	_check(not rest.is_sitting(), "the refused sit left Henry sitting")
	body.free()


## The ordinary path: Henry sits and his hand is empty.
func _test_sit_empties_the_hands() -> void:
	var body := _body()
	var rest := RestComponent.new()
	body.add_child(rest)
	var item := ItemHolder.new()
	body.add_child(item)
	var spot := _spot()

	_check(rest.sit(spot), "Henry did not sit although every holder could let go")
	_check(item.put_away_calls == 1, "the holder was asked to let go more than once")
	_check(not item.holding, "the hand still holds what it put away")
	_check(rest.is_sitting(), "Henry did not stay sitting")
	body.free()


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


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("test_rest_sit: " + message)
