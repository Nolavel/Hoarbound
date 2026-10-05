class_name SnowChunkCover
extends RefCounted
## Settled snow over a whole streamed city chunk: a grid on the terrain whose
## vertices carry the city wind factor; depth and ridges come from the shader.

const WIND_FIELD_PATH: String = "res://data/world/key_west/snow_wind.png"
const SHADER: Shader = preload("res://shaders/environment/snow/snow_chunk_cover.gdshader")
const STEP_M: float = 2.0
const BAKE_VERSION: int = 1
const CLIP_EPS: float = 0.0001
const MIN_PIECE_AREA_M2: float = 0.00001
## Snow thins to nothing this close above the sea, as SnowField does.
const SHORE_M: Vector2 = Vector2(0.05, 0.8)
const SEA_LEVEL_M: float = 0.04
## Finished meshes kept after their chunk unloads; the mesh never depends on weather.
const CACHE_SIZE: int = 12

static var _field: SnowField
static var _material: ShaderMaterial
static var _cache: Dictionary = {}
static var _cache_order: Array[Vector2] = []


## One chunk mesh built a few rows per frame; `step` until it returns true.
class Job extends RefCounted:
	var terrain: IslandTerrain
	var city: Object
	var origin: Vector2
	var size_m: float
	var n: int
	var row: int = 0
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var open := PackedByteArray()
	var indices := PackedInt32Array()
	var exact_obstacles: bool = false
	var contours: Array[PackedVector2Array] = []
	var contour_cursor: int = 0
	## Each exact footprint is triangulated once; cells index only nearby triangles.
	var obstacle_triangles: Array[PackedVector2Array] = []
	var obstacle_cells: Dictionary = {}


## Mesh for the square chunk at `origin` of side `size_m`, or null when no snow lies there.
static func build(terrain: IslandTerrain, origin: Vector2, size_m: float, city: Object = null) -> MeshInstance3D:
	if _cache.has(origin):
		return cached(origin)
	var job: Job = begin(terrain, origin, size_m, city)
	step(job, 1 << 40)
	return finish(job)


## True when a finished mesh for this chunk is cached.
static func is_cached(origin: Vector2) -> bool:
	return _cache.has(origin)


## A new instance of the cached mesh at `origin`, or null (also when that chunk holds no snow).
static func cached(origin: Vector2) -> MeshInstance3D:
	var mesh: ArrayMesh = _cache.get(origin)
	_touch(origin)
	return _instance(mesh) if mesh != null else null


## Applies the live snow material to a geometry-only mesh baked in the editor.
static func from_baked(mesh: ArrayMesh) -> MeshInstance3D:
	_ensure_shared()
	mesh.surface_set_material(0, _material)
	return _instance(mesh)


static func begin(terrain: IslandTerrain, origin: Vector2, size_m: float, city: Object = null) -> Job:
	_ensure_shared()
	var job := Job.new()
	job.terrain = terrain
	job.city = city
	job.origin = origin
	job.size_m = size_m
	job.n = int(size_m / STEP_M) + 1
	var count: int = job.n * job.n
	job.verts.resize(count)
	job.uvs.resize(count)
	job.normals.resize(count)
	job.open.resize(count)
	job.exact_obstacles = city != null and city.has_method(&"get_snow_obstacles_in_rect")
	if job.exact_obstacles:
		var source_contours: Array = city.call(&"get_snow_obstacles_in_rect", Rect2(origin, Vector2.ONE * size_m))
		for contour: PackedVector2Array in source_contours:
			job.contours.append(contour)
	return job


## Advances the job within `budget_usec`; rows of samples first, then normals and faces.
static func step(job: Job, budget_usec: int) -> bool:
	var start: int = Time.get_ticks_usec()
	var n: int = job.n
	while job.contour_cursor < job.contours.size():
		_index_obstacle(job, job.contours[job.contour_cursor])
		job.contour_cursor += 1
		if Time.get_ticks_usec() - start >= budget_usec:
			return false
	if job.contour_cursor == job.contours.size() and not job.contours.is_empty():
		job.contours.clear()
		job.contour_cursor = 0
	while job.row < 2 * n:
		if job.row < n:
			_sample_row(job, job.row)
		else:
			_shade_row(job, job.row - n)
		job.row += 1
		if Time.get_ticks_usec() - start >= budget_usec:
			break
	return job.row >= 2 * n


