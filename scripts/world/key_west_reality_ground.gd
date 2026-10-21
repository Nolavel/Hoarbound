class_name KeyWestRealityGround
extends Node3D
## Ground heights, building outlines and settled snow of the active Reality chunks, for the snow and
## height consumers (get_height, snow obstacles). Reads only chunks the StreamingSystem made live.

const GROUND_GROUP: StringName = &"snow_ground"
const OBSTACLE_GROUP: StringName = &"snow_obstacles"
const CELL_M: float = 8.0
const CHUNK_M: float = 512.0
const FALLBACK_Y: float = 1.0
## Snow cover build time per frame.
const SNOW_BUDGET_USEC: int = 3000
## Road paving time per frame, beside the cover's.
const PAVE_BUDGET_USEC: int = 1500
## A sample on a chunk's far edge belongs to the next chunk; nudge back into this one.
const EDGE_NUDGE_M: float = 0.01
## Road ribbons ride a few centimetres over the terrain; anything higher is a deck the physics ray owns.
const PAVED_MAX_LIFT_M: float = 0.3
## Pavement this wide or wider is a main street (Key West's top ~15 % of road length) the wind can run down.
const WIDE_STREET_M: float = 7.0

var _tiles: Dictionary = {}
var _outlines: Dictionary = {}
var _cells: Dictionary = {}
var _container: Node3D
var _snow_jobs: Dictionary = {}
var _snow: Dictionary = {}
var _snow_root: Node3D
var _pave_jobs: Dictionary = {}
var _streets: Dictionary = {}
## Chunks live at boot whose paving or cover is unfinished: built at full speed under the startup card.
var _boot_keys: Dictionary = {}


func _ready() -> void:
	add_to_group(GROUND_GROUP)
	add_to_group(OBSTACLE_GROUP)
	_snow_root = Node3D.new()
	_snow_root.name = "SnowCover"
	_snow_root.top_level = true
	add_child(_snow_root)
	set_process(false)


## Paves and builds pending chunk snow covers within the frame budget; the chunk under Henry finishes at once.
func _process(_delta: float) -> void:
	if _snow_jobs.is_empty() and _pave_jobs.is_empty():
		set_process(false)
		return
	var window: Vector4 = SnowShell.live_window
	var centre: Vector2 = Vector2(window.x, window.y) + Vector2.ONE * window.z * 0.5
	## Cover and paving run side by side on their own budgets: a cover waiting on paving left
	## the chunk bare outside Henry's rings (a square of snow) until it all landed in one hitch.
	if not _snow_jobs.is_empty():
		var key: Vector2i = _nearest(_snow_jobs.keys(), centre)
		var job: SnowChunkCover.Job = _snow_jobs[key]
		if SnowChunkCover.step(job, 1 << 40 if _rush(key, window, centre) else SNOW_BUDGET_USEC):
			_snow_jobs.erase(key)
			_attach_snow(key, SnowChunkCover.finish(job))
			_settle_boot(key)
	if not _pave_jobs.is_empty():
		var lot: Vector2i = _nearest(_pave_jobs.keys(), centre)
		if _pave_step(lot, 1 << 40 if _rush(lot, window, centre) else PAVE_BUDGET_USEC):
			_pave_jobs.erase(lot)
			_settle_boot(lot)


## True while chunks live at boot still pave or build cover (BootLoadCapability).
func has_boot_work() -> bool:
	return not _boot_keys.is_empty()


func _rush(key: Vector2i, window: Vector4, centre: Vector2) -> bool:
	return _boot_keys.has(key) or _under_henry(key, window, centre)


func _settle_boot(key: Vector2i) -> void:
	if not _snow_jobs.has(key) and not _pave_jobs.has(key):
		_boot_keys.erase(key)


