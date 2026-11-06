class_name HeldReleaseCapability
extends RefCounted

## The holder protocol at the boundary. Gameplay asks whether a holder holds
## something, whether it may let go of it, and asks it to let go - and never
## reflects on the holder itself. The holder owns the answers: it knows what it
## holds and whether that can be put away.
##
## The can_release answer is the guard the holder's own release uses, so a
## release after a true answer cannot fail. That is what lets a caller empty
## the hands without needing a way back.
##
## A holder publishes the capability with its own method names:
##
##     HeldReleaseCapability.publish(self, &"is_holding", &"is_holding_unlit", &"put_away_unlit")
##
## A child that does not publish this capability is not a holder: nothing is
## asked of it.

const ID: StringName = &"held_release"
const HOLDS: StringName = &"holds"
const CAN_RELEASE: StringName = &"can_release"
const RELEASE: StringName = &"release"


## Publishes the capability on a holder. The three method names are the
## holder's own: what it holds, whether it may let go, and how it lets go.
static func publish(
	owner: Object,
	holds_method: StringName,
	can_release_method: StringName,
	release_method: StringName
) -> bool:
	return CapabilityContract.publish(owner, ID, owner, {
		HOLDS: holds_method,
		CAN_RELEASE: can_release_method,
		RELEASE: release_method,
	})


## Whether the holder holds something in its hand.
static func holds(holder: Object) -> bool:
	if not CapabilityContract.has(holder, ID):
		return false
	return bool(CapabilityContract.invoke(holder, ID, HOLDS))


## Whether the holder may let go of what it holds right now. Nothing changes.
static func can_release(holder: Object) -> bool:
	if not CapabilityContract.has(holder, ID):
		return false
	return bool(CapabilityContract.invoke(holder, ID, CAN_RELEASE))


## Asks the holder to let go of what it holds. True when it did.
static func release(holder: Object) -> bool:
	if not CapabilityContract.has(holder, ID):
		return false
	return bool(CapabilityContract.invoke(holder, ID, RELEASE))