## Turns a finished job into its chunk instance and caches the mesh.
static func finish(job: Job) -> MeshInstance3D:
	var mesh: ArrayMesh = null
	if not job.indices.is_empty():
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = job.verts
		arrays[Mesh.ARRAY_NORMAL] = job.normals
		arrays[Mesh.ARRAY_TEX_UV] = job.uvs
		arrays[Mesh.ARRAY_INDEX] = job.indices
		mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		## Depth lifts vertices in the shader; keep the chunk from culling early.
		mesh.custom_aabb = AABB(Vector3(job.origin.x, -5.0, job.origin.y), Vector3(job.size_m, 60.0, job.size_m))
		mesh.surface_set_material(0, _material)
	_cache[job.origin] = mesh
	_touch(job.origin)
	while _cache_order.size() > CACHE_SIZE:
		_cache.erase(_cache_order.pop_front())
	return _instance(mesh) if mesh != null else null


static func clear_cache() -> void:
	_cache.clear()
	_cache_order.clear()


static func _ensure_shared() -> void:
	if _field != null:
		return
	_field = SnowField.new()
	_field.load_wind_field(WIND_FIELD_PATH)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	if _field.wind_texture != null:
		_material.set_shader_parameter("wind_tex", _field.wind_texture)
		_material.set_shader_parameter("wind_origin", _field.wind_field_origin)
		_material.set_shader_parameter("wind_extent",
			Vector2(_field.wind_field.get_width(), _field.wind_field.get_height()) * _field.wind_field_cell_m)
		_material.set_shader_parameter("wind_max", _field.wind_field_max)


## Subtract convex triangles of the source footprints from only the grid cells
## they touch. Triangulating a building once also handles a house entirely inside
## a 2 m cell: there is no polygon-with-hole result to accidentally fill.
static func _index_obstacle(job: Job, contour: PackedVector2Array) -> void:
	var chunk_bounds := Rect2(job.origin, Vector2.ONE * job.size_m)
	var triangles: PackedInt32Array = Geometry2D.triangulate_polygon(contour)
	if triangles.is_empty():
		push_warning("SnowChunkCover: skipped a non-triangulable city footprint")
		return
	for t: int in range(0, triangles.size(), 3):
		var tri := PackedVector2Array([
			contour[triangles[t]], contour[triangles[t + 1]], contour[triangles[t + 2]]
		])
		var bounds := Rect2(tri[0], Vector2.ZERO)
		for point: Vector2 in tri:
			bounds = bounds.expand(point)
		if not bounds.intersects(chunk_bounds, true):
			continue
		var id: int = job.obstacle_triangles.size()
		job.obstacle_triangles.append(tri)
		var lo := Vector2i(
			clampi(floori((bounds.position.x - job.origin.x) / STEP_M), 0, job.n - 2),
			clampi(floori((bounds.position.y - job.origin.y) / STEP_M), 0, job.n - 2)
		)
		var hi := Vector2i(
			clampi(floori((bounds.end.x - job.origin.x) / STEP_M), 0, job.n - 2),
			clampi(floori((bounds.end.y - job.origin.y) / STEP_M), 0, job.n - 2)
		)
		for z: int in range(lo.y, hi.y + 1):
			for x: int in range(lo.x, hi.x + 1):
				var cell := Vector2i(x, z)
				var ids: Array = job.obstacle_cells.get(cell, [])
				ids.append(id)
				job.obstacle_cells[cell] = ids


static func _sample_row(job: Job, j: int) -> void:
	for i: int in range(job.n):
		var at: Vector2 = job.origin + Vector2(i, j) * STEP_M
		var h: float = job.terrain.get_height(at.x, at.y)
		var shore: float = smoothstep(SEA_LEVEL_M + SHORE_M.x, SEA_LEVEL_M + SHORE_M.y, h)
		var k: int = j * job.n + i
		job.verts[k] = Vector3(at.x, h, at.y)
		job.uvs[k] = Vector2(_field.wind_factor(at) * shore, shore)
		## Exact city footprints clip triangles below. Stand-alone jobs retain the
		## baked raster mask because they have no source polygon index.
		job.open[k] = 1 if job.exact_obstacles else (0 if _field.is_building(at) else 1)