func _nearest(keys: Array, centre: Vector2) -> Vector2i:
	var key: Vector2i = keys[0]
	for candidate: Vector2i in keys:
		if (Vector2(candidate) + Vector2.ONE * 0.5).distance_to(centre / CHUNK_M) < (Vector2(key) + Vector2.ONE * 0.5).distance_to(centre / CHUNK_M):
			key = candidate
	return key


func _under_henry(key: Vector2i, window: Vector4, centre: Vector2) -> bool:
	return window.w > 0.5 and Rect2(Vector2(key) * CHUNK_M, Vector2.ONE * CHUNK_M).has_point(centre)


func on_world_ready(context: WorldContext) -> void:
	_container = context.stream_container
	for system: Node in context.systems:
		if system is StreamingSystem:
			(system as StreamingSystem).cell_state_changed.connect(_on_cell)
	if _container != null:
		for chunk: Node in _container.get_children():
			_index(chunk)
	for key: Vector2i in _snow_jobs.keys() + _pave_jobs.keys():
		_boot_keys[key] = true
	BootLoadCapability.publish(self, self, &"has_boot_work")


## Terrain height (NAVD88 m) at local x/z, bilinear on the chunk's HeightMapShape3D data.
func get_height(x: float, z: float) -> float:
	var tile: Dictionary = _tile_at(x, z)
	return FALLBACK_Y if tile.is_empty() else _bilinear(tile, tile["data"], x, z)


## The drawn ground under snow: the terrain, or a road ribbon where one lies above it.
func get_surface_height(x: float, z: float) -> float:
	var tile: Dictionary = _tile_at(x, z)
	return FALLBACK_Y if tile.is_empty() else _bilinear(tile, tile.get("surface", tile["data"]), x, z)


## True once the chunk under x/z is live, so get_height reads real ground there and not FALLBACK_Y.
func has_ground_at(x: float, z: float) -> bool:
	return not _tile_at(x, z).is_empty()


## True once get_surface_height under x/z carries the chunk's roads too.
func has_surface_at(x: float, z: float) -> bool:
	var tile: Dictionary = _tile_at(x, z)
	return not tile.is_empty() and tile.has("paved")


## Building outlines touching bounds, for SnowChunkCover's exact footprint cut.
func get_snow_obstacles_in_rect(bounds: Rect2) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var region: Rect2 = bounds.abs()
	for key: Vector2i in _outlines.keys():
		if not Rect2(Vector2(key) * CHUNK_M, Vector2.ONE * CHUNK_M).intersects(region, true):
			continue
		for ring: PackedVector2Array in _outlines[key]:
			var box: Rect2 = Rect2(ring[0], Vector2.ZERO)
			for p: Vector2 in ring:
				box = box.expand(p)
			if box.intersects(region, true):
				out.append(ring)
	return out


## True inside a building outline (the same prism outline the collision uses).
func has_snow_obstacle_at(point: Vector2) -> bool:
	for ref: Vector2i in _cells.get(Vector2i(floori(point.x / CELL_M), floori(point.y / CELL_M)), []):
		var rings: Array = _outlines.get(_chunk_of_ref(ref), [])
		if ref.y < rings.size() and Geometry2D.is_point_in_polygon(point, rings[ref.y]):
			return true
	return false


func _bilinear(tile: Dictionary, data: PackedFloat32Array, x: float, z: float) -> float:
	var n: int = tile["n"]
	var step: float = tile["step"]
	var fx: float = clampf((x - float(tile["ox"])) / step, 0.0, n - 1.001)
	var fz: float = clampf((z - float(tile["oz"])) / step, 0.0, n - 1.001)
	var cx: int = int(fx)
	var cz: int = int(fz)
	var tx: float = fx - cx
	var tz: float = fz - cz
	var top: float = lerpf(data[cz * n + cx], data[cz * n + cx + 1], tx)
	var bottom: float = lerpf(data[(cz + 1) * n + cx], data[(cz + 1) * n + cx + 1], tx)
	return lerpf(top, bottom, tz)


