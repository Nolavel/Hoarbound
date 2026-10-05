class_name ChunkedCityMassing
extends Node3D

## Experimental chunk-aware Key West city renderer for issue #138.
## It is deliberately isolated from the production streaming path.
##
## Ring 0: per-chunk oriented building proxies.
## Near detail: exact OSM footprint extrusion, built lazily per chunk.
## Roads: per-chunk ribbon batches.
## Airport: explicit runway/taxiway/apron layer.
## Metadata stays in the dataset and can be surfaced as debug labels.

## Walls reach this far below a building's lowest corner, so slopes show no gap.
const WALL_SINK_M: float = 0.3
## Height of the low wall round a flat roof.
const PARAPET_M: float = 0.45
## Frame time spent building chunk snow while it streams in.
const SNOW_BUDGET_USEC: int = 4000
## Missing-bake fallback: chunks near Henry's window build in the same frame.
const SNOW_SYNC_MARGIN_M: float = 256.0
## Source footprints are indexed in smaller world cells than rendered city chunks.
const SNOW_FOOTPRINT_CELL_M: float = 32.0
const SNOW_BAKE_DIR: String = "res://data/world/key_west/snow_chunk"

var terrain: IslandTerrain
var data: Dictionary = {}
var chunk_size_m: float = 512.0
var detail_radius_m: float = 1150.0
var massing_radius_m: float = 3600.0

var _chunks: Dictionary = {}
var _buildings: Array = []
var _roads: Array = []
var _airport_features: Array = []
var _labels_node: Node3D
var _grid_node: Node3D
var _ring0_roads: Node3D
var _enrichment: Dictionary = {}
var _visual_materials: Dictionary = {}
var _stream_to_chunk: Dictionary = {}
var _far_stream_to_chunk: Dictionary = {}
var _far_sector_nodes: Dictionary = {}
var _stream_active: Dictionary = {}
var _stream_ring0_ready: bool = false
var _excluded_building_ids: Dictionary = {}
var _snow_footprint_cells: Dictionary = {}
var _snow_footprint_polygons: Array[PackedVector2Array] = []
var _snow_footprint_bounds: Array[Rect2] = []
var _snow_authored_obstacles: Dictionary = {}
var _helper_collision_chunks: Dictionary = {}
## Chunk snow built a slice per frame, keyed by chunk id.
var _snow_jobs: Dictionary = {}
var _baked_snow: Dictionary = {}

var _massing_material: Material
var _detail_material: Material
var _road_material: Material
var _runway_material: Material
var _taxiway_material: Material
var _apron_material: Material


func configure(terrain_node: IslandTerrain, data_path: String, enrichment_path: String = "") -> bool:
	terrain = terrain_node
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("ChunkedCityMassing: invalid dataset %s" % data_path)
		return false
	data = parsed as Dictionary
	chunk_size_m = float(data.get("chunk_size_m", 512.0))
	var rings: Dictionary = data.get("rings", {})
	detail_radius_m = float(rings.get("detail_radius_m", 1150.0))
	massing_radius_m = float(rings.get("massing_radius_m", 3600.0))
	_buildings = data.get("buildings", [])
	_roads = data.get("roads", [])
	_airport_features = data.get("airport_features", [])
	if not enrichment_path.is_empty() and FileAccess.file_exists(enrichment_path):
		var parsed_enrichment: Variant = JSON.parse_string(FileAccess.get_file_as_string(enrichment_path))
		if typeof(parsed_enrichment) == TYPE_DICTIONARY:
			_enrichment = parsed_enrichment as Dictionary
	_visual_materials = KeyWestCityVisuals.make_materials()
	_make_materials()
	_create_chunk_states()
	_index_snow_footprints()
	_load_baked_snow_index()
	_build_global_visual_index()
	return true


## Runtime-source API consumed by StreamingSystem. The JSON snapshot stays
## untouched; only exact chunk geometry is created/destroyed around the focus.
## Suppresses source footprints replaced by authored gameplay buildings.
## This is runtime-only: city_preview.json remains immutable.
func exclude_buildings_near(point: Vector2, radius_m: float = 1.0) -> int:
	var excluded: int = 0
	for index: int in range(_buildings.size()):
		var building := _buildings[index] as Dictionary
		var proxy: Dictionary = building.get("proxy", {})
		var position := Vector2(float(proxy.get("x", 0.0)), float(proxy.get("z", 0.0)))
		if position.distance_to(point) <= radius_m:
			if not _excluded_building_ids.has(index):
				_excluded_building_ids[index] = true
				excluded += 1
	return excluded


## Hides every building whose real footprint overlaps `outline`. Returns how many.
func exclude_buildings_overlapping(outline: PackedVector2Array) -> int:
	var excluded: int = 0
	var bounds := Rect2(outline[0], Vector2.ZERO)
	for p: Vector2 in outline:
		bounds = bounds.expand(p)
	for index: int in range(_buildings.size()):
		if _excluded_building_ids.has(index):
			continue
		var polygon: PackedVector2Array = KeyWestCityVisuals.normalized_footprint(
			(_buildings[index] as Dictionary).get("footprint", [])
		)
		if polygon.size() < 3:
			continue
		var box := Rect2(polygon[0], Vector2.ZERO)
		for p: Vector2 in polygon:
			box = box.expand(p)
		if not box.intersects(bounds):
			continue
		if not Geometry2D.intersect_polygons(polygon, outline).is_empty():
			_excluded_building_ids[index] = true
			excluded += 1
	return excluded


func _filtered_building_ids(ids: Array) -> Array:
	var filtered: Array = []
	for id_variant: Variant in ids:
		var index: int = int(id_variant)
		if not _excluded_building_ids.has(index):
			filtered.append(index)
	return filtered


