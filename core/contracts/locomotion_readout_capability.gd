class_name LocomotionReadoutCapability
extends RefCounted

## What a moving body tells its animation and camera (Henry, or a test body): every operation is optional and the
## reader keeps its own fallback. Legacy method names are adapted here, the only place that asks by name.

const ID: StringName = &"locomotion_readout"
## Operation -> the body's legacy method name.
const LEGACY: Dictionary = {
	&"speed_ratio": &"get_locomotion_speed_ratio",
	&"crouch_ratio": &"get_crouch_speed_ratio",
	&"crouching": &"is_crouching",
	&"view_ray": &"get_view_ray",
	&"view_direction": &"get_view_direction",
}


## Publishes `owner`'s own methods by operation (any subset of LEGACY's keys).
static func publish(owner: Object, operations: Dictionary) -> bool:
	return CapabilityContract.publish_self(owner, ID, operations)


## Whether `owner` reads out anything, adapting whichever legacy methods it has once.
static func ensure(owner: Object) -> bool:
	if CapabilityContract.has(owner, ID):
		return true
	if owner == null or not is_instance_valid(owner):
		return false
	var found: Dictionary = {}
	for operation: StringName in LEGACY:
		if owner.has_method(LEGACY[operation]):
			found[operation] = LEGACY[operation]
	return not found.is_empty() and publish(owner, found)


static func offers(owner: Object, operation: StringName) -> bool:
	return ensure(owner) and CapabilityContract.has_operation(owner, ID, operation)


## The body's answer to `operation`, or `fallback` when it does not offer it.
static func read(owner: Object, operation: StringName, fallback: Variant = null) -> Variant:
	if not offers(owner, operation):
		return fallback
	return CapabilityContract.invoke(owner, ID, operation)
