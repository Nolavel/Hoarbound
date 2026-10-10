class_name KeyWestChunkBuilder
extends RefCounted
## Builds one Reality Library chunk (editor interchange JSON v2) into a Node3D tree with meshes,
## collision and the per-node metadata contract. Editor-time only; never used at runtime.

const GENERATOR_VERSION: String = "kw_chunk_builder.3"
const GROUPS: Array[String] = ["Terrain", "Buildings", "Roads", "Barriers", "Infrastructure", "Vegetation", "Coastal", "LandUse", "Anchors"]
const WALL_SINK_M: float = 0.3
const WIRE_SAG_RATIO: float = 0.015
const WIRE_SEGMENTS: int = 8
const CONTRACT_KEYS: Array[String] = ["feature_id", "feature_class", "source_geometry_hash", "source_dataset", "source_epoch",
	"reconstruction_class", "confidence", "override_state", "authoring_state", "regen_action"]
const MESH_FLAGS: int = Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES

var stats: Dictionary = {}
var _mat: Dictionary = {}
var _crown_mesh: SphereMesh
var _trunk_mesh: CylinderMesh
var _pole_mesh: CylinderMesh
var _prop_mesh: CylinderMesh
var _batches: Dictionary = {}
var _collision_faces: PackedVector3Array = PackedVector3Array()
var _collision_ranges: Array = []
var _footprints: Array = []


func _init() -> void:
	_mat["walls"] = _material(Color(0.86, 0.83, 0.76))
	_mat["walls_placeholder"] = _material(Color(0.85, 0.30, 0.30))
	_mat["roof_lidar"] = _material(Color(0.58, 0.40, 0.33))
	_mat["roof_flat"] = _material(Color(0.62, 0.62, 0.64))
	_mat["roof_placeholder"] = _material(Color(0.85, 0.30, 0.30))
	_mat["road"] = _material(Color(0.25, 0.25, 0.27))
	_mat["path"] = _material(Color(0.55, 0.53, 0.50))
	_mat["deck"] = _material(Color(0.50, 0.42, 0.33))
	_mat["barrier"] = _material(Color(0.45, 0.42, 0.38), true)
	_mat["hedge"] = _material(Color(0.24, 0.40, 0.22), true)
	_mat["pole"] = _material(Color(0.33, 0.27, 0.21))
	_mat["wire"] = _material(Color(0.08, 0.08, 0.08), true)
	_mat["crown"] = _material(Color(0.20, 0.44, 0.22))
	_mat["trunk"] = _material(Color(0.36, 0.28, 0.20))
	_mat["canopy"] = _material(Color(0.18, 0.38, 0.20))
	_mat["water"] = _material(Color(0.20, 0.38, 0.52), true)
	_mat["prop"] = _material(Color(0.70, 0.62, 0.20))
	_mat["terrain"] = _material(Color(1, 1, 1))
	(_mat["terrain"] as StandardMaterial3D).vertex_color_use_as_albedo = true
	_crown_mesh = SphereMesh.new()
	_crown_mesh.radius = 1.0
	_crown_mesh.height = 1.0
	_crown_mesh.radial_segments = 8
	_crown_mesh.rings = 4
	_crown_mesh.material = _mat["crown"]
	_trunk_mesh = _cylinder(0.12, 0.18, 1.0, _mat["trunk"])
	_pole_mesh = _cylinder(0.12, 0.16, 1.0, _mat["pole"])
	_prop_mesh = _cylinder(0.15, 0.15, 1.0, _mat["prop"])


