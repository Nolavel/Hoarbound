class_name CapabilityContract
extends RefCounted

## Language-neutral capability bindings live on the owner Object itself.
## Reflection and dynamic calls stay inside this boundary, not gameplay code.

const META_KEY: StringName = &"_hb_capabilities_v1"
const PROVIDER_KEY: StringName = &"provider"
const OPERATIONS_KEY: StringName = &"operations"


static func publish(
	owner: Object,
	capability: StringName,
	provider: Object,
	operations: Dictionary
) -> bool:
	if owner == null or not is_instance_valid(owner):
		push_error("CapabilityContract: owner is invalid")
		return false
	if capability == &"":
		push_error("CapabilityContract: capability id is empty")
		return false
	if provider == null or not is_instance_valid(provider):
		push_error("CapabilityContract: provider for '%s' is invalid" % capability)
		return false
	if operations.is_empty():
		push_error("CapabilityContract: '%s' has no operations" % capability)
		return false

	var normalized: Dictionary = {}
	for raw_operation: Variant in operations.keys():
		var operation: StringName = StringName(str(raw_operation))
		var method: StringName = StringName(str(operations[raw_operation]))
		if operation == &"" or method == &"":
			push_error("CapabilityContract: '%s' contains an empty operation" % capability)
			return false
		## This is the single reflection boundary used to fail wiring early.
		if not provider.has_method(method):
			push_error(
				"CapabilityContract: '%s' provider lacks method '%s'"
				% [capability, method]
			)
			return false
		normalized[operation] = method

	var contracts: Dictionary = _read(owner).duplicate()
	contracts[capability] = {
		PROVIDER_KEY: provider,
		OPERATIONS_KEY: normalized,
	}
	owner.set_meta(META_KEY, contracts)
	return true


static func publish_self(owner: Object, capability: StringName, operations: Dictionary) -> bool:
	return publish(owner, capability, owner, operations)


static func has(owner: Object, capability: StringName) -> bool:
	var descriptor: Dictionary = _descriptor(owner, capability)
	if descriptor.is_empty():
		return false
	var provider: Variant = descriptor.get(PROVIDER_KEY)
	return typeof(provider) == TYPE_OBJECT and is_instance_valid(provider)


static func invoke(
	owner: Object,
	capability: StringName,
	operation: StringName,
	arguments: Array = []
) -> Variant:
	var descriptor: Dictionary = _descriptor(owner, capability)
	if descriptor.is_empty():
		push_error("CapabilityContract: '%s' is not published" % capability)
		return null

	var provider_value: Variant = descriptor.get(PROVIDER_KEY)
	if typeof(provider_value) != TYPE_OBJECT or not is_instance_valid(provider_value):
		push_error("CapabilityContract: '%s' provider is no longer valid" % capability)
		return null
	var provider: Object = provider_value

	var operations_value: Variant = descriptor.get(OPERATIONS_KEY, {})
	if typeof(operations_value) != TYPE_DICTIONARY:
		push_error("CapabilityContract: '%s' operation map is invalid" % capability)
		return null
	var operations: Dictionary = operations_value
	if not operations.has(operation):
		push_error("CapabilityContract: '%s' has no operation '%s'" % [capability, operation])
		return null

	var method: StringName = StringName(str(operations[operation]))
	return provider.callv(method, arguments)


static func unpublish(owner: Object, capability: StringName) -> void:
	if owner == null or not is_instance_valid(owner):
		return
	var contracts: Dictionary = _read(owner).duplicate()
	if not contracts.erase(capability):
		return
	if contracts.is_empty():
		owner.remove_meta(META_KEY)
		return
	owner.set_meta(META_KEY, contracts)


static func _descriptor(owner: Object, capability: StringName) -> Dictionary:
	var contracts: Dictionary = _read(owner)
	if not contracts.has(capability):
		return {}
	var value: Variant = contracts[capability]
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var descriptor: Dictionary = value
	return descriptor


static func _read(owner: Object) -> Dictionary:
	if owner == null or not is_instance_valid(owner) or not owner.has_meta(META_KEY):
		return {}
	var value: Variant = owner.get_meta(META_KEY)
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var contracts: Dictionary = value
	return contracts
