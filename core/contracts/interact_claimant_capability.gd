class_name InteractClaimantCapability
extends RefCounted

## Something that owns the interact key while claimed: claimed() on key down, and optionally held(duration) and
## released(duration). Legacy on_interact_* names are adapted here, the only place that asks by name.

const ID: StringName = &"interact_claimant"
const CLAIMED: StringName = &"claimed"
const HELD: StringName = &"held"
const RELEASED: StringName = &"released"
const LEGACY: Dictionary = {
	CLAIMED: &"on_interact_claimed",
	HELD: &"on_interact_held",
	RELEASED: &"on_interact_released",
}


## Publishes `owner`'s own methods; `held_method` and `released_method` may be &"".
static func publish(owner: Object, claimed_method: StringName, held_method: StringName = &"",
		released_method: StringName = &"") -> bool:
	var operations: Dictionary = {CLAIMED: claimed_method}
	if held_method != &"":
		operations[HELD] = held_method
	if released_method != &"":
		operations[RELEASED] = released_method
	return CapabilityContract.publish_self(owner, ID, operations)


## Whether `owner` can take the key, adapting the legacy names once.
static func ensure(owner: Object) -> bool:
	if CapabilityContract.has(owner, ID):
		return true
	if owner == null or not is_instance_valid(owner) or not owner.has_method(LEGACY[CLAIMED]):
		return false
	return publish(owner, LEGACY[CLAIMED], LEGACY[HELD] if owner.has_method(LEGACY[HELD]) else &"",
		LEGACY[RELEASED] if owner.has_method(LEGACY[RELEASED]) else &"")


static func claimed(owner: Object) -> void:
	if ensure(owner):
		CapabilityContract.invoke(owner, ID, CLAIMED)


static func held(owner: Object, duration: float) -> void:
	if ensure(owner) and CapabilityContract.has_operation(owner, ID, HELD):
		CapabilityContract.invoke(owner, ID, HELD, [duration])


static func released(owner: Object, duration: float) -> void:
	if ensure(owner) and CapabilityContract.has_operation(owner, ID, RELEASED):
		CapabilityContract.invoke(owner, ID, RELEASED, [duration])
