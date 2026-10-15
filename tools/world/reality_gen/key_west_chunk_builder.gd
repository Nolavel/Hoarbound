class_name KeyWestChunkBuilder
extends RefCounted
## Builds one Reality Library chunk (editor interchange JSON v2) into a Node3D tree with meshes,
## collision and the per-node metadata contract. Editor-time only; never used at runtime.

const GENERATOR_VERSION: String = "kw_chunk_builder.12"
const GROUPS: Array[String] = ["Terrain", "Buildings", "Roads", "Barriers", "Infrastructure", "Vegetation", "Coastal", "LandUse", "Winter", "Anchors"]
const WALL_SINK_M: float = 0.3
const WIRE_SAG_RATIO: float = 0.015
const WIRE_SEGMENTS: int = 8
const CONTRACT_KEYS: Array[String] = ["feature_id", "feature_class", "source_geometry_hash", "source_dataset", "source_epoch",
	"reconstruction_class", "confidence", "override_state", "authoring_state", "regen_action"]
const MESH_FLAGS: int = Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
const TERRAIN_SHADER: Shader = preload("res://shaders/environment/terrain/island_terrain.gdshader")
## Lidar crowns narrower than this share of the tree height read as palms (no species in the data).
const PALM_CROWN_RATIO: float = 0.35
## Shrub stems lean downwind of the profile's prevailing wind (bearing it blows from).
const WIND_PROFILE: String = "res://data/world_profiles/key_west_reality.tres"
const STEM_LEAN_DEG: float = 12.0
## Stems ride up with the drawn snow so they always poke out (shader reads the snow field).
const STEM_SHADER: Shader = preload("res://shaders/environment/vegetation/snow_stems.gdshader")
const FROZEN_SEA_SHADER: Shader = preload("res://shaders/environment/ice/frozen_sea.gdshader")
const FRAME_PATH: String = "res://data/world/key_west/reality/config/frame.json"
## The terrain's ice sheet sits this far under the mapped water polygons (MSL), so they draw on top.
const ICE_UNDER_WATER_M: float = 0.03
## Far view: terrain every this many tile samples (16 m on the 1 m DEM tile).
const FAR_TERRAIN_STRIDE: int = 16
## Static snow (data layer "winter"): the dynamic fresh-snow colour, so caps and ground match.
const STATIC_SNOW_COLOR: Color = Color(0.8, 0.83, 0.88)
## Snow on a wire this wide (cable plus crust) and on a pole top this wide.
const WIRE_SNOW_HALF_M: float = 0.02
const POLE_SNOW_RADIUS_M: float = 0.16
## Facade windows on generated buildings: a common sash window, its sill, the spacing along a wall,
## and how far the pane stands off the wall. Storeys come from the footprint's levels, else from the
## measured wall height at STOREY_M each.
const WINDOW_SIZE_M: Vector2 = Vector2(1.0, 1.4)
const WINDOW_SILL_M: float = 0.9
const WINDOW_PITCH_M: float = 3.2
const WINDOW_OFFSET_M: float = 0.04
const WINDOW_EAVE_GAP_M: float = 0.25
const STOREY_M: float = 3.2
## Measured outlines step in ~1 m edges; points within this of a straight run belong to one facade.
const FACADE_TOLERANCE_M: float = 0.35
## Frost on the windows of a building with nothing inside it covers the whole pane.
const EMPTY_HOUSE_FROST: float = 1.0
const FROSTED_WINDOW_SHADER: Shader = preload("res://shaders/environment/windows/frosted_window.gdshader")
## Winter dressing is not drawn past this distance; the far mesh carries no caps.
const WINTER_VISIBLE_M: float = 450.0
## HLOD v1 (docs/technical/REALITY_HLOD.md): chunks listed here move their generated buildings into cluster cells.
const HLOD_CONFIG_PATH: String = "res://data/world/key_west/reality/config/hlod.json"
const CHUNK_M: float = 512.0

var stats: Dictionary = {}
var _mat: Dictionary = {}
var _pole_mesh: CylinderMesh
var _prop_mesh: CylinderMesh
var _palm_mesh: ArrayMesh
var _stem_mesh: ArrayMesh
## Terrain tile of the chunk being built: point features stand on the surface the player sees.
var _tile: Dictionary = {}
var _downwind: Vector3 = Vector3.BACK
var _bare_mesh: ArrayMesh
var _bare_aabb: AABB
var _batches: Dictionary = {}
var _collision_faces: PackedVector3Array = PackedVector3Array()
var _collision_ranges: Array = []
var _footprints: Array = []
var _centre: Vector3 = Vector3.ZERO
var _snow: Dictionary = {}  # settled_depth_m, repose_deg from the export (config static_snow)
var _winter: Dictionary = {}  # "roofs" | "fences" | "wires" -> [PackedVector3Array, PackedColorArray, PackedInt32Array]
var _pole_tops: Array[Vector3] = []
## Cluster cells of the chunk just built (HLOD chunks only): cluster id -> root, saved as their own scenes.
var clusters: Dictionary = {}
var _hlod: bool = false
var _cur: String = ""  # cluster id of the feature being built, "" for the chunk itself
var _cluster_collision: Dictionary = {}  # cluster id -> [faces, ranges]
static var _hlod_config_cache: Dictionary = {}


