class_name KeyWestStreetProps
extends RefCounted
## Mapped street furniture and trees for Key West as simple instanced models.
## Positions come from Overture/OSM; each prop faces its nearest road.

## Collision shapes per city chunk id, filled by build() and the barrier builder.
static var colliders: Dictionary = {}
## Small props per city chunk id, shown only while that chunk streams in.
static var visuals: Dictionary = {}
## Terrain-following crossing meshes keyed by the same streamed city chunks.
static var crossings: Dictionary = {}

const CHUNK_SIZE_M: float = 512.0
## Faded paint of abandoned cars and moored boats.
const CAR_COLORS: Array[Color] = [
	Color(0.55, 0.12, 0.1), Color(0.16, 0.22, 0.35), Color(0.75, 0.75, 0.72),
	Color(0.2, 0.2, 0.21), Color(0.42, 0.44, 0.45), Color(0.3, 0.38, 0.3), Color(0.65, 0.58, 0.42),
]
const BOAT_COLORS: Array[Color] = [
	Color(0.9, 0.9, 0.88), Color(0.85, 0.86, 0.84), Color(0.2, 0.3, 0.45), Color(0.6, 0.15, 0.12),
]
const LANDSCAPE_PATH: String = "res://data/world/key_west/landscape.json"
const ROAD_CELL_M: float = 40.0
const ROAD_SEARCH_M: float = 25.0
const TREE_ROW_SPACING_M: float = 7.0
const WOOD_SPACING_M: float = 12.0
const SCRUB_SPACING_M: float = 5.0
const CROSSING_LENGTH_M: float = 3.0
const PALM_BASE_HEIGHT_M: float = 9.0
const CAR_BAY_M: Vector2 = Vector2(3.0, 6.5)
## Share of parking bays holding an abandoned car.
const CAR_FILL: float = 0.18
const MAX_CARS: int = 500
const BOAT_SPACING_M: float = 7.0
const BOAT_FILL: float = 0.6
## Marinas reach piers this far outside their mapped outline.
const MARINA_REACH_M: float = 25.0
const TOMB_SPACING_M: float = 4.5
## Wire height above ground for mapped power and distribution lines.
const POWER_LINE_M: float = 12.5
const MINOR_LINE_M: float = 8.3


## Builds every prop layer; returns an empty node when there is no data.
static func build(terrain: IslandTerrain, enrichment: Dictionary, roads: Array) -> Node3D:
	var holder := Node3D.new()
	holder.name = "StreetProps"
	var index: Dictionary = index_roads(roads)
	var mats: Dictionary = _materials()
	var points: Dictionary = {}
	for feature: Dictionary in enrichment.get("infrastructure", []):
		var geometry: Dictionary = feature.get("geometry", {})
		if String(geometry.get("type", "")) != "Point":
			continue
		var c: Array = geometry.get("coordinates", [])
		var kind: String = String(feature.get("class", ""))
		if not points.has(kind):
			points[kind] = []
		(points[kind] as Array).append(Vector2(float(c[0]), float(c[1])))
	for feature: Dictionary in enrichment.get("supplemental", []):
		var geometry: Dictionary = feature.get("geometry", {})
		var kind: String = String(feature.get("kind", ""))
		if String(geometry.get("type", "")) != "Point" or not kind in ["street_lamp", "power:pole"]:
			continue
		var c: Array = geometry.get("coordinates", [])
		var key: String = "osm_lamp" if kind == "street_lamp" else "osm_pole"
		if not points.has(key):
			points[key] = []
		(points[key] as Array).append(Vector2(float(c[0]), float(c[1])))

	var pole := _cyl_shape(0.15, 8.0)
	_add_facing(holder, "PowerPoles", points.get("osm_pole", []), _power_pole_mesh(mats), index, terrain, false, [pole, Vector3(0, 4.0, 0)])
	_add_facing(holder, "StreetLamps", points.get("osm_lamp", []), _lamp_mesh(mats), index, terrain, true, [_cyl_shape(0.1, 6.0), Vector3(0, 3.0, 0)])
	_add_facing(holder, "TrafficSignals", points.get("traffic_signals", []), _signal_mesh(mats), index, terrain, true, [_cyl_shape(0.15, 5.0), Vector3(0, 2.5, 0)])
	var post := [_cyl_shape(0.06, 2.2), Vector3(0, 1.1, 0)]
	_add_facing(holder, "StopSigns", points.get("stop", []), _stop_mesh(mats), index, terrain, true, post)
	var bench := [_box_shape(Vector3(1.8, 0.9, 0.5)), Vector3(0, 0.45, 0)]
	_add_facing(holder, "BusStops", points.get("bus_stop", []), _bus_stop_mesh(mats), index, terrain, true, bench)
	_add_facing(holder, "Benches", points.get("bench", []), _bench_mesh(mats), index, terrain, true, bench)
	var low := [_cyl_shape(0.28, 0.9), Vector3(0, 0.45, 0)]
	_add_facing(holder, "WasteBaskets", points.get("waste_basket", []), _basket_mesh(mats), index, terrain, true, low)
	_add_facing(holder, "FireHydrants", points.get("fire_hydrant", []), _hydrant_mesh(mats), index, terrain, true, [_cyl_shape(0.18, 0.8), Vector3(0, 0.4, 0)])
	_add_facing(holder, "Bollards", points.get("bollard", []), _bollard_mesh(mats), index, terrain, false, [_cyl_shape(0.1, 1.0), Vector3(0, 0.5, 0)])
	_add_facing(holder, "PostBoxes", points.get("post_box", []), _post_box_mesh(mats), index, terrain, true, [_box_shape(Vector3(0.55, 1.2, 0.55)), Vector3(0, 0.6, 0)])
	_add_crossings(holder, points.get("crossing", []), index, terrain)
	var gate := [_box_shape(Vector3(0.3, 1.4, 3.4)), Vector3(0, 0.7, 0)]
	_add_facing(holder, "Gates", points.get("gate", []) + points.get("swing_gate", []), _gate_mesh(mats), index, terrain, true, gate)
	_add_facing(holder, "LiftGates", points.get("lift_gate", []), _lift_gate_mesh(mats), index, terrain, true, [_cyl_shape(0.15, 1.1), Vector3(0, 0.55, 0)])
	_add_parking(holder, enrichment, terrain, mats)
	_add_wires(holder, enrichment, terrain, mats)
	_add_tanks(holder, enrichment, terrain, mats)
	_add_vegetation(holder, index, terrain, mats)
	return holder


