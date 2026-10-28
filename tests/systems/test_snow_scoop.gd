extends SceneTree

## Empty mug -> mug of snow, without a second inventory.
## Run: godot --headless --script tests/systems/test_snow_scoop.gd

var _failures: int = 0
var _frame: int = 0


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame != 1:
		return false
	var body := CharacterBody3D.new()
	var inventory := InventoryComponent.new()
	body.add_child(inventory)
	var scoop := SnowScoopComponent.new()
	scoop.inventory = inventory
	body.add_child(scoop)
	root.add_child(body)

	inventory.try_add(load("res://data/items/mug.tres") as ItemResource)
	_check(scoop.can_use(&"mug"), "an empty mug cannot scoop snow outdoors")
	_check(scoop.use(&"mug"), "using the empty mug did not scoop snow")
	_check(not inventory.has_item(&"mug") and inventory.has_item(&"mug_snow"),
		"the empty mug was not replaced by a mug of snow")
	_check(not scoop.use(&"mug"), "snow was scooped without another empty mug")

	## F on the ground: bare ground refuses, snow fills a packed mug or gives a handful.
	var on_snow: SnowScoopComponent = _scoop_on_depth(body, inventory, 0.0)
	_check(on_snow.scoop_target()["refusal"] == "SNOW_SCOOP_NO_SNOW", "F on bare ground offered a scoop")
	on_snow.queue_free()
	var deep: SnowScoopComponent = _scoop_on_depth(body, inventory, 0.12)
	_check(deep.scoop_target()["item"] == SnowScoopComponent.HANDFUL, "a free hand on snow is not offered a handful")
	_check(deep.finish_scoop(SnowScoopComponent.HANDFUL) and inventory.has_item(&"snow_handful"), "the handful was not taken")
	inventory.try_add(load("res://data/items/mug.tres") as ItemResource)
	_check(deep.finish_scoop(SnowScoopComponent.FILLED_MUG) and not inventory.has_item(&"mug"),
		"the packed mug was not filled from the ground")

	print("test_snow_scoop: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)
	return false


## A scoop that reads depth_m of settled snow under Henry instead of the live snow field.
func _scoop_on_depth(body: Node, inventory: InventoryComponent, depth_m: float) -> SnowScoopComponent:
	var script := GDScript.new()
	script.source_code = "extends SnowScoopComponent\nvar depth: float = 0.0\nfunc snow_depth_underfoot() -> float:\n\treturn depth\n"
	script.reload()
	var scoop: SnowScoopComponent = script.new()
	scoop.set(&"depth", depth_m)
	scoop.inventory = inventory
	body.add_child(scoop)
	return scoop


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