## An authored building that replaces OSM geometry can keep far and near snow
## clear even before its scene or collision body enters the streaming ring.
func register_snow_obstacle(id: StringName, outline: PackedVector2Array) -> void:
	if _snow_authored_obstacles.has(id):
		return
	var polygon: PackedVector2Array = outline.duplicate()
	if polygon.size() > 2 and polygon[0].is_equal_approx(polygon[polygon.size() - 1]):
		polygon.remove_at(polygon.size() - 1)
	if polygon.size() < 3:
		return
	var area: float = KeyWestCityVisuals.signed_area(polygon)
	if absf(area) < 0.0001:
		return
	if area < 0.0:
		polygon.reverse()
	var index: int = _snow_footprint_polygons.size()
	_snow_footprint_polygons.append(PackedVector2Array())
	_snow_footprint_bounds.append(Rect2())
	_insert_snow_footprint(index, polygon)
	_snow_authored_obstacles[id] = index


## Exact city walls for snow, independent of streamed detail and collision bodies.
## The same source polygons build the nearby houses; runtime exclusions still win.
func has_snow_obstacle_at(point: Vector2) -> bool:
	var cell := Vector2i(
		floori(point.x / SNOW_FOOTPRINT_CELL_M),
		floori(point.y / SNOW_FOOTPRINT_CELL_M)
	)
	var ids: Array = _snow_footprint_cells.get(cell, [])
	for id_variant: Variant in ids:
		var index: int = int(id_variant)
		if index < _buildings.size() and _excluded_building_ids.has(index):
			continue
		var bounds: Rect2 = _snow_footprint_bounds[index]
		if point.x < bounds.position.x or point.y < bounds.position.y \
			or point.x > bounds.end.x or point.y > bounds.end.y:
			continue
		if Geometry2D.is_point_in_polygon(point, _snow_footprint_polygons[index]):
			return true
	return false


## World-XZ source contours intersecting a snow cell; callers may clip them to
## `bounds`. Each contour has positive signed area and is returned only once.
func get_snow_obstacles_in_rect(bounds: Rect2) -> Array[PackedVector2Array]:
	var contours: Array[PackedVector2Array] = []
	var region: Rect2 = bounds.abs()
	var lo := Vector2i(
		floori(region.position.x / SNOW_FOOTPRINT_CELL_M),
		floori(region.position.y / SNOW_FOOTPRINT_CELL_M)
	)
	var hi := Vector2i(
		floori(region.end.x / SNOW_FOOTPRINT_CELL_M),
		floori(region.end.y / SNOW_FOOTPRINT_CELL_M)
	)
	var seen: Dictionary = {}
	for z: int in range(lo.y, hi.y + 1):
		for x: int in range(lo.x, hi.x + 1):
			var ids: Array = _snow_footprint_cells.get(Vector2i(x, z), [])
			for id_variant: Variant in ids:
				var index: int = int(id_variant)
				if seen.has(index):
					continue
				seen[index] = true
				if index < _buildings.size() and _excluded_building_ids.has(index):
					continue
				if not _snow_footprint_bounds[index].intersects(region, true):
					continue
				contours.append(_snow_footprint_polygons[index])
	return contours


## Index every polygon into all cells its true bounds cross, once at configuration.
## Re-normalizing thousands of OSM point arrays on each snow sample is too costly.
func _index_snow_footprints() -> void:
	_snow_footprint_cells.clear()
	_snow_footprint_polygons.clear()
	_snow_footprint_bounds.clear()
	_snow_authored_obstacles.clear()
	_snow_footprint_polygons.resize(_buildings.size())
	_snow_footprint_bounds.resize(_buildings.size())
	for index: int in range(_buildings.size()):
		var building := _buildings[index] as Dictionary
		var polygon: PackedVector2Array = KeyWestCityVisuals.normalized_footprint(
			building.get("footprint", [])
		)
		if polygon.size() < 3:
			continue
		_insert_snow_footprint(index, polygon)


func _insert_snow_footprint(index: int, polygon: PackedVector2Array) -> void:
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for vertex: Vector2 in polygon:
		bounds = bounds.expand(vertex)
	_snow_footprint_polygons[index] = polygon
	_snow_footprint_bounds[index] = bounds
	var lo := Vector2i(
		floori(bounds.position.x / SNOW_FOOTPRINT_CELL_M),
		floori(bounds.position.y / SNOW_FOOTPRINT_CELL_M)
	)
	var hi := Vector2i(
		floori(bounds.end.x / SNOW_FOOTPRINT_CELL_M),
		floori(bounds.end.y / SNOW_FOOTPRINT_CELL_M)
	)
	for z: int in range(lo.y, hi.y + 1):
		for x: int in range(lo.x, hi.x + 1):
			var cell := Vector2i(x, z)
			var ids: Array = _snow_footprint_cells.get(cell, [])
			ids.append(index)
			_snow_footprint_cells[cell] = ids


func get_stream_chunks() -> Array:
	_index_stream_chunks()
	var descriptors: Array = []
	var radius: float = chunk_size_m * 0.70710678
	for stream_id_variant: Variant in _stream_to_chunk:
		var stream_id := stream_id_variant as StringName
		var cid: String = String(_stream_to_chunk[stream_id])
		var state: Dictionary = _chunks[cid]
		var center: Vector2 = state["center"]
		descriptors.append({
			"id": stream_id,
			"position": Vector3(center.x, 0.0, center.y),
			"radius": radius,
		})
	_far_stream_to_chunk.clear()
	for cid_variant: Variant in _chunks:
		var cid: String = String(cid_variant)
		var far_path: String = _far_sector_path(cid)
		if not FileAccess.file_exists(far_path):
			continue
		var stream_id := StringName("kw_far_%s" % cid.replace(":", "_"))
		_far_stream_to_chunk[stream_id] = cid
		var center: Vector2 = (_chunks[cid] as Dictionary)["center"]
		descriptors.append({
			"id": stream_id,
			"position": Vector3(center.x, 0.0, center.y),
			"radius": massing_radius_m + radius,
		})
	return descriptors


