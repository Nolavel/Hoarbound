extends SceneTree

## IslandTerrain: heights match the heightmap, detail follows the focus, and
## collision exists under it and matches the ground.
## Run: godot --headless --script tests/systems/test_island_terrain.gd

## Spawn from docs/world/FIRST_EXIT.md, and a far point on the west cape.
const SPAWN: Vector3 = Vector3(1420.0, 0.0, -943.0)
const FAR: Vector2 = Vector2(-1700.0, -800.0)

var _failures: int = 0
var _frame: int = 0
var _terrain: IslandTerrain
var _focus: Node3D


func _physics_process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		1:
			_focus = Node3D.new()
			root.add_child(_focus)
			_focus.global_position = SPAWN
			_terrain = IslandTerrain.new()
			_terrain.focus = _focus
			root.add_child(_terrain)
		4:
			_check_heights()
			_check_detail()
			_check_collision()
			_finish()
	return false


func _check_heights() -> void:
	## Pixel (3496, 745) of the source PNG, verified in Python: 4.0706 m.
	var h: float = _terrain.get_height(1200.0, -800.0)
	_check(absf(h - 4.0706) < 0.002, "height at (1200, -800) is %.4f, expected 4.0706" % h)
	_check(_terrain.get_height(3000.0, 3000.0) < 0.0, "far outside the map is not sea")


func _check_detail() -> void:
	_check(_terrain.get_chunk_count() > 100, "only %d chunks built" % _terrain.get_chunk_count())
	_check(_terrain.get_lod_of(SPAWN.x, SPAWN.z) == 0, "the spawn chunk is not at full detail")
	_check(_terrain.get_lod_of(FAR.x, FAR.y) == 2, "a far chunk is not at the coarsest level")


func _check_collision() -> void:
	_check(_terrain.has_collision_at(SPAWN.x, SPAWN.z), "no collision under the spawn")
	_check(not _terrain.has_collision_at(FAR.x, FAR.y), "collision on a far chunk")
	_check_collision_at(Vector2(SPAWN.x, SPAWN.z))


func _check_collision_at(at: Vector2) -> void:
	var space: PhysicsDirectSpaceState3D = _terrain.get_world_3d().direct_space_state
	for offset: Vector2 in [Vector2.ZERO, Vector2(37.3, -21.6), Vector2(-60.0, 45.5)]:
		var x: float = at.x + offset.x
		var z: float = at.y + offset.y
		var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 100.0, z), Vector3(x, -50.0, z)))
		_check(not hit.is_empty(), "no ground hit at (%.1f, %.1f)" % [x, z])
		if not hit.is_empty():
			var ground: float = _terrain.get_height(x, z)
			_check(absf(hit["position"].y - ground) < 0.15, "collision %.2f vs ground %.2f at (%.1f, %.1f)" % [hit["position"].y, ground, x, z])


func _finish() -> void:
	if _failures > 0:
		push_error("island terrain: %d check(s) failed" % _failures)
		quit(1)
		return
	print("island terrain: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("island terrain: %s" % message)