## Buckets road segments into a coarse grid for nearest-road queries.
static func index_roads(roads: Array) -> Dictionary:
	var cells: Dictionary = {}
	for road: Dictionary in roads:
		var pts: Array = road.get("points", [])
		var width: float = float(road.get("width", 6.0))
		for i: int in range(pts.size() - 1):
			var a := Vector2(float(pts[i][0]), float(pts[i][1]))
			var b := Vector2(float(pts[i + 1][0]), float(pts[i + 1][1]))
			var lo := Vector2i((a.min(b) / ROAD_CELL_M).floor())
			var hi := Vector2i((a.max(b) / ROAD_CELL_M).floor())
			for x: int in range(lo.x, hi.x + 1):
				for y: int in range(lo.y, hi.y + 1):
					var key := Vector2i(x, y)
					if not cells.has(key):
						cells[key] = []
					(cells[key] as Array).append([a, b, width])
	return cells


## Nearest road segment: {point, dir, dist, width}, or empty when none is near.
static func nearest_road(index: Dictionary, p: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = ROAD_SEARCH_M
	var c := Vector2i((p / ROAD_CELL_M).floor())
	for x: int in range(c.x - 1, c.x + 2):
		for y: int in range(c.y - 1, c.y + 2):
			for seg: Array in index.get(Vector2i(x, y), []):
				var a: Vector2 = seg[0]
				var b: Vector2 = seg[1]
				var q: Vector2 = Geometry2D.get_closest_point_to_segment(p, a, b)
				var d: float = p.distance_to(q)
				if d < best_d and a.distance_to(b) > 0.01:
					best_d = d
					best = {"point": q, "dir": (b - a).normalized(), "dist": d, "width": float(seg[2])}
	return best


## Places a prop at each point; its local +Z looks at the nearest road.
static func _add_facing(parent: Node3D, node_name: String, pts: Array, mesh: Mesh, index: Dictionary,
		terrain: IslandTerrain, face_road: bool, collider: Array = []) -> void:
	if pts.is_empty():
		return
	var xfs: Array[Transform3D] = []
	for i: int in range(pts.size()):
		var p: Vector2 = pts[i]
		var yaw: float = float(hash(p) % 628) * 0.01
		var road: Dictionary = nearest_road(index, p)
		if face_road and not road.is_empty():
			var to_road: Vector2 = road["point"] - p
			if to_road.length() < 0.3:
				## Sits on the centreline: face across the road instead.
				var d: Vector2 = road["dir"]
				to_road = Vector2(-d.y, d.x)
			yaw = atan2(to_road.x, to_road.y)
		elif not road.is_empty():
			var d: Vector2 = road["dir"]
			yaw = atan2(d.x, d.y)
		xfs.append(Transform3D(Basis(Vector3.UP, yaw), _ground(terrain, p)))
	_add_transforms(parent, node_name, mesh, xfs)
	if not collider.is_empty():
		_add_bodies(parent, node_name + "Collision", collider[0], collider[1], xfs)


## Zebra stripes across the road at each mapped crossing.
static func _add_crossings(_parent: Node3D, pts: Array, index: Dictionary, terrain: IslandTerrain) -> void:
	var chunk_geometry: Dictionary = {}
	for p: Vector2 in pts:
		var road: Dictionary = nearest_road(index, p)
		if road.is_empty() or float(road["dist"]) > 3.0:
			continue
		var dir: Vector2 = road["dir"]
		var side := Vector2(-dir.y, dir.x)
		var centre: Vector2 = road["point"]
		var key: String = chunk_key(centre)
		if not chunk_geometry.has(key):
			chunk_geometry[key] = [PackedVector3Array(), PackedVector3Array(), PackedInt32Array()]
		var geometry: Array = chunk_geometry[key]
		var v: PackedVector3Array = geometry[0]
		var n: PackedVector3Array = geometry[1]
		var ind: PackedInt32Array = geometry[2]
		var half: float = maxf(float(road["width"]) * 0.5 - 0.4, 1.5)
		var s: float = -half
		while s < half:
			var at: Vector2 = centre + side * (s + 0.25)
			KeyWestCityVisuals._append_ribbon(v, n, ind, at - dir * CROSSING_LENGTH_M * 0.5, at + dir * CROSSING_LENGTH_M * 0.5, 0.25, 0.4, terrain)
			s += 1.0
		geometry[0] = v
		geometry[1] = n
		geometry[2] = ind
	for key: String in chunk_geometry:
		var chunk_arrays: Array = chunk_geometry[key]
		var mesh_vertices: PackedVector3Array = chunk_arrays[0]
		if mesh_vertices.is_empty():
			continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = mesh_vertices
		arrays[Mesh.ARRAY_NORMAL] = chunk_arrays[1]
		arrays[Mesh.ARRAY_INDEX] = chunk_arrays[2]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, StylizedEnvironmentMaterial.make_unshaded(Color(0.93, 0.94, 0.9)))
		crossings[key] = mesh


