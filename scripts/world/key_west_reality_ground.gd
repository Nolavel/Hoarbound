class_name KeyWestRealityGround
extends Node3D
## Ground heights and building outlines of the active Reality chunks, for systems written
## against IslandTerrain + KeyWestCity (snow). Reads only chunks the StreamingSystem made live.

const GROUND_GROUP: StringName = &"snow_ground"
const OBSTACLE_GROUP: StringName = &"snow_obstacles"
const CELL_M: float = 8.0
const CHUNK_M: float = 512.0
const FALLBACK_Y: float = 1.0

var _tiles: Dictionary = {}
var _outlines: Dictionary = {}
var _cells: Dictionary = {}
var _container: Node3D


func _ready() -> void:
	add_to_group(GROUND_GROUP)
	add_to_group(OBSTACLE_GROUP)


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
	var tile: Dictionary = _tiles.get(Vector2i(floori(x / CHUNK_M), floori(z / CHUNK_M)), {})
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


## True inside a building outline (the same prism outline the collision uses).
func has_snow_obstacle_at(point: Vector2) -> bool:
	for ref: Vector2i in _cells.get(Vector2i(floori(point.x / CELL_M), floori(point.y / CELL_M)), []):
		var rings: Array = _outlines.get(_chunk_of_ref(ref), [])
		if ref.y < rings.size() and Geometry2D.is_point_in_polygon(point, rings[ref.y]):
			return true
	return false


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
	if not chunk.has_meta("chunk_id"):
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


func _drop(key: Vector2i) -> void:
	_tiles.erase(key)
	if not _outlines.has(key):
		return
	_outlines.erase(key)
	for cell: Vector2i in _cells.keys():
		var refs: Array = (_cells[cell] as Array).filter(func(r: Vector2i) -> bool: return _chunk_of_ref(r) != key)
		if refs.is_empty():
			_cells.erase(cell)
		else:
			_cells[cell] = refs