func build_stream_ring0(_container: Node3D) -> void:
	if _stream_ring0_ready:
		return
	_index_stream_chunks()
	for state_variant: Variant in _chunks.values():
		var state := state_variant as Dictionary
		var detail := state["detail"] as Node3D
		if detail != null:
			detail.visible = false
		var roads := state["roads"] as Node3D
		if roads != null:
			roads.visible = false
	_stream_ring0_ready = true


func activate_stream_chunk(stream_id: StringName, _container: Node3D) -> Node3D:
	_index_stream_chunks()
	if _far_stream_to_chunk.has(stream_id):
		var far_cid: String = String(_far_stream_to_chunk[stream_id])
		var mesh: Mesh = ResourceLoader.load(_far_sector_path(far_cid)) as Mesh
		if mesh == null:
			push_warning("ChunkedCityMassing: far sector failed to load: %s" % far_cid)
			return null
		var far_holder := Node3D.new()
		far_holder.name = "FarCity_%s" % far_cid.replace(":", "_")
		var far_center: Vector2 = (_chunks[far_cid] as Dictionary)["center"]
		far_holder.position = Vector3(far_center.x, 0.0, far_center.y)
		var far_instance := MeshInstance3D.new()
		far_instance.name = "BakedUltraLow"
		far_instance.mesh = mesh
		far_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		far_instance.visibility_range_begin = 640.0
		far_instance.visibility_range_begin_margin = 80.0
		far_instance.visibility_range_end = massing_radius_m
		far_instance.visibility_range_end_margin = 120.0
		far_instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		far_holder.add_child(far_instance)
		add_child(far_holder)
		_far_sector_nodes[stream_id] = far_holder
		return far_holder
	var cid: String = String(_stream_to_chunk.get(stream_id, ""))
	if cid.is_empty() or not _chunks.has(cid):
		return null
	var state := _chunks[cid] as Dictionary
	if state.get("global_visuals") == null:
		var origin_values: Array = (state["data"] as Dictionary).get("origin", [])
		if origin_values.size() < 2:
			return null
		var origin := Vector2(float(origin_values[0]), float(origin_values[1]))
		var bounds := Rect2(origin, Vector2.ONE * chunk_size_m)
		var helper := KeyWestCityVisuals.build_supplemental_node(
			terrain, _enrichment, _visual_materials, bounds,
			not _helper_collision_chunks.has(cid)
		)
		_helper_collision_chunks[cid] = true
		if helper.get_child_count() > 0:
			(state["node"] as Node3D).add_child(helper)
			state["global_visuals"] = helper
		else:
			helper.free()
			state["global_visuals"] = null
	if state.get("airport") == null:
		var airport := _build_airport_chunk(state["data"] as Dictionary)
		if airport != null:
			(state["node"] as Node3D).add_child(airport)
		state["airport"] = airport
	_ensure_detail(state)
	_ensure_roads(state)
	if state.get("props") == null:
		var props := KeyWestStreetProps.build_chunk_body(cid)
		if props != null:
			(state["node"] as Node3D).add_child(props)
		state["props"] = props
	if state.get("prop_visuals") == null:
		var visuals := KeyWestStreetProps.build_chunk_visuals(cid)
		if visuals != null:
			(state["node"] as Node3D).add_child(visuals)
		state["prop_visuals"] = visuals
	if state.get("snow") == null and not _snow_jobs.has(cid) and SnowField.high_quality():
		_start_snow(cid, state)
	var massing := state["massing"] as Node3D
	if massing != null:
		massing.visible = false
	var detail := state["detail"] as Node3D
	if detail != null:
		detail.visible = true
	var roads := state["roads"] as Node3D
	if roads != null:
		roads.visible = true
	_stream_active[stream_id] = true
	return state["node"] as Node3D


func _process(_delta: float) -> void:
	if _snow_jobs.is_empty():
		return
	## After a jump the window lands late; chunks it now reaches finish at once.
	for near: String in _snow_jobs.keys():
		if _near_snow_window((_snow_jobs[near] as SnowChunkCover.Job).origin):
			_finish_snow(near, 1 << 40)
	if not _snow_jobs.is_empty():
		_finish_snow(_snow_jobs.keys()[0], SNOW_BUDGET_USEC)


func _finish_snow(cid: String, budget_usec: int) -> void:
	var job: SnowChunkCover.Job = _snow_jobs[cid]
	if SnowChunkCover.step(job, budget_usec):
		_snow_jobs.erase(cid)
		_attach_snow(_chunks[cid] as Dictionary, SnowChunkCover.finish(job))


## True when Henry's snow window is not live yet or lies within reach of this chunk.
func _near_snow_window(origin: Vector2) -> bool:
	var window: Vector4 = SnowShell.live_window
	var rect := Rect2(origin, Vector2.ONE * chunk_size_m).grow(SNOW_SYNC_MARGIN_M)
	return window.w < 0.5 or rect.has_point(Vector2(window.x, window.y) + Vector2.ONE * window.z * 0.5)


