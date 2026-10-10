extends SceneTree
## Editor-time proof: builds one Reality Library chunk JSON into a saved Godot scene.
## Usage: godot --headless --script tools/world/build_key_west_reality_chunk.gd -- <chunk.json> <out.scn>

const GENERATOR_VERSION: String = "reality_chunk_proof.1"
const UNKNOWN_HEIGHT_M: float = 3.0
const POLE_HEIGHT_M: float = 9.0
const GROUPS: Array[String] = ["Buildings", "Roads", "Barriers", "Infrastructure", "Vegetation", "Coastal", "LandUse"]

var _wall_material: StandardMaterial3D
var _roof_material: StandardMaterial3D
var _unknown_material: StandardMaterial3D
var _road_material: StandardMaterial3D
var _tree_material: StandardMaterial3D
var _pole_material: StandardMaterial3D
var _tree_mesh: Mesh
var _pole_mesh: Mesh
var _stats: Dictionary = {}


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("build_key_west_reality_chunk: <chunk.json> <out.scn> required")
		quit(1)
		return
	var text: String = FileAccess.get_file_as_string(args[0])
	var doc: Variant = JSON.parse_string(text)
	if not doc is Dictionary:
		push_error("build_key_west_reality_chunk: cannot parse %s" % args[0])
		quit(1)
		return
	_make_resources()
	var root: Node3D = _build_chunk(doc as Dictionary)
	var packed: PackedScene = PackedScene.new()
	var error: Error = packed.pack(root)
	if error == OK:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(args[1]).get_base_dir())
		error = ResourceSaver.save(packed, args[1])
	print("build_key_west_reality_chunk: %s -> %s %s (err %d)" % [doc.get("chunk_id"), args[1], JSON.stringify(_stats), error])
	root.free()
	quit(0 if error == OK else 1)


func _build_chunk(doc: Dictionary) -> Node3D:
	var parts: PackedStringArray = String(doc["chunk_id"]).split(":")
	var root: Node3D = Node3D.new()
	root.name = "Chunk_%s_%s" % [parts[0], parts[1]]
	root.set_meta("chunk_id", doc["chunk_id"])
	root.set_meta("generator_version", GENERATOR_VERSION)
	root.set_meta("library", doc["library"])
	root.set_meta("generated_at", doc["exported_at"])
	var groups: Dictionary = {}
	for group_name: String in GROUPS:
		var group: Node3D = Node3D.new()
		group.name = group_name
		root.add_child(group)
		group.owner = root
		groups[group_name] = group
	for feature: Dictionary in doc["features"]:
		if feature["regen_action"] in ["keep_locked", "needs_rebase", "orphaned"]:
			_count("skipped_authored")
			continue
		var node: Node3D = _build_feature(feature)
		if node == null:
			continue
		_apply_meta(node, feature, doc)
		var parent: Node3D = groups.get(feature["group"], root)
		parent.add_child(node)
		node.owner = root
		for child: Node in node.get_children():
			child.owner = root
	return root


func _build_feature(feature: Dictionary) -> Node3D:
	var family: String = feature["family"]
	var geometry: Dictionary = feature["geometry"]
	if family == "buildings" and geometry["type"] == "polygon":
		return _building(feature)
	if family == "roads" and geometry["type"] == "line":
		return _road(feature)
	if family == "trees" and geometry["type"] == "point":
		return _tree(feature)
	if family == "power" and geometry["type"] == "point":
		return _pole(feature)
	var marker: Node3D = Node3D.new()
	marker.name = feature["node_name"]
	var ground: Array = _ground(feature)
	var anchor: Vector2 = _anchor(geometry)
	marker.position = Vector3(anchor.x, float(ground[0]) if ground.size() > 0 else 0.0, anchor.y)
	_count("markers")
	return marker


