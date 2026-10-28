extends SceneTree

## Wall stones (#257): spots lie just outside the wall, never inside the building, come back the
## same on every visit, and hold a stone at roughly the authored share of the wall.
## Run: godot --headless --script tests/systems/test_stone_scatter.gd

var _failures: int = 0


func _initialize() -> void:
	## A long terrace, 120 x 80 m, wound either way.
	var ring := PackedVector2Array([Vector2(0, 0), Vector2(120, 0), Vector2(120, 80), Vector2(0, 80)])
	var spots: Array[Vector2] = StoneScatter.wall_spots(ring)
	var reversed := ring.duplicate()
	reversed.reverse()
	_check(spots == StoneScatter.wall_spots(ring), "the same wall gave different stones")
	_check(StoneScatter.wall_spots(reversed).size() == spots.size(), "winding changed how many stones a wall has")
	var candidates: float = 400.0 / StoneScatter.SPOT_SPACING_M
	var share: float = float(spots.size()) / candidates
	print("stones: %d on 400 m of wall (share %.3f, authored %.2f)" % [spots.size(), share, StoneScatter.CHANCE])
	_check(spots.size() > 0 and absf(share - StoneScatter.CHANCE) < 0.06, "stone share %.3f is far from %.2f" % [share, StoneScatter.CHANCE])
	for spot: Vector2 in spots:
		_check(not Geometry2D.is_point_in_polygon(spot, ring), "a stone lies inside the building at %s" % spot)
		var gap: float = minf(minf(spot.x, 120.0 - spot.x), minf(spot.y, 80.0 - spot.y))
		_check(absf(absf(gap) - StoneScatter.WALL_GAP_M) < 0.01, "a stone is %.2f m from the wall, not %.2f" % [absf(gap), StoneScatter.WALL_GAP_M])
	print("test_stone_scatter: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