func _init() -> void:
	_mat["walls"] = _material(Color(0.86, 0.83, 0.76))
	_mat["walls_placeholder"] = _material(Color(0.85, 0.30, 0.30))
	## Far prisms skip per-ring winding; both faces draw.
	_mat["far_walls"] = _material(Color(0.86, 0.83, 0.76), true)
	_mat["roof_lidar"] = _material(Color(0.58, 0.40, 0.33))
	_mat["roof_flat"] = _material(Color(0.62, 0.62, 0.64))
	_mat["roof_placeholder"] = _material(Color(0.85, 0.30, 0.30))
	_mat["road"] = _paved(Color(0.25, 0.25, 0.27))
	_mat["path"] = _paved(Color(0.55, 0.53, 0.50))
	_mat["deck"] = _material(Color(0.50, 0.42, 0.33))
	_mat["barrier"] = _material(Color(0.45, 0.42, 0.38), true)
	_mat["hedge"] = _material(Color(0.24, 0.40, 0.22), true)
	_mat["pole"] = _material(Color(0.33, 0.27, 0.21))
	_mat["wire"] = _material(Color(0.08, 0.08, 0.08), true)
	var windows: ShaderMaterial = ShaderMaterial.new()
	windows.shader = FROSTED_WINDOW_SHADER
	_mat["windows"] = windows
	_mat["static_snow"] = _material(STATIC_SNOW_COLOR, true)
	_mat["static_snow"].set_shader_parameter(&"use_vertex_color", true)
	_mat["canopy"] = _material(Color(0.18, 0.38, 0.20))
	_mat["stem"] = _material(Color(0.33, 0.27, 0.21))
	(_mat["stem"] as ShaderMaterial).shader = STEM_SHADER
	## Sea, ponds and pools are frozen: the existing frozen-sea surface, without the legacy mask.
	var ice: ShaderMaterial = ShaderMaterial.new()
	ice.shader = FROZEN_SEA_SHADER
	ice.set_shader_parameter(&"use_ocean_mask", false)
	_mat["water"] = ice
	_mat["prop"] = _material(Color(0.70, 0.62, 0.20))
	var terrain: ShaderMaterial = ShaderMaterial.new()
	terrain.shader = TERRAIN_SHADER
	var frame: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FRAME_PATH))
	terrain.set_shader_parameter(&"under_ice", true)
	terrain.set_shader_parameter(&"ice_level_m", float(frame["vertical"]["tidal_datums_navd88_m"]["MSL"]) - ICE_UNDER_WATER_M)
	_mat["terrain"] = terrain
	## The legacy city's own procedural palms and winter-bare broadleaf trees.
	var props: Dictionary = WinterTreeMeshes.materials()
	_palm_mesh = WinterTreeMeshes.palm(props)
	_bare_mesh = WinterTreeMeshes.bare_tree(props)
	_bare_aabb = _bare_mesh.get_aabb()
	_pole_mesh = _cylinder(0.12, 0.16, 1.0, _mat["pole"])
	_prop_mesh = _cylinder(0.15, 0.15, 1.0, _mat["prop"])
	_stem_mesh = _stem_clump_mesh(_mat["stem"])
	var profile: Resource = load(WIND_PROFILE)
	var from_deg: float = float(profile.get("wind_direction_override_deg")) if profile != null else -1.0
	if from_deg >= 0.0:
		var to_rad: float = deg_to_rad(from_deg + 180.0)
		_downwind = Vector3(sin(to_rad), 0.0, -cos(to_rad))  # local frame: +x east, +z south


## Builds the chunk tree. terrain_dir holds the .f32 tiles named in the JSON.
func build(doc: Dictionary, terrain_dir: String) -> Node3D:
	stats = {}
	_batches = {}
	_tile = {}
	_collision_faces = PackedVector3Array()
	_collision_ranges = []
	_footprints = []
	_winter = {}
	_pole_tops = []
	clusters = {}
	_cluster_collision = {}
	_snow = doc.get("static_snow", {})
	_hlod = (hlod_config().get("chunks", []) as Array).has(String(doc["chunk_id"]))
	var parts: PackedStringArray = String(doc["chunk_id"]).split(":")
	var root: Node3D = Node3D.new()
	root.name = "Chunk_%s_%s" % [parts[0], parts[1]]
	for key: String in ["chunk_id", "fidelity", "generator_version", "exported_at", "library", "library_sha256", "frame"]:
		root.set_meta(key, doc.get(key))
	root.set_meta("builder_version", GENERATOR_VERSION)
	root.set_meta("corridors", doc.get("corridors", []))
	## StreamingSystem places a chunk root at its centre, so content is stored relative to it.
	var origin: Array = doc["origin_local"]
	var half: float = float(doc["size_m"]) * 0.5
	var centre: Vector3 = Vector3(float(origin[0]) + half, 0.0, float(origin[1]) + half)
	_centre = centre
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
		_cur = cluster_of_feature(doc, feature) if _hlod else ""
		if _cur != "":
			_swap_collision(_cur)
		var node: Node3D = _feature(feature)
		if _cur != "":
			_swap_collision(_cur)
		if node == null:
			continue
		_apply_meta(node, feature, doc)
		if _cur != "":
			(_cluster_root(_cur, doc).get_node(^"Buildings") as Node3D).add_child(node)
		else:
			(groups.get(feature["group"], root) as Node3D).add_child(node)
	_cur = ""
	for wire: Dictionary in doc.get("wires", []):
		(groups["Infrastructure"] as Node3D).add_child(_wire(wire, doc))
	for custom: Dictionary in doc.get("custom_structures", []):
		(groups["Anchors"] as Node3D).add_child(_custom_marker(custom))
	for anchor: Node3D in _route_anchors(doc):
		(groups["Anchors"] as Node3D).add_child(anchor)
	_flush_batches(groups, doc)
	_flush_collision(groups["Buildings"] as Node3D)
	_flush_winter(groups["Winter"] as Node3D)
	_flush_clusters()
	root.set_meta("snow_footprints", _footprints)
	if _hlod:
		var ids: Array = clusters.keys()
		ids.sort()
		root.set_meta("hlod_clusters", ids)
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
		## The asset brings its own collision; its outline still keeps runtime snow out of it.
		var ring: PackedVector2Array = _points(feature["mesh"].get("collision", {}).get("ring", []))
		if ring.size() >= 3:
			_footprints.append(ring)
		_count("authored_assets")
		return scene
	if action == "orphaned":
		return null
	var mesh: Dictionary = feature["mesh"]
	match String(mesh.get("kind", "marker")):
		"building":
			if mesh.has("snow_cap"):
				_add_roof_cap(mesh["snow_cap"])
			return _building(feature, mesh)
		"ribbon":
			return _ribbon(feature, mesh)
		"slab":
			return _slab(feature, mesh, _mat["deck"], true)
		"drape":
			return _drape(feature, mesh)
		"wall":
			_add_fence_snow(mesh)
			return _wall(feature, mesh)
		"pole":
			return _pole(feature, mesh)
		"tree":
			return _tree(feature, mesh)
		"stems":
			return _stems(feature, mesh)
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
	var placeholder: bool = String(m["roof_source"]) == "flat_cap_placeholder"
	var panes: SurfaceTool = SurfaceTool.new()
	panes.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pane_count: int = 0
	var levels: int = int(feature.get("attrs", {}).get("levels", 0))
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
		if r == 0 and not placeholder:
			for f: Array in _facades(ring, ring_tops, flip):
				pane_count += _window_row(panes, f[0] - centre, f[1] - centre, float(f[2]) - base, f[3], levels,
					"%s|%d" % [feature["feature_id"], f[4]])
	walls.index()
	var mesh: ArrayMesh = walls.commit(null, MESH_FLAGS)
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
	var slots: Array[String] = ["walls", "roof"]
	if pane_count > 0:
		panes.index()
		panes.commit(mesh, MESH_FLAGS)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _mat["windows"])
		mesh.surface_set_name(mesh.get_surface_count() - 1, "windows")
		slots.append("windows")
		_count("windows", pane_count)
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = feature["node_name"]
	instance.mesh = mesh
	instance.position = origin
	instance.set_meta("material_slots", slots)
	instance.set_meta("roof_source", m["roof_source"])
	if m.has("roof_model"):
		instance.set_meta("roof_model", m["roof_model"])
	instance.set_meta("height_sources", feature.get("height_sources", {}))
	_collect_collision(feature["feature_id"], m, base)
	_count("buildings")
	return instance