## Load static geometry at activation; source builds remain a development fallback.
func _start_snow(cid: String, state: Dictionary) -> void:
	if _baked_snow.has(cid):
		var baked_file: String = String(_baked_snow[cid])
		if baked_file.is_empty():
			return
		var baked_mesh: ArrayMesh = ResourceLoader.load(SNOW_BAKE_DIR.path_join(baked_file)) as ArrayMesh
		if baked_mesh != null:
			_attach_snow(state, SnowChunkCover.from_baked(baked_mesh))
			return
		push_warning("ChunkedCityMassing: missing baked snow for %s; rebuilding from source" % cid)
	var o: Array = (state["data"] as Dictionary).get("origin", [0, 0])
	var origin := Vector2(float(o[0]), float(o[1]))
	if SnowChunkCover.is_cached(origin):
		_attach_snow(state, SnowChunkCover.cached(origin))
		return
	if _near_snow_window(origin):
		_attach_snow(state, SnowChunkCover.build(terrain, origin, chunk_size_m, self))
		return
	_snow_jobs[cid] = SnowChunkCover.begin(terrain, origin, chunk_size_m, self)


func _load_baked_snow_index() -> void:
	_baked_snow.clear()
	var path: String = SNOW_BAKE_DIR.path_join("manifest.json")
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return
	var manifest: Dictionary = parsed as Dictionary
	if int(manifest.get("version", -1)) != SnowChunkCover.BAKE_VERSION \
		or not is_equal_approx(float(manifest.get("chunk_size_m", -1.0)), chunk_size_m):
		push_warning("ChunkedCityMassing: incompatible snow bake; rebuilding from source")
		return
	_baked_snow = manifest.get("chunks", {}) as Dictionary


func _attach_snow(state: Dictionary, snow: MeshInstance3D) -> void:
	if snow != null:
		(state["node"] as Node3D).add_child(snow)
	state["snow"] = snow


func deactivate_stream_chunk(stream_id: StringName) -> void:
	if _far_stream_to_chunk.has(stream_id):
		var far_holder := _far_sector_nodes.get(stream_id) as Node3D
		if is_instance_valid(far_holder):
			far_holder.queue_free()
		_far_sector_nodes.erase(stream_id)
		return
	var cid: String = String(_stream_to_chunk.get(stream_id, ""))
	if cid.is_empty() or not _chunks.has(cid):
		return
	var state := _chunks[cid] as Dictionary
	var detail := state["detail"] as Node3D
	if is_instance_valid(detail):
		detail.queue_free()
	state["detail"] = null
	var roads := state["roads"] as Node3D
	if is_instance_valid(roads):
		roads.queue_free()
	state["roads"] = null
	var props := state.get("props") as Node3D
	if is_instance_valid(props):
		props.queue_free()
	state["props"] = null
	var prop_visuals := state.get("prop_visuals") as Node3D
	if is_instance_valid(prop_visuals):
		prop_visuals.queue_free()
	state["prop_visuals"] = null
	var helper := state.get("global_visuals") as Node3D
	if is_instance_valid(helper):
		helper.queue_free()
	state["global_visuals"] = null
	var airport := state.get("airport") as Node3D
	if is_instance_valid(airport):
		airport.queue_free()
	state["airport"] = null
	_snow_jobs.erase(cid)
	var snow := state.get("snow") as Node3D
	if is_instance_valid(snow):
		snow.queue_free()
	state["snow"] = null
	var massing := state["massing"] as Node3D
	if massing != null:
		massing.visible = true
	_stream_active.erase(stream_id)


func get_stream_active_detail_count() -> int:
	return _stream_active.size()


func _index_stream_chunks() -> void:
	if not _stream_to_chunk.is_empty():
		return
	for cid_variant: Variant in _chunks:
		var cid: String = String(cid_variant)
		var stream_id := StringName("kw_city_%s" % cid.replace(":", "_"))
		_stream_to_chunk[stream_id] = cid


func get_stats() -> Dictionary:
	return data.get("stats", {})


func get_airport_center() -> Vector2:
	var airport: Dictionary = data.get("airport", {})
	var center: Variant = airport.get("center")
	if center is Array and center.size() >= 2:
		return Vector2(float(center[0]), float(center[1]))
	return Vector2.ZERO


func get_airport_metadata() -> Dictionary:
	var airport: Dictionary = data.get("airport", {})
	return airport.get("metadata", {})


func get_densest_chunk_center() -> Vector2:
	var best_count: int = -1
	var best := Vector2.ZERO
	var chunks: Dictionary = data.get("chunks", {})
	for chunk_variant: Variant in chunks.values():
		var chunk := chunk_variant as Dictionary
		var count: int = (chunk.get("building_ids", []) as Array).size()
		if count <= best_count:
			continue
		best_count = count
		var origin_values: Array = chunk.get("origin", [])
		if origin_values.size() < 2:
			continue
		best = Vector2(
			float(origin_values[0]) + chunk_size_m * 0.5,
			float(origin_values[1]) + chunk_size_m * 0.5
		)
	return best


func set_focus(point: Vector2, show_all_massing: bool = false) -> void:
	for state_variant: Variant in _chunks.values():
		var state := state_variant as Dictionary
		var center: Vector2 = state["center"]
		var distance: float = center.distance_to(point)
		var detailed: bool = distance <= detail_radius_m
		var massing: bool = show_all_massing or distance <= massing_radius_m

		if detailed:
			_ensure_detail(state)
			_ensure_roads(state)
			var detail_node: Node3D = state["detail"]
			if detail_node != null:
				detail_node.visible = true
			var mass_node: Node3D = state["massing"]
			if mass_node != null:
				mass_node.visible = false
			var road_node: Node3D = state["roads"]
			if road_node != null:
				road_node.visible = true
		else:
			_ensure_massing(state)
			if massing:
				_ensure_roads(state)
			var detail_node: Node3D = state["detail"]
			if detail_node != null:
				detail_node.visible = false
			var mass_node: Node3D = state["massing"]
			if mass_node != null:
				mass_node.visible = massing
			var road_node: Node3D = state["roads"]
			if road_node != null:
				road_node.visible = massing


