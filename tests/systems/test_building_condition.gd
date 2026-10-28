extends SceneTree

## Shelter readability (#235): a building condition from data dresses a generated building
## from its own geometry: footprint hull, burnt materials, an empty doorway on the street
## side, a snow drift round the walls. Applied once, listed buildings only.

var _failures: int = 0


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_test_footprint()
	_test_burnt()
	_test_empty()
	_test_snowed()
	_test_table()
	print("test_building_condition: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)


## A 10 x 4 x 6 m generated-style building: walls, roof and windows surfaces, base at y = 0.
func _building(node_name: String) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	var box := BoxMesh.new()
	box.size = Vector3(10.0, 4.0, 6.0)
	var arrays: Array = box.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i: int in range(vertices.size()):
		vertices[i] += Vector3.UP * 2.0
	arrays[Mesh.ARRAY_VERTEX] = vertices
	for _surface: int in range(3):
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var building := MeshInstance3D.new()
	building.name = node_name
	building.mesh = mesh
	building.set_meta("material_slots", ["walls", "roof", "windows"])
	root.add_child(building)
	return building


func _test_footprint() -> void:
	var b := _building("KW_BUILDING_test_hull")
	var hull: PackedVector2Array = BuildingCondition.footprint(b.mesh)
	_check(hull.size() == 4, "box footprint has %d corners, expected 4" % hull.size())
	var area: float = 0.0
	for i: int in range(hull.size()):
		var p: Vector2 = hull[i]
		var q: Vector2 = hull[(i + 1) % hull.size()]
		area += p.x * q.y - q.x * p.y
	_check(is_equal_approx(absf(area) * 0.5, 60.0), "footprint area %.1f, expected 60" % (absf(area) * 0.5))
	b.free()


func _test_burnt() -> void:
	var b := _building("KW_BUILDING_test_burnt")
	BuildingCondition.apply(b, {"condition": "burnt"})
	var walls := b.get_surface_override_material(0) as ShaderMaterial
	_check(walls != null and walls.shader == BuildingCondition.BURNT_SHADER, "burnt walls lack the char shader")
	var windows := b.get_surface_override_material(2) as StandardMaterial3D
	_check(windows != null and windows.albedo_color.v < 0.05, "burnt windows are not black")
	_check(b.get_meta(BuildingCondition.APPLIED_META, "") == "burnt", "burnt condition not recorded")
	b.free()


func _test_empty() -> void:
	var b := _building("KW_BUILDING_test_empty")
	BuildingCondition.apply(b, {"condition": "empty", "front": [0.0, 1.0]})
	var hole := b.get_node_or_null(^"Condition_Doorway") as MeshInstance3D
	_check(hole != null, "empty house has no doorway")
	if hole != null:
		_check(hole.position.z > 2.9 and absf(hole.position.x) < 0.1, "doorway is not on the +Z street side: %s" % hole.position)
		_check(is_equal_approx(hole.position.y, BuildingCondition.DOOR_SIZE.y * 0.5), "doorway does not stand on the base")
	_check(b.get_node_or_null(^"Condition_TornDoor") != null, "empty house has no torn door")
	var windows := b.get_surface_override_material(2) as StandardMaterial3D
	_check(windows != null and windows.albedo_color.v < 0.05, "empty house windows are not dark holes")
	b.free()


func _test_snowed() -> void:
	var b := _building("KW_BUILDING_test_snowed")
	BuildingCondition.apply(b, {"condition": "snowed"})
	var drift := b.get_node_or_null(^"Condition_SnowDrift") as MeshInstance3D
	_check(drift != null, "snowed house has no drift")
	if drift != null:
		var aabb: AABB = drift.mesh.get_aabb()
		_check(is_equal_approx(aabb.end.y, BuildingCondition.DRIFT_HEIGHT), "drift top %.2f, expected %.2f" % [aabb.end.y, BuildingCondition.DRIFT_HEIGHT])
		_check(aabb.size.x > 10.0 + BuildingCondition.DRIFT_SPREAD and aabb.size.z > 6.0 + BuildingCondition.DRIFT_SPREAD,
			"drift does not spread round the walls: %s" % aabb.size)
	b.free()


## The world table lists only real buildings with a known condition, each applied once.
func _test_table() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BuildingCondition.TABLE_PATH))
	_check(parsed is Dictionary and (parsed as Dictionary).has("buildings"), "building_conditions.json is unreadable")
	if not parsed is Dictionary:
		return
	var seen: Dictionary = {}
	for name: String in (parsed as Dictionary)["buildings"]:
		var entry: Dictionary = (parsed as Dictionary)["buildings"][name]
		_check(name.begins_with("KW_BUILDING_"), "%s is not a generated building name" % name)
		_check(String(entry.get("condition")) in ["burnt", "empty", "snowed"], "%s has unknown condition %s" % [name, entry.get("condition")])
		seen[String(entry.get("condition"))] = true
	_check(seen.size() == 3, "the 727 street does not show all three shells")
	var holder := Node3D.new()
	root.add_child(holder)
	var b := _building("KW_BUILDING_osm_w585507160")
	b.reparent(holder)
	BuildingCondition.decorate(holder)
	BuildingCondition.decorate(holder)
	_check(b.get_children().filter(func(c: Node) -> bool: return c.name.begins_with("Condition_SnowDrift")).size() == 1,
		"decorate applied the drift twice")
	holder.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_building_condition: " + message)