## Straight facades of a closed outline: [a, b, lowest wall top, outward normal, start index] each.
## Consecutive points stay in one facade while they keep within FACADE_TOLERANCE_M of its line.
func _facades(ring: PackedVector2Array, tops: Array, flip: bool) -> Array:
	var n: int = ring.size()
	var start: int = 0
	var sharpest: float = 2.0
	for i: int in range(n):
		var d0: Vector2 = (ring[i] - ring[(i - 1 + n) % n]).normalized()
		var d1: Vector2 = (ring[(i + 1) % n] - ring[i]).normalized()
		if d0.dot(d1) < sharpest:
			sharpest = d0.dot(d1)
			start = i
	var out: Array = []
	var anchor: int = 0
	while anchor < n:
		var end: int = anchor + 1
		while end + 1 <= n and _straight(ring, start, anchor, end + 1):
			end += 1
		var a: Vector2 = ring[(start + anchor) % n]
		var b: Vector2 = ring[(start + end) % n]
		var low: float = INF
		for k: int in range(anchor, end + 1):
			low = minf(low, float(tops[(start + k) % n]))
		var side: Vector2 = (b - a).normalized().orthogonal()
		if flip:
			side = -side
		if not a.is_equal_approx(b):
			out.append([a, b, low, Vector3(side.x, 0.0, side.y), (start + anchor) % n])
		anchor = end
	return out


## True when every outline point between from and to (offsets past start) lies near their chord.
func _straight(ring: PackedVector2Array, start: int, from: int, to: int) -> bool:
	var n: int = ring.size()
	var a: Vector2 = ring[(start + from) % n]
	var b: Vector2 = ring[(start + to) % n]
	for k: int in range(from + 1, to):
		var p: Vector2 = ring[(start + k) % n]
		if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) > FACADE_TOLERANCE_M:
			return false
	return true


