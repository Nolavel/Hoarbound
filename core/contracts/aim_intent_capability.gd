class_name AimIntentCapability
extends RefCounted

## How far an actor is drawn into an aim (a throw held back), 0..1. The camera closes in over
## the shoulder by it. Zero when unpublished.

const ID: StringName = &"aim_intent"
const WEIGHT: StringName = &"weight"


static func publish(owner: Object, provider: Object, weight_method: StringName) -> bool:
	return CapabilityContract.publish(owner, ID, provider, {WEIGHT: weight_method})


## The actor's aim weight now, 0 when nothing is published.
static func weight(actor: Object) -> float:
	if actor == null or not is_instance_valid(actor) or not CapabilityContract.has(actor, ID):
		return 0.0
	var value: Variant = CapabilityContract.invoke(actor, ID, WEIGHT)
	return float(value) if typeof(value) in [TYPE_FLOAT, TYPE_INT] else 0.0
