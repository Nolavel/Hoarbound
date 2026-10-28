extends SceneTree

## Snow melting in the hand (#257 stage 4): a handful lasts 40 s in a barely warm room, 20 s at
## room warmth, keeps below freezing, and is gone from storage once melted.
## Run: godot --headless --script tests/systems/test_hand_snow_melt.gd

var _failures: int = 0


func _initialize() -> void:
	_check(is_inf(HandSnowMelt.melt_seconds(-8.0)), "snow melts below freezing")
	_check(is_equal_approx(HandSnowMelt.melt_seconds(5.0), 40.0), "a cool room does not take 40 s")
	_check(is_equal_approx(HandSnowMelt.melt_seconds(22.0), 20.0), "a warm room does not take 20 s")
	var body := Node.new()
	var inventory := InventoryComponent.new()
	body.add_child(inventory)
	var melt := HandSnowMelt.new()
	melt.inventory = inventory
	body.add_child(melt)
	root.add_child(body)
	inventory.try_add(load("res://data/items/snow_handful.tres") as ItemResource)
	var gone: Array = [false]
	melt.melted.connect(func() -> void: gone[0] = true)
	melt.advance(30.0, -5.0)
	_check(melt.get_melt() == 0.0 and inventory.has_item(&"snow_handful"), "the handful melted outdoors in the frost")
	melt.advance(10.0, 20.0)
	_check(absf(melt.get_melt() - 0.5) < 0.01, "10 s at 20 C is not half melted (%.2f)" % melt.get_melt())
	melt.advance(10.5, 20.0)
	_check(gone[0] and not inventory.has_item(&"snow_handful"), "the melted handful is still in storage")
	print("test_hand_snow_melt: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