## One row of panes per storey along a wall from a to b (building-local plan points), standing
## WINDOW_OFFSET_M off the wall. Returns how many panes it added.
func _window_row(st: SurfaceTool, a: Vector2, b: Vector2, wall_top: float, normal: Vector3, levels: int, seed_key: String) -> int:
	var length: float = a.distance_to(b)
	if length < WINDOW_SIZE_M.x + 1.0:
		return 0
	var storeys: int = levels if levels > 0 else maxi(1, int(floor(wall_top / STOREY_M)))
	var storey_h: float = wall_top / float(storeys)
	var columns: int = maxi(1, int(floor((length - 0.8) / WINDOW_PITCH_M)))
	var along: Vector2 = (b - a) / length
	var off: Vector3 = normal * WINDOW_OFFSET_M
	var half: Vector3 = Vector3(along.x, 0.0, along.y) * WINDOW_SIZE_M.x * 0.5
	var added: int = 0
	for storey: int in range(storeys):
		var y0: float = storey * storey_h + minf(WINDOW_SILL_M, storey_h * 0.3)
		var y1: float = y0 + minf(WINDOW_SIZE_M.y, storey_h * 0.5)
		if y1 > wall_top - WINDOW_EAVE_GAP_M:
			break
		for c: int in range(columns):
			var p: Vector2 = a + (b - a) * ((float(c) + 0.5) / float(columns))
			var centre: Vector3 = Vector3(p.x, 0.0, p.y) + off
			var seed: float = float(absi(hash("%s|%d|%d" % [seed_key, storey, c])) % 1000) / 1000.0
			var col: Color = Color(EMPTY_HOUSE_FROST, seed, 0.0)
			var q: Array[Vector3] = [centre - half + Vector3.UP * y0, centre + half + Vector3.UP * y0,
				centre + half + Vector3.UP * y1, centre - half + Vector3.UP * y1]
			var uv: Array[Vector2] = [Vector2(0.0, 1.0), Vector2(1.0, 1.0), Vector2(1.0, 0.0), Vector2(0.0, 0.0)]
			for tri: Array in [[0, 1, 2], [0, 2, 3]]:
				if (q[tri[2]] - q[tri[0]]).cross(q[tri[1]] - q[tri[0]]).dot(normal) < 0.0:
					tri = [tri[0], tri[2], tri[1]]  # front face toward the street, as _triangle winds walls
				for k: int in tri:
					st.set_color(col)
					st.set_uv(uv[k])
					st.set_normal(normal)
					st.add_vertex(q[k])
			added += 1
	return added


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
		var rings: Array = poly["rings"]
		var outer: PackedVector2Array = _open_ring(rings[0])
		if outer.size() < 3:
			continue
		if not have:
			var c: Vector2 = _centroid(outer)
			origin = Vector3(c.x, top, c.y)
			have = true
		for piece: PackedVector2Array in fill_pieces(rings):
			var tris: PackedInt32Array = Geometry2D.triangulate_polygon(piece)
			for i: int in range(0, tris.size(), 3):
				var a: Vector2 = piece[tris[i]]
				var b: Vector2 = piece[tris[i + 1]]
				var c2: Vector2 = piece[tris[i + 2]]
				_triangle(st, Vector3(a.x, top, a.y) - origin, Vector3(b.x, top, b.y) - origin, Vector3(c2.x, top, c2.y) - origin, Vector3.UP)
		if thick <= 0.0:
			continue
		for r: int in range(rings.size()):
			var ring: PackedVector2Array = _open_ring(rings[r])
			if ring.size() < 3:
				continue
			var flip: bool = _ring_needs_flip(rings, ring, r == 0)
			for i: int in range(ring.size()):
				var a: Vector2 = ring[i]
				var b: Vector2 = ring[(i + 1) % ring.size()]
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


## Parking and apron paving draped on the DEM (exporter triangulation); no collision, the
## terrain under it carries Henry.
func _drape(feature: Dictionary, m: Dictionary) -> Node3D:
	var v: Array = m["v"]
	var idx: Array = m["i"]
	if idx.is_empty():
		return null
	var origin: Vector3 = Vector3(float(v[0]), float(v[1]), float(v[2]))
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t: int in range(0, idx.size(), 3):
		var p: Array[Vector3] = []
		for k: int in range(3):
			var o: int = int(idx[t + k]) * 3
			p.append(Vector3(float(v[o]), float(v[o + 1]), float(v[o + 2])) - origin)
		_triangle(st, p[0], p[1], p[2], _up_normal(p[0], p[1], p[2]))
	st.index()
	var mesh: ArrayMesh = st.commit(null, MESH_FLAGS)
	mesh.surface_set_material(0, _mat["road"])
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = feature["node_name"]
	instance.mesh = mesh
	instance.position = origin
	instance.set_meta("height_sources", feature.get("height_sources", {}))
	_count("drapes")
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
	_batch(feature, "Poles", _pole_mesh, xf)
	_pole_tops.append(Vector3(float(p[0]), float(m["base_y"]) + top, float(p[1])))
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
	var line: PackedVector3Array = PackedVector3Array()
	for k: int in range(WIRE_SEGMENTS + 1):
		var t: float = float(k) / float(WIRE_SEGMENTS)
		line.append(a.lerp(b, t) - Vector3(0.0, sag * 4.0 * t * (1.0 - t), 0.0))
	_add_ridge("wires", line, WIRE_SNOW_HALF_M)
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
	var base: Vector3 = Vector3(float(p[0]), _ground(float(p[0]), float(p[1]), float(m["base_y"])), float(p[1]))
	var yaw: float = float(abs(hash(String(feature["feature_id"]))) % 628) * 0.01
	if r < h * PALM_CROWN_RATIO:
		var s: float = h / WinterTreeMeshes.PALM_BASE_HEIGHT_M
		_batch(feature, "Palms", _palm_mesh, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), base))
		_count("palms")
	else:
		var reach: float = maxf(maxf(_bare_aabb.size.x, _bare_aabb.size.z) * 0.5, 0.1)
		var xz: float = r / reach
		var basis: Basis = Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(xz, h / maxf(_bare_aabb.end.y, 0.1), xz))
		_batch(feature, "BareTrees", _bare_mesh, Transform3D(basis, base))
		_count("bare_trees")
	_count("trees")
	return null


## Frozen-out shrub: one clump per exported point, batched; scale comes from the export.
func _stems(feature: Dictionary, m: Dictionary) -> Node3D:
	var p: Array = m["p"]
	var ys: Array = m["y"]
	var scales: Array = m["s"]
	var axis: Vector3 = Vector3.UP.cross(_downwind).normalized()
	for k: int in range(ys.size()):
		var yaw: float = float(abs(hash("%s:%d" % [feature["feature_id"], k])) % 628) * 0.01
		var sc: float = float(scales[k])
		var basis: Basis = Basis(axis, deg_to_rad(STEM_LEAN_DEG)) * Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc)
		var x: float = float(p[2 * k])
		var z: float = float(p[2 * k + 1])
		_batch(feature, "Stems", _stem_mesh, Transform3D(basis, Vector3(x, _ground(x, z, float(ys[k])), z)))
		_count("stem_clumps")
	return null