## Builds the chunk tree. terrain_dir holds the .f32 tiles named in the JSON.
func build(doc: Dictionary, terrain_dir: String) -> Node3D:
	stats = {}
	_batches = {}
	_collision_faces = PackedVector3Array()
	_collision_ranges = []
	_footprints = []
	var parts: PackedStringArray = String(doc["chunk_id"]).split(":")
	var root: Node3D = Node3D.new()
	root.name = "Chunk_%s_%s" % [parts[0], parts[1]]
	for key: String in ["chunk_id", "fidelity", "generator_version", "exported_at", "library", "library_sha256", "frame"]:
		root.set_meta(key, doc.get(key))
	root.set_meta("builder_version", GENERATOR_VERSION)
	root.set_meta("corridors", doc.get("corridors", []))
	var groups: Dictionary = {}
	for group_name: String in GROUPS:
		var group: Node3D = Node3D.new()
		group.name = group_name
		root.add_child(group)
		groups[group_name] = group
	var terrain: Node3D = _terrain(doc, terrain_dir)
	if terrain != null:
		(groups["Terrain"] as Node3D).add_child(terrain)
	for feature: Dictionary in doc["features"]:
		var node: Node3D = _feature(feature)
		if node == null:
			continue
		_apply_meta(node, feature, doc)
		(groups.get(feature["group"], root) as Node3D).add_child(node)
	for wire: Dictionary in doc.get("wires", []):
		(groups["Infrastructure"] as Node3D).add_child(_wire(wire, doc))
	for custom: Dictionary in doc.get("custom_structures", []):
		(groups["Anchors"] as Node3D).add_child(_custom_marker(custom))
	for anchor: Node3D in _route_anchors(doc):
		(groups["Anchors"] as Node3D).add_child(anchor)
	_flush_batches(groups, doc)
	_flush_collision(groups["Buildings"] as Node3D)
	root.set_meta("snow_footprints", _footprints)
	## StreamingSystem places a chunk root at its centre, so content is stored relative to it.
	var origin: Array = doc["origin_local"]
	var half: float = float(doc["size_m"]) * 0.5
	var centre: Vector3 = Vector3(float(origin[0]) + half, 0.0, float(origin[1]) + half)
	for group: Node3D in groups.values():
		group.position = -centre
	root.set_meta("centre_local", [centre.x, centre.z])
	root.set_meta("placement", "instance at centre_local; children are offset by -centre")
	_set_owner_recursive(root, root)
	return root


func _feature(feature: Dictionary) -> Node3D:
	var action: String = feature["regen_action"]
	var authored: Variant = feature["meta"].get("authored_scene")
	if action in ["keep", "keep_locked", "needs_rebase"] and authored is String and ResourceLoader.exists(authored):
		var scene: Node3D = (load(authored) as PackedScene).instantiate() as Node3D
		scene.name = feature["node_name"]
		var at: Variant = feature["meta"].get("asset_origin_local")
		if at is Array:
			scene.position = Vector3(float(at[0]), float(at[1]), float(at[2]))
		scene.set_meta("authored_asset", authored)
		_count("authored_assets")
		return scene
	if action == "orphaned":
		return null
	var mesh: Dictionary = feature["mesh"]
	match String(mesh.get("kind", "marker")):
		"building":
			return _building(feature, mesh)
		"ribbon":
			return _ribbon(feature, mesh)
		"slab":
			return _slab(feature, mesh, _mat["deck"], true)
		"wall":
			return _wall(feature, mesh)
		"pole":
			return _pole(feature, mesh)
		"tree":
			return _tree(feature, mesh)
		"canopy_mass":
			return _canopy(feature, mesh)
		"water":
			return _slab(feature, mesh, _mat["water"], false)
		"prop":
			return _prop(feature, mesh)
		"none":
			return null
		_:
			return _marker(feature, mesh)


