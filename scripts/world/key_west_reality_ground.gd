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
## A sample on a chunk's far edge belongs to the next chunk; nudge back into this one.
const EDGE_NUDGE_M: float = 0.01

var _tiles: Dictionary = {}
var _outlines: Dictionary = {}
var _cells: Dictionary = {}
var _container: Node3D
var _snow_jobs: Dictionary = {}
var _snow: Dictionary = {}
var _snow_root: Node3D


func _ready() -> void:
	add_to_group(GROUND_GROUP)
	add_to_group(OBSTACLE_GROUP)
	_snow_root = Node3D.new()
	_snow_root.name = "SnowCover"
	_snow_root.top_level = true
	add_child(_snow_root)
	set_process(false)


## Builds pending chunk snow covers within the frame budget; the one under Henry finishes at once.
func _process(_delta: float) -> void:
	if _snow_jobs.is_empty():
		set_process(false)
		return
	var window: Vector4 = SnowShell.live_window
	var centre: Vector2 = Vector2(window.x, window.y) + Vector2.ONE * window.z * 0.5
	var key: Vector2i = _snow_jobs.keys()[0]
	for candidate: Vector2i in _snow_jobs.keys():
		if (Vector2(candidate) + Vector2.ONE * 0.5).distance_to(centre / CHUNK_M) < (Vector2(key) + Vector2.ONE * 0.5).distance_to(centre / CHUNK_M):
			key = candidate
	var under_henry: bool = window.w > 0.5 and Rect2(Vector2(key) * CHUNK_M, Vector2.ONE * CHUNK_M).has_point(centre)
	var job: SnowChunkCover.Job = _snow_jobs[key]
	if SnowChunkCover.step(job, 1 << 40 if under_henry else SNOW_BUDGET_USEC):
		_snow_jobs.erase(key)
		_attach_snow(key, SnowChunkCover.finish(job))


func on_world_ready(context: WorldContext) -> void:
	_container = context.stream_container
	for system: Node in context.systems:
		if system is StreamingSystem:
			(system as StreamingSystem).cell_state_changed.connect(_on_cell)
	if _container != null:
		for chunk: Node in _container.get_children():
			_index(chunk)


## Terrain height (NAVD88 m) at local x/z, bilinear on the chunk's HeightMapShape3D data.
func get_height(x: float, z: float) -> float:
	var tile: Dictionary = _tile_at(x, z)
	if tile.is_empty():
		return FALLBACK_Y
	var n: int = tile["n"]
	var step: float = tile["step"]
	var fx: float = clampf((x - float(tile["ox"])) / step, 0.0, n - 1.001)
	var fz: float = clampf((z - float(tile["oz"])) / step, 0.0, n - 1.001)
	var cx: int = int(fx)
	var cz: int = int(fz)
	var data: PackedFloat32Array = tile["data"]
	var tx: float = fx - cx
	var tz: float = fz - cz
	var top: float = lerpf(data[cz * n + cx], data[cz * n + cx + 1], tx)
	var bottom: float = lerpf(data[(cz + 1) * n + cx], data[(cz + 1) * n + cx + 1], tx)
	return lerpf(top, bottom, tz)


## True once the chunk under x/z is live, so get_height reads real ground there and not FALLBACK_Y.
func has_ground_at(x: float, z: float) -> bool:
	return not _tile_at(x, z).is_empty()


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
	_snow_jobs.erase(key)
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
