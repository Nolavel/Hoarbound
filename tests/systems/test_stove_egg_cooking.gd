extends SceneTree

## Physical pan/egg ownership, per-ring independence and heat authority.
var _failed: int = 0

func _initialize() -> void:
	call_deferred(&"_run")

func _run() -> void:
	var stove := HeatSource.new()
	stove.starts_burning = false
	root.add_child(stove)
	var first := StoveWarmer.new()
	first.name = "Warmer"
	stove.add_child(first)
	var second := StoveWarmer.new()
	second.name = "Warmer2"
	second.save_key = &"stove_warmer_2"
	stove.add_child(second)
	var inventory := InventoryComponent.new()
	root.add_child(inventory)
	var raw: ItemResource = ItemCatalog.get_item(&"egg_raw")
	var pan: ItemResource = ItemCatalog.get_item(&"frying_pan")
	var cooked: ItemResource = ItemCatalog.get_item(&"egg_fried")
	_check(raw != null and cooked != null and pan != null, "catalog is missing pan/egg ids")
	if raw == null or cooked == null or pan == null:
		quit(1)
		return
	_check(inventory.try_add_instance(pan, {"wear": 0.37}), "cannot seed a stateful pan")
	_check(inventory.try_add(raw), "cannot seed the raw egg")
	_check(first.put_pan(inventory), "cannot install pan")
	_check(first.has_pan() and not inventory.has_item(&"frying_pan"), "pan duplicated on installation")
	_check(not first.put_pan(inventory), "same pan installed twice")
	_check(not first.crack_egg(inventory), "egg cracked on a cold stove")
	stove.restore_fuel(0.5, true)
	_check(first.crack_egg(inventory), "egg did not crack")
	_check(not inventory.has_item(&"egg_raw"), "raw egg retained after cracking")
	_check(not first.take_pan(inventory), "removed pan with unfinished food")
	stove.heat_elapsed.emit(StoveWarmer.EGG_COOK_HOURS * 0.4)
	var saved: Dictionary = first.get_save_data()
	_check(first.get_egg_state() == StoveWarmer.EggState.COOKING, "egg finished prematurely")
	_check(is_equal_approx(first.get_egg_progress_h(), StoveWarmer.EGG_COOK_HOURS * 0.4), "wrong heat progress")
	_check(second.get_egg_state() == StoveWarmer.EggState.NONE, "cooking leaked to second ring")
	first.load_save_data(saved)
	stove.extinguish()
	stove.advance_fuel(0.1)
	_check(is_equal_approx(first.get_egg_progress_h(), StoveWarmer.EGG_COOK_HOURS * 0.4), "food cooked without fire")
	_check(not first.take_fried_egg(inventory), "undercooked egg can be taken as ready")
	stove.restore_fuel(0.5, true)
	stove.heat_elapsed.emit(StoveWarmer.EGG_COOK_HOURS * 0.61)
	_check(first.get_egg_state() == StoveWarmer.EggState.READY, "egg never finished")
	_check(first.take_fried_egg(inventory), "ready egg not transferred to inventory")
	_check(inventory.has_item(&"egg_fried") and first.has_pan(), "ready egg or pan ownership wrong")
	_check(first.take_pan(inventory), "pan could not be retrieved")
	_check(not first.has_pan() and inventory.has_item(&"frying_pan"), "pan duplicated or lost")
	_check(is_equal_approx(float(inventory.get_first_instance_state(&"frying_pan").get("wear", -1.0)), 0.37),
		"pan instance state did not survive cooking")
	_check(first.get_save_key() != second.get_save_key(), "rings share a save key")
	var cook_mode := CooktopInteractionController.new()
	stove.add_child(cook_mode)
	cook_mode.select_plate(1)
	_check(cook_mode.get_selected_warmer() == second, "RMB cooktop selection did not resolve second ring")
	cook_mode.select_plate(0)
	_check(cook_mode.get_selected_warmer() == first, "cooktop selection did not return to first ring")
	var context := StoveInteractionRing.new()
	context.bind_cooktop(cook_mode)
	root.add_child(context)
	_check(context.describe(StoveInteractionRing.Arc.FUEL)["state"] == StoveInteractionRing.ArcState.INACTIVE,
		"empty cooktop incorrectly shows a pan")
	context.queue_free()
	print("test_stove_egg_cooking: %s" % ("all checks passed" if _failed == 0 else "%d FAILED" % _failed))
	quit(1 if _failed > 0 else 0)

func _check(ok: bool, reason: String) -> void:
	if ok:
		return
	_failed += 1
	push_error("stove egg: " + reason)
