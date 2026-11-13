extends SceneTree

## Scenes moved out of code must draw what the code built (RUNTIME_CONSTRUCTION_AUDIT.md).
## Each fixture was snapshotted from the old code-built tree before the move; an optional
## third entry names the node to compare inside a larger scene.
## Run: godot --headless --script tests/systems/test_authored_scene_parity.gd

const CASES: Array = [
	["res://scenes/environment/thermometer/wall_thermometer.tscn", "res://tests/fixtures/scene_parity/wall_thermometer.json"],
	["res://scenes/environment/stove/stove_log.tscn", "res://tests/fixtures/scene_parity/stove_log.json"],
	## The stove inside the shelter: its room light, door control and tinder need the HeatSource.
	["res://scenes/world/first_exit/first_exit_blockout.tscn", "res://tests/fixtures/scene_parity/stove_visual_in_shelter.json",
		"ShelterHouse/House/ShelterZone/Stove/StoveVisual"],
	## The flare's light, fog and particle layers; its Body is the new Emberline model on purpose.
	["res://scenes/actors/player/held/HeldFlare.tscn", "res://tests/fixtures/scene_parity/held_flare.json", ".", ["Body"]],
]

var _failures: int = 0


func _process(_delta: float) -> bool:
	for pair: Array in CASES:
		var node := (load(pair[0]) as PackedScene).instantiate() as Node3D
		root.add_child(node)
		var target: Node3D = node.get_node(NodePath(pair[2])) as Node3D if pair.size() > 2 and pair[2] != "." else node
		var exclude: Array = pair[3] if pair.size() > 3 else []
		var problems: Array[String] = SceneParity.diff(SceneParity.load_file(pair[1]), SceneParity.snapshot(target, exclude))
		for problem: String in problems.slice(0, 8):
			push_error("authored_scene_parity: %s: %s" % [pair[0].get_file(), problem])
		_failures += problems.size()
		root.remove_child(node)
		node.free()
	if _failures > 0:
		push_error("authored_scene_parity: %d check(s) failed" % _failures)
		quit(1)
		return true
	print("authored_scene_parity: all checks passed")
	quit(0)
	return true
