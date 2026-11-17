class_name SimulationParticipantCapability
extends RefCounted

## Something the simulation clock advances (weather, afflictions, snow, a held light...): advance(hours, context)
## and priority() (lower runs first). Providers may be GDScript, C# or C++; the legacy
## advance_simulation/get_simulation_priority names are adapted here, the only place that asks by name.

const ID: StringName = &"simulation_participant"
const ADVANCE: StringName = &"advance"
const PRIORITY: StringName = &"priority"
## A participant with no priority of its own runs after every one that has one.
const DEFAULT_PRIORITY: int = 1000
const LEGACY_ADVANCE: StringName = &"advance_simulation"
const LEGACY_PRIORITY: StringName = &"get_simulation_priority"


## Publishes `owner`'s own methods: advance(hours: float, context: SimulationStepContext) and, optionally,
## priority() -> int (&"" for DEFAULT_PRIORITY).
static func publish(owner: Object, advance_method: StringName, priority_method: StringName = &"") -> bool:
	var operations: Dictionary = {ADVANCE: advance_method}
	if priority_method != &"":
		operations[PRIORITY] = priority_method
	return CapabilityContract.publish_self(owner, ID, operations)


## Whether `owner` is a participant, adapting the legacy method names once.
static func ensure(owner: Object) -> bool:
	if CapabilityContract.has(owner, ID):
		return true
	if owner == null or not is_instance_valid(owner) or not owner.has_method(LEGACY_ADVANCE):
		return false
	return publish(owner, LEGACY_ADVANCE, LEGACY_PRIORITY if owner.has_method(LEGACY_PRIORITY) else &"")


static func priority(owner: Object) -> int:
	if not ensure(owner) or not CapabilityContract.has_operation(owner, ID, PRIORITY):
		return DEFAULT_PRIORITY
	return int(CapabilityContract.invoke(owner, ID, PRIORITY))


static func advance(owner: Object, hours: float, context: SimulationStepContext) -> void:
	if ensure(owner):
		CapabilityContract.invoke(owner, ID, ADVANCE, [hours, context])