## Mapped trees, tree rows, woods and scrub; palms dominate as in the old town.
static func _add_vegetation(parent: Node3D, index: Dictionary, terrain: IslandTerrain, mats: Dictionary) -> void:
	if not FileAccess.file_exists(LANDSCAPE_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LANDSCAPE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var trees: Array[Vector2] = []
	var woods: Array[Vector2] = []
	var bushes: Array[Vector2] = []
	var tombs: Array[Vector2] = []
	var flags: Array[Vector2] = []
	var tees: Array[Vector2] = []
	var marinas: Array[PackedVector2Array] = []
	for f: Dictionary in (parsed as Dictionary).get("features", []):
		var coords: Array = f.get("coordinates", [])
		match String(f.get("kind", "")):
			"tree":
				trees.append(Vector2(float(coords[0]), float(coords[1])))
			"tree_row":
				for i: int in range(coords.size() - 1):
					var a := Vector2(float(coords[i][0]), float(coords[i][1]))
					var b := Vector2(float(coords[i + 1][0]), float(coords[i + 1][1]))
					var count: int = maxi(1, int(a.distance_to(b) / TREE_ROW_SPACING_M))
					for k: int in range(count):
						trees.append(a.lerp(b, (float(k) + 0.5) / float(count)))
			"wood":
				woods.append_array(_scatter(coords, WOOD_SPACING_M, index))
			"scrub":
				bushes.append_array(_scatter(coords, SCRUB_SPACING_M, index))
			"cemetery":
				tombs.append_array(_scatter(coords, TOMB_SPACING_M, index))
			"golf_green":
				flags.append(_centroid(coords))
			"golf_tee":
				tees.append(_centroid(coords))
			"marina":
				marinas.append(_polygon(coords))
	var palms: Array[Transform3D] = []
	var broad: Array[Transform3D] = []
	for p: Vector2 in trees:
		var h: int = absi(hash(p))
		var yaw: float = float(h % 628) * 0.01
		if h % 4 == 0:
			var s: float = 0.7 + float((h / 7) % 60) * 0.01
			broad.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), _ground(terrain, p)))
		else:
			## Palms from 5 to 12 m.
			var s: float = lerpf(5.0, 12.0, float((h / 11) % 100) * 0.01) / PALM_BASE_HEIGHT_M
			palms.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), _ground(terrain, p)))
	## Hammocks and mangroves are hardwood: bare in this winter.
	for p: Vector2 in woods:
		var h: int = absi(hash(p))
		var s: float = 0.6 + float((h / 7) % 60) * 0.01
		broad.append(Transform3D(Basis(Vector3.UP, float(h % 628) * 0.01).scaled(Vector3.ONE * s), _ground(terrain, p)))
	var bush_xf: Array[Transform3D] = []
	for p: Vector2 in bushes:
		var h: int = absi(hash(p))
		var s: float = 0.6 + float(h % 70) * 0.01
		bush_xf.append(Transform3D(Basis(Vector3.UP, float(h % 628) * 0.01).scaled(Vector3(s, s * 0.7, s)), _ground(terrain, p)))
	_add_transforms(parent, "Palms", _palm_mesh(mats), palms)
	_add_transforms(parent, "BareTrees", _bare_tree_mesh(mats), broad)
	_add_transforms(parent, "Scrub", _bush_mesh(mats), bush_xf)
	var trunk := _cyl_shape(0.22, 3.0)
	_add_bodies(parent, "PalmCollision", trunk, Vector3(0, 1.5, 0), _unscaled(palms))
	_add_bodies(parent, "BareTreeCollision", trunk, Vector3(0, 1.5, 0), _unscaled(broad))
	var flag_xf: Array[Transform3D] = []
	for p: Vector2 in flags:
		flag_xf.append(Transform3D(Basis(Vector3.UP, float(absi(hash(p)) % 628) * 0.01), _ground(terrain, p)))
	_add_transforms(parent, "GolfFlags", _golf_flag_mesh(mats), flag_xf)
	var tee_xf: Array[Transform3D] = []
	for p: Vector2 in tees:
		tee_xf.append(Transform3D(Basis(Vector3.UP, float(absi(hash(p)) % 628) * 0.01), _ground(terrain, p)))
	_add_transforms(parent, "GolfTeeMarkers", _tee_mesh(mats), tee_xf)
	_add_boats(parent, (parsed as Dictionary).get("features", []), marinas, index, mats)
	## Key West Cemetery: rows of whitewashed above-ground vaults.
	var vaults: Array[Transform3D] = []
	for p: Vector2 in tombs:
		var h: int = absi(hash(p))
		var road: Dictionary = nearest_road(index, p)
		var yaw: float = 0.0 if road.is_empty() else atan2((road["dir"] as Vector2).x, (road["dir"] as Vector2).y)
		var tall: float = 0.7 + float(h % 8) * 0.08
		vaults.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(1.0, tall, 1.0)), _ground(terrain, p)))
	_add_transforms(parent, "CemeteryVaults", _vault_mesh(mats), vaults)
	_add_bodies(parent, "CemeteryVaultCollision", _box_shape(Vector3(0.9, 1.0, 2.0)), Vector3(0, 0.5, 0), _unscaled(vaults))


## Grid points inside a polygon, jittered, kept off roads.
static func _scatter(coords: Array, spacing: float, index: Dictionary) -> Array[Vector2]:
	var poly := PackedVector2Array()
	for c: Array in coords:
		poly.append(Vector2(float(c[0]), float(c[1])))
	var out: Array[Vector2] = []
	if poly.size() < 3:
		return out
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for q: Vector2 in poly:
		lo = lo.min(q)
		hi = hi.max(q)
	var x: float = lo.x
	while x < hi.x:
		var y: float = lo.y
		while y < hi.y:
			var p := Vector2(x, y)
			var h: int = absi(hash(p))
			p += Vector2(float(h % 100) - 50.0, float((h / 100) % 100) - 50.0) * spacing * 0.008
			if Geometry2D.is_point_in_polygon(p, poly):
				var road: Dictionary = nearest_road(index, p)
				if road.is_empty() or float(road["dist"]) > float(road["width"]) * 0.5 + 1.5:
					out.append(p)
			y += spacing
		x += spacing
	return out


