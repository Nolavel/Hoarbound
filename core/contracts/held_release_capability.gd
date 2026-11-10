class_name HeldReleaseCapability
extends RefCounted

## Something shown in Henry's hand (a held item, the hammer, a flare) letting it go back to its storage.
## can_release is the holder's own guard: a release after it answered true cannot fail (ARCHITECTURE §16, rule 3).

const ID: StringName = &"held_release"
const HOLDS: StringName = &"holds"
const CAN_RELEASE: StringName = &"can_release"
const RELEASE: StringName = &"release"


## Publishes `owner`'s own methods for the three operations: holds() -> bool, can_release() -> bool,
## release() -> bool.
static func publish(owner: Object, holds_method: StringName, can_release_method: StringName,
		release_method: StringName) -> bool:
	return CapabilityContract.publish_self(owner, ID, {
		HOLDS: holds_method,
		CAN_RELEASE: can_release_method,
		RELEASE: release_method,
	})


## Every child of `player` that holds something now (a child that never published the contract is not a holder).
static func holders(player: Node) -> Array[Node]:
	var out: Array[Node] = []
	if player == null:
		return out
	for child: Node in player.get_children():
		if CapabilityContract.has(child, ID) and holds(child):
			out.append(child)
	return out


static func holds(owner: Object) -> bool:
	return bool(CapabilityContract.invoke(owner, ID, HOLDS))


static func can_release(owner: Object) -> bool:
	return bool(CapabilityContract.invoke(owner, ID, CAN_RELEASE))


static func release(owner: Object) -> bool:
	return bool(CapabilityContract.invoke(owner, ID, RELEASE))
