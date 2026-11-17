class_name HeldDrawCapability
extends RefCounted

## A hand that shows an item Henry keeps in a pocket (a held item, the hammer, a flare): draws it from its pocket,
## names the pocket it came from, and uses it (Quick Access). Published by the same holders as HeldReleaseCapability.

const ID: StringName = &"held_draw"
const DRAW: StringName = &"draw"
const SOURCE_ZONE: StringName = &"source_zone"
const USE: StringName = &"use"


## Publishes `owner`'s own methods: draw(item_id, zone_path) -> bool, source_zone() -> StringName (the pocket the
## shown item belongs to, or ""), use() -> bool (false when it has no use from Quick Access).
static func publish(owner: Object, draw_method: StringName, source_zone_method: StringName,
		use_method: StringName) -> bool:
	return CapabilityContract.publish_self(owner, ID, {
		DRAW: draw_method,
		SOURCE_ZONE: source_zone_method,
		USE: use_method,
	})


## Every child of `player` that publishes the contract, in tree order.
static func hands(player: Node) -> Array[Node]:
	var out: Array[Node] = []
	if player == null:
		return out
	for child: Node in player.get_children():
		if CapabilityContract.has(child, ID):
			out.append(child)
	return out


static func draw(owner: Object, item_id: StringName, zone_path: StringName) -> bool:
	return bool(CapabilityContract.invoke(owner, ID, DRAW, [item_id, zone_path]))


static func source_zone(owner: Object) -> StringName:
	return StringName(str(CapabilityContract.invoke(owner, ID, SOURCE_ZONE)))


static func use(owner: Object) -> bool:
	return bool(CapabilityContract.invoke(owner, ID, USE))
