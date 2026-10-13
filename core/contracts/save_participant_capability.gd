class_name SaveParticipantCapability
extends RefCounted

## Cross-language save capability. Providers may be GDScript, C#, or C++.
## Legacy method discovery is contained here during migration.

const ID: StringName = &"save_participant"
const KEY: StringName = &"key"
const CAPTURE: StringName = &"capture"
const RESTORE: StringName = &"restore"

const LEGACY_METHODS: Dictionary = {
	KEY: &"get_save_key",
	CAPTURE: &"get_save_data",
	RESTORE: &"load_save_data",
}


static func publish(
	owner: Object,
	provider: Object,
	key_method: StringName,
	capture_method: StringName,
	restore_method: StringName
) -> bool:
	return CapabilityContract.publish(owner, ID, provider, {
		KEY: key_method,
		CAPTURE: capture_method,
		RESTORE: restore_method,
	})


static func ensure(owner: Object) -> bool:
	if CapabilityContract.has(owner, ID):
		return true
	if not _can_adapt_legacy(owner):
		return false
	return CapabilityContract.publish_self(owner, ID, LEGACY_METHODS)


static func get_key(owner: Object) -> StringName:
	if not ensure(owner):
		return &""
	var value: Variant = CapabilityContract.invoke(owner, ID, KEY)
	if typeof(value) == TYPE_STRING_NAME:
		return value
	if typeof(value) == TYPE_STRING:
		return StringName(value)
	return &""


static func capture(owner: Object) -> Variant:
	if not ensure(owner):
		return null
	return CapabilityContract.invoke(owner, ID, CAPTURE)


static func restore(owner: Object, data: Dictionary) -> void:
	if not ensure(owner):
		return
	CapabilityContract.invoke(owner, ID, RESTORE, [data])


static func _can_adapt_legacy(owner: Object) -> bool:
	return (
		owner != null
		and is_instance_valid(owner)
		and owner.has_method(LEGACY_METHODS[KEY])
		and owner.has_method(LEGACY_METHODS[CAPTURE])
		and owner.has_method(LEGACY_METHODS[RESTORE])
	)
