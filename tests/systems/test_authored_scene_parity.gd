extends SceneTree

## Scenes moved out of code must draw what the code built (RUNTIME_CONSTRUCTION_AUDIT.md).
## Each fixture was snapshotted from the old code-built tree before the move.
## Run: godot --headless --script tests/systems/test_authored_scene_parity.gd

const CASES: Array = [
	["res://scenes/environment/thermometer/wall_thermometer.tscn", "res://tests/fixtures/scene_parity/wall_thermometer.json"],
]

var _failures: int = 0


func _process(_delta: float) -> bool:
	for pair: Array in CASES:
		var node := (load(pair[0]) as PackedScene).instantiate() as Node3D
		root.add_child(node)
		var problems: Array[String] = SceneParity.diff(SceneParity.load_file(pair[1]), SceneParity.snapshot(node))
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
