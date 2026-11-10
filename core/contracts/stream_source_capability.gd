class_name StreamSourceCapability
extends RefCounted

## Something that streams generated chunks: chunks() -> Array[{id, position, radius}], activate(id, container) ->
## Node3D, deactivate(id), and optionally ring0(container). Legacy *_stream_* names are adapted here only.

const ID: StringName = &"stream_source"
const CHUNKS: StringName = &"chunks"
const ACTIVATE: StringName = &"activate"
const DEACTIVATE: StringName = &"deactivate"
const RING0: StringName = &"ring0"
const LEGACY: Dictionary = {
	CHUNKS: &"get_stream_chunks",
	ACTIVATE: &"activate_stream_chunk",
	DEACTIVATE: &"deactivate_stream_chunk",
	RING0: &"build_stream_ring0",
}


## Publishes `owner`'s own methods; `ring0_method` may be &"" (no ring 0 of its own).
static func publish(owner: Object, chunks_method: StringName, activate_method: StringName,
		deactivate_method: StringName, ring0_method: StringName = &"") -> bool:
	var operations: Dictionary = {CHUNKS: chunks_method, ACTIVATE: activate_method, DEACTIVATE: deactivate_method}
	if ring0_method != &"":
		operations[RING0] = ring0_method
	return CapabilityContract.publish_self(owner, ID, operations)


## Whether `owner` is a whole source, adapting the legacy names once; one that cannot activate or deactivate
## what it lists is refused, so no chunk is registered that could never load or unload.
static func ensure(owner: Object) -> bool:
	if CapabilityContract.has(owner, ID):
		return true
	if owner == null or not is_instance_valid(owner):
		return false
	for operation: StringName in [CHUNKS, ACTIVATE, DEACTIVATE]:
		if not owner.has_method(LEGACY[operation]):
			return false
	return publish(owner, LEGACY[CHUNKS], LEGACY[ACTIVATE], LEGACY[DEACTIVATE],
		LEGACY[RING0] if owner.has_method(LEGACY[RING0]) else &"")


static func chunks(owner: Object) -> Variant:
	return CapabilityContract.invoke(owner, ID, CHUNKS) if ensure(owner) else null


static func activate(owner: Object, id: StringName, container: Node3D) -> Node3D:
	return CapabilityContract.invoke(owner, ID, ACTIVATE, [id, container]) as Node3D if ensure(owner) else null


static func deactivate(owner: Object, id: StringName) -> void:
	if ensure(owner):
		CapabilityContract.invoke(owner, ID, DEACTIVATE, [id])


static func build_ring0(owner: Object, container: Node3D) -> void:
	if ensure(owner) and CapabilityContract.has_operation(owner, ID, RING0):
		CapabilityContract.invoke(owner, ID, RING0, [container])
