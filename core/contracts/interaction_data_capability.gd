class_name InteractionDataCapability
extends RefCounted

## A scene an InteractiveArea loads that names itself: data() -> Dictionary (name, description, highlight_color,
## circle_radius; any may be left out). The legacy get_interaction_data name is adapted here only.

const ID: StringName = &"interaction_data"
const DATA: StringName = &"data"
const LEGACY_DATA: StringName = &"get_interaction_data"


static func publish(owner: Object, data_method: StringName) -> bool:
	return CapabilityContract.publish_self(owner, ID, {DATA: data_method})


static func ensure(owner: Object) -> bool:
	if CapabilityContract.has(owner, ID):
		return true
	if owner == null or not is_instance_valid(owner) or not owner.has_method(LEGACY_DATA):
		return false
	return publish(owner, LEGACY_DATA)


## What `owner` says about itself, empty when it says nothing.
static func data(owner: Object) -> Dictionary:
	if not ensure(owner):
		return {}
	var value: Variant = CapabilityContract.invoke(owner, ID, DATA)
	return value if value is Dictionary else {}