## Lots lie under the snow; only their abandoned cars show in some bays; the lot follows its longest edge.
static func _add_parking(parent: Node3D, enrichment: Dictionary, terrain: IslandTerrain, mats: Dictionary) -> void:
	var cars: Array[Transform3D] = []
	var colors: Array[Color] = []
	for f: Dictionary in enrichment.get("infrastructure", []):
		var geometry: Dictionary = f.get("geometry", {})
		if String(f.get("class", "")) != "parking" or String(geometry.get("type", "")) != "Polygon":
			continue
		var poly: PackedVector2Array = _polygon((geometry.get("coordinates", [[]]) as Array)[0])
		if poly.size() < 3:
			continue
		var axis: Vector2 = _longest_edge(poly)
		var side := Vector2(-axis.y, axis.x)
		var yaw: float = atan2(side.x, side.y)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for q: Vector2 in poly:
			var local := Vector2(q.dot(axis), q.dot(side))
			lo = lo.min(local)
			hi = hi.max(local)
		var a: float = lo.x + CAR_BAY_M.x * 0.5
		while a < hi.x:
			var b: float = lo.y + CAR_BAY_M.y * 0.5
			while b < hi.y:
				var p: Vector2 = axis * a + side * b
				var h: int = absi(hash(p))
				if float(h % 100) < CAR_FILL * 100.0 and Geometry2D.is_point_in_polygon(p, poly):
					var skew: float = (float((h / 100) % 30) - 15.0) * 0.01
					cars.append(Transform3D(Basis(Vector3.UP, yaw + skew), _ground(terrain, p)))
					colors.append(CAR_COLORS[(h / 7) % CAR_COLORS.size()])
				b += CAR_BAY_M.y
			a += CAR_BAY_M.x
	if cars.is_empty():
		return
	## Keep an even spread of at most MAX_CARS across the island.
	if cars.size() > MAX_CARS:
		var stride: float = float(cars.size()) / float(MAX_CARS)
		var kept: Array[Transform3D] = []
		var kept_colors: Array[Color] = []
		for k: int in range(MAX_CARS):
			kept.append(cars[int(float(k) * stride)])
			kept_colors.append(colors[int(float(k) * stride)])
		cars = kept
		colors = kept_colors
	_stream("AbandonedCars", _car_mesh(mats), cars, colors)
	_add_bodies(parent, "CarCollision", _box_shape(Vector3(1.8, 1.4, 4.4)), Vector3(0, 0.7, 0), cars)


## Boats moored along piers inside or beside mapped marinas.
static func _add_boats(parent: Node3D, _features: Array, marinas: Array[PackedVector2Array], _index: Dictionary, mats: Dictionary) -> void:
	if marinas.is_empty():
		return
	var enrichment_path: String = "res://data/world/key_west/visual_enrichment.json"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(enrichment_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var boats: Array[Transform3D] = []
	var colors: Array[Color] = []
	## One boat per 6 m cell so piers mapped twice do not stack hulls.
	var taken: Dictionary = {}
	for f: Dictionary in (parsed as Dictionary).get("supplemental", []):
		if String(f.get("kind", "")) != "pier":
			continue
		var c: Array = (f.get("geometry", {}) as Dictionary).get("coordinates", [])
		for i: int in range(c.size() - 1):
			var a := Vector2(float(c[i][0]), float(c[i][1]))
			var b := Vector2(float(c[i + 1][0]), float(c[i + 1][1]))
			if not _near_any(a.lerp(b, 0.5), marinas):
				continue
			var dir: Vector2 = (b - a).normalized()
			var side := Vector2(-dir.y, dir.x)
			var count: int = int(a.distance_to(b) / BOAT_SPACING_M)
			for k: int in range(count):
				for s: float in [-1.0, 1.0]:
					var p: Vector2 = a.lerp(b, (float(k) + 0.5) / float(count)) + side * s * 4.8
					var h: int = absi(hash(p))
					var cell := Vector2i((p / 6.0).floor())
					if float(h % 100) >= BOAT_FILL * 100.0 or taken.has(cell):
						continue
					taken[cell] = true
					## Bow points away from the pier; frozen in at the waterline.
					var yaw: float = atan2(side.x * s, side.y * s) + (float((h / 100) % 20) - 10.0) * 0.01
					var scale: float = 0.8 + float((h / 7) % 50) * 0.01
					boats.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), Vector3(p.x, -0.25, p.y)))
					colors.append(BOAT_COLORS[(h / 11) % BOAT_COLORS.size()])
	if boats.is_empty():
		return
	_stream("MooredBoats", _boat_mesh(mats), boats, colors)
	_add_bodies(parent, "BoatCollision", _box_shape(Vector3(2.4, 1.6, 7.0)), Vector3(0, 0.8, 0), _unscaled(boats))


static func _near_any(p: Vector2, polys: Array[PackedVector2Array]) -> bool:
	for poly: PackedVector2Array in polys:
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
		for i: int in range(poly.size()):
			var q: Vector2 = Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
			if p.distance_to(q) < MARINA_REACH_M:
				return true
	return false


static func _polygon(coords: Array) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for c: Array in coords:
		poly.append(Vector2(float(c[0]), float(c[1])))
	if poly.size() > 1 and poly[0].is_equal_approx(poly[poly.size() - 1]):
		poly.remove_at(poly.size() - 1)
	return poly


static func _centroid(coords: Array) -> Vector2:
	var sum := Vector2.ZERO
	for c: Array in coords:
		sum += Vector2(float(c[0]), float(c[1]))
	return sum / maxf(float(coords.size()), 1.0)


static func _longest_edge(poly: PackedVector2Array) -> Vector2:
	var best := Vector2.RIGHT
	var best_len: float = 0.0
	for i: int in range(poly.size()):
		var e: Vector2 = poly[(i + 1) % poly.size()] - poly[i]
		if e.length() > best_len:
			best_len = e.length()
			best = e.normalized()
	return best


