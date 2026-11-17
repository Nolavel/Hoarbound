class_name GroundSourceCapability
extends RefCounted

## The ground snow lies on: height(x, z) and, optionally, obstacles_in_rect(bounds) -> Array[PackedVector2Array]
## (footprints snow never covers). Legacy get_height/get_snow_obstacles_in_rect names are adapted here only.

const ID: StringName = &"ground_source"
const HEIGHT: StringName = &"height"
const OBSTACLES: StringName = &"obstacles_in_rect"
const LEGACY_HEIGHT: StringName = &"get_height"
const LEGACY_OBSTACLES: StringName = &"get_snow_obstacles_in_rect"


## Publishes `owner`'s own methods; `obstacles_method` may be &"" (no obstacles of its own).
static func publish(owner: Object, height_method: StringName, obstacles_method: StringName = &"") -> bool:
	var operations: Dictionary = {HEIGHT: height_method}
	if obstacles_method != &"":
		operations[OBSTACLES] = obstacles_method
	return CapabilityContract.publish_self(owner, ID, operations)


## Whether `owner` is a ground, adapting the legacy names once.
static func ensure(owner: Object) -> bool:
	if CapabilityContract.has(owner, ID):
		return true
	if owner == null or not is_instance_valid(owner) or not owner.has_method(LEGACY_HEIGHT):
		return false
	return publish(owner, LEGACY_HEIGHT, LEGACY_OBSTACLES if owner.has_method(LEGACY_OBSTACLES) else &"")


## The height sampler, bound once for a loop over many vertices; empty when `owner` is no ground.
static func height_sampler(owner: Object) -> Callable:
	return CapabilityContract.bind(owner, ID, HEIGHT) if ensure(owner) else Callable()


static func offers_obstacles(owner: Object) -> bool:
	return ensure(owner) and CapabilityContract.has_operation(owner, ID, OBSTACLES)


## Obstacle outlines inside `bounds`, empty when the ground has none.
static func obstacles_in_rect(owner: Object, bounds: Rect2) -> Array:
	if not offers_obstacles(owner):
		return []
	return CapabilityContract.invoke(owner, ID, OBSTACLES, [bounds])