## A clump of thin dead stems about 1 m tall, a few with a side twig (fixed shape; yaw varies).
func _stem_clump_mesh(material: Material) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stems: Array = [[0.0, 0.0, 1.0, 0.0], [0.09, 1.3, 0.78, 0.16], [0.07, 2.6, 0.62, -0.12], [0.11, 3.9, 0.9, 0.2],
		[0.05, 5.0, 0.5, -0.18], [0.12, 5.9, 0.7, 0.1]]
	for stem: Array in stems:
		var base: Vector3 = Vector3(cos(stem[1]), 0.0, sin(stem[1])) * float(stem[0])
		var tip: Vector3 = base + Vector3(cos(stem[1]) * float(stem[3]), float(stem[2]), sin(stem[1]) * float(stem[3]))
		_stick(st, base - Vector3(0.0, 0.25, 0.0), tip, 0.018, 0.004)
		if float(stem[2]) > 0.7:
			var fork: Vector3 = base.lerp(tip, 0.6)
			_stick(st, fork, fork + Vector3(-sin(stem[1]) * 0.18, 0.2, cos(stem[1]) * 0.18), 0.008, 0.003)
	st.index()
	var mesh: ArrayMesh = st.commit(null, MESH_FLAGS)
	mesh.surface_set_material(0, material)
	return mesh


## Tapered three-sided stick from a to b.
func _stick(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float) -> void:
	var dir: Vector3 = (b - a).normalized()
	var side: Vector3 = dir.cross(Vector3.RIGHT if absf(dir.x) < 0.9 else Vector3.FORWARD).normalized()
	for i: int in range(3):
		var a0: float = TAU * i / 3.0
		var a1: float = TAU * (i + 1) / 3.0
		var o0: Vector3 = side.rotated(dir, a0)
		var o1: Vector3 = side.rotated(dir, a1)
		var n: Vector3 = (o0 + o1).normalized()
		_triangle(st, a + o0 * r0, a + o1 * r0, b + o1 * r1, n)
		_triangle(st, a + o0 * r0, b + o1 * r1, b + o0 * r1, n)


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
	_batch(feature, "Props", _prop_mesh, xf)
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
	var tile_origin: Array = doc["origin_local"]
	_tile = {"h": heights, "n": n, "step": step, "ox": float(tile_origin[0]), "oz": float(tile_origin[1])}
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
	shape.name = "Shape"
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


## Far view of the chunk just built: its terrain tile every FAR_TERRAIN_STRIDE samples and each
## building's collision prism (outline to median eave), relative to the chunk centre. No collision.
func far_mesh(doc: Dictionary) -> ArrayMesh:
	var origin: Array = doc["origin_local"]
	var half: float = float(doc["size_m"]) * 0.5
	var centre: Vector3 = Vector3(float(origin[0]) + half, 0.0, float(origin[1]) + half)
	var mesh: ArrayMesh = ArrayMesh.new()
	if not _tile.is_empty():
		var st: SurfaceTool = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var n: int = int(_tile["n"])
		var step: float = float(_tile["step"])
		var heights: PackedFloat32Array = _tile["h"]
		var cols: Array[int] = []
		for i: int in range(0, n, FAR_TERRAIN_STRIDE):
			cols.append(i)
		if cols[-1] != n - 1:
			cols.append(n - 1)
		var at: Callable = func(r: int, c: int) -> Vector3:
			return Vector3(float(_tile["ox"]) + c * step, heights[r * n + c], float(_tile["oz"]) + r * step) - centre
		for a: int in range(cols.size() - 1):
			for b: int in range(cols.size() - 1):
				var p00: Vector3 = at.call(cols[a], cols[b])
				var p01: Vector3 = at.call(cols[a], cols[b + 1])
				var p10: Vector3 = at.call(cols[a + 1], cols[b])
				var p11: Vector3 = at.call(cols[a + 1], cols[b + 1])
				_triangle(st, p00, p01, p10, _up_normal(p00, p01, p10))
				_triangle(st, p01, p11, p10, _up_normal(p01, p11, p10))
		st.index()
		st.commit(mesh, MESH_FLAGS)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _mat["terrain"])
	var walls: SurfaceTool = SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any: bool = false
	for feature: Dictionary in doc["features"]:
		var m: Dictionary = feature.get("mesh", {})
		if m.get("kind", "") != "building" or not m.has("collision"):
			continue
		var col: Dictionary = m["collision"]
		var rings: Array = [col["ring"]]
		rings.append_array(col.get("holes", []))
		var top: float = float(col["top_y"])
		var y0: float = float(m["base_y"]) - WALL_SINK_M
		for flat: Array in rings:
			var r: PackedVector2Array = _open_ring(flat)
			for i: int in range(r.size()):
				var a2: Vector2 = r[i]
				var b2: Vector2 = r[(i + 1) % r.size()]
				var side: Vector2 = (b2 - a2).normalized().orthogonal()
				var nrm: Vector3 = Vector3(side.x, 0.0, side.y)
				var a0: Vector3 = Vector3(a2.x, y0, a2.y) - centre
				var b0: Vector3 = Vector3(b2.x, y0, b2.y) - centre
				_triangle(walls, a0, b0, b0 + Vector3.UP * (top - y0), nrm)
				_triangle(walls, a0, b0 + Vector3.UP * (top - y0), a0 + Vector3.UP * (top - y0), nrm)
		for piece: PackedVector2Array in fill_pieces(rings):
			var tris: PackedInt32Array = Geometry2D.triangulate_polygon(piece)
			for k: int in range(0, tris.size(), 3):
				var q: Array[Vector3] = []
				for j: int in range(3):
					q.append(Vector3(piece[tris[k + j]].x, top, piece[tris[k + j]].y) - centre)
				_triangle(walls, q[0], q[1], q[2], Vector3.UP)
		any = true
	if any:
		walls.index()
		walls.commit(mesh, MESH_FLAGS)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _mat["far_walls"])
	return mesh