## Walls follow the measured roof edge; roof is the measured surface or a flat cap (surfaces walls/roof).
func _building(feature: Dictionary, m: Dictionary) -> Node3D:
	var rings: Array = m["rings"]
	var tops: Array = m["ring_top_y"]
	var base: float = float(m["base_y"])
	var outer: PackedVector2Array = _points(rings[0])
	var centre: Vector2 = _centroid(outer)
	var origin: Vector3 = Vector3(centre.x, base, centre.y)
	var walls: SurfaceTool = SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r: int in range(rings.size()):
		var ring: PackedVector2Array = _points(rings[r])
		var ring_tops: Array = tops[r]
		var n: int = ring.size()
		if n < 3:
			continue
		var flip: bool = _ring_needs_flip(rings, ring, r == 0)
		for i: int in range(n):
			var j: int = (i + 1) % n
			var a: Vector2 = ring[i] - centre
			var b: Vector2 = ring[j] - centre
			if a.is_equal_approx(b):
				continue
			var side: Vector2 = (b - a).normalized().orthogonal()
			if flip:
				side = -side
			var normal: Vector3 = Vector3(side.x, 0.0, side.y)
			var ta: float = float(ring_tops[i]) - base
			var tb: float = float(ring_tops[j]) - base
			var a0: Vector3 = Vector3(a.x, -WALL_SINK_M, a.y)
			var b0: Vector3 = Vector3(b.x, -WALL_SINK_M, b.y)
			var a1: Vector3 = Vector3(a.x, ta, a.y)
			var b1: Vector3 = Vector3(b.x, tb, b.y)
			_triangle(walls, a0, b0, b1, normal)
			_triangle(walls, a0, b1, a1, normal)
	walls.index()
	var mesh: ArrayMesh = walls.commit(null, MESH_FLAGS)
	var placeholder: bool = String(m["roof_source"]) == "flat_cap_placeholder"
	mesh.surface_set_material(0, _mat["walls_placeholder"] if placeholder else _mat["walls"])
	mesh.surface_set_name(0, "walls")
	var roof: SurfaceTool = SurfaceTool.new()
	roof.begin(Mesh.PRIMITIVE_TRIANGLES)
	var v: Array = m["roof_v"]
	var idx: Array = m["roof_i"]
	for t: int in range(0, idx.size(), 3):
		var p: Array[Vector3] = []
		for k: int in range(3):
			var o: int = int(idx[t + k]) * 3
			p.append(Vector3(float(v[o]), float(v[o + 1]), float(v[o + 2])) - origin)
		var face: Vector3 = (p[1] - p[0]).cross(p[2] - p[0]).normalized()
		if face.y < 0.0:
			face = -face
		_triangle(roof, p[0], p[1], p[2], face)
	roof.index()
	roof.commit(mesh, MESH_FLAGS)
	if mesh.get_surface_count() > 1:
		var roof_mat: Material = _mat["roof_lidar"]
		if String(m["roof_source"]).begins_with("flat_cap"):
			roof_mat = _mat["roof_placeholder"] if placeholder else _mat["roof_flat"]
		mesh.surface_set_material(1, roof_mat)
		mesh.surface_set_name(1, "roof")
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = feature["node_name"]
	instance.mesh = mesh
	instance.position = origin
	instance.set_meta("material_slots", ["walls", "roof"])
	instance.set_meta("roof_source", m["roof_source"])
	if m.has("roof_model"):
		instance.set_meta("roof_model", m["roof_model"])
	instance.set_meta("height_sources", feature.get("height_sources", {}))
	_collect_collision(feature["feature_id"], m, base)
	_count("buildings")
	return instance


func _ribbon(feature: Dictionary, m: Dictionary) -> Node3D:
	var width: float = float(m["width"])
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var origin: Vector3 = Vector3.ZERO
	var first: bool = true
	for part: Dictionary in m["parts"]:
		var pts: PackedVector2Array = _points(part["p"])
		var ys: Array = part["y"]
		if pts.size() < 2:
			continue
		if first:
			origin = Vector3(pts[0].x, float(ys[0]), pts[0].y)
			first = false
		for i: int in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var side: Vector2 = (b - a).normalized().orthogonal() * width * 0.5
			var ya: float = float(ys[i])
			var yb: float = float(ys[i + 1])
			var q0: Vector3 = Vector3(a.x + side.x, ya, a.y + side.y) - origin
			var q1: Vector3 = Vector3(a.x - side.x, ya, a.y - side.y) - origin
			var q2: Vector3 = Vector3(b.x - side.x, yb, b.y - side.y) - origin
			var q3: Vector3 = Vector3(b.x + side.x, yb, b.y + side.y) - origin
			_triangle(st, q0, q1, q2, Vector3.UP)
			_triangle(st, q0, q2, q3, Vector3.UP)
	if first:
		return null
	st.index()
	var mesh: ArrayMesh = st.commit(null, MESH_FLAGS)
	var path_like: bool = String(feature["class"]) in ["footway", "path", "cycleway", "steps", "pedestrian", "track"]
	mesh.surface_set_material(0, _mat["path"] if path_like else _mat["road"])
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = feature["node_name"]
	instance.mesh = mesh
	instance.position = origin
	instance.set_meta("width_m", width)
	instance.set_meta("height_sources", feature.get("height_sources", {}))
	if feature["family"] == "bridges" or "bridge" in feature["attrs"].get("flags", []):
		_add_collision(instance, mesh)
	_count("ribbons")
	return instance