func set_chunk_grid_visible(enabled: bool) -> void:
	if enabled and _grid_node == null:
		_grid_node = _build_chunk_grid()
	if _grid_node != null:
		_grid_node.visible = enabled


func get_map_label_entries(
	point: Vector2,
	radius_m: float = 95.0,
	max_house_numbers: int = 22,
	max_street_names: int = 8
) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var house_candidates: Array[Dictionary] = []
	for index: int in range(_buildings.size()):
		if _excluded_building_ids.has(index):
			continue
		var building := _buildings[index] as Dictionary
		var metadata: Dictionary = building.get("metadata", {})
		var number: String = String(metadata.get("addr:housenumber", "")).strip_edges()
		if number.is_empty():
			continue
		var proxy: Dictionary = building.get("proxy", {})
		var position := Vector2(float(proxy.get("x", 0.0)), float(proxy.get("z", 0.0)))
		var distance: float = position.distance_to(point)
		if distance > radius_m:
			continue
		var ground: float = maxf(terrain.get_height(position.x, position.y), 0.0) if terrain != null else 0.0
		var height: float = KeyWestCityVisuals.effective_height(building, _enrichment)
		house_candidates.append({
			"distance": distance,
			"kind": &"house",
			"text": number,
			"position": Vector3(position.x, ground + height + 1.8, position.y),
		})
	house_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["distance"]) < float(b["distance"])
	)
	for i: int in range(mini(max_house_numbers, house_candidates.size())):
		entries.append(house_candidates[i])

	var best_by_street: Dictionary = {}
	for road_variant: Variant in _roads:
		var road := road_variant as Dictionary
		var name: String = String(road.get("name", "")).strip_edges()
		if name.is_empty():
			continue
		var points: Array = road.get("points", [])
		if points.size() < 2:
			continue
		var best_distance: float = INF
		var best_position := Vector2.ZERO
		for i: int in range(points.size() - 1):
			var a_values := points[i] as Array
			var b_values := points[i + 1] as Array
			if a_values.size() < 2 or b_values.size() < 2:
				continue
			var a := Vector2(float(a_values[0]), float(a_values[1]))
			var b := Vector2(float(b_values[0]), float(b_values[1]))
			var middle := a.lerp(b, 0.5)
			var distance: float = middle.distance_to(point)
			if distance < best_distance:
				best_distance = distance
				best_position = middle
		if best_distance > radius_m:
			continue
		var previous: Dictionary = best_by_street.get(name, {})
		if previous.is_empty() or best_distance < float(previous.get("distance", INF)):
			var ground: float = maxf(terrain.get_height(best_position.x, best_position.y), 0.0) if terrain != null else 0.0
			best_by_street[name] = {
				"distance": best_distance,
				"kind": &"street",
				"text": name,
				"position": Vector3(best_position.x, ground + 2.4, best_position.y),
			}

	var street_candidates: Array[Dictionary] = []
	for street_variant: Variant in best_by_street.values():
		street_candidates.append(street_variant as Dictionary)
	street_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["distance"]) < float(b["distance"])
	)
	for i: int in range(mini(max_street_names, street_candidates.size())):
		entries.append(street_candidates[i])
	return entries


func show_metadata_labels(point: Vector2, radius_m: float = 500.0) -> void:
	clear_metadata_labels()
	_labels_node = Node3D.new()
	_labels_node.name = "MetadataLabels"
	add_child(_labels_node)

	var candidates: Array = []
	for building_variant: Variant in _buildings:
		var building := building_variant as Dictionary
		var proxy: Dictionary = building.get("proxy", {})
		var position := Vector2(float(proxy.get("x", 0.0)), float(proxy.get("z", 0.0)))
		var distance: float = position.distance_to(point)
		if distance > radius_m:
			continue
		var metadata: Dictionary = building.get("metadata", {})
		var label_text: String = _building_label(metadata)
		if label_text.is_empty():
			continue
		candidates.append([distance, position, label_text])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))

	var placed: int = 0
	for candidate_variant: Variant in candidates:
		if placed >= 10:
			break
		var candidate := candidate_variant as Array
		var p: Vector2 = candidate[1]
		_add_label(String(candidate[2]), p, 13.0)
		placed += 1

	var road_candidates: Array = []
	for road_variant: Variant in _roads:
		var road := road_variant as Dictionary
		var name: String = String(road.get("name", ""))
		if name.is_empty():
			continue
		var points: Array = road.get("points", [])
		if points.size() < 2:
			continue
		var middle: Array = points[points.size() / 2]
		var p := Vector2(float(middle[0]), float(middle[1]))
		var distance: float = p.distance_to(point)
		if distance <= radius_m:
			road_candidates.append([distance, p, name])
	road_candidates.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	placed = 0
	for candidate_variant: Variant in road_candidates:
		if placed >= 12:
			break
		var candidate := candidate_variant as Array
		_add_label(String(candidate[2]), candidate[1], 7.0)
		placed += 1


func clear_metadata_labels() -> void:
	if _labels_node != null and is_instance_valid(_labels_node):
		_labels_node.queue_free()
	_labels_node = null


func _building_label(metadata: Dictionary) -> String:
	var name: String = String(metadata.get("name", ""))
	if not name.is_empty():
		return name
	var number: String = String(metadata.get("addr:housenumber", ""))
	var street: String = String(metadata.get("addr:street", ""))
	if not number.is_empty() and not street.is_empty():
		return "%s %s" % [number, street]
	return ""