static func _up_normal(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var n: Vector3 = (b - a).cross(c - a).normalized()
	return -n if n.y < 0.0 else n


## Bilinear height of the chunk's terrain tile (fallback when the point lies off the tile).
func _ground(x: float, z: float, fallback: float) -> float:
	if _tile.is_empty():
		return fallback
	var n: int = _tile["n"]
	var step: float = _tile["step"]
	var fx: float = (x - float(_tile["ox"])) / step
	var fz: float = (z - float(_tile["oz"])) / step
	if fx < 0.0 or fz < 0.0 or fx > n - 1 or fz > n - 1:
		return fallback
	var cx: int = mini(int(fx), n - 2)
	var cz: int = mini(int(fz), n - 2)
	var h: PackedFloat32Array = _tile["h"]
	var top: float = lerpf(h[cz * n + cx], h[cz * n + cx + 1], fx - cx)
	var bottom: float = lerpf(h[(cz + 1) * n + cx], h[(cz + 1) * n + cx + 1], fx - cx)
	return lerpf(top, bottom, fz - cz)


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
func _batch(feature: Dictionary, kind: String, mesh: Mesh, xf: Transform3D) -> void:
	var key: String = "%s/%s" % [feature["group"], kind]
	if not _batches.has(key):
		_batches[key] = {"group": feature["group"], "kind": kind, "mesh": mesh, "xf": [], "meta": {}}
	var b: Dictionary = _batches[key]
	(b["xf"] as Array).append(xf)
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
		for k: String in (b["meta"] as Dictionary).keys():
			node.set_meta("instance_" + k, b["meta"][k])
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
	var rings: Array = [col["ring"]]
	rings.append_array(col.get("holes", []))
	for flat: Array in rings:
		var r: PackedVector2Array = _open_ring(flat)
		for i: int in range(r.size()):
			var a: Vector2 = r[i]
			var b: Vector2 = r[(i + 1) % r.size()]
			var a0: Vector3 = Vector3(a.x, y0, a.y)
			var b0: Vector3 = Vector3(b.x, y0, b.y)
			var a1: Vector3 = Vector3(a.x, top, a.y)
			var b1: Vector3 = Vector3(b.x, top, b.y)
			_collision_faces.append_array([a0, b0, b1, a0, b1, a1])
	for piece: PackedVector2Array in fill_pieces(rings):
		var tris: PackedInt32Array = Geometry2D.triangulate_polygon(piece)
		for k: int in range(tris.size()):
			var p: Vector2 = piece[tris[k]]
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
	col.name = "Shape"
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


## Simple pieces covering a polygon with holes (rings[0] outer, the rest holes). Godot's ear
## clipper takes no holes, so a vertical cut through each hole splits it before Clipper subtracts it.
static func fill_pieces(rings: Array) -> Array[PackedVector2Array]:
	var outer: PackedVector2Array = _open_ring(rings[0])
	var holes: Array[PackedVector2Array] = []
	for k: int in range(1, rings.size()):
		var hole: PackedVector2Array = _open_ring(rings[k])
		if hole.size() >= 3:
			holes.append(hole)
	if holes.is_empty():
		return [outer]
	var box: Rect2 = Rect2(outer[0], Vector2.ZERO)
	for p: Vector2 in outer:
		box = box.expand(p)
	box = box.grow(1.0)
	var xs: Array[float] = [box.position.x, box.end.x]
	for hole: PackedVector2Array in holes:
		xs.append(_centroid(hole).x)
	xs.sort()
	var out: Array[PackedVector2Array] = []
	for i: int in range(xs.size() - 1):
		if xs[i + 1] - xs[i] < 0.001:
			continue
		var strip: PackedVector2Array = PackedVector2Array([Vector2(xs[i], box.position.y), Vector2(xs[i + 1], box.position.y),
			Vector2(xs[i + 1], box.end.y), Vector2(xs[i], box.end.y)])
		var pieces: Array[PackedVector2Array] = Geometry2D.intersect_polygons(outer, strip)
		for hole: PackedVector2Array in holes:
			var next: Array[PackedVector2Array] = []
			for piece: PackedVector2Array in pieces:
				next.append_array(Geometry2D.clip_polygons(piece, hole))
			pieces = next
		out.append_array(pieces)
	return out


static func _open_ring(flat: Array) -> PackedVector2Array:
	var ring: PackedVector2Array = PackedVector2Array()
	for i: int in range(0, flat.size() - 1, 2):
		ring.append(Vector2(float(flat[i]), float(flat[i + 1])))
	if ring.size() > 1 and ring[0].is_equal_approx(ring[ring.size() - 1]):
		ring.remove_at(ring.size() - 1)
	return ring


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


static func _points(flat: Array) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for i: int in range(0, flat.size() - 1, 2):
		out.append(Vector2(float(flat[i]), float(flat[i + 1])))
	return out


func _vec3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func _centroid(ring: PackedVector2Array) -> Vector2:
	var sum: Vector2 = Vector2.ZERO
	for p: Vector2 in ring:
		sum += p
	return sum / float(maxi(ring.size(), 1))


## The legacy city's stylized environment material (stylized shadows), not a StandardMaterial3D.
## Paving takes snow exactly as the terrain does (island_terrain paved mode), never shows through it.
func _paved(colour: Color) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = TERRAIN_SHADER
	material.set_shader_parameter(&"paved", true)
	material.set_shader_parameter(&"paved_color", colour)
	return material


func _material(colour: Color, double_sided: bool = false) -> ShaderMaterial:
	return StylizedEnvironmentMaterial.make_static(colour, 0.9, double_sided)


func _cylinder(top: float, bottom: float, height: float, material: Material) -> CylinderMesh:
	var c: CylinderMesh = CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = 6
	c.material = material
	return c


## Instanced landmark scenes keep their own internals; owning them would save a second copy.
func _set_owner_recursive(node: Node, owner: Node) -> void:
	for child: Node in node.get_children():
		child.owner = owner
		if child.scene_file_path == "":
			_set_owner_recursive(child, owner)


func _count(key: String, by: int = 1) -> void:
	stats[key] = int(stats.get(key, 0)) + by


## Roof cap from the export (static_snow.py): absolute vertices, shade per vertex, indices.
func _add_roof_cap(cap: Dictionary) -> void:
	var v: Array = cap["v"]
	var shades: Array = cap["c"]
	var key: String = "roofs" if _cur == "" else "roofs|" + _cur
	var bucket: Array = _winter.get_or_add(key, [PackedVector3Array(), PackedColorArray(), PackedInt32Array()])
	## Packed arrays are values: grow local copies and write them back.
	var verts: PackedVector3Array = bucket[0]
	var colors: PackedColorArray = bucket[1]
	var indices: PackedInt32Array = bucket[2]
	var base: int = verts.size()
	for k: int in range(shades.size()):
		verts.append(Vector3(float(v[3 * k]), float(v[3 * k + 1]), float(v[3 * k + 2])) - _centre)
		var g: float = float(shades[k])
		colors.append(Color(g, g, g))
	for idx: Variant in cap["i"]:
		indices.append(base + int(idx))
	_winter[key] = [verts, colors, indices]


## A snow ridge along the top of a fence or wall, as wide as the wall plus a crust.
func _add_fence_snow(m: Dictionary) -> void:
	var height: float = float(m["height"])
	var half_w: float = float(m.get("thickness", 0.2)) * 0.5 + WIRE_SNOW_HALF_M
	for part: Dictionary in m["parts"]:
		var pts: PackedVector2Array = _points(part["p"])
		var ys: Array = part["y"]
		var line: PackedVector3Array = PackedVector3Array()
		for i: int in range(pts.size()):
			line.append(Vector3(pts[i].x, float(ys[i]) + height, pts[i].y))
		_add_ridge("fences", line, half_w)


## Snow lying on a narrow top: a ridge whose height the repose angle sets, capped at the settled depth.
func _add_ridge(kind: String, line: PackedVector3Array, half_w: float) -> void:
	if line.size() < 2:
		return
	var rise: float = minf(float(_snow.get("settled_depth_m", 0.25)), half_w * tan(deg_to_rad(float(_snow.get("repose_deg", 50.0)))))
	var bucket: Array = _winter.get_or_add(kind, [PackedVector3Array(), PackedColorArray(), PackedInt32Array()])
	var verts: PackedVector3Array = bucket[0]
	var colors: PackedColorArray = bucket[1]
	var indices: PackedInt32Array = bucket[2]
	for i: int in range(line.size() - 1):
		var a: Vector3 = line[i] - _centre
		var b: Vector3 = line[i + 1] - _centre
		var along: Vector3 = Vector3(b.x - a.x, 0.0, b.z - a.z)
		if along.length() < 0.01:
			continue
		var side: Vector3 = along.normalized().cross(Vector3.UP) * half_w
		var base: int = verts.size()
		for p: Vector3 in [a - side, a + Vector3.UP * rise, a + side, b - side, b + Vector3.UP * rise, b + side]:
			verts.append(p)
			colors.append(Color(1.0, 1.0, 1.0))
		## Each flank faces out and up; Godot draws clockwise triangles as front faces.
		for tri: Array in [[0, 4, 1, -1.0], [0, 3, 4, -1.0], [1, 5, 2, 1.0], [1, 4, 5, 1.0]]:
			var out: Vector3 = side * float(tri[3]) + Vector3.UP * half_w
			var ids: Array = [base + int(tri[0]), base + int(tri[1]), base + int(tri[2])]
			if (verts[ids[1]] - verts[ids[0]]).cross(verts[ids[2]] - verts[ids[0]]).dot(out) > 0.0:
				ids = [ids[0], ids[2], ids[1]]
			for k: int in ids:
				indices.append(k)
	_winter[kind] = [verts, colors, indices]


## Winter group: one mesh per kind of static snow and one MultiMesh of pole caps, drawn near only.
func _flush_winter(group: Node3D) -> void:
	for kind: String in ["roofs", "fences", "wires"]:
		_add_snow_mesh(group, kind, kind)
	if _pole_tops.is_empty():
		return
	var cap: SphereMesh = SphereMesh.new()
	cap.radius = POLE_SNOW_RADIUS_M
	cap.height = POLE_SNOW_RADIUS_M * 2.0
	cap.is_hemisphere = true
	cap.radial_segments = 8
	cap.rings = 2
	cap.material = _mat["static_snow"]
	var rise: float = minf(float(_snow.get("settled_depth_m", 0.25)), POLE_SNOW_RADIUS_M * tan(deg_to_rad(float(_snow.get("repose_deg", 50.0)))))
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cap
	mm.instance_count = _pole_tops.size()
	for k: int in range(_pole_tops.size()):
		mm.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3(1.0, rise / POLE_SNOW_RADIUS_M, 1.0)), _pole_tops[k] - _centre))
	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	node.name = "WinterSnow_Poles"
	node.multimesh = mm
	node.position = _centre
	_winter_meta(node, "poles")
	node.set_meta("instances_of", "Poles")
	group.add_child(node)