func _tile_at(x: float, z: float) -> Dictionary:
	for nudge: Vector2 in [Vector2.ZERO, Vector2(EDGE_NUDGE_M, 0.0), Vector2(0.0, EDGE_NUDGE_M), Vector2.ONE * EDGE_NUDGE_M]:
		var tile: Dictionary = _tiles.get(Vector2i(floori((x - nudge.x) / CHUNK_M), floori((z - nudge.y) / CHUNK_M)), {})
		if not tile.is_empty():
			return tile
	return {}


## Outline refs pack (chunk, index) into one Vector2i: x = cx << 12 | (cz + 2048), y = index.
func _chunk_of_ref(ref: Vector2i) -> Vector2i:
	return Vector2i(ref.x >> 12, (ref.x & 0xFFF) - 2048)


func _ref(key: Vector2i, index: int) -> Vector2i:
	return Vector2i((key.x << 12) | (key.y + 2048), index)


func _on_cell(id: StringName, state: StreamingSystem.CellState) -> void:
	var parts: PackedStringArray = String(id).trim_prefix("kw_gen_").split("_")
	if parts.size() != 2:
		return
	var key: Vector2i = Vector2i(int(parts[0]), int(parts[1]))
	if state == StreamingSystem.CellState.ACTIVE and _container != null:
		var chunk: Node = _container.get_node_or_null(NodePath("Chunk_%d_%d" % [key.x, key.y]))
		if chunk != null:
			_index(chunk)
	elif state == StreamingSystem.CellState.UNLOADED:
		_drop(key)


func _index(chunk: Node) -> void:
	## An HLOD cluster names its source chunk too but carries no terrain; indexing it would drop that chunk's ground.
	if not chunk.has_meta("chunk_id") or chunk.has_meta("cluster_id"):
		return
	var parts: PackedStringArray = String(chunk.get_meta("chunk_id")).split(":")
	var key: Vector2i = Vector2i(int(parts[0]), int(parts[1]))
	_drop(key)
	var terrain: Node3D = chunk.get_node_or_null(NodePath("Terrain/Terrain_%d_%d" % [key.x, key.y]))
	var shape_node: CollisionShape3D = terrain.get_node_or_null(^"Collision").get_child(0) if terrain != null and terrain.get_node_or_null(^"Collision") != null else null
	if shape_node != null and shape_node.shape is HeightMapShape3D:
		var hm: HeightMapShape3D = shape_node.shape
		_tiles[key] = {"n": hm.map_width, "step": shape_node.scale.x, "data": hm.map_data,
			"ox": terrain.global_position.x, "oz": terrain.global_position.z}
		_pave(key, chunk)
	var rings: Array = chunk.get_meta("snow_footprints", [])
	_outlines[key] = rings
	for i: int in range(rings.size()):
		var ring: PackedVector2Array = rings[i]
		var box: Rect2 = Rect2(ring[0], Vector2.ZERO)
		for p: Vector2 in ring:
			box = box.expand(p)
		for cx: int in range(floori(box.position.x / CELL_M), floori(box.end.x / CELL_M) + 1):
			for cz: int in range(floori(box.position.y / CELL_M), floori(box.end.y / CELL_M) + 1):
				var cell: Vector2i = Vector2i(cx, cz)
				if not _cells.has(cell):
					_cells[cell] = []
				(_cells[cell] as Array).append(_ref(key, i))
	_start_snow(key)


