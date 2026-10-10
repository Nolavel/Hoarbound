extends SceneTree

## KeyWestRealityGround serves heights and building outlines of streamed Reality chunks to
## the snow shell. Uses a synthetic chunk, so it needs no generated scenes.
## Run: godot --headless --script tests/systems/test_key_west_reality_ground.gd

var _failures: int = 0


func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	var ground := KeyWestRealityGround.new()
	root.add_child(ground)
	var chunk := _chunk(Vector2i(-7, 3))
	root.add_child(chunk)
	ground._index(chunk)
	_check(ground.is_in_group(KeyWestRealityGround.GROUND_GROUP), "provider is not in the snow_ground group")
	## Heights rise 1 m per 2 m step east: bilinear must read 1.5 at 1 m into the first cell.
	_check(is_equal_approx(ground.get_height(-7 * 512.0 + 1.0, 3 * 512.0 + 0.5), 1.5), "bilinear height wrong: %f" % ground.get_height(-7 * 512.0 + 1.0, 3 * 512.0 + 0.5))
	_check(ground.has_snow_obstacle_at(Vector2(-7 * 512.0 + 15.0, 3 * 512.0 + 15.0)), "point inside the outline is not an obstacle")
	_check(not ground.has_snow_obstacle_at(Vector2(-7 * 512.0 + 40.0, 3 * 512.0 + 40.0)), "open ground reported as an obstacle")
	ground._on_cell(&"kw_gen_-7_3", StreamingSystem.CellState.UNLOADED)
	_check(ground.get_height(-7 * 512.0 + 1.0, 3 * 512.0 + 0.5) == KeyWestRealityGround.FALLBACK_Y, "unloaded chunk still answers heights")
	_check(not ground.has_snow_obstacle_at(Vector2(-7 * 512.0 + 15.0, 3 * 512.0 + 15.0)), "unloaded chunk still answers obstacles")
	chunk.free()
	ground.free()
	if _failures > 0:
		push_error("reality ground: %d check(s) failed" % _failures)
		quit(1)
		return
	print("reality ground: all checks passed")
	quit(0)


func _chunk(key: Vector2i) -> Node3D:
	var n: int = 4
	var data := PackedFloat32Array()
	for row: int in range(n):
		for col: int in range(n):
			data.append(1.0 + col)
	var hm := HeightMapShape3D.new()
	hm.map_width = n
	hm.map_depth = n
	hm.map_data = data
	var shape := CollisionShape3D.new()
	shape.shape = hm
	shape.scale = Vector3(2.0, 1.0, 2.0)
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.add_child(shape)
	var tile := MeshInstance3D.new()
	tile.name = "Terrain_%d_%d" % [key.x, key.y]
	tile.position = Vector3(key.x * 512.0, 0.0, key.y * 512.0)
	tile.add_child(body)
	var terrain := Node3D.new()
	terrain.name = "Terrain"
	terrain.add_child(tile)
	var root_node := Node3D.new()
	root_node.name = "Chunk_%d_%d" % [key.x, key.y]
	root_node.set_meta("chunk_id", "%d:%d" % [key.x, key.y])
	var o := Vector2(key.x * 512.0, key.y * 512.0)
	root_node.set_meta("snow_footprints", [PackedVector2Array([o + Vector2(10, 10), o + Vector2(20, 10), o + Vector2(20, 20), o + Vector2(10, 20)])])
	root_node.add_child(terrain)
	return root_node


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("reality ground: %s" % message)