## Sagging wires between the vertices of mapped power lines.
static func _add_wires(parent: Node3D, enrichment: Dictionary, terrain: IslandTerrain, mats: Dictionary) -> void:
	var spans: Array[Transform3D] = []
	for f: Dictionary in enrichment.get("infrastructure", []):
		var kind: String = String(f.get("class", ""))
		var geometry: Dictionary = f.get("geometry", {})
		if not kind in ["power_line", "minor_line", "cable", "communication_line"] or String(geometry.get("type", "")) != "LineString":
			continue
		var lift: float = POWER_LINE_M if kind == "power_line" else MINOR_LINE_M
		var c: Array = geometry.get("coordinates", [])
		for i: int in range(c.size() - 1):
			var a: Vector3 = _ground(terrain, Vector2(float(c[i][0]), float(c[i][1]))) + Vector3.UP * lift
			var b: Vector3 = _ground(terrain, Vector2(float(c[i + 1][0]), float(c[i + 1][1]))) + Vector3.UP * lift
			var length: float = a.distance_to(b)
			if length < 1.0:
				continue
			## Two straight halves dipping to a mid-span sag.
			var mid: Vector3 = (a + b) * 0.5 + Vector3.DOWN * minf(length * 0.03, 1.5)
			for pair: Array in [[a, mid], [mid, b]]:
				for side: float in [-0.5, 0.5]:
					var from: Vector3 = pair[0]
					var to: Vector3 = pair[1]
					var shift := (to - from).cross(Vector3.UP).normalized() * side
					var z: Vector3 = to - from
					var basis := Basis.looking_at(z.normalized(), Vector3.UP).scaled_local(Vector3(1, 1, z.length()))
					spans.append(Transform3D(basis, (from + to) * 0.5 + shift))
	_add_transforms(parent, "PowerWires", _compose([[_box(Vector3(0.03, 0.03, 1.0)), Transform3D.IDENTITY, mats["wire"]]]), spans)


## Mapped storage tanks and water towers as cylinders sized to their outline.
static func _add_tanks(parent: Node3D, enrichment: Dictionary, terrain: IslandTerrain, mats: Dictionary) -> void:
	var tanks: Array[Transform3D] = []
	for f: Dictionary in enrichment.get("infrastructure", []):
		var kind: String = String(f.get("class", ""))
		var geometry: Dictionary = f.get("geometry", {})
		if not kind in ["storage_tank", "water_tower"] or String(geometry.get("type", "")) != "Polygon":
			continue
		var ring: Array = (geometry.get("coordinates", [[]]) as Array)[0]
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for c: Array in ring:
			lo = lo.min(Vector2(float(c[0]), float(c[1])))
			hi = hi.max(Vector2(float(c[0]), float(c[1])))
		var r: float = clampf((hi - lo).length() * 0.35, 2.0, 30.0)
		var h: float = 30.0 if kind == "water_tower" else clampf(r * 0.8, 4.0, 14.0)
		tanks.append(Transform3D(Basis.IDENTITY.scaled(Vector3(r, h, r)), _ground(terrain, (lo + hi) * 0.5)))
	_add_transforms(parent, "StorageTanks", _compose([[_cyl(1.0, 1.0, 16), _at(0, 0.5, 0), mats["tank"]]]), tanks)
	for xf: Transform3D in tanks:
		var shape := CylinderShape3D.new()
		shape.radius = xf.basis.x.length()
		shape.height = xf.basis.y.length()
		register_shape(shape, Transform3D(Basis.IDENTITY, xf.origin + Vector3.UP * shape.height * 0.5))


## Queues a layer's colliders; bodies exist only while their city chunk streams in.
static func _add_bodies(_parent: Node3D, _node_name: String, shape: Shape3D, offset: Vector3, xfs: Array[Transform3D]) -> void:
	for xf: Transform3D in xfs:
		register_shape(shape, xf * Transform3D(Basis.IDENTITY, offset))


## Files a collision shape under the city chunk that holds its origin.
static func register_shape(shape: Shape3D, xf: Transform3D) -> void:
	var key: String = chunk_key(Vector2(xf.origin.x, xf.origin.z))
	if not colliders.has(key):
		colliders[key] = []
	(colliders[key] as Array).append([shape, xf])


## Splits triangle soup (fences, walls) into per-chunk concave shapes.
static func register_faces(faces: PackedVector3Array) -> void:
	var buckets: Dictionary = {}
	for i: int in range(0, faces.size(), 3):
		var key: String = chunk_key(Vector2(faces[i].x, faces[i].z))
		if not buckets.has(key):
			buckets[key] = PackedVector3Array()
		var bucket: PackedVector3Array = buckets[key]
		bucket.append_array([faces[i], faces[i + 1], faces[i + 2]])
		buckets[key] = bucket
	for key: String in buckets:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(buckets[key])
		shape.backface_collision = true
		if not colliders.has(key):
			colliders[key] = []
		(colliders[key] as Array).append([shape, Transform3D.IDENTITY])


static func chunk_key(p: Vector2) -> String:
	return "%d:%d" % [floori(p.x / CHUNK_SIZE_M), floori(p.y / CHUNK_SIZE_M)]


## Static body for one streamed chunk, or null when it holds no props.
static func build_chunk_body(chunk_id: String) -> StaticBody3D:
	var entries: Array = colliders.get(chunk_id, [])
	if entries.is_empty():
		return null
	var body := StaticBody3D.new()
	body.name = "PropCollision"
	for entry: Array in entries:
		var col := CollisionShape3D.new()
		col.shape = entry[0]
		col.transform = entry[1]
		body.add_child(col)
	return body


static func _unscaled(xfs: Array[Transform3D]) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for xf: Transform3D in xfs:
		out.append(Transform3D(xf.basis.orthonormalized(), xf.origin))
	return out