## Flat top at measured height with sides down by thickness (piers, decks, aprons, water).
func _slab(feature: Dictionary, m: Dictionary, material: Material, solid: bool) -> Node3D:
	var top: float = float(m["top_y"])
	var thick: float = float(m.get("thickness", 0.0))
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var origin: Vector3 = Vector3.ZERO
	var have: bool = false
	for poly: Dictionary in m["polys"]:
		var outer: PackedVector2Array = _points(poly["rings"][0])
		if outer.size() > 1 and outer[0].is_equal_approx(outer[outer.size() - 1]):
			outer.remove_at(outer.size() - 1)
		if outer.size() < 3:
			continue
		if not have:
			var c: Vector2 = _centroid(outer)
			origin = Vector3(c.x, top, c.y)
			have = true
		var tris: PackedInt32Array = Geometry2D.triangulate_polygon(outer)
		for i: int in range(0, tris.size(), 3):
			var a: Vector2 = outer[tris[i]]
			var b: Vector2 = outer[tris[i + 1]]
			var c2: Vector2 = outer[tris[i + 2]]
			_triangle(st, Vector3(a.x, top, a.y) - origin, Vector3(b.x, top, b.y) - origin, Vector3(c2.x, top, c2.y) - origin, Vector3.UP)
		if thick > 0.0:
			var flip: bool = _ring_needs_flip([poly["rings"][0]], outer, true)
			for i: int in range(outer.size()):
				var a: Vector2 = outer[i]
				var b: Vector2 = outer[(i + 1) % outer.size()]
				var side: Vector2 = (b - a).normalized().orthogonal() * (-1.0 if flip else 1.0)
				var n: Vector3 = Vector3(side.x, 0.0, side.y)
				var a1: Vector3 = Vector3(a.x, top, a.y) - origin
				var b1: Vector3 = Vector3(b.x, top, b.y) - origin
				var a0: Vector3 = a1 - Vector3(0.0, thick, 0.0)
				var b0: Vector3 = b1 - Vector3(0.0, thick, 0.0)
				_triangle(st, a0, b0, b1, n)
				_triangle(st, a0, b1, a1, n)
	if not have:
		return null
	st.index()
	var mesh: ArrayMesh = st.commit(null, MESH_FLAGS)
	mesh.surface_set_material(0, material)
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = feature["node_name"]
	instance.mesh = mesh
	instance.position = origin
	instance.set_meta("height_sources", feature.get("height_sources", {}))
	if solid:
		_add_collision(instance, mesh)
	_count("slabs")
	return instance


func _wall(feature: Dictionary, m: Dictionary) -> Node3D:
	var height: float = float(m["height"])
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var origin: Vector3 = Vector3.ZERO
	var first: bool = true
	for part: Dictionary in m["parts"]:
		var pts: PackedVector2Array = _points(part["p"])
		var ys: Array = part["y"]
		for i: int in range(pts.size() - 1):
			var a: Vector3 = Vector3(pts[i].x, float(ys[i]), pts[i].y)
			var b: Vector3 = Vector3(pts[i + 1].x, float(ys[i + 1]), pts[i + 1].y)
			if first:
				origin = a
				first = false
			var side: Vector2 = (pts[i + 1] - pts[i]).normalized().orthogonal()
			var n: Vector3 = Vector3(side.x, 0.0, side.y)
			var up: Vector3 = Vector3(0.0, height, 0.0)
			_triangle(st, a - origin, b - origin, b + up - origin, n)
			_triangle(st, a - origin, b + up - origin, a + up - origin, n)
	if first:
		return null
	st.index()
	var mesh: ArrayMesh = st.commit(null, MESH_FLAGS)
	mesh.surface_set_material(0, _mat["hedge"] if feature["class"] == "hedge" else _mat["barrier"])
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = feature["node_name"]
	instance.mesh = mesh
	instance.position = origin
	instance.set_meta("height_sources", feature.get("height_sources", {}))
	instance.set_meta("presentation_height_m", height)
	_count("walls")
	return instance


