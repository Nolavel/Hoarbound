extends SceneTree

## Three individually heated eggs, independent plate ownership, pantry resources and legacy saves.
var _failures: int = 0

func _initialize() -> void:
	call_deferred(&"_run")

func _run() -> void:
	var stove := HeatSource.new()
	stove.starts_burning = false
	root.add_child(stove)
	var a := StoveWarmer.new()
	a.name = "Warmer"
	stove.add_child(a)
	var b := StoveWarmer.new()
	b.name = "Warmer2"
	b.save_key = &"stove_warmer_2"
	stove.add_child(b)
	var bag := InventoryComponent.new()
	root.add_child(bag)
	_check(bag.try_add_instance(ItemCatalog.get_item(&"frying_pan"), {"wear": 0.21}), "stateful pan not seeded")
	for id: StringName in [&"egg_raw", &"egg_raw", &"egg_raw", &"cooking_oil_portion", &"salt_pinch", &"pepper_pinch"]:
		_check(bag.try_add(ItemCatalog.get_item(id)), "missing cooking item " + String(id))
	_check(a.put_pan(bag), "pan not put on plate A")
	_check(not a.crack_egg(bag), "cold stove incorrectly allowed egg")
	stove.restore_fuel(0.8, true)
	_check(a.crack_egg(bag), "first egg failed")
	_check(a.add_oil(bag), "oil failed")
	_check(not a.add_oil(bag), "oil was added twice")
	_check(a.add_seasoning(bag, StoveWarmer.SALT_ID), "salt failed")
	_check(a.add_seasoning(bag, StoveWarmer.PEPPER_ID), "pepper failed")
	_check(not a.add_seasoning(bag, StoveWarmer.SALT_ID), "salt duplicated")
	stove.heat_elapsed.emit(0.05)
	_check(a.crack_egg(bag), "second egg failed")
	stove.heat_elapsed.emit(0.04)
	_check(a.get_egg_quality(0) == &"ready" and a.get_egg_quality(1) == &"cooking",
		"egg heating was shared instead of per portion")
	_check(a.crack_egg(bag), "third egg failed")
	_check(a.get_egg_count() == 3 and not a.crack_egg(bag), "capacity was not three")
	_check(not a.take_pan(bag), "pan with food can be removed")
	_check(b.get_egg_count() == 0 and not b.has_pan(), "plate B inherited A")
	var recipe: Dictionary = a.get_recipe_data()
	_check(bool(recipe.get("oil")) and bool(recipe.get("salt")) and bool(recipe.get("pepper")),
		"seasonings not retained")
	_check(not bag.has_item(&"egg_raw") and not bag.has_item(&"cooking_oil_portion"),
		"ingredients duplicated in inventory")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(a.get_save_data()))
	_check(saved.has("pan_recipe") and saved["pan_recipe"]["eggs"].size() == 3, "three-egg save was not written")
	a.load_save_data(saved)
	_check(a.get_egg_count() == 3, "three eggs lost during save/load")
	stove.heat_elapsed.emit(0.07)
	_check(a.get_egg_quality(0) == &"well" and a.get_egg_quality(1) == &"ready" and a.get_egg_quality(2) == &"cooking",
		"well/ready/cooking not independently tracked")
	var at_pause: float = float(a.get_recipe_data()["eggs"][0]["heat_h"])
	stove.extinguish()
	stove.advance_fuel(0.1)
	_check(is_equal_approx(float(a.get_recipe_data()["eggs"][0]["heat_h"]), at_pause),
		"eggs continued cooking after fire-out")
	stove.restore_fuel(0.8, true)
	stove.heat_elapsed.emit(0.04)
	_check(a.get_egg_quality(0) == &"burnt" and a.get_egg_quality(1) == &"well" and a.get_egg_quality(2) == &"ready",
		"burn/well/ready states not distinct")
	_check(a.take_fried_egg(bag), "could not retrieve burnt egg")
	_check(a.take_fried_egg(bag), "could not retrieve well egg")
	_check(a.take_fried_egg(bag), "could not retrieve normally fried egg")
	_check(bag.has_item(&"egg_fried_burnt") and bag.has_item(&"egg_fried_well") and bag.has_item(&"egg_fried"),
		"distinct output quality item ids were not catalogued/transferred")
	_check(a.get_egg_count() == 0, "food stayed on pan after pickup")
	## Re-adding an egg after removing the first must claim its vacated position.
	var layout := PanCookingModel.new()
	_check(layout.add_egg() and layout.add_egg() and layout.add_egg(), "cannot lay out three yolks")
	var old_spot: Dictionary = layout.eggs[0]
	layout.eggs.remove_at(0)
	_check(layout.add_egg(), "cannot refill after removing one egg")
	var added: Dictionary = layout.eggs[2]
	_check(is_equal_approx(float(old_spot["x"]), float(added["x"])) and is_equal_approx(float(old_spot["z"]), float(added["z"])),
		"new egg overlaps an occupied yolk")
	_check(a.take_pan(bag), "empty pan cannot be retrieved")
	_check(is_equal_approx(float(bag.get_first_instance_state(&"frying_pan").get("wear", -1.0)), 0.21),
		"pan's instance state was lost")
	a.load_save_data({"pan_installed": true, "egg_state": 2, "egg_progress_h": 0.08, "egg_intro_seconds": 3.0})
	_check(a.get_egg_count() == 1 and a.get_egg_quality(0) == &"ready",
		"legacy save migration lost single fried egg")
	var mode := CooktopInteractionController.new()
	stove.add_child(mode)
	mode.select_plate(0)
	mode._preview_inventory = bag
	_check(mode.get_actions().size() > 0, "context menu has no actions")
	print("PAN_RITUAL_PASS" if _failures == 0 else "PAN_RITUAL_FAIL %d" % _failures)
	quit(0 if _failures == 0 else 1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("pan cooking ritual: " + message)
