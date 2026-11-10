extends SceneTree

## The capability contract, success and refusal (ARCHITECTURE §16, rule 4):
## - a save participant exposes its own method names through the shared capability layer without a Port node;
## - legacy get_save_key/get_save_data/load_save_data providers are adapted at the boundary;
## - a refused publish (missing method, empty id or map, no provider) publishes nothing and keeps what was there;
## - a freed provider or an unpublished capability answers nothing instead of crashing;
## - a participant that does not return a Dictionary refuses the whole save, and the slot keeps its last good save;
## - a slot without a participant's key leaves that participant untouched on load;
## - a simulation participant: legacy names adapted, a missing priority defaults, own names mapped, a
##   non-participant refused, and the clock advances them in priority order.
## Expected refusals print errors; the verdict is the last line.

const TEST_SLOT: int = 5

var _failures: int = 0


class MappedSaveParticipant:
	extends Node

	var value: int = 0
	var broken: bool = false

	func stable_id() -> StringName:
		return &"mapped_capability"

	func snapshot() -> Variant:
		return "not a dictionary" if broken else {"value": value}

	func restore_snapshot(data: Dictionary) -> void:
		value = int(data.get("value", 0))


class LegacySaveParticipant:
	extends Node

	var value: int = 0

	func get_save_key() -> StringName:
		return &"legacy_capability"

	func get_save_data() -> Dictionary:
		return {"value": value}

	func load_save_data(data: Dictionary) -> void:
		value = int(data.get("value", 0))


class PartialSaveParticipant:
	extends Node

	func get_save_key() -> StringName:
		return &"partial_capability"

	func get_save_data() -> Dictionary:
		return {}


func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	var manager := SaveManager.new()
	root.add_child(manager)
	manager.delete_slot(TEST_SLOT)

	var participant := MappedSaveParticipant.new()
	root.add_child(participant)
	_check(
		SaveParticipantCapability.publish(participant, participant, &"stable_id", &"snapshot", &"restore_snapshot"),
		"explicit save capability mapping failed"
	)
	_check(CapabilityContract.has(participant, SaveParticipantCapability.ID), "published capability is not visible on the owner")
	var legacy := LegacySaveParticipant.new()
	root.add_child(legacy)
	_check(SaveParticipantCapability.ensure(legacy), "a legacy provider was not adapted at the boundary")

	manager.register(participant)
	manager.register(legacy)
	participant.value = 42
	legacy.value = 7
	_check(manager.save_to_slot(TEST_SLOT), "save through capability failed")
	participant.value = 1
	legacy.value = 1
	_check(manager.load_from_slot(TEST_SLOT), "load through capability failed")
	_check(participant.value == 42, "mapped provider did not restore its state")
	_check(legacy.value == 7, "legacy provider did not restore its state")

	_refused_publish(participant)
	_dead_provider()
	_refused_save(manager, participant)
	_absent_key(manager, participant)
	_partial_legacy(manager)
	_simulation_participants()

	manager.delete_slot(TEST_SLOT)
	_dispose(legacy)
	_dispose(participant)
	_dispose(manager)
	if _failures > 0:
		push_error("capability contract: %d check(s) failed" % _failures)
		quit(1)
		return
	print("capability contract: all checks passed")
	quit(0)


## A publish that is refused publishes nothing and leaves an earlier publication as it was.
func _refused_publish(participant: MappedSaveParticipant) -> void:
	var probe := &"probe_capability"
	_check(not CapabilityContract.publish(participant, probe, participant, {&"do": &"no_such_method"}),
		"a provider lacking its method was published")
	_check(not CapabilityContract.has(participant, probe), "a refused publish left a capability behind")
	_check(not CapabilityContract.publish(participant, &"", participant, {&"do": &"snapshot"}), "an empty id was published")
	_check(not CapabilityContract.publish(participant, probe, participant, {}), "an empty operation map was published")
	_check(not CapabilityContract.publish(participant, probe, null, {&"do": &"snapshot"}), "a missing provider was published")
	_check(not SaveParticipantCapability.publish(participant, participant, &"stable_id", &"missing", &"restore_snapshot"),
		"a save capability with a missing method was published")
	_check(SaveParticipantCapability.get_key(participant) == &"mapped_capability",
		"a refused republish replaced the working capability")
	CapabilityContract.publish_self(participant, probe, {&"do": &"snapshot"})
	CapabilityContract.unpublish(participant, probe)
	_check(not CapabilityContract.has(participant, probe), "unpublish left the capability")
	_check(CapabilityContract.has(participant, SaveParticipantCapability.ID), "unpublish removed another capability too")