func _pole(feature: Dictionary, m: Dictionary) -> Node3D:
	var p: Array = m["p"]
	var top: float = float(m["top_y"])
	var xf: Transform3D = Transform3D(Basis.from_scale(Vector3(1.0, top, 1.0)), Vector3(float(p[0]), float(m["base_y"]) + top * 0.5, float(p[1])))
	_batch(feature, "Poles", _pole_mesh, xf, true)
	_count("poles")
	return null


## Catenary-like sag between two measured pole tops; one node per topology edge.
func _wire(wire: Dictionary, doc: Dictionary) -> Node3D:
	var a: Vector3 = _vec3(wire["a"])
	var b: Vector3 = _vec3(wire["b"])
	var sag: float = a.distance_to(b) * WIRE_SAG_RATIO
	var im: ArrayMesh = ArrayMesh.new()
	var verts: PackedVector3Array = PackedVector3Array()
	for i: int in range(WIRE_SEGMENTS):
		for k: int in [i, i + 1]:
			var t: float = float(k) / float(WIRE_SEGMENTS)
			verts.append(a.lerp(b, t) - Vector3(0.0, sag * 4.0 * t * (1.0 - t), 0.0) - a)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	im.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	im.surface_set_material(0, _mat["wire"])
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = "KW_WIRE_" + String(wire["edge_id"]).replace(":", "_").replace("#", "_")
	instance.mesh = im
	instance.position = a
	for key: String in ["edge_id", "from", "to", "line"]:
		instance.set_meta(key, wire[key])
	instance.set_meta("feature_id", wire["line"])
	instance.set_meta("feature_class", "power_wire")
	instance.set_meta("reconstruction_class", "derived")
	instance.set_meta("presentation", "sag 1.5 % of span (inferred); endpoints = lidar-measured pole tops")
	instance.set_meta("generator_version", GENERATOR_VERSION)
	instance.set_meta("generated_at", doc["exported_at"])
	_count("wires")
	return instance


func _tree(feature: Dictionary, m: Dictionary) -> Node3D:
	var p: Array = m["p"]
	var h: float = float(m["height"])
	var r: float = float(m["crown_radius"])
	var base: Vector3 = Vector3(float(p[0]), float(m["base_y"]), float(p[1]))
	var crown_h: float = maxf(h * 0.55, 1.5)
	_batch(feature, "TreeCrowns", _crown_mesh, Transform3D(Basis.from_scale(Vector3(r, crown_h, r)), base + Vector3(0.0, h - crown_h * 0.5, 0.0)), true)
	_batch(feature, "TreeTrunks", _trunk_mesh, Transform3D(Basis.from_scale(Vector3(1.0, h * 0.6, 1.0)), base + Vector3(0.0, h * 0.3, 0.0)), false)
	_count("trees")
	return null


func _canopy(feature: Dictionary, m: Dictionary) -> Node3D:
	var node: Node3D = _slab(feature, {"top_y": m["top_y"], "thickness": float(m["top_y"]) - float(m["base_y"]), "polys": m["polys"]},
		_mat["canopy"], false)
	if node != null:
		node.set_meta("presentation", "canopy_mass_proxy: measured canopy top, crowns not separated")
		_count("canopy_masses")
	return node


func _prop(feature: Dictionary, m: Dictionary) -> Node3D:
	var p: Array = m["p"]
	var h: float = float(m["height"])
	var xf: Transform3D = Transform3D(Basis.from_scale(Vector3(1.0, h, 1.0)), Vector3(float(p[0]), float(m["base_y"]) + h * 0.5, float(p[1])))
	_batch(feature, "Props", _prop_mesh, xf, true)
	_count("props")
	return null


