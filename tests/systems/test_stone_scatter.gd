extends SceneTree

## Wall stones (#257): spots lie just outside the wall, never inside the building, come back the
## same on every visit, and hold a stone at roughly the authored share of the wall.
## Run: godot --headless --script tests/systems/test_stone_scatter.gd

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
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
	await _test_lifecycle(ring)
	print("test_stone_scatter: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


## Exercise the actual refresh/ledger/free path, not just the wall geometry.
func _test_lifecycle(ring: PackedVector2Array) -> void:
	var ground := KeyWestRealityGround.new()
	root.add_child(ground)
	ground._outlines[Vector2i.ZERO] = [ring]
	var scatter := StoneScatter.new()
	root.add_child(scatter)
	scatter._ground = ground
	var ledger := PickupLedger.new()
	root.add_child(ledger)
	var spots: Array[Vector2] = StoneScatter.wall_spots(ring)
	if spots.is_empty():
		_check(false, "no lifecycle test spot")
		return
	var centre: Vector2 = spots[0]
	scatter.refresh(centre)
	var id := StringName("stone:%d:%d" % [roundi(centre.x * 10.0), roundi(centre.y * 10.0)])
	_check(scatter._spots.has(id), "refresh did not place fixture stone")
	if not scatter._spots.has(id):
		return
	var picked := scatter._spots[id] as ItemPickup
	ledger.record(id)
	picked.queue_free()
	scatter.refresh(centre)
	_check(scatter._spots.has(id) and scatter._spots[id] == picked, "queued pickup was replaced in the same frame")
	await process_frame
	await process_frame
	_check(not is_instance_valid(picked), "collected pickup was not freed")
	scatter.refresh(centre)
	_check(not scatter._spots.has(id), "freed pickup was not pruned")
	scatter.refresh(centre)
	_check(not scatter._spots.has(id), "ledger allowed a collected stone to respawn")
	# An untaken stone must be evicted and then recreated on return.
	var other := &""
	for key: StringName in scatter._spots.keys():
		other = key
		break
	if other == &"":
		for spot: Vector2 in spots:
			if spot != centre:
				scatter.refresh(spot)
				for key: StringName in scatter._spots.keys():
					other = key
					break
				if other != &"":
					break
	_check(other != &"", "no untaken stone for streaming test")
	if other != &"":
		var old := scatter._spots[other] as ItemPickup
		var at := Vector2(old.global_position.x, old.global_position.z)
		scatter.refresh(at + Vector2(1000, 1000))
		await process_frame
		await process_frame
		scatter.refresh(at)
		_check(not is_instance_valid(old) and scatter._spots.has(other), "untaken stone did not respawn after eviction")
	scatter.free()
	ground.free()
	ledger.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