## Ground normals from neighbouring heights; ridges add their slope in the shader.
static func _shade_row(job: Job, j: int) -> void:
	var n: int = job.n
	var v: PackedVector3Array = job.verts
	for i: int in range(n):
		var hx: float = v[j * n + mini(i + 1, n - 1)].y - v[j * n + maxi(i - 1, 0)].y
		var hz: float = v[mini(j + 1, n - 1) * n + i].y - v[maxi(j - 1, 0) * n + i].y
		job.normals[j * n + i] = Vector3(-hx, 2.0 * STEP_M, -hz).normalized()
	## Faces of row j - 1 need normals on both their top and bottom edges.
	if j == 0:
		return
	var cell_j: int = j - 1
	for i: int in range(n - 1):
		var a: int = cell_j * n + i
		## Front faces wind clockwise seen from above.
		if job.exact_obstacles:
			var ids: Array = job.obstacle_cells.get(Vector2i(i, cell_j), [])
			if ids.is_empty():
				job.indices.append_array([a, a + 1, a + n, a + 1, a + n + 1, a + n])
			else:
				_append_clipped_triangle(job, a, a + 1, a + n, ids)
				_append_clipped_triangle(job, a + 1, a + n + 1, a + n, ids)
		elif job.open[a] + job.open[a + 1] + job.open[a + n] + job.open[a + n + 1] == 4:
			job.indices.append_array([a, a + 1, a + n, a + 1, a + n + 1, a + n])


static func _append_clipped_triangle(job: Job, a: int, b: int, c: int, obstacle_ids: Array) -> void:
	var source := PackedVector2Array([
		Vector2(job.verts[a].x, job.verts[a].z),
		Vector2(job.verts[b].x, job.verts[b].z),
		Vector2(job.verts[c].x, job.verts[c].z),
	])
	var source_area: float = _signed_area(source)
	## Most cells under a building lie wholly inside one source triangle. Drop
	## those before allocating any clipped polygons.
	for obstacle_id: Variant in obstacle_ids:
		if _triangle_contains_polygon(job.obstacle_triangles[int(obstacle_id)], source):
			return
	var pieces: Array[PackedVector2Array] = []
	pieces.append(source)
	for obstacle_id: Variant in obstacle_ids:
		var next_pieces: Array[PackedVector2Array] = []
		var obstacle: PackedVector2Array = job.obstacle_triangles[int(obstacle_id)]
		for piece: PackedVector2Array in pieces:
			next_pieces.append_array(_subtract_convex_triangle(piece, obstacle))
		pieces = next_pieces
		if pieces.is_empty():
			return
	for piece: PackedVector2Array in pieces:
		if piece.size() < 3 or absf(_signed_area(piece)) < MIN_PIECE_AREA_M2:
			continue
		var start: int = job.verts.size()
		for point: Vector2 in piece:
			var weights: Vector3 = _barycentric(point, source)
			var y: float = job.verts[a].y * weights.x + job.verts[b].y * weights.y + job.verts[c].y * weights.z
			job.verts.append(Vector3(point.x, y, point.y))
			job.uvs.append(job.uvs[a] * weights.x + job.uvs[b] * weights.y + job.uvs[c] * weights.z)
			job.normals.append((job.normals[a] * weights.x + job.normals[b] * weights.y + job.normals[c] * weights.z).normalized())
		for k: int in range(1, piece.size() - 1):
			var tri := PackedVector2Array([piece[0], piece[k], piece[k + 1]])
			var area: float = _signed_area(tri)
			if absf(area) >= MIN_PIECE_AREA_M2:
				if area * source_area >= 0.0:
					job.indices.append_array([start, start + k, start + k + 1])
				else:
					job.indices.append_array([start, start + k + 1, start + k])