static func _cyl_shape(radius: float, height: float) -> CylinderShape3D:
	var c := CylinderShape3D.new()
	c.radius = radius
	c.height = height
	return c


static func _box_shape(size: Vector3) -> BoxShape3D:
	var b := BoxShape3D.new()
	b.size = size
	return b


static func _ground(terrain: IslandTerrain, p: Vector2) -> Vector3:
	return Vector3(p.x, maxf(terrain.get_height(p.x, p.y), 0.0), p.y)


## All mapped props are filed into their streamed city chunk.
static func _add_transforms(_parent: Node3D, node_name: String, mesh: Mesh, xfs: Array[Transform3D]) -> void:
	if xfs.is_empty():
		return
	_stream(node_name, mesh, xfs)


static func _stream(node_name: String, mesh: Mesh, xfs: Array[Transform3D], colors: Array[Color] = []) -> void:
	for i: int in range(xfs.size()):
		var key: String = chunk_key(Vector2(xfs[i].origin.x, xfs[i].origin.z))
		if not visuals.has(key):
			visuals[key] = {}
		var kinds: Dictionary = visuals[key]
		if not kinds.has(node_name):
			var placed: Array[Transform3D] = []
			var tints: Array[Color] = []
			kinds[node_name] = [mesh, placed, tints]
		(kinds[node_name][1] as Array).append(xfs[i])
		if not colors.is_empty():
			(kinds[node_name][2] as Array).append(colors[i])


## Small props of one streamed chunk, or null when it holds none.
static func build_chunk_visuals(chunk_id: String) -> Node3D:
	var kinds: Dictionary = visuals.get(chunk_id, {})
	if kinds.is_empty() and not crossings.has(chunk_id):
		return null
	var holder := Node3D.new()
	holder.name = "StreetPropsChunk"
	if crossings.has(chunk_id):
		var crossing := MeshInstance3D.new()
		crossing.name = "Crossings"
		crossing.mesh = crossings[chunk_id]
		holder.add_child(crossing)
	for node_name: String in kinds:
		var entry: Array = kinds[node_name]
		var xfs: Array = entry[1]
		var colors: Array = entry[2]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = not colors.is_empty()
		mm.mesh = entry[0]
		mm.instance_count = xfs.size()
		for i: int in range(xfs.size()):
			mm.set_instance_transform(i, xfs[i])
			if mm.use_colors:
				mm.set_instance_color(i, colors[i])
		_add_instance(holder, node_name, mm)
	return holder


static func _add_instance(parent: Node3D, node_name: String, mm: MultiMesh) -> void:
	var inst := MultiMeshInstance3D.new()
	inst.name = node_name
	inst.multimesh = mm
	parent.add_child(inst)


# --- Models: +Z faces the road, origin at the ground --------------------------

static func _materials() -> Dictionary:
	return {
		"metal": _mat(Color(0.24, 0.25, 0.26), 0.7),
		"wood": _mat(Color(0.33, 0.29, 0.25), 0.95),
		"stop": _mat(Color(0.62, 0.08, 0.07), 0.6),
		"sign": _mat(Color(0.1, 0.24, 0.45), 0.6),
		"white": _mat(Color(0.85, 0.86, 0.84), 0.6),
		"lamp": _mat(Color(0.75, 0.72, 0.6), 0.4),
		"signal": _mat(Color(0.12, 0.12, 0.1), 0.6),
		"bin": _mat(Color(0.18, 0.22, 0.2), 0.85),
		"palm_trunk": _mat(Color(0.36, 0.33, 0.29), 0.95),
		"palm_frond": _mat(Color(0.34, 0.33, 0.24), 0.9, true),
		"bark": _mat(Color(0.27, 0.24, 0.21), 0.95),
		"twig": _mat(Color(0.3, 0.27, 0.24), 0.95),
		"hydrant": _mat(Color(0.62, 0.52, 0.12), 0.6),
		"postbox": _mat(Color(0.12, 0.2, 0.42), 0.6),
		"wire": _mat(Color(0.08, 0.08, 0.08), 0.8),
		"tank": _mat(Color(0.7, 0.71, 0.69), 0.6),
		"vault": _mat(Color(0.8, 0.79, 0.75), 0.9),
		"paint": _vertex_mat(0.55),
		"glass": _mat(Color(0.12, 0.14, 0.16), 0.2),
		"snowcap": _mat(Color(0.8, 0.83, 0.88), 0.85),
		"tyre": _mat(Color(0.07, 0.07, 0.07), 0.9),
		"stripe_red": _mat(Color(0.7, 0.1, 0.08), 0.6),
		"flag": _mat(Color(0.75, 0.12, 0.1), 0.8, true),
	}


## Takes its albedo from the MultiMesh instance colour.
static func _vertex_mat(roughness: float) -> Material:
	return StylizedEnvironmentMaterial.make(Color.WHITE, roughness, true)


static func _mat(color: Color, roughness: float, double_sided: bool = false) -> Material:
	return StylizedEnvironmentMaterial.make(color, roughness, false, double_sided)


## Merges primitive parts into one mesh, one surface per material.
static func _compose(parts: Array) -> ArrayMesh:
	var tools: Dictionary = {}
	for part: Array in parts:
		var mat: Material = part[2]
		if not tools.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[mat] = st
		(tools[mat] as SurfaceTool).append_from(part[0] as Mesh, 0, part[1] as Transform3D)
	var mesh := ArrayMesh.new()
	for mat: Material in tools:
		(tools[mat] as SurfaceTool).commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	return mesh


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _cyl(radius: float, height: float, segments: int = 8, top: float = -1.0) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.bottom_radius = radius
	c.top_radius = radius if top < 0.0 else top
	c.height = height
	c.radial_segments = segments
	c.rings = 1
	return c