## One static snow mesh from the bucket under key, if it has triangles.
func _add_snow_mesh(group: Node3D, key: String, kind: String) -> void:
	if not _winter.has(key) or (_winter[key][2] as PackedInt32Array).is_empty():
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _winter[key][0]
	arrays[Mesh.ARRAY_COLOR] = _winter[key][1]
	arrays[Mesh.ARRAY_INDEX] = _winter[key][2]
	var st: SurfaceTool = SurfaceTool.new()
	st.create_from_arrays(arrays)
	st.generate_normals()
	var mesh: ArrayMesh = st.commit(null, MESH_FLAGS)
	mesh.surface_set_material(0, _mat["static_snow"])
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = "WinterSnow_" + kind.capitalize()
	instance.mesh = mesh
	instance.position = _centre
	_winter_meta(instance, kind)
	group.add_child(instance)
	_count("winter_" + kind + "_triangles", (_winter[key][2] as PackedInt32Array).size() / 3)


func _winter_meta(node: GeometryInstance3D, kind: String) -> void:
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if kind != "roofs" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	## In HLOD chunks thin snow (wires, fences, poles) ends where the buildings hand over to their proxies.
	node.visibility_range_end = detail_band_m() if _hlod and kind != "roofs" else WINTER_VISIBLE_M
	node.set_meta("data_layer", "winter")
	node.set_meta("presentation", "static snow, %s; never deformed, never read by the dynamic snow" % kind)
	node.set_meta("generator_version", GENERATOR_VERSION)