func _marker(feature: Dictionary, m: Dictionary) -> Node3D:
	var marker: Marker3D = Marker3D.new()
	marker.name = feature["node_name"]
	var p: Array = m.get("p", [0.0, 0.0])
	marker.position = Vector3(float(p[0]), float(m.get("base_y", 0.0)), float(p[1]))
	_count("markers")
	return marker


func _custom_marker(custom: Dictionary) -> Node3D:
	var marker: Marker3D = Marker3D.new()
	marker.name = "Custom_" + String(custom["override_id"]).get_slice(":", custom["override_id"].count(":"))
	marker.position = Vector3(float(custom["local_xz"][0]), 0.0, float(custom["local_xz"][1]))
	marker.set_meta("override_id", custom["override_id"])
	marker.set_meta("params", custom["params"])
	marker.set_meta("reconstruction_class", "manual_override")
	return marker


## Route anchors (owner decision #211) that fall inside this chunk, as named markers.
func _route_anchors(doc: Dictionary) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var origin: Array = doc["origin_local"]
	var size: float = float(doc["size_m"])
	var names: Array[String] = ["Start", "Shelter"]
	for corridor: Dictionary in doc.get("anchors", []):
		var points: Array = corridor["points"]
		for i: int in range(points.size()):
			var x: float = float(points[i][0])
			var z: float = float(points[i][1])
			if x < float(origin[0]) or x >= float(origin[0]) + size or z < float(origin[1]) or z >= float(origin[1]) + size:
				continue
			var marker: Marker3D = Marker3D.new()
			marker.name = "%s_%s" % [String(corridor["name"]).to_pascal_case(), names[mini(i, 1)]]
			marker.position = Vector3(x, 0.0, z)
			marker.gizmo_extents = 6.0
			marker.set_meta("corridor", corridor["name"])
			marker.set_meta("source", "owner decision #211; docs/world/KEY_WEST_FIRST_EXIT.md")
			out.append(marker)
	return out


## Terrain tile from the DEM (measured), with HeightMapShape3D collision.
func _terrain(doc: Dictionary, terrain_dir: String) -> Node3D:
	var info: Dictionary = doc.get("terrain", {})
	if info.is_empty():
		return null
	var path: String = terrain_dir.path_join(info["file"])
	if not FileAccess.file_exists(path):
		return null
	var n: int = int(info["n"])
	var step: float = float(info["step_m"])
	var heights: PackedFloat32Array = FileAccess.get_file_as_bytes(path).to_float32_array()
	if heights.size() != n * n:
		push_error("terrain tile %s has %d samples, expected %d" % [path, heights.size(), n * n])
		return null
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colours: PackedColorArray = PackedColorArray()
	verts.resize(n * n)
	normals.resize(n * n)
	colours.resize(n * n)
	for row: int in range(n):
		for col: int in range(n):
			var k: int = row * n + col
			var y: float = heights[k]
			verts[k] = Vector3(col * step, y, row * step)
			var hl: float = heights[row * n + maxi(col - 1, 0)]
			var hr: float = heights[row * n + mini(col + 1, n - 1)]
			var hu: float = heights[maxi(row - 1, 0) * n + col]
			var hd: float = heights[mini(row + 1, n - 1) * n + col]
			normals[k] = Vector3(hl - hr, 2.0 * step, hu - hd).normalized()
			colours[k] = _terrain_colour(y)
	var indices: PackedInt32Array = PackedInt32Array()
	indices.resize((n - 1) * (n - 1) * 6)
	var w: int = 0
	for row: int in range(n - 1):
		for col: int in range(n - 1):
			var i0: int = row * n + col
			var i1: int = i0 + 1
			var i2: int = i0 + n
			var i3: int = i2 + 1
			indices[w] = i0
			indices[w + 1] = i1
			indices[w + 2] = i2
			indices[w + 3] = i1
			indices[w + 4] = i3
			indices[w + 5] = i2
			w += 6
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, MESH_FLAGS)
	mesh.surface_set_material(0, _mat["terrain"])
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = "Terrain_" + String(doc["chunk_id"]).replace(":", "_")
	instance.mesh = mesh
	var origin: Array = doc["origin_local"]
	instance.position = Vector3(float(origin[0]), 0.0, float(origin[1]))
	instance.set_meta("source", info["source"])
	instance.set_meta("reconstruction_class", info["recon"])
	instance.set_meta("step_m", step)
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Collision"
	var shape: CollisionShape3D = CollisionShape3D.new()
	var hm: HeightMapShape3D = HeightMapShape3D.new()
	hm.map_width = n
	hm.map_depth = n
	hm.map_data = heights
	shape.shape = hm
	shape.scale = Vector3(step, 1.0, step)
	shape.position = Vector3((n - 1) * step * 0.5, 0.0, (n - 1) * step * 0.5)
	body.add_child(shape)
	instance.add_child(body)
	_count("terrain_tiles")
	return instance