## Footprint walls (surface 0) + flat cap at measured top (surface 1); origin at ring centroid on the ground.
func _building(feature: Dictionary) -> Node3D:
	var rings: Array = feature["geometry"]["rings"]
	var outer: PackedVector2Array = _ring(rings[0])
	var attrs: Dictionary = feature["attrs"]
	var ground: float = float(attrs.get("ground_elevation_m", _min_ground(feature)))
	var known: bool = attrs.has("height_m")
	var height: float = float(attrs.get("height_m", UNKNOWN_HEIGHT_M))
	var centre: Vector2 = _centroid(outer)
	var walls: SurfaceTool = SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring_index: int in range(rings.size()):
		var ring: PackedVector2Array = _ring(rings[ring_index])
		for i: int in range(ring.size() - 1):
			var a: Vector2 = ring[i] - centre
			var b: Vector2 = ring[i + 1] - centre
			if a.is_equal_approx(b):
				continue
			var mid: Vector2 = (ring[i] + ring[i + 1]) * 0.5
			var side: Vector2 = (b - a).normalized().orthogonal()
			var outside: bool = not _inside(rings, mid + side * 0.05)
			var n: Vector2 = side if outside else -side
			_wall_quad(walls, a, b, height, Vector3(n.x, 0.0, n.y))
	var mesh: ArrayMesh = walls.commit()
	mesh.surface_set_material(0, _wall_material if known else _unknown_material)
	mesh.surface_set_name(0, "walls")
	var roof: SurfaceTool = SurfaceTool.new()
	roof.begin(Mesh.PRIMITIVE_TRIANGLES)
	var local_outer: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in outer:
		local_outer.append(p - centre)
	if local_outer.size() > 1 and local_outer[0].is_equal_approx(local_outer[local_outer.size() - 1]):
		local_outer.remove_at(local_outer.size() - 1)
	var tris: PackedInt32Array = Geometry2D.triangulate_polygon(local_outer)
	for i: int in range(0, tris.size(), 3):
		var p0: Vector2 = local_outer[tris[i]]
		var p1: Vector2 = local_outer[tris[i + 1]]
		var p2: Vector2 = local_outer[tris[i + 2]]
		_add_triangle(roof, Vector3(p0.x, height, p0.y), Vector3(p1.x, height, p1.y), Vector3(p2.x, height, p2.y), Vector3.UP)
	roof.commit(mesh)
	if mesh.get_surface_count() > 1:
		mesh.surface_set_material(1, _roof_material)
		mesh.surface_set_name(1, "roof")
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = feature["node_name"]
	instance.mesh = mesh
	instance.position = Vector3(centre.x, ground, centre.y)
	instance.set_meta("height_placeholder", not known)
	instance.set_meta("material_slots", ["walls", "roof"])
	_count("buildings")
	return instance


## Wall quad from a to b (plan coordinates relative to the origin), facing n.
func _wall_quad(st: SurfaceTool, a: Vector2, b: Vector2, height: float, n: Vector3) -> void:
	var a0: Vector3 = Vector3(a.x, 0.0, a.y)
	var b0: Vector3 = Vector3(b.x, 0.0, b.y)
	var a1: Vector3 = Vector3(a.x, height, a.y)
	var b1: Vector3 = Vector3(b.x, height, b.y)
	_add_triangle(st, a0, b0, b1, n)
	_add_triangle(st, a0, b1, a1, n)


## Adds a triangle whose front face (Godot: clockwise seen from the front) points along n.
func _add_triangle(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, n: Vector3) -> void:
	if (v2 - v0).cross(v1 - v0).dot(n) < 0.0:
		var t: Vector3 = v1
		v1 = v2
		v2 = t
	for v: Vector3 in [v0, v1, v2]:
		st.set_normal(n)
		st.add_vertex(v)


func _road(feature: Dictionary) -> Node3D:
	var pts: PackedVector2Array = _ring(feature["geometry"]["p"])
	var ground: Array = _ground(feature)
	var width: float = float(feature["attrs"].get("width_m", 4.0))
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var origin: Vector2 = pts[0]
	for i: int in range(pts.size() - 1):
		var a: Vector2 = pts[i] - origin
		var b: Vector2 = pts[i + 1] - origin
		var side: Vector2 = (b - a).normalized().orthogonal() * width * 0.5
		var ya: float = float(ground[i]) + 0.05 if i < ground.size() else 0.05
		var yb: float = float(ground[i + 1]) + 0.05 if i + 1 < ground.size() else 0.05
		var q: Array[Vector3] = [Vector3(a.x + side.x, ya, a.y + side.y), Vector3(a.x - side.x, ya, a.y - side.y),
			Vector3(b.x - side.x, yb, b.y - side.y), Vector3(b.x + side.x, yb, b.y + side.y)]
		_add_triangle(st, q[0], q[1], q[2], Vector3.UP)
		_add_triangle(st, q[0], q[2], q[3], Vector3.UP)
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = feature["node_name"]
	instance.mesh = st.commit()
	if instance.mesh != null and instance.mesh.get_surface_count() > 0:
		instance.mesh.surface_set_material(0, _road_material)
	instance.position = Vector3(origin.x, 0.0, origin.y)
	_count("roads")
	return instance


