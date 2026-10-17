extends SceneTree

const CLIPMAP: GDScript = preload("res://scripts/systems/world/snow/snow_surface_clipmap.gd")
const SHELL: GDScript = preload("res://scripts/systems/world/snow/deterministic_snow_shell.gd")

var _failures: int = 0


func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	_test_two_level_mesh_is_watertight()
	_test_geometry_budget_is_lower_than_legacy_shell()
	_test_production_shell_installs_clipmap()
	if _failures > 0:
		push_error("snow surface clipmap: %d check(s) failed" % _failures)
		quit(1)
		return
	print("snow surface clipmap: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("snow surface clipmap: %s" % message)


func _test_two_level_mesh_is_watertight() -> void:
	var mesh: ArrayMesh = CLIPMAP.build(25.6, 3.84, 0.08, 0.16)
	_check(mesh.get_surface_count() == 1, "clipmap did not build one draw surface")
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	_check(indices.size() % 3 == 0, "triangle index buffer is not divisible by three")

	var half := 12.8
	var edges: Dictionary = {}
	for k: int in range(0, indices.size(), 3):
		var a: Vector3 = vertices[indices[k]]
		var b: Vector3 = vertices[indices[k + 1]]
		var c: Vector3 = vertices[indices[k + 2]]
		var winding: float = (b - a).cross(c - a).y
		_check(winding < -0.0000001, "triangle winding flipped or collapsed at triangle %d" % (k / 3))
		_count_edge(edges, a, b)
		_count_edge(edges, b, c)
		_count_edge(edges, c, a)

	var internal_open: int = 0
	var overlap_edges: int = 0
	var perimeter_edges: int = 0
	for entry: Variant in edges.values():
		var row: Dictionary = entry
		var count: int = int(row["count"])
		if count == 1:
			if _is_outer_edge(row["a"], row["b"], half):
				perimeter_edges += 1
			else:
				internal_open += 1
		elif count != 2:
			overlap_edges += 1
	_check(internal_open == 0, "%d open internal edges at an L0/L1 stitch" % internal_open)
	_check(overlap_edges == 0, "%d geometric edges are covered by overlapping triangles" % overlap_edges)
	_check(perimeter_edges > 0, "outer perimeter was not found")


func _test_geometry_budget_is_lower_than_legacy_shell() -> void:
	var stats: Dictionary = CLIPMAP.describe(25.6, 3.84, 0.08, 0.16)
	var vertices: int = int(stats["vertices"])
	var triangles: int = int(stats["triangles"])
	## The shipped graded grid at HIGH is 74,529 vertices / 147,968 triangles.
	## This first two-level proof should roughly halve that before L2/far work starts.
	_check(vertices > 10000, "L0/L1 mesh is implausibly sparse: %d vertices" % vertices)
	_check(vertices < 40000, "L0/L1 mesh lost its geometry-budget advantage: %d vertices" % vertices)
	_check(triangles > 20000 and triangles < 80000, "unexpected triangle budget: %d" % triangles)


func _test_production_shell_installs_clipmap() -> void:
	var old_graphics: Variant = ProjectSettings.get_setting("hfn/graphics/quality", "low")
	var old_snow: Variant = ProjectSettings.get_setting("hfn/snow/quality", "high")
	var old_clipmap: Variant = ProjectSettings.get_setting("hfn/snow/clipmap_geometry", true)
	ProjectSettings.set_setting("hfn/graphics/quality", "high")
	ProjectSettings.set_setting("hfn/snow/quality", "high")
	ProjectSettings.set_setting("hfn/snow/clipmap_geometry", true)
	var shell: Node3D = SHELL.new()
	root.add_child(shell)
	var surface := shell.get_node_or_null("SnowShellMesh") as MeshInstance3D
	_check(surface != null and surface.mesh != null, "production shell has no snow surface mesh")
	if surface != null and surface.mesh != null:
		var arrays: Array = surface.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var expected: int = int(CLIPMAP.describe(25.6, 3.84, 0.08, 0.16)["vertices"])
		_check(vertices.size() == expected, "DeterministicSnowShell did not install the L0/L1 mesh")
	shell.free()
	ProjectSettings.set_setting("hfn/graphics/quality", old_graphics)
	ProjectSettings.set_setting("hfn/snow/quality", old_snow)
	ProjectSettings.set_setting("hfn/snow/clipmap_geometry", old_clipmap)


func _count_edge(edges: Dictionary, a: Vector3, b: Vector3) -> void:
	var ak: String = _point_key(a)
	var bk: String = _point_key(b)
	var key: String = ak + ";" + bk if ak < bk else bk + ";" + ak
	if not edges.has(key):
		edges[key] = {"count": 1, "a": a, "b": b}
	else:
		var row: Dictionary = edges[key]
		row["count"] = int(row["count"]) + 1
		edges[key] = row


func _point_key(v: Vector3) -> String:
	return "%d,%d" % [roundi(v.x * 10000.0), roundi(v.z * 10000.0)]


func _is_outer_edge(a: Vector3, b: Vector3, half: float) -> bool:
	var eps := 0.0002
	return (
		(absf(a.x - half) < eps and absf(b.x - half) < eps)
		or (absf(a.x + half) < eps and absf(b.x + half) < eps)
		or (absf(a.z - half) < eps and absf(b.z - half) < eps)
		or (absf(a.z + half) < eps and absf(b.z + half) < eps)
	)
