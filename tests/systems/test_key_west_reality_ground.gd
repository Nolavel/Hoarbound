extends SceneTree

## KeyWestRealityGround serves heights and building outlines of streamed Reality chunks to
## the snow shell; an HLOD cluster of a chunk leaves the chunk's data alone. Uses a synthetic chunk, so it needs
## no generated scenes.
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
	## A sample on the chunk's far edge (the next chunk is not loaded) still reads this chunk.
	_check(absf(ground.get_height(-6 * 512.0, 3 * 512.0 + 0.5) - 4.0) < 0.01, "far-edge height fell back: %f" % ground.get_height(-6 * 512.0, 3 * 512.0 + 0.5))
	_check(ground.get_snow_obstacles_in_rect(Rect2(Vector2(-7 * 512.0, 3 * 512.0), Vector2.ONE * 512.0)).size() == 1, "outline missing from the chunk rect")
	## A streamed HLOD cluster names its source chunk; seeing it (boot scan of the container) must not drop that chunk.
	var cluster := Node3D.new()
	cluster.set_meta("chunk_id", "-7:3")
	cluster.set_meta("cluster_id", "c128_-28_12")
	root.add_child(cluster)
	ground._index(cluster)
	_check(ground.has_ground_at(-7 * 512.0 + 1.0, 3 * 512.0 + 0.5), "an HLOD cluster of the chunk dropped its ground")
	_check(ground.has_snow_obstacle_at(Vector2(-7 * 512.0 + 15.0, 3 * 512.0 + 15.0)), "an HLOD cluster of the chunk dropped its outlines")
	cluster.free()
	_check(ground.get_snow_obstacles_in_rect(Rect2(Vector2(-7 * 512.0 + 100.0, 3 * 512.0 + 100.0), Vector2.ONE * 50.0)).is_empty(), "outline reported in a rect it does not touch")
	ground._on_cell(&"kw_gen_-7_3", StreamingSystem.CellState.UNLOADED)
	_check(ground.get_height(-7 * 512.0 + 1.0, 3 * 512.0 + 0.5) == KeyWestRealityGround.FALLBACK_Y, "unloaded chunk still answers heights")
	_check(not ground.has_snow_obstacle_at(Vector2(-7 * 512.0 + 15.0, 3 * 512.0 + 15.0)), "unloaded chunk still answers obstacles")
	chunk.free()
	ground.free()
	_test_roads_raise_the_surface()
	if _failures > 0:
		push_error("reality ground: %d check(s) failed" % _failures)
		quit(1)
		return
	print("reality ground: all checks passed")
	quit(0)


func _chunk(key: Vector2i, n: int = 4, rise: float = 1.0) -> Node3D:
	var data := PackedFloat32Array()
	for row: int in range(n):
		for col: int in range(n):
			data.append(1.0 + col * rise)
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


## A road ribbon a few centimetres over the terrain is the ground snow lies on; a high deck is not.
func _test_roads_raise_the_surface() -> void:
	var ground := KeyWestRealityGround.new()
	root.add_child(ground)
	var key := Vector2i(-5, 2)
	var o := Vector3(key.x * 512.0, 0.0, key.y * 512.0)
	var chunk := _chunk(key, 8, 0.0)
	var roads := Node3D.new()
	roads.name = "Roads"
	var street := _ribbon(o + Vector3(2.0, 1.07, 5.0), o + Vector3(12.0, 1.07, 7.0))
	street.set_meta("width_m", 8.0)
	roads.add_child(street)
	roads.add_child(_ribbon(o + Vector3(2.0, 3.0, 10.0), o + Vector3(12.0, 3.0, 12.0)))
	chunk.add_child(roads)
	root.add_child(chunk)
	ground._index(chunk)
	_check(not ground.has_surface_at(o.x + 6.0, o.z + 6.0), "surface reported before the roads were paved")
	_check(is_equal_approx(ground.get_surface_height(o.x + 6.0, o.z + 6.0), 1.0), "unpaved surface is not the terrain")
	while not ground._pave_jobs.is_empty():
		var lot: Vector2i = ground._pave_jobs.keys()[0]
		if ground._pave_step(lot, 1 << 30):
			ground._pave_jobs.erase(lot)
	_check(ground.has_surface_at(o.x + 6.0, o.z + 6.0), "paved surface not reported")
	_check(absf(ground.get_surface_height(o.x + 6.0, o.z + 6.0) - 1.07) < 0.001, "road not under the snow: %f" % ground.get_surface_height(o.x + 6.0, o.z + 6.0))
	_check(absf(ground.get_surface_height(o.x + 6.0, o.z + 5.0) - 1.07) < 0.001, "road edge dips below the ribbon: %f" % ground.get_surface_height(o.x + 6.0, o.z + 5.0))
	_check(is_equal_approx(ground.get_height(o.x + 6.0, o.z + 6.0), 1.0), "the road changed the terrain height")
	_check(is_equal_approx(ground.get_surface_height(o.x + 6.0, o.z + 11.0), 1.0), "a 2 m deck became the snow's ground")
	## A wide street's quad gives one centreline segment along it (BlizzardFlow places its flow there).
	var streets: Array[Dictionary] = ground.get_wide_streets(Vector2(o.x + 6.0, o.z + 6.0), 5.0)
	_check(streets.size() == 1, "wide street segments: %d" % streets.size())
	if streets.size() == 1:
		var a: Vector2 = streets[0]["a"]
		var b: Vector2 = streets[0]["b"]
		_check(absf(absf(a.x - b.x) - 10.0) < 0.01 and absf(a.y - (o.z + 6.0)) < 0.01, "street centreline wrong: %s %s" % [a, b])
	chunk.free()
	ground.free()


func _ribbon(lo: Vector3, hi: Vector3) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p: Vector3 in [lo, Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, hi.z), lo, Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]:
		st.add_vertex(p)
	var ribbon := MeshInstance3D.new()
	ribbon.mesh = st.commit()
	return ribbon


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("reality ground: %s" % message)