func _add_label(text: String, position: Vector2, lift: float) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = Vector3(
		position.x,
		maxf(terrain.get_height(position.x, position.y), 0.0) + lift,
		position.y
	)
	label.font_size = 28
	label.outline_size = 7
	label.pixel_size = 0.075
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	_labels_node.add_child(label)


func _make_materials() -> void:
	_massing_material = _standard_material(Color(0.48, 0.51, 0.53), 0.92)
	_detail_material = _visual_materials.get("building", _standard_material(Color(0.72, 0.74, 0.74), 0.88))
	_road_material = _visual_materials.get("asphalt", _standard_material(Color(0.13, 0.14, 0.15), 0.97))
	_runway_material = _standard_material(Color(0.10, 0.11, 0.12), 0.94)
	_taxiway_material = _standard_material(Color(0.20, 0.21, 0.22), 0.94)
	_apron_material = _standard_material(Color(0.31, 0.32, 0.33), 0.93)


func _standard_material(color: Color, roughness: float) -> Material:
	return StylizedEnvironmentMaterial.make(color, roughness)


func _create_chunk_states() -> void:
	var chunks: Dictionary = data.get("chunks", {})
	for cid: String in chunks:
		var chunk := chunks[cid] as Dictionary
		var origin_values: Array = chunk.get("origin", [])
		if origin_values.size() < 2:
			continue
		var center := Vector2(
			float(origin_values[0]) + chunk_size_m * 0.5,
			float(origin_values[1]) + chunk_size_m * 0.5
		)
		var holder := Node3D.new()
		holder.name = "CityChunk_%s" % cid.replace(":", "_")
		add_child(holder)
		_chunks[cid] = {
			"data": chunk,
			"node": holder,
			"center": center,
			"massing": null,
			"detail": null,
			"roads": null,
			"global_visuals": null,
			"airport": null,
		}


func _far_sector_path(cid: String) -> String:
	return "res://data/world/key_west/far_city/%s.obj" % cid.replace(":", "_")


func _ensure_massing(state: Dictionary) -> void:
	if state["massing"] != null:
		return
	var chunk: Dictionary = state["data"]
	var building_ids: Array = _filtered_building_ids(chunk.get("building_ids", []))
	if building_ids.is_empty():
		return

	var box := BoxMesh.new()
	box.size = Vector3.ONE
	box.material = _massing_material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = box
	multimesh.instance_count = building_ids.size()

	for local_i: int in range(building_ids.size()):
		var building := _buildings[int(building_ids[local_i])] as Dictionary
		var proxy: Dictionary = building.get("proxy", {})
		var x: float = float(proxy.get("x", 0.0))
		var z: float = float(proxy.get("z", 0.0))
		var width: float = maxf(float(proxy.get("width", 2.5)), 2.5)
		var depth: float = maxf(float(proxy.get("depth", 2.5)), 2.5)
		var height: float = maxf(float(building.get("height", 3.0)), 3.0)
		var angle: float = float(proxy.get("angle", 0.0))
		var ground: float = maxf(terrain.get_height(x, z), 0.0)
		var basis := Basis(Vector3.UP, angle).scaled_local(Vector3(width, height, depth))
		multimesh.set_instance_transform(
			local_i,
			Transform3D(basis, Vector3(x, ground + height * 0.5 + 0.04, z))
		)

	var instance := MultiMeshInstance3D.new()
	instance.name = "Ring0Massing"
	instance.multimesh = multimesh
	(state["node"] as Node3D).add_child(instance)
	state["massing"] = instance


func _ensure_detail(state: Dictionary) -> void:
	if state["detail"] != null:
		return
	var chunk: Dictionary = state["data"]
	var building_ids: Array = _filtered_building_ids(chunk.get("building_ids", []))
	if building_ids.is_empty():
		return
	var holder := Node3D.new()
	holder.name = "BuildingDetail"
	var mesh := _build_exact_building_mesh(building_ids)
	if mesh != null:
		var instance := MeshInstance3D.new()
		instance.name = "FootprintWalls"
		instance.mesh = mesh
		holder.add_child(instance)
	var roof_mesh := KeyWestCityVisuals.build_roof_mesh(
		_buildings, building_ids, terrain, _enrichment, _visual_materials.get("roof")
	)
	if roof_mesh != null:
		var roof_instance := MeshInstance3D.new()
		roof_instance.name = "Roofs"
		roof_instance.mesh = roof_mesh
		holder.add_child(roof_instance)
	_add_collision(holder, [mesh, roof_mesh] as Array[Mesh])
	var facade_node := KeyWestCityVisuals.build_facade_accents(
		_buildings, building_ids, terrain, _visual_materials.get("awning")
	)
	if facade_node != null:
		holder.add_child(facade_node)
	if holder.get_child_count() == 0:
		holder.free()
		return
	(state["node"] as Node3D).add_child(holder)
	state["detail"] = holder