static func _triangle_contains_polygon(triangle: PackedVector2Array, polygon: PackedVector2Array) -> bool:
	var sign: float = 1.0 if _signed_area(triangle) >= 0.0 else -1.0
	for point: Vector2 in polygon:
		for edge: int in range(3):
			if (triangle[(edge + 1) % 3] - triangle[edge]).cross(point - triangle[edge]) * sign < -CLIP_EPS:
				return false
	return true


## Peel the portion outside each edge of a convex obstacle triangle. The
## retained pieces are convex, including when the obstacle lies wholly inside
## the snow triangle; no hole rings are triangulated as snow.
static func _subtract_convex_triangle(subject: PackedVector2Array, obstacle: PackedVector2Array) -> Array[PackedVector2Array]:
	var inside: PackedVector2Array = subject
	var outside: Array[PackedVector2Array] = []
	var sign: float = 1.0 if _signed_area(obstacle) >= 0.0 else -1.0
	for edge: int in range(3):
		var a: Vector2 = obstacle[edge]
		var b: Vector2 = obstacle[(edge + 1) % 3]
		var peeled: PackedVector2Array = _clip_half_plane(inside, a, b, sign, false)
		if peeled.size() >= 3 and absf(_signed_area(peeled)) >= MIN_PIECE_AREA_M2:
			outside.append(peeled)
		inside = _clip_half_plane(inside, a, b, sign, true)
		if inside.size() < 3:
			break
	return outside


static func _clip_half_plane(polygon: PackedVector2Array, a: Vector2, b: Vector2, sign: float, keep_inside: bool) -> PackedVector2Array:
	var clipped := PackedVector2Array()
	if polygon.is_empty():
		return clipped
	var previous: Vector2 = polygon[polygon.size() - 1]
	var previous_side: float = (b - a).cross(previous - a) * sign
	var previous_kept: bool = previous_side >= -CLIP_EPS if keep_inside else previous_side <= CLIP_EPS
	for current: Vector2 in polygon:
		var current_side: float = (b - a).cross(current - a) * sign
		var current_kept: bool = current_side >= -CLIP_EPS if keep_inside else current_side <= CLIP_EPS
		if previous_kept != current_kept:
			var denom: float = previous_side - current_side
			if absf(denom) > 0.00000001:
				clipped = _with_distinct(clipped, previous.lerp(current, clampf(previous_side / denom, 0.0, 1.0)))
		if current_kept:
			clipped = _with_distinct(clipped, current)
		previous = current
		previous_side = current_side
		previous_kept = current_kept
	if clipped.size() > 1 and clipped[0].distance_squared_to(clipped[clipped.size() - 1]) < CLIP_EPS * CLIP_EPS:
		clipped.remove_at(clipped.size() - 1)
	return clipped


static func _with_distinct(points: PackedVector2Array, point: Vector2) -> PackedVector2Array:
	if points.is_empty() or points[points.size() - 1].distance_squared_to(point) >= CLIP_EPS * CLIP_EPS:
		points.append(point)
	return points


static func _signed_area(points: PackedVector2Array) -> float:
	var twice_area: float = 0.0
	if points.size() < 3:
		return 0.0
	## Local coordinates avoid cancellation for tiny slivers at kilometre-scale
	## world coordinates.
	for i: int in range(1, points.size() - 1):
		twice_area += (points[i] - points[0]).cross(points[i + 1] - points[0])
	return twice_area * 0.5


static func _barycentric(point: Vector2, triangle: PackedVector2Array) -> Vector3:
	var a: Vector2 = triangle[0]
	var b: Vector2 = triangle[1]
	var c: Vector2 = triangle[2]
	var area: float = (b - a).cross(c - a)
	if absf(area) < 0.00000001:
		return Vector3(1.0, 0.0, 0.0)
	var wb: float = (point - a).cross(c - a) / area
	var wc: float = (b - a).cross(point - a) / area
	return Vector3(1.0 - wb - wc, wb, wc)


static func _touch(origin: Vector2) -> void:
	_cache_order.erase(origin)
	_cache_order.append(origin)


static func _instance(mesh: ArrayMesh) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.name = "SnowChunkCover"
	inst.mesh = mesh
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return inst