## Queues the chunk's road triangles; _pave_step raises a copy of the tile to them, padded one node
## so ribbon edges never dip below the snow's ground.
func _pave(key: Vector2i, chunk: Node) -> void:
	var tile: Dictionary = _tiles[key]
	var tris := PackedVector3Array()
	var roads: Node = chunk.get_node_or_null(^"Roads")
	if roads == null:
		tile["paved"] = true
		return
	for road: Node in roads.get_children():
		var ribbon := road as MeshInstance3D
		if ribbon == null or ribbon.mesh == null:
			continue
		var xf: Transform3D = ribbon.global_transform
		var first: int = tris.size()
		for p: Vector3 in ribbon.mesh.get_faces():
			tris.append(xf * p)
		var width: float = float(ribbon.get_meta("width_m", 0.0))
		if width >= WIDE_STREET_M:
			_add_street_segments(key, tris, first, width)
	if tris.is_empty():
		tile["paved"] = true
		return
	_pave_jobs[key] = {"tris": tris, "next": 0, "surface": (tile["data"] as PackedFloat32Array).duplicate()}
	set_process(true)


## Wide-street segments within `radius` of `centre`: {a, b: Vector2 (centreline), width, y}.
func get_wide_streets(centre: Vector2, radius: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for key: Vector2i in _streets.keys():
		if not Rect2(Vector2(key) * CHUNK_M, Vector2.ONE * CHUNK_M).grow(radius).has_point(centre):
			continue
		for segment: Dictionary in _streets[key]:
			var a: Vector2 = segment["a"]
			var b: Vector2 = segment["b"]
			if Geometry2D.get_closest_point_to_segment(centre, a, b).distance_to(centre) <= radius:
				out.append(segment)
	return out


## One centreline segment per ribbon quad: the two short sides of the quad are its ends.
func _add_street_segments(key: Vector2i, tris: PackedVector3Array, first: int, width: float) -> void:
	if not _streets.has(key):
		_streets[key] = [] as Array[Dictionary]
	for i: int in range(first, tris.size() - 5, 6):
		var corners: Array[Vector3] = []
		for k: int in range(6):
			var p: Vector3 = tris[i + k]
			if not corners.any(func(c: Vector3) -> bool: return c.distance_squared_to(p) < 1e-4):
				corners.append(p)
		if corners.size() != 4:
			continue
		var ends: Array = _quad_ends(corners)
		var a: Vector3 = (ends[0][0] + ends[0][1]) * 0.5
		var b: Vector3 = (ends[1][0] + ends[1][1]) * 0.5
		if Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z)) < 1.0:
			continue
		(_streets[key] as Array).append({"a": Vector2(a.x, a.z), "b": Vector2(b.x, b.z), "width": width, "y": (a.y + b.y) * 0.5})


## The two disjoint corner pairs with the shortest total span: a ribbon quad's ends.
func _quad_ends(c: Array[Vector3]) -> Array:
	var pairings: Array = [[[c[0], c[1]], [c[2], c[3]]], [[c[0], c[2]], [c[1], c[3]]], [[c[0], c[3]], [c[1], c[2]]]]
	var best: Array = pairings[0]
	var best_span: float = INF
	for pairing: Array in pairings:
		var span: float = (pairing[0][0] as Vector3).distance_to(pairing[0][1]) + (pairing[1][0] as Vector3).distance_to(pairing[1][1])
		if span < best_span:
			best_span = span
			best = pairing
	return best


func _pave_step(key: Vector2i, budget_usec: int) -> bool:
	var tile: Dictionary = _tiles.get(key, {})
	if tile.is_empty():
		return true
	var job: Dictionary = _pave_jobs[key]
	var tris: PackedVector3Array = job["tris"]
	var surface: PackedFloat32Array = job["surface"]
	var ground: PackedFloat32Array = tile["data"]
	var deadline: int = Time.get_ticks_usec() + budget_usec
	var i: int = job["next"]
	while i + 2 < tris.size():
		_pave_triangle(tile, surface, ground, tris[i], tris[i + 1], tris[i + 2])
		i += 3
		if Time.get_ticks_usec() >= deadline:
			break
	job["next"] = i
	if i + 2 < tris.size():
		return false
	tile["surface"] = surface
	tile["paved"] = true
	return true


