extends SceneTree

## Stove-top cooking/melting uses the common TimeCostedAction path. The action
## advances world time; HeatSource heat_elapsed remains the recipe truth.
## Run: godot --headless --script tests/systems/test_stove_warmer.gd

class FireParticipant:
	extends Node

	func get_simulation_priority() -> int:
		return 300

	func advance_simulation(hours: float, _context: SimulationStepContext) -> void:
		HeatSource.advance_all_fuel(hours)


var _failures: int = 0
var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _run() -> void:
	var state: Node = root.get_node_or_null(^"PlayerState")
	if state != null:
		state.set_mode(state.Mode.ON_FOOT)

	var clock := SimulationClock.new()
	root.add_child(clock)
	clock.set_total_hours(12.0, &"test_seed")

	var fire_participant := FireParticipant.new()
	root.add_child(fire_participant)
	clock.register_participant(fire_participant)

	var actions := TimeCostedActionSystem.new()
	actions.simulation_clock = clock
	root.add_child(actions)

	var stove := HeatSource.new()
	stove.starts_burning = false
	root.add_child(stove)
	var warmer := StoveWarmer.new()
	stove.add_child(warmer)

	var body := CharacterBody3D.new()
	body.add_to_group(&"player")
	var inventory := InventoryComponent.new()
	body.add_child(inventory)
	var eater := ConsumptionController.new()
	eater.name = "ConsumptionController"
	eater.inventory = inventory
	eater.bio_monitor = BioMonitorManager.new()
	body.add_child(eater.bio_monitor)
	body.add_child(eater)
	root.add_child(body)

	_test_stew_action(clock, actions, stove, warmer, body, inventory)
	_test_melt_action(clock, actions, stove, warmer, body, inventory)
	_test_fire_out_resume(clock, actions, stove, warmer, body, inventory)
	_test_save_restore(warmer)

	print("test_stove_warmer: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _test_stew_action(
	clock: SimulationClock,
	actions: TimeCostedActionSystem,
	stove: HeatSource,
	warmer: StoveWarmer,
	body: Node,
	inventory: InventoryComponent
) -> void:
	inventory.try_add(ItemCatalog.get_item(&"tinned_stew"))
	stove.ignite()
	var before_time: float = clock.get_total_hours()
	var before_fuel: float = stove.get_remaining_hours()

	_check(warmer.can_interact_with(body), "burning stove does not offer carried stew")
	warmer.interact_with(body)
	_check(warmer.get_state() == StoveWarmer.State.WARMING, "stew did not enter warming state")
	_check(actions.is_active(), "stew warming did not start TimeCostedAction")
	_check(actions.get_active_action_id().begins_with("cook_food:"), "stew used wrong action id")
	var state: Node = root.get_node_or_null(^"PlayerState")
	if state != null:
		_check(state.mode == state.Mode.WORKING, "cooking did not enter WORKING mode")
	_check(not inventory.has_item(&"tinned_stew"), "stew stayed in inventory while cooking")

	actions._process(StoveWarmer.WARM_PRESENTATION_SECONDS)
	_check(not actions.is_active(), "cooking action did not finish")
	if state != null:
		_check(state.mode == state.Mode.ON_FOOT, "cooking did not restore PlayerState")
	_check(warmer.get_state() == StoveWarmer.State.READY and warmer.get_item_id() == &"tinned_stew_hot",
		"stew did not become hot through action-driven world time")
	_check(is_equal_approx(clock.get_total_hours() - before_time, StoveWarmer.WARM_HOURS),
		"cooking billed the wrong game time")
	_check(is_equal_approx(before_fuel - stove.get_remaining_hours(), StoveWarmer.WARM_HOURS),
		"cooking did not burn the matching amount of stove fuel")

	warmer.interact_with(body)
	_check(warmer.get_state() == StoveWarmer.State.EMPTY, "eating did not clear stove ring")
	_check(inventory.has_item(&"empty_tin"), "hot stew left no empty tin")


func _test_melt_action(
	clock: SimulationClock,
	actions: TimeCostedActionSystem,
	stove: HeatSource,
	warmer: StoveWarmer,
	body: Node,
	inventory: InventoryComponent
) -> void:
	inventory.try_add(ItemCatalog.get_item(&"mug_snow"))
	if not stove.is_burning():
		stove.ignite()
	var before: float = clock.get_total_hours()

	warmer.interact_with(body)
	_check(actions.is_active(), "mug of snow did not start TimeCostedAction")
	_check(actions.get_active_action_id().begins_with("melt_snow:"), "snow used wrong action id")
	actions._process(StoveWarmer.WARM_PRESENTATION_SECONDS)

	_check(warmer.get_state() == StoveWarmer.State.READY and warmer.get_item_id() == &"warm_water_mug",
		"snow did not become warm water")
	_check(is_equal_approx(clock.get_total_hours() - before, StoveWarmer.WARM_HOURS),
		"snow melt billed the wrong game time")

	warmer.interact_with(body)
	_check(inventory.has_item(&"mug"), "drinking warm water did not return empty mug")


func _test_fire_out_resume(
	clock: SimulationClock,
	actions: TimeCostedActionSystem,
	stove: HeatSource,
	warmer: StoveWarmer,
	body: Node,
	inventory: InventoryComponent
) -> void:
	inventory.try_add(ItemCatalog.get_item(&"tinned_stew"))
	stove.restore_fuel(0.1, true)
	var before: float = clock.get_total_hours()

	warmer.interact_with(body)
	_check(actions.is_active(), "partial-fuel cooking did not start")
	actions._process(StoveWarmer.WARM_PRESENTATION_SECONDS)

	_check(not actions.is_active(), "cooking kept running after fire went out")
	_check(not stove.is_burning(), "test fire did not go out")
	_check(warmer.get_state() == StoveWarmer.State.WARMING, "fire-out incorrectly completed recipe")
	_check(warmer.get_item_id() == &"tinned_stew", "fire-out transformed raw item")
	var saved: Dictionary = warmer.get_save_data()
	var partial: float = float(saved["progress"])
	_check(partial > 0.08 and partial < 0.12, "partial heat progress is not actual burned fuel time")
	_check(clock.get_total_hours() - before < StoveWarmer.WARM_HOURS,
		"fire-out action billed the full recipe duration")

	stove.restore_fuel(1.0, true)
	_check(warmer.can_interact_with(body), "partially warmed item cannot resume after relight")
	warmer.interact_with(body)
	_check(actions.is_active(), "resume did not start a new action")
	var remaining_ratio: float = (StoveWarmer.WARM_HOURS - partial) / StoveWarmer.WARM_HOURS
	actions._process(StoveWarmer.WARM_PRESENTATION_SECONDS * remaining_ratio + 0.01)
	_check(warmer.get_state() == StoveWarmer.State.READY, "resumed cooking did not finish")


func _test_save_restore(warmer: StoveWarmer) -> void:
	warmer.load_save_data({"state": 1, "item": "snow_handful", "progress": 0.1})
	_check(warmer.get_state() == StoveWarmer.State.WARMING and warmer.get_item_id() == &"snow_handful",
		"saved warming ring did not restore")
	_check(is_equal_approx(float(warmer.get_save_data()["progress"]), 0.1), "warming progress did not restore")


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("stove warmer: " + message)
