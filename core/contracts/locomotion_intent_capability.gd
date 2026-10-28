class_name LocomotionIntentCapability
extends RefCounted

## Where an actor means to go this tick, world space, length = input strength (0 when idle).
## The camera leads by intent, not only by velocity. Zero when unpublished.

const ID: StringName = &"locomotion_intent"
const INTENT: StringName = &"intent"


static func publish(owner: Object, provider: Object, intent_method: StringName) -> bool:
	return CapabilityContract.publish(owner, ID, provider, {INTENT: intent_method})


## The actor's movement intent this tick, Vector3.ZERO when nothing is published.
static func intent(actor: Object) -> Vector3:
	if actor == null or not is_instance_valid(actor) or not CapabilityContract.has(actor, ID):
		return Vector3.ZERO
	var value: Variant = CapabilityContract.invoke(actor, ID, INTENT)
	return value if typeof(value) == TYPE_VECTOR3 else Vector3.ZERO
