class_name InteractHostCapability
extends RefCounted

## The body InteractComponent works for (Henry, or a test walker): every operation is optional and has a stand-in
## when the host lacks it. Legacy method names on the host are adapted here, the only place that asks by name.

const ID: StringName = &"interact_host"
## Operation -> the host's legacy method name.
const LEGACY: Dictionary = {
	&"animate": &"play_action_animation",
	&"attention_origin": &"get_attention_origin",
	&"attention_direction": &"get_attention_direction",
	&"face": &"face_work_target",
	&"walk_to": &"move_to_position",
	&"stop": &"stop_moving",
	&"action_locked": &"is_action_locking",
}


## Publishes `owner`'s own methods by operation (any subset of LEGACY's keys).
static func publish(owner: Object, operations: Dictionary) -> bool:
	return CapabilityContract.publish_self(owner, ID, operations)


## Whether `owner` hosts anything, adapting whichever legacy methods it has once.
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


## Whether the host offers `operation`.
static func offers(owner: Object, operation: StringName) -> bool:
	return ensure(owner) and CapabilityContract.has_operation(owner, ID, operation)


## Runs `operation` with `arguments` when the host offers it: [true, result], else [false, null].
static func run(owner: Object, operation: StringName, arguments: Array = []) -> Array:
	if not offers(owner, operation):
		return [false, null]
	return [true, CapabilityContract.invoke(owner, ID, operation, arguments)]