## A freed provider or an unpublished capability answers nothing; nothing crashes.
func _dead_provider() -> void:
	var owner := Node.new()
	var provider := MappedSaveParticipant.new()
	_check(SaveParticipantCapability.publish(owner, provider, &"stable_id", &"snapshot", &"restore_snapshot"),
		"publish with a separate provider failed")
	provider.free()
	_check(not CapabilityContract.has(owner, SaveParticipantCapability.ID), "a freed provider still counts as published")
	_check(CapabilityContract.invoke(owner, SaveParticipantCapability.ID, SaveParticipantCapability.CAPTURE) == null,
		"a freed provider still answered")
	_check(CapabilityContract.invoke(owner, &"never_published", &"do") == null, "an unpublished capability answered")
	owner.free()


## A participant returning something other than a Dictionary refuses the save; the last good save stays.
func _refused_save(manager: SaveManager, participant: MappedSaveParticipant) -> void:
	participant.broken = true
	participant.value = 99
	_check(not manager.save_to_slot(TEST_SLOT), "a save with a non-Dictionary capture was accepted")
	participant.broken = false
	participant.value = 3
	_check(manager.load_from_slot(TEST_SLOT), "the last good save was lost after a refused save")
	_check(participant.value == 42, "the refused save overwrote the last good one (value %d)" % participant.value)


## A slot that has no entry for a participant leaves that participant as it is.
func _absent_key(manager: SaveManager, participant: MappedSaveParticipant) -> void:
	var keyed := _KeyedParticipant.new()
	root.add_child(keyed)
	keyed.value = 11
	manager.register(keyed)
	_check(manager.load_from_slot(TEST_SLOT), "load failed with a participant the slot does not know")
	_check(keyed.value == 11, "a participant missing from the slot was changed on load (value %d)" % keyed.value)
	_check(participant.value == 42, "the known participant was not restored next to an unknown one")
	manager.unregister(keyed)
	_dispose(keyed)


## A legacy provider missing one of its three methods is refused, not half adapted.
func _partial_legacy(manager: SaveManager) -> void:
	var partial := PartialSaveParticipant.new()
	root.add_child(partial)
	_check(not SaveParticipantCapability.ensure(partial), "a provider with two of three methods was adapted")
	_check(not CapabilityContract.has(partial, SaveParticipantCapability.ID), "a refused adaptation left a capability")
	manager.register(partial)
	_check(manager.save_to_slot(TEST_SLOT), "an unadapted provider broke the save of the others")
	_dispose(partial)


func _simulation_participants() -> void:
	var legacy := _LegacyTicker.new()
	var plain := _PlainTicker.new()
	var mapped := _MappedTicker.new()
	var stranger := Node.new()
	_check(SimulationParticipantCapability.ensure(legacy), "a legacy simulation participant was not adapted")
	_check(SimulationParticipantCapability.priority(legacy) == 5, "a legacy participant's own priority was lost")
	_check(SimulationParticipantCapability.ensure(plain), "a participant with no priority method was refused")
	_check(SimulationParticipantCapability.priority(plain) == SimulationParticipantCapability.DEFAULT_PRIORITY,
		"a participant with no priority did not get the default")
	_check(SimulationParticipantCapability.publish(mapped, &"tick", &"rank"), "own simulation method names were refused")
	_check(not SimulationParticipantCapability.publish(mapped, &"no_such_tick"), "a missing advance method was published")
	_check(not SimulationParticipantCapability.ensure(stranger), "a node with no advance became a participant")
	var clock := SimulationClock.new()
	root.add_child(clock)
	var order: Array[String] = []
	for ticker: Node in [plain, legacy, mapped]:
		ticker.set_meta(&"log", order)
		clock.register_participant(ticker)
	clock.register_participant(stranger)
	_check(clock.get_participant_count() == 3, "the clock took %d participants, not 3" % clock.get_participant_count())
	clock.advance_hours(0.1, &"test")
	_check(order == ["mapped", "legacy", "plain"], "the clock advanced in order %s, not by priority" % [order])
	for node: Node in [clock, legacy, plain, mapped, stranger]:
		node.free()


class _LegacyTicker:
	extends Node

	func get_simulation_priority() -> int:
		return 5

	func advance_simulation(_hours: float, _context: SimulationStepContext) -> void:
		(get_meta(&"log") as Array).append("legacy")


class _PlainTicker:
	extends Node

	func advance_simulation(_hours: float, _context: SimulationStepContext) -> void:
		(get_meta(&"log") as Array).append("plain")


class _MappedTicker:
	extends Node

	func rank() -> int:
		return 1

	func tick(_hours: float, _context: SimulationStepContext) -> void:
		(get_meta(&"log") as Array).append("mapped")


class _KeyedParticipant:
	extends Node

	var value: int = 0

	func get_save_key() -> StringName:
		return &"absent_from_slot"

	func get_save_data() -> Dictionary:
		return {"value": value}

	func load_save_data(data: Dictionary) -> void:
		value = int(data.get("value", 0))


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("capability contract: %s" % message)


func _dispose(node: Node) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()
