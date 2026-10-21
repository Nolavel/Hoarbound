class_name BootLoadCapability
extends RefCounted

## Cross-language boot work capability: a provider reports start-up work still pending, and the
## startup card holds the world hidden until none is. Providers join GROUP and publish PENDING.

const ID: StringName = &"boot_load"
const GROUP: StringName = &"boot_load"
const PENDING: StringName = &"pending"


static func publish(owner: Node, provider: Object, pending_method: StringName) -> bool:
	if not CapabilityContract.publish(owner, ID, provider, {PENDING: pending_method}):
		return false
	owner.add_to_group(GROUP)
	return true


## True while any published provider in the tree still has start-up work.
static func any_pending(tree: SceneTree) -> bool:
	return not pending_names(tree).is_empty()


## Names of the providers still at work (boot log).
static func pending_names(tree: SceneTree) -> PackedStringArray:
	var names: PackedStringArray = []
	for node: Node in tree.get_nodes_in_group(GROUP):
		if CapabilityContract.has(node, ID) and bool(CapabilityContract.invoke(node, ID, PENDING)):
			names.append(String(node.name))
	return names