## HLOD settings (config/hlod.json), read once per process.
static func hlod_config() -> Dictionary:
	if _hlod_config_cache.is_empty() and FileAccess.file_exists(HLOD_CONFIG_PATH):
		_hlod_config_cache = JSON.parse_string(FileAccess.get_file_as_string(HLOD_CONFIG_PATH))
	return _hlod_config_cache


## Distance from a cluster centre at which the streamer brings its detail in: cluster radius + load margin.
static func detail_band_m() -> float:
	var cfg: Dictionary = hlod_config()
	return float(cfg.get("cluster_m", 128)) * sqrt(2.0) * 0.5 + float(cfg.get("streamer_load_margin_m", 140))


static func cluster_id_of(cell: Vector2i) -> String:
	return "c%d_%d_%d" % [int(hlod_config().get("cluster_m", 128)), cell.x, cell.y]


## Cluster cell id of a feature that goes to HLOD clusters, or "" when it stays in its chunk.
## Generated buildings only; the cell holds the footprint centroid, clamped into the owning chunk.
static func cluster_of_feature(doc: Dictionary, feature: Dictionary) -> String:
	if not is_hlod_source(feature):
		return ""
	var c: Vector2 = _centroid(_points(feature["mesh"]["rings"][0]))
	var size: float = float(hlod_config().get("cluster_m", 128))
	var per: int = int(CHUNK_M / size)
	var origin: Array = doc["origin_local"]
	var ox: int = roundi(float(origin[0]) / size)
	var oz: int = roundi(float(origin[1]) / size)
	return cluster_id_of(Vector2i(clampi(floori(c.x / size), ox, ox + per - 1), clampi(floori(c.y / size), oz, oz + per - 1)))


## HLOD v1 sources: generated static opaque buildings. Authored, orphaned and kept features stay Tier 0.
static func is_hlod_source(feature: Dictionary) -> bool:
	return String(feature["mesh"].get("kind", "")) == "building" and String(feature["regen_action"]) == "generate"


## Centre of a cluster cell in local metres (y 0), from its id.
static func cluster_centre(cluster_id: String) -> Vector3:
	var p: PackedStringArray = cluster_id.split("_")
	var size: float = float(p[0].trim_prefix("c"))
	return Vector3((float(p[1]) + 0.5) * size, 0.0, (float(p[2]) + 0.5) * size)


## Swaps the collision accumulators between the chunk and a cluster (called around each cluster feature).
func _swap_collision(cluster_id: String) -> void:
	var held: Array = _cluster_collision.get(cluster_id, [PackedVector3Array(), []])
	_cluster_collision[cluster_id] = [_collision_faces, _collision_ranges]
	_collision_faces = held[0]
	_collision_ranges = held[1]


func _cluster_root(cluster_id: String, doc: Dictionary) -> Node3D:
	if clusters.has(cluster_id):
		return clusters[cluster_id]
	var root: Node3D = Node3D.new()
	root.name = "Cluster_" + cluster_id
	var centre: Vector3 = cluster_centre(cluster_id)
	for key: String in ["chunk_id", "library_sha256"]:
		root.set_meta(key, doc.get(key))
	root.set_meta("cluster_id", cluster_id)
	root.set_meta("builder_version", GENERATOR_VERSION)
	root.set_meta("hlod_build_version", hlod_config().get("build_version", ""))
	root.set_meta("tier", 0)
	root.set_meta("centre_local", [centre.x, centre.z])
	root.set_meta("placement", "instance at centre_local; children are offset by -centre")
	for group_name: String in ["Buildings", "Winter"]:
		var group: Node3D = Node3D.new()
		group.name = group_name
		group.position = -centre
		root.add_child(group)
	clusters[cluster_id] = root
	return root


## Collision and roof snow of each cluster go into its own root; owners are set for saving.
func _flush_clusters() -> void:
	var ids: Array = clusters.keys()
	ids.sort()
	for cluster_id: String in ids:
		var root: Node3D = clusters[cluster_id]
		var held: Array = _cluster_collision.get(cluster_id, [PackedVector3Array(), []])
		var chunk_faces: PackedVector3Array = _collision_faces
		var chunk_ranges: Array = _collision_ranges
		_collision_faces = held[0]
		_collision_ranges = held[1]
		_flush_collision(root.get_node(^"Buildings") as Node3D)
		_collision_faces = chunk_faces
		_collision_ranges = chunk_ranges
		_add_snow_mesh(root.get_node(^"Winter") as Node3D, "roofs|" + cluster_id, "roofs")
		var members: PackedStringArray = PackedStringArray()
		for node: Node in root.get_node(^"Buildings").get_children():
			if node.has_meta("feature_id"):
				members.append(String(node.get_meta("feature_id")))
		members.sort()
		root.set_meta("source_ids", members)
		_set_owner_recursive(root, root)