func _pave_triangle(tile: Dictionary, surface: PackedFloat32Array, ground: PackedFloat32Array, a: Vector3, b: Vector3, c: Vector3) -> void:
	var e1: Vector3 = b - a
	var e2: Vector3 = c - a
	var det: float = e1.x * e2.z - e2.x * e1.z
	if absf(det) < 1e-6:
		return
	## The ribbon's plane as y = a.y + gx * dx + gz * dz.
	var gx: float = (e1.y * e2.z - e2.y * e1.z) / det
	var gz: float = (e2.y * e1.x - e1.y * e2.x) / det
	var n: int = tile["n"]
	var step: float = tile["step"]
	var ox: float = tile["ox"]
	var oz: float = tile["oz"]
	var z0: float = minf(a.z, minf(b.z, c.z))
	var z1: float = maxf(a.z, maxf(b.z, c.z))
	for cz: int in range(maxi(ceili((z0 - step - oz) / step), 0), mini(floori((z1 + step - oz) / step), n - 1) + 1):
		var z: float = oz + cz * step
		var span: Vector2 = _row_span(a, b, c, clampf(z, z0, z1))
		span = _union(span, _row_span(a, b, c, clampf(z - step, z0, z1)))
		span = _union(span, _row_span(a, b, c, clampf(z + step, z0, z1)))
		for cx: int in range(maxi(ceili((span.x - step - ox) / step), 0), mini(floori((span.y + step - ox) / step), n - 1) + 1):
			var k: int = cz * n + cx
			var y: float = a.y + gx * (ox + cx * step - a.x) + gz * (z - a.z)
			if y > surface[k] and y - ground[k] < PAVED_MAX_LIFT_M:
				surface[k] = y


## X extent of the triangle along the line at z (empty as x > y).
func _row_span(a: Vector3, b: Vector3, c: Vector3, z: float) -> Vector2:
	return _union(_union(_edge_span(a, b, z), _edge_span(b, c, z)), _edge_span(c, a, z))


func _edge_span(p: Vector3, q: Vector3, z: float) -> Vector2:
	if z < minf(p.z, q.z) or z > maxf(p.z, q.z):
		return Vector2(INF, -INF)
	if absf(q.z - p.z) < 1e-6:
		return Vector2(minf(p.x, q.x), maxf(p.x, q.x))
	var x: float = lerpf(p.x, q.x, (z - p.z) / (q.z - p.z))
	return Vector2(x, x)


func _union(p: Vector2, q: Vector2) -> Vector2:
	return Vector2(minf(p.x, q.x), maxf(p.y, q.y))


func _start_snow(key: Vector2i) -> void:
	if not SnowField.high_quality() or not _tiles.has(key):
		return
	var origin: Vector2 = Vector2(key) * CHUNK_M
	if SnowChunkCover.is_cached(origin):
		_attach_snow(key, SnowChunkCover.cached(origin))
		return
	_snow_jobs[key] = SnowChunkCover.begin(self, origin, CHUNK_M, self)
	set_process(true)


func _attach_snow(key: Vector2i, cover: MeshInstance3D) -> void:
	if cover == null:
		return
	cover.name = "Snow_%d_%d" % [key.x, key.y]
	_snow_root.add_child(cover)
	_snow[key] = cover


func _drop(key: Vector2i) -> void:
	_tiles.erase(key)
	_pave_jobs.erase(key)
	_streets.erase(key)
	_snow_jobs.erase(key)
	_boot_keys.erase(key)
	if _snow.has(key):
		(_snow[key] as Node).queue_free()
		_snow.erase(key)
	if not _outlines.has(key):
		return
	_outlines.erase(key)
	for cell: Vector2i in _cells.keys():
		var refs: Array = (_cells[cell] as Array).filter(func(r: Vector2i) -> bool: return _chunk_of_ref(r) != key)
		if refs.is_empty():
			_cells.erase(cell)
		else:
			_cells[cell] = refs