func _build_exact_building_mesh(building_ids: Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	for id_variant: Variant in building_ids:
		var building := _buildings[int(id_variant)] as Dictionary
		var polygon: PackedVector2Array = KeyWestCityVisuals.normalized_footprint(building.get("footprint", []))
		if polygon.size() < 3:
			continue
		var triangles: PackedInt32Array = Geometry2D.triangulate_polygon(polygon)
		if triangles.is_empty():
			continue
		var height: float = KeyWestCityVisuals.effective_height(building, _enrichment)
		var facade: Color = KeyWestCityVisuals.facade_color(building, _enrichment)
		var roof: Color = KeyWestCityVisuals.roof_color(building, _enrichment)
		## One base for walls and roof; walls sink below it so slopes never show a gap.
		var base: float = KeyWestCityVisuals.building_base(polygon, terrain)
		var top: float = base + height + 0.05
		var bottom: float = base - WALL_SINK_M
		var flat: bool = KeyWestCityVisuals.roof_shape(building, _enrichment) == "flat" \
			or KeyWestCityVisuals.footprint_box(polygon).is_empty()
		var wall_top: float = top + (PARAPET_M if flat else 0.0)

		for i: int in range(0, triangles.size(), 3):
			var a: Vector2 = polygon[triangles[i]]
			var b: Vector2 = polygon[triangles[i + 1]]
			var c: Vector2 = polygon[triangles[i + 2]]
			KeyWestCityVisuals.emit_tri(
				vertices, normals, colors, indices,
				Vector3(a.x, top, a.y), Vector3(b.x, top, b.y), Vector3(c.x, top, c.y), Vector3.UP, roof
			)

		for i: int in range(polygon.size()):
			var a: Vector2 = polygon[i]
			var b: Vector2 = polygon[(i + 1) % polygon.size()]
			var edge: Vector2 = b - a
			if edge.length_squared() < 0.0001:
				continue
			## Positive area: the outward side of edge a→b is (dz, -dx).
			var out := Vector3(edge.y, 0.0, -edge.x).normalized()
			_emit_quad(vertices, normals, colors, indices, a, b, bottom, wall_top, out, facade)
			if flat:
				## The parapet's inner face, seen from above the roof.
				_emit_quad(vertices, normals, colors, indices, a, b, top, wall_top, -out, facade)

	if vertices.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _detail_material)
	return mesh


func _emit_quad(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	a: Vector2,
	b: Vector2,
	low: float,
	high: float,
	facing: Vector3,
	color: Color
) -> void:
	var a0 := Vector3(a.x, low, a.y)
	var b0 := Vector3(b.x, low, b.y)
	var a1 := Vector3(a.x, high, a.y)
	var b1 := Vector3(b.x, high, b.y)
	KeyWestCityVisuals.emit_tri(vertices, normals, colors, indices, a0, b0, a1, facing, color)
	KeyWestCityVisuals.emit_tri(vertices, normals, colors, indices, a1, b0, b1, facing, color)


## A static body shaped like the given meshes, so Henry and snow meet the city.
func _add_collision(holder: Node3D, meshes: Array[Mesh]) -> void:
	var faces := PackedVector3Array()
	for mesh: Mesh in meshes:
		if mesh != null:
			faces.append_array(mesh.get_faces())
	if faces.is_empty():
		return
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var collision := CollisionShape3D.new()
	collision.shape = shape
	var body := StaticBody3D.new()
	body.name = "CityCollision"
	body.add_child(collision)
	holder.add_child(body)


func _ensure_roads(state: Dictionary) -> void:
	if state["roads"] != null:
		return
	var chunk: Dictionary = state["data"]
	var segments: Array = chunk.get("road_segments", [])
	if segments.is_empty():
		return
	var node := KeyWestCityVisuals.build_road_node(
		segments, _roads, terrain, _enrichment, _visual_materials
	)
	if node == null or node.get_child_count() == 0:
		if node != null:
			node.free()
		return
	(state["node"] as Node3D).add_child(node)
	state["roads"] = node


