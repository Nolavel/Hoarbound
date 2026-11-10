class_name ItemUserCapability
extends RefCounted

## Something Henry uses an item with (the bedroll laid, a tin opened, a flare lit, the hammer drawn, snow scooped):
## can_use(item_id) -> bool and use(item_id) -> bool. The Hub hands an item to the first that can use it. The
## legacy can_use/use names are adapted here, the only place that asks by name.

const ID: StringName = &"item_user"
const CAN_USE: StringName = &"can_use"
const USE: StringName = &"use"


static func publish(owner: Object, can_use_method: StringName, use_method: StringName) -> bool:
	return CapabilityContract.publish_self(owner, ID, {CAN_USE: can_use_method, USE: use_method})


## Whether `owner` uses items, adapting the legacy names once.
static func ensure(owner: Object) -> bool:
	if CapabilityContract.has(owner, ID):
		return true
	if owner == null or not is_instance_valid(owner) or not owner.has_method(CAN_USE) or not owner.has_method(USE):
		return false
	return publish(owner, CAN_USE, USE)


static func can_use(owner: Object, item_id: StringName) -> bool:
	return ensure(owner) and bool(CapabilityContract.invoke(owner, ID, CAN_USE, [item_id]))


static func use(owner: Object, item_id: StringName) -> bool:
	return ensure(owner) and bool(CapabilityContract.invoke(owner, ID, USE, [item_id]))