func _terrain_colour(y: float) -> Color:
	if y < -0.265:
		return Color(0.40, 0.55, 0.62).darkened(clampf(-y / 8.0, 0.0, 0.6))
	if y < 0.4:
		return Color(0.70, 0.66, 0.52)
	return Color(0.48, 0.55, 0.38).lerp(Color(0.58, 0.55, 0.46), clampf((y - 0.4) / 4.0, 0.0, 1.0))


## Copies the Reality Library metadata contract onto the node (docs/world/KEY_WEST_REALITY_LIBRARY.md §10).
func _apply_meta(node: Node3D, feature: Dictionary, doc: Dictionary) -> void:
	var meta: Dictionary = feature["meta"]
	for key: String in meta.keys():
		if meta[key] != null:
			node.set_meta(key, meta[key])
	node.set_meta("generator_version", GENERATOR_VERSION)
	node.set_meta("generated_at", doc["exported_at"])
	node.set_meta("regen_action", feature["regen_action"])
	node.set_meta("fidelity", feature.get("fidelity", "default"))
	if not feature["overrides"].is_empty():
		node.set_meta("override_ids", feature["overrides"].map(func(o: Dictionary) -> String: return o["override_id"]))


## Point features of one mesh kind share a MultiMesh; per-instance provenance sits in parallel arrays.
func _batch(feature: Dictionary, kind: String, mesh: Mesh, xf: Transform3D, carries_meta: bool) -> void:
	var key: String = "%s/%s" % [feature["group"], kind]
	if not _batches.has(key):
		_batches[key] = {"group": feature["group"], "kind": kind, "mesh": mesh, "xf": [], "meta": {}, "carries_meta": carries_meta}
	var b: Dictionary = _batches[key]
	(b["xf"] as Array).append(xf)
	if carries_meta:
		var meta: Dictionary = feature["meta"]
		for k: String in CONTRACT_KEYS:
			var v: Variant = feature["regen_action"] if k == "regen_action" else meta.get(k)
			var values: PackedStringArray = (b["meta"] as Dictionary).get(k, PackedStringArray())
			values.append("" if v == null else str(v))
			b["meta"][k] = values  # packed arrays are values: write the grown copy back


func _flush_batches(groups: Dictionary, doc: Dictionary) -> void:
	for key: String in _batches.keys():
		var b: Dictionary = _batches[key]
		var mm: MultiMesh = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = b["mesh"]
		var xfs: Array = b["xf"]
		mm.instance_count = xfs.size()
		for i: int in range(xfs.size()):
			mm.set_instance_transform(i, xfs[i])
		var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
		node.name = "KW_" + String(b["kind"])
		node.multimesh = mm
		node.set_meta("generator_version", GENERATOR_VERSION)
		node.set_meta("generated_at", doc["exported_at"])
		node.set_meta("instance_count", xfs.size())
		if b["carries_meta"]:
			for k: String in (b["meta"] as Dictionary).keys():
				node.set_meta("instance_" + k, b["meta"][k])
		else:
			node.set_meta("instances_of", "KW_TreeCrowns")
		(groups.get(b["group"], groups["Infrastructure"]) as Node3D).add_child(node)