func _build_road_mesh(segments: Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for segment_variant: Variant in segments:
		var segment := segment_variant as Dictionary
		var road := _roads[int(segment.get("road_id", -1))] as Dictionary
		var a_values: Array = segment.get("a", [])
		var b_values: Array = segment.get("b", [])
		if a_values.size() < 2 or b_values.size() < 2:
			continue
		_append_ribbon_segment(
			vertices, normals, indices,
			Vector2(float(a_values[0]), float(a_values[1])),
			Vector2(float(b_values[0]), float(b_values[1])),
			maxf(float(road.get("width", 4.0)) * 0.5, 1.0),
			0.12
		)
	if vertices.is_empty():
		return null
	return _mesh_from_arrays(vertices, normals, indices, _road_material)


func _build_airport_chunk(chunk: Dictionary) -> Node3D:
	var feature_ids: Array = chunk.get("airport_feature_ids", [])
	if feature_ids.is_empty():
		return null
	var airport := Node3D.new()
	airport.name = "AirportChunk_%s" % String(chunk.get("id", "" )).replace(":", "_")
	var origin_values: Array = chunk.get("origin", [])
	if origin_values.size() < 2:
		airport.free()
		return null
	var bounds := Rect2(
		Vector2(float(origin_values[0]), float(origin_values[1])),
		Vector2.ONE * float(chunk.get("size_m", chunk_size_m))
	)
	var runway_segments: Array = []
	var taxiway_segments: Array = []
	var areas: Array = []
	var features: Array = []
	for feature_id_variant: Variant in feature_ids:
		var feature_id: int = int(feature_id_variant)
		if feature_id < 0 or feature_id >= _airport_features.size():
			continue
		var feature := _airport_features[feature_id] as Dictionary
		features.append(feature)
		var kind: String = String(feature.get("kind", ""))
		if bool(feature.get("is_area", false)):
			areas.append(feature)
		elif kind == "runway":
			runway_segments.append(feature)
		elif kind in ["taxiway", "taxilane"]:
			taxiway_segments.append(feature)

	_add_airport_ribbons(airport, runway_segments, _runway_material, 0.22, "Runways", bounds)
	_add_airport_ribbons(airport, taxiway_segments, _taxiway_material, 0.20, "Taxiways", bounds)
	_add_airport_areas(airport, areas, bounds)
	KeyWestCityVisuals.add_airport_markings(airport, features, terrain, _visual_materials, bounds)
	return airport


func _build_global_visual_index() -> void:
	KeyWestStreetProps.colliders.clear()
	KeyWestStreetProps.visuals.clear()
	KeyWestStreetProps.crossings.clear()
	var props_index: Node3D = KeyWestStreetProps.build(terrain, _enrichment, _roads)
	props_index.free()


func _add_airport_ribbons(
	parent: Node3D,
	features: Array,
	material: Material,
	lift: float,
	node_name: String,
	bounds: Rect2
) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for feature_variant: Variant in features:
		var feature := feature_variant as Dictionary
		var points: Array = feature.get("points", [])
		var half_width: float = maxf(float(feature.get("width", 10.0)) * 0.5, 2.0)
		for i: int in range(points.size() - 1):
			var a_values: Array = points[i]
			var b_values: Array = points[i + 1]
			var a := Vector2(float(a_values[0]), float(a_values[1]))
			var b := Vector2(float(b_values[0]), float(b_values[1]))
			var clipped: PackedVector2Array = KeyWestCityVisuals._clip_segment(a, b, bounds)
			if clipped.size() != 2:
				continue
			_append_ribbon_segment(
				vertices, normals, indices,
				clipped[0], clipped[1],
				half_width, lift
			)
	if vertices.is_empty():
		return
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = _mesh_from_arrays(vertices, normals, indices, material)
	parent.add_child(instance)


func _add_airport_areas(parent: Node3D, features: Array, bounds: Rect2) -> void:
	for feature_variant: Variant in features:
		var feature := feature_variant as Dictionary
		var values: Array = feature.get("points", [])
		if values.size() < 3:
			continue
		var polygon := PackedVector2Array()
		for point_variant: Variant in values:
			var point := point_variant as Array
			polygon.append(Vector2(float(point[0]), float(point[1])))
		var clipper := PackedVector2Array([
			bounds.position,
			Vector2(bounds.end.x, bounds.position.y),
			bounds.end,
			Vector2(bounds.position.x, bounds.end.y),
		])
		var pieces: Array[PackedVector2Array] = Geometry2D.clip_polygons(polygon, clipper)
		for piece: PackedVector2Array in pieces:
			var triangles: PackedInt32Array = Geometry2D.triangulate_polygon(piece)
			if triangles.is_empty():
				continue
			var vertices := PackedVector3Array()
			var normals := PackedVector3Array()
			var indices := PackedInt32Array()
			for p: Vector2 in piece:
				vertices.append(Vector3(p.x, maxf(terrain.get_height(p.x, p.y), 0.0) + 0.16, p.y))
				normals.append(Vector3.UP)
			for index: int in triangles:
				indices.append(index)
			var material: Material = _apron_material
			var kind: String = String(feature.get("kind", ""))
			if kind == "runway":
				material = _runway_material
			elif kind in ["taxiway", "taxilane"]:
				material = _taxiway_material
			var instance := MeshInstance3D.new()
			instance.name = "AirportArea_%s_%s" % [kind, feature.get("id", 0)]
			instance.mesh = _mesh_from_arrays(vertices, normals, indices, material)
			parent.add_child(instance)


func _append_ribbon_segment(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	indices: PackedInt32Array,
	a: Vector2,
	b: Vector2,
	half_width: float,
	lift: float
) -> void:
	var delta := b - a
	if delta.length_squared() < 0.25:
		return
	var direction := delta.normalized()
	var side := Vector2(-direction.y, direction.x) * half_width
	var ay: float = maxf(terrain.get_height(a.x, a.y), 0.0) + lift
	var by: float = maxf(terrain.get_height(b.x, b.y), 0.0) + lift
	var base: int = vertices.size()
	vertices.append(Vector3(a.x + side.x, ay, a.y + side.y))
	vertices.append(Vector3(a.x - side.x, ay, a.y - side.y))
	vertices.append(Vector3(b.x + side.x, by, b.y + side.y))
	vertices.append(Vector3(b.x - side.x, by, b.y - side.y))
	for _j: int in range(4):
		normals.append(Vector3.UP)
	indices.append_array([
		base, base + 2, base + 1,
		base + 1, base + 2, base + 3,
	])


func _mesh_from_arrays(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	indices: PackedInt32Array,
	material: Material
) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


func _build_chunk_grid() -> Node3D:
	var holder := Node3D.new()
	holder.name = "ChunkGrid"
	add_child(holder)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var half: float = 2.5
	for state_variant: Variant in _chunks.values():
		var state := state_variant as Dictionary
		var chunk: Dictionary = state["data"]
		var origin_values: Array = chunk.get("origin", [])
		if origin_values.size() < 2:
			continue
		var ox: float = float(origin_values[0])
		var oz: float = float(origin_values[1])
		var a := Vector2(ox, oz)
		var b := Vector2(ox + chunk_size_m, oz)
		var c := Vector2(ox + chunk_size_m, oz + chunk_size_m)
		var d := Vector2(ox, oz + chunk_size_m)
		_append_ribbon_segment(vertices, normals, indices, a, b, half, 0.35)
		_append_ribbon_segment(vertices, normals, indices, b, c, half, 0.35)
		_append_ribbon_segment(vertices, normals, indices, c, d, half, 0.35)
		_append_ribbon_segment(vertices, normals, indices, d, a, half, 0.35)
	## Debug chunk boundaries stay deliberately unshaded and outside the
	## production stylized-lighting contract.
	var material := StylizedEnvironmentMaterial.make_unshaded(Color(0.92, 0.08, 0.06))
	var instance := MeshInstance3D.new()
	instance.mesh = _mesh_from_arrays(vertices, normals, indices, material)
	holder.add_child(instance)
	return holder