static func _at(x: float, y: float, z: float, basis: Basis = Basis.IDENTITY) -> Transform3D:
	return Transform3D(basis, Vector3(x, y, z))


static func _power_pole_mesh(m: Dictionary) -> ArrayMesh:
	return _compose([
		[_cyl(0.13, 9.0, 6, 0.09), _at(0, 4.5, 0), m["wood"]],
		[_box(Vector3(2.4, 0.12, 0.12)), _at(0, 8.4, 0), m["wood"]],
		[_box(Vector3(1.6, 0.1, 0.1)), _at(0, 7.6, 0), m["wood"]],
		[_cyl(0.3, 0.9, 8), _at(0.0, 6.8, -0.35), m["metal"]],
	])


static func _lamp_mesh(m: Dictionary) -> ArrayMesh:
	return _compose([
		[_cyl(0.08, 7.0, 6, 0.05), _at(0, 3.5, 0), m["metal"]],
		[_box(Vector3(0.08, 0.08, 1.8)), _at(0, 6.9, 0.9), m["metal"]],
		[_box(Vector3(0.3, 0.12, 0.6)), _at(0, 6.82, 1.8), m["lamp"]],
	])


static func _signal_mesh(m: Dictionary) -> ArrayMesh:
	var parts: Array = [
		[_cyl(0.12, 6.0, 8), _at(0, 3.0, 0), m["metal"]],
		[_box(Vector3(0.12, 0.12, 6.0)), _at(0, 5.8, 3.0), m["metal"]],
	]
	for z: float in [3.0, 5.5]:
		parts.append([_box(Vector3(0.36, 1.1, 0.3)), _at(0, 5.1, z), m["signal"]])
	parts.append([_box(Vector3(0.36, 1.1, 0.3)), _at(0, 2.8, 0.2), m["signal"]])
	return _compose(parts)


static func _stop_mesh(m: Dictionary) -> ArrayMesh:
	## Octagon plate facing the road.
	var plate := _cyl(0.38, 0.03, 8)
	var face := Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.UP, PI / 8.0)
	return _compose([
		[_cyl(0.035, 2.4, 6), _at(0, 1.2, 0), m["metal"]],
		[plate, _at(0, 2.2, 0.04, face), m["stop"]],
	])


static func _bus_stop_mesh(m: Dictionary) -> ArrayMesh:
	var parts: Array = [
		[_cyl(0.04, 2.6, 6), _at(-1.6, 1.3, 0.6), m["metal"]],
		[_box(Vector3(0.45, 0.6, 0.03)), _at(-1.6, 2.35, 0.62), m["sign"]],
	]
	parts.append_array(_bench_parts(m, 0.0))
	return _compose(parts)


static func _bench_parts(m: Dictionary, x: float) -> Array:
	return [
		[_box(Vector3(1.8, 0.06, 0.45)), _at(x, 0.45, 0), m["wood"]],
		[_box(Vector3(1.8, 0.4, 0.05)), _at(x, 0.72, -0.22), m["wood"]],
		[_box(Vector3(0.06, 0.45, 0.4)), _at(x - 0.8, 0.22, 0), m["metal"]],
		[_box(Vector3(0.06, 0.45, 0.4)), _at(x + 0.8, 0.22, 0), m["metal"]],
	]


static func _bench_mesh(m: Dictionary) -> ArrayMesh:
	return _compose(_bench_parts(m, 0.0))


static func _basket_mesh(m: Dictionary) -> ArrayMesh:
	return _compose([
		[_cyl(0.28, 0.9, 10), _at(0, 0.45, 0), m["bin"]],
	])


## Palm from the Graciosa blockout: four bent trunk segments, drooping fronds; 9 m tall.
static func _palm_mesh(m: Dictionary) -> ArrayMesh:
	var parts: Array = []
	var seg: float = PALM_BASE_HEIGHT_M / 4.0
	var top := Vector3(0, -0.3, 0)
	var tilt: float = 0.0
	for i: int in range(4):
		tilt += deg_to_rad(4.0 + float(i) * 1.5)
		var dir := Vector3(0, cos(tilt), -sin(tilt))
		var r: float = 0.2 - 0.03 * float(i)
		parts.append([_cyl(r, seg + 0.15, 7, r - 0.03), Transform3D(Basis(Vector3.RIGHT, -tilt), top + dir * seg * 0.5), m["palm_trunk"]])
		top += dir * seg
	for k: int in range(7):
		var yaw: float = TAU * float(k) / 7.0
		var droop: float = deg_to_rad(25.0 + float(k % 3) * 12.0)
		var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, droop)
		parts.append([_box(Vector3(0.45, 0.03, 3.0)), Transform3D(b, top + b * Vector3(0, 0, 1.4)), m["palm_frond"]])
	return _compose(parts)


## Leafless winter tree: trunk, five limbs and a second tier of twigs.
static func _bare_tree_mesh(m: Dictionary) -> ArrayMesh:
	var parts: Array = [[_cyl(0.22, 3.2, 7, 0.15), _at(0, 1.6, 0), m["bark"]]]
	for k: int in range(5):
		var yaw: float = TAU * float(k) / 5.0 + 0.3
		var limb := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(38.0 + float(k % 2) * 12.0))
		var base := Vector3(0, 2.6 + float(k % 3) * 0.3, 0)
		parts.append([_cyl(0.1, 2.6, 5, 0.05), Transform3D(limb, base + limb * Vector3(0, 1.3, 0)), m["bark"]])
		var tip: Vector3 = base + limb * Vector3(0, 2.4, 0)
		for j: int in range(2):
			var twig := Basis(Vector3.UP, yaw + (float(j) - 0.5) * 1.1) * Basis(Vector3.RIGHT, deg_to_rad(25.0))
			parts.append([_cyl(0.04, 1.4, 4, 0.015), Transform3D(twig, tip + twig * Vector3(0, 0.7, 0)), m["twig"]])
	return _compose(parts)


