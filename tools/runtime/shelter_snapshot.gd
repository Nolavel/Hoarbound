extends RefCounted
## Persistent 727 state a sleep save must bring back: boards, fire, taken pickups, kit counts, Henry indoors.
## Shared by loop_key_west_727.gd (in-process reload) and continue_after_relaunch.gd (new process).

const KIT: Array[String] = ["HammerShelter", "NailsShelter", "LighterShelterTest", "StewShelterTest"]
const BOARD_STACKS: Array[String] = ["BoardsShelterInside", "BoardsShelterTest1", "BoardsShelterTest2",
	"BoardsShelterTest3", "BoardsShelterTest4", "BoardsShelterTest5", "BoardsShelterTest6"]


static func take(world: Node, player: Node3D) -> Dictionary:
	var house := world.find_child("Shelter727", true, false).get_node(^"House") as Node3D
	var inventory := player.get_node(^"InventoryComponent") as InventoryComponent
	var zone := house.get_node(^"ShelterZone") as ThermalZone
	var boards: Dictionary = {}
	for breach: ShelterBreach in zone.get_breaches():
		boards[String(breach.name)] = snappedf(breach.get_coverage_fraction(), 0.01)
	var source: HeatSource = (house.get_node(^"ShelterZone/Stove/Feed") as HeatSourceFeed).heat_source
	var taken: Array[String] = []
	for name: String in KIT + BOARD_STACKS + ["FirewoodShelter"]:
		if world.find_child(name, true, false) == null:
			taken.append(name)
	var p: Vector3 = house.to_local(player.global_position)
	return {"boards": boards, "fire_burning": source.is_burning(), "fire_hours": snappedf(source.get_remaining_hours(), 0.1),
		"taken": taken, "hammer": inventory.get_count(&"hammer"), "nails": inventory.get_count(&"nails"),
		"stew": inventory.get_count(&"tinned_stew"), "player_in_727": absf(p.x) < 14.0 and absf(p.z) < 11.0}


static func diff(expected: Dictionary, got: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key: String in expected:
		if str(expected[key]) != str(got.get(key)):
			out.append("%s: saved %s, reloaded %s" % [key, expected[key], got.get(key)])
	return out