func _tree(feature: Dictionary) -> Node3D:
	var p: Array = feature["geometry"]["p"]
	var ground: Array = _ground(feature)
	var height: float = float(feature["attrs"].get("height_m", 6.0))
	var crown: float = float(feature["attrs"].get("crown_radius_m", height * 0.3))
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = feature["node_name"]
	instance.mesh = _tree_mesh
	instance.position = Vector3(float(p[0]), float(ground[0]) if ground.size() > 0 else 0.0, float(p[1]))
	instance.scale = Vector3(crown, height, crown)
	_count("trees")
	return instance


func _pole(feature: Dictionary) -> Node3D:
	var p: Array = feature["geometry"]["p"]
	var ground: Array = _ground(feature)
	var base: float = float(ground[0]) if ground.size() > 0 else 0.0
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = feature["node_name"]
	instance.mesh = _pole_mesh
	instance.position = Vector3(float(p[0]), base + POLE_HEIGHT_M * 0.5, float(p[1]))
	instance.set_meta("presentation_height_inferred", POLE_HEIGHT_M)
	_count("poles")
	return instance


## Copies the Reality Library metadata contract onto the node (docs/world/KEY_WEST_REALITY_LIBRARY.md).
func _apply_meta(node: Node3D, feature: Dictionary, doc: Dictionary) -> void:
	var meta: Dictionary = feature["meta"]
	for key: String in meta.keys():
		if meta[key] != null:
			node.set_meta(key, meta[key])
	node.set_meta("generator_version", GENERATOR_VERSION)
	node.set_meta("generated_at", doc["exported_at"])
	node.set_meta("regen_action", feature["regen_action"])
	if not feature["overrides"].is_empty():
		node.set_meta("override_ids", feature["overrides"].map(func(o: Dictionary) -> String: return o["override_id"]))


func _make_resources() -> void:
	_wall_material = _material(Color(0.82, 0.78, 0.70))
	_roof_material = _material(Color(0.55, 0.36, 0.30))
	_unknown_material = _material(Color(0.85, 0.30, 0.30))
	_road_material = _material(Color(0.24, 0.24, 0.26))
	_tree_material = _material(Color(0.20, 0.45, 0.22))
	_pole_material = _material(Color(0.35, 0.28, 0.22))
	var crown: SphereMesh = SphereMesh.new()
	crown.radius = 1.0
	crown.height = 1.0
	crown.radial_segments = 8
	crown.rings = 4
	crown.material = _tree_material
	_tree_mesh = crown
	var pole: CylinderMesh = CylinderMesh.new()
	pole.top_radius = 0.12
	pole.bottom_radius = 0.15
	pole.height = POLE_HEIGHT_M
	pole.radial_segments = 6
	pole.material = _pole_material
	_pole_mesh = pole


func _material(colour: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 0.9
	return m


func _ring(flat: Array) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for i: int in range(0, flat.size() - 1, 2):
		out.append(Vector2(float(flat[i]), float(flat[i + 1])))
	return out


func _anchor(geometry: Dictionary) -> Vector2:
	match geometry["type"]:
		"point":
			return Vector2(float(geometry["p"][0]), float(geometry["p"][1]))
		"line":
			return _ring(geometry["p"])[0]
		"polygon":
			return _centroid(_ring(geometry["rings"][0]))
		_:
			return _anchor(geometry["parts"][0])


func _centroid(ring: PackedVector2Array) -> Vector2:
	var sum: Vector2 = Vector2.ZERO
	var n: int = maxi(ring.size() - 1, 1)
	for i: int in range(n):
		sum += ring[i]
	return sum / float(n)


## Even-odd point-in-polygon over all rings (outer + holes), plan coordinates.
func _inside(rings: Array, p: Vector2) -> bool:
	var inside: bool = false
	for ring_data: Array in rings:
		if Geometry2D.is_point_in_polygon(p, _ring(ring_data)):
			inside = not inside
	return inside


func _min_ground(feature: Dictionary) -> float:
	var ground: Array = _ground(feature)
	var lowest: float = INF
	for v: Variant in ground:
		lowest = minf(lowest, float(v))
	return 0.0 if lowest == INF else lowest


## Per-vertex NAVD88 ground from the export; empty for multi-part geometry.
func _ground(feature: Dictionary) -> Array:
	var value: Variant = feature.get("ground_y")
	return value if value is Array else []


func _count(key: String) -> void:
	_stats[key] = int(_stats.get(key, 0)) + 1