## Bare shrub: a fan of thin stems.
static func _bush_mesh(m: Dictionary) -> ArrayMesh:
	var parts: Array = []
	for k: int in range(7):
		var b := Basis(Vector3.UP, TAU * float(k) / 7.0) * Basis(Vector3.RIGHT, deg_to_rad(20.0 + float(k % 3) * 12.0))
		parts.append([_cyl(0.03, 1.4, 4, 0.01), Transform3D(b, b * Vector3(0, 0.7, 0)), m["twig"]])
	return _compose(parts)


static func _hydrant_mesh(m: Dictionary) -> ArrayMesh:
	return _compose([
		[_cyl(0.13, 0.7, 8), _at(0, 0.35, 0), m["hydrant"]],
		[_cyl(0.16, 0.08, 8), _at(0, 0.72, 0), m["hydrant"]],
		[_cyl(0.06, 0.34, 6), _at(0, 0.45, 0, Basis(Vector3.FORWARD, PI * 0.5)), m["hydrant"]],
	])


static func _bollard_mesh(m: Dictionary) -> ArrayMesh:
	return _compose([[_cyl(0.1, 1.0, 8), _at(0, 0.5, 0), m["metal"]]])


static func _post_box_mesh(m: Dictionary) -> ArrayMesh:
	return _compose([
		[_box(Vector3(0.5, 0.9, 0.5)), _at(0, 0.75, 0), m["postbox"]],
		[_cyl(0.25, 0.5, 10), _at(0, 1.2, 0, Basis(Vector3.RIGHT, PI * 0.5)), m["postbox"]],
		[_box(Vector3(0.08, 0.3, 0.08)), _at(0.18, 0.15, 0.18), m["metal"]],
		[_box(Vector3(0.08, 0.3, 0.08)), _at(-0.18, 0.15, -0.18), m["metal"]],
	])


## Above-ground vault with a pitched cap, 1 m tall before per-instance height.
static func _vault_mesh(m: Dictionary) -> ArrayMesh:
	return _compose([
		[_box(Vector3(0.9, 0.9, 2.0)), _at(0, 0.45, 0), m["vault"]],
		[_box(Vector3(1.0, 0.1, 2.1)), _at(0, 0.95, 0), m["vault"]],
		[_box(Vector3(0.5, 0.5, 0.08)), _at(0, 1.2, -0.95), m["vault"]],
	])


## Abandoned sedan, long axis +Z, with a cap of settled snow.
static func _car_mesh(m: Dictionary) -> ArrayMesh:
	var parts: Array = [
		[_box(Vector3(1.8, 0.7, 4.4)), _at(0, 0.6, 0), m["paint"]],
		[_box(Vector3(1.6, 0.55, 2.2)), _at(0, 1.22, -0.2), m["glass"]],
		[_box(Vector3(1.62, 0.12, 2.1)), _at(0, 1.55, -0.2), m["snowcap"]],
		[_box(Vector3(1.75, 0.08, 1.1)), _at(0, 0.99, 1.55), m["snowcap"]],
	]
	for x: float in [-0.8, 0.8]:
		for z: float in [-1.4, 1.4]:
			parts.append([_cyl(0.32, 0.25, 10), _at(x, 0.32, z, Basis(Vector3.FORWARD, PI * 0.5)), m["tyre"]])
	return _compose(parts)


## Small motor boat, bow toward +Z.
static func _boat_mesh(m: Dictionary) -> ArrayMesh:
	var bow := PrismMesh.new()
	bow.size = Vector3(2.4, 1.2, 1.6)
	return _compose([
		[_box(Vector3(2.4, 1.2, 5.0)), _at(0, 0.6, -0.6), m["paint"]],
		[bow, _at(0, 0.6, 2.7, Basis(Vector3.RIGHT, PI * 0.5)), m["paint"]],
		[_box(Vector3(1.8, 0.9, 1.8)), _at(0, 1.65, -0.8), m["white"]],
		[_box(Vector3(1.9, 0.1, 1.9)), _at(0, 2.15, -0.8), m["snowcap"]],
	])


## Farm gate between two posts, spanning the drive (+Z).
static func _gate_mesh(m: Dictionary) -> ArrayMesh:
	var parts: Array = [
		[_cyl(0.07, 1.5, 6), _at(0, 0.75, -1.6), m["metal"]],
		[_cyl(0.07, 1.5, 6), _at(0, 0.75, 1.6), m["metal"]],
	]
	for y: float in [0.3, 0.75, 1.2]:
		parts.append([_box(Vector3(0.05, 0.05, 3.1)), _at(0, y, 0), m["metal"]])
	return _compose(parts)


## Car-park barrier: post and a red-and-white boom lying across the lane.
static func _lift_gate_mesh(m: Dictionary) -> ArrayMesh:
	var parts: Array = [[_box(Vector3(0.3, 1.1, 0.3)), _at(0, 0.55, 0), m["metal"]]]
	for k: int in range(8):
		parts.append([_box(Vector3(0.08, 0.1, 0.5)), _at(0, 0.95, 0.4 + float(k) * 0.5), m["stripe_red"] if k % 2 == 0 else m["white"]])
	return _compose(parts)


static func _golf_flag_mesh(m: Dictionary) -> ArrayMesh:
	return _compose([
		[_cyl(0.02, 2.3, 5), _at(0, 1.15, 0), m["white"]],
		[_box(Vector3(0.02, 0.35, 0.5)), _at(0, 2.1, 0.25), m["flag"]],
	])


static func _tee_mesh(m: Dictionary) -> ArrayMesh:
	return _compose([
		[_box(Vector3(0.2, 0.2, 0.2)), _at(-1.5, 0.1, 0), m["stripe_red"]],
		[_box(Vector3(0.2, 0.2, 0.2)), _at(1.5, 0.1, 0), m["stripe_red"]],
	])
