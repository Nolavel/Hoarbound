class_name ThrowImpactCapability
extends RefCounted

## Something a thrown item can strike (a window pane, a wall that keeps snow). The item calls
## it once at first contact; the target decides what the hit does. Unpublished targets ignore it.

const ID: StringName = &"throw_impact"
const HIT: StringName = &"hit"


static func publish(owner: Object, provider: Object, hit_method: StringName) -> bool:
	return CapabilityContract.publish(owner, ID, provider, {HIT: hit_method})


## Delivers a hit: item_id, world point and normal, and the impulse in N*s. True if it was used.
static func hit(target: Object, item_id: StringName, point: Vector3, normal: Vector3, impulse: float) -> bool:
	if target == null or not is_instance_valid(target) or not CapabilityContract.has(target, ID):
		return false
	return CapabilityContract.invoke(target, ID, HIT, [item_id, point, normal, impulse]) == true