## Building collision is a prism on the source outline up to the median eave, merged per chunk;
## face_ranges maps faces back to features. Render triangles would cost ~8x more to build.
func _collect_collision(feature_id: String, m: Dictionary, base: float) -> void:
	var col: Dictionary = m.get("collision", {})
	var ring: PackedVector2Array = _points(col.get("ring", []))
	if ring.size() < 3:
		return
	var top: float = float(col["top_y"])
	var y0: float = base - WALL_SINK_M
	_footprints.append(ring)
	var start: int = _collision_faces.size() / 3
	for i: int in range(ring.size()):
		var a: Vector2 = ring[i]
		var b: Vector2 = ring[(i + 1) % ring.size()]
		var a0: Vector3 = Vector3(a.x, y0, a.y)
		var b0: Vector3 = Vector3(b.x, y0, b.y)
		var a1: Vector3 = Vector3(a.x, top, a.y)
		var b1: Vector3 = Vector3(b.x, top, b.y)
		_collision_faces.append_array([a0, b0, b1, a0, b1, a1])
	var tris: PackedInt32Array = Geometry2D.triangulate_polygon(ring)
	for k: int in range(tris.size()):
		var p: Vector2 = ring[tris[k]]
		_collision_faces.append(Vector3(p.x, top, p.y))
	_collision_ranges.append([start, feature_id])


func _flush_collision(group: Node3D) -> void:
	if _collision_faces.is_empty():
		return
	var shape: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
	shape.set_faces(_collision_faces)
	shape.backface_collision = true  # prism winding is not normalised per ring
	var col: CollisionShape3D = CollisionShape3D.new()
	col.name = "Shape"
	col.shape = shape
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "BuildingCollision"
	body.set_meta("face_ranges", _collision_ranges)
	body.add_child(col)
	group.add_child(body)


func _add_collision(instance: MeshInstance3D, mesh: ArrayMesh) -> void:
	var shape: ConcavePolygonShape3D = mesh.create_trimesh_shape()
	if shape == null:
		return
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Collision"
	var col: CollisionShape3D = CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	instance.add_child(body)


## Adds a triangle whose front face (Godot: clockwise seen from the front) points along n.
func _triangle(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, n: Vector3) -> void:
	if (v2 - v0).cross(v1 - v0).dot(n) < 0.0:
		var t: Vector3 = v1
		v1 = v2
		v2 = t
	for v: Vector3 in [v0, v1, v2]:
		st.set_normal(n)
		st.add_vertex(v)


## True when an edge's left-hand normal points into the solid; decided once per ring.
func _ring_needs_flip(rings: Array, ring: PackedVector2Array, _is_outer: bool) -> bool:
	for i: int in range(ring.size()):
		var a: Vector2 = ring[i]
		var b: Vector2 = ring[(i + 1) % ring.size()]
		if a.distance_to(b) < 0.05:
			continue
		var probe: Vector2 = (a + b) * 0.5 + (b - a).normalized().orthogonal() * 0.05
		return _inside(rings, probe)
	return false


func _inside(rings: Array, p: Vector2) -> bool:
	var inside: bool = false
	for ring_data: Array in rings:
		if Geometry2D.is_point_in_polygon(p, _points(ring_data)):
			inside = not inside
	return inside


func _points(flat: Array) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for i: int in range(0, flat.size() - 1, 2):
		out.append(Vector2(float(flat[i]), float(flat[i + 1])))
	return out


func _vec3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func _centroid(ring: PackedVector2Array) -> Vector2:
	var sum: Vector2 = Vector2.ZERO
	for p: Vector2 in ring:
		sum += p
	return sum / float(maxi(ring.size(), 1))


func _material(colour: Color, double_sided: bool = false) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 0.9
	if double_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _cylinder(top: float, bottom: float, height: float, material: Material) -> CylinderMesh:
	var c: CylinderMesh = CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = 6
	c.material = material
	return c


func _set_owner_recursive(node: Node, owner: Node) -> void:
	for child: Node in node.get_children():
		child.owner = owner
		_set_owner_recursive(child, owner)


func _count(key: String) -> void:
	stats[key] = int(stats.get(key, 0)) + 1
