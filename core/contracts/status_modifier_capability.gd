class_name StatusModifierCapability
extends RefCounted

## Named status multipliers an actor publishes (afflictions today): movement, sprint, work and
## fine-motor timing read them here without knowing which system sets them. 1.0 when unpublished.

const ID: StringName = &"status_modifier"
const MULTIPLIER: StringName = &"multiplier"


static func publish(owner: Object, provider: Object, multiplier_method: StringName) -> bool:
	return CapabilityContract.publish(owner, ID, provider, {MULTIPLIER: multiplier_method})


## The actor's multiplier for one stat, 1.0 when nothing is published.
static func multiplier(actor: Object, stat_id: StringName) -> float:
	if actor == null or not is_instance_valid(actor) or not CapabilityContract.has(actor, ID):
		return 1.0
	return maxf(float(CapabilityContract.invoke(actor, ID, MULTIPLIER, [stat_id])), 0.0)
