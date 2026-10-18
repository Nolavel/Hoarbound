class_name WorldSnowTileSurface
extends "res://scripts/systems/world/snow/world_snow_tile_prototype.gd"

## Production replacement for moving render geometry, NOT the snow simulator.
## Persistent world-keyed tiles, immutable terrain baseline, three radial
## topology densities (10/20/40 cm). Once a tile is visited, it is never
## downgraded; its deformation image is never resampled on a focus change.
## All LOD borders sample the same 10 cm world positions, with zipper collars.
const PRODUCTION_SHADER: Shader = preload("res://shaders/environment/snow/snow_chunk_cover.gdshader")
const GROUND_STEP_M: float = 2.0
const SEA_M: float = 0.04
var snow_field: SnowField
var track_store: SnowTrackStore
var _levels: Dictionary = {} # permanent tile key -> finest topology ever requested
var _ground_cache: Dictionary = {} # 2m point -> (height, shore, prev*shore, storm*shore)


func focus(world_xz: Vector2) -> void:
	super.focus(world_xz)
	# Only upgrade geometry in the direction of increased detail. A passed print
	# never returns to a lower-resolution mesh and never changes stored texels.
	for variant: Variant in _surface.keys():
		var key: Vector2i = variant
		var desired: int = _lod_for_key(key, world_xz)
		if desired < int(_levels.get(key, 2)):
			_levels[key] = desired
			var mesh: ArrayMesh = _build_baked_mesh(key)
			_meshes[key] = mesh
			(_surface[key] as MeshInstance3D).mesh = mesh


func _lod_for_key(key: Vector2i, focus_xz: Vector2) -> int:
	var center: Vector2 = key_origin(key) + Vector2.ONE * TILE_M * 0.5
	var r: float = center.distance_to(focus_xz)
	return 0 if r < 4.2 else (1 if r < 9.0 else 2)


func _install(key: Vector2i) -> void:
	if not _data.has(key):
		var tile_image: Image = Image.create_empty(SIDE, SIDE, false, Image.FORMAT_RGBAF)
		tile_image.fill(Color.TRANSPARENT)
		if track_store != null and track_store.tiles.has(key):
			# Native save/streaming store is the cold-start fallback; live high
			# precision deformation never gets replaced during recenter.
			tile_image = track_store.restore(key_origin(key), TILE_M, SIDE)
		_data[key] = tile_image
	if not _frozen.has(key):
		_frozen[key] = ImageTexture.create_from_image(_data[key])
	if not _meshes.has(key):
		_levels[key] = _lod_for_key(key, Vector2(_focus_cell) * TILE_M + Vector2.ONE * 1.6)
		_meshes[key] = _build_baked_mesh(key)
		mesh_builds += 1
	var mat := ShaderMaterial.new()
	mat.shader = PRODUCTION_SHADER
	mat.set_shader_parameter("is_world_tile", true)
	mat.set_shader_parameter("world_tiles_active", true)
	mat.set_shader_parameter("deformation", _frozen[key])
	mat.set_shader_parameter("tile_origin", key_origin(key))
	mat.set_shader_parameter("tile_m", TILE_M)
	mat.set_shader_parameter("debug_height", debug_height)
	mat.set_shader_parameter("reference_y", reference_y)
	if snow_field != null and snow_field.wind_texture != null:
		mat.set_shader_parameter("wind_tex", snow_field.wind_texture)
		mat.set_shader_parameter("wind_origin", snow_field.wind_field_origin)
		mat.set_shader_parameter("wind_extent",
			Vector2(snow_field.wind_field.get_width(), snow_field.wind_field.get_height()) * snow_field.wind_field_cell_m)
		mat.set_shader_parameter("wind_max", snow_field.wind_field_max)
	var inst := MeshInstance3D.new()
	inst.name = "WorldSnow_%d_%d_L%d" % [key.x, key.y, int(_levels[key])]
	inst.mesh = _meshes[key]
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.extra_cull_margin = 10.0
	inst.layers = 1 | RenderLayers.SNOW_TILE_EXPERIMENT
	add_child(inst)
	_surface[key] = inst


func _world_ground(x: float, z: float) -> Vector4:
	# Reconstruct exactly the two triangles in SnowChunkCover._shade_row;
	# no sampling of a moving SnowField or new DEM heights at each recenter.
	var x0: int = floori(x / GROUND_STEP_M)
	var z0: int = floori(z / GROUND_STEP_M)
	var f := Vector2(clampf(x / GROUND_STEP_M - float(x0), 0.0, 1.0),
		clampf(z / GROUND_STEP_M - float(z0), 0.0, 1.0))
	var a := _ground_node(Vector2i(x0, z0))
	var b := _ground_node(Vector2i(x0 + 1, z0))
	var c := _ground_node(Vector2i(x0, z0 + 1))
	var d := _ground_node(Vector2i(x0 + 1, z0 + 1))
	return a + (b - a) * f.x + (c - a) * f.y if f.x + f.y <= 1.0 else d + (c - d) * (1.0 - f.x) + (b - d) * (1.0 - f.y)


func _ground_node(coord: Vector2i) -> Vector4:
	if _ground_cache.has(coord):
		return _ground_cache[coord]
	var x: float = float(coord.x) * GROUND_STEP_M
	var z: float = float(coord.y) * GROUND_STEP_M
	var h: float = float(_top_at.call(x, z))
	var shore: float = smoothstep(SEA_M + 0.05, SEA_M + 0.8, h)
	# Equivalent to SnowChunkCover's 2m GPU vertex evaluation. Barycentric
	# interpolation of BOTH weather factors is exact for any intermediate LOD,
	# so upgrading triangles does not modify the untouched settled surface.
	var winds: Vector2 = snow_field.wind_factors(Vector2(x, z)) if snow_field != null else Vector2.ONE
	var sample := Vector4(h, shore, winds.x * shore, winds.y * shore)
	_ground_cache[coord] = sample
	return sample


func _point(vertices: PackedVector3Array, normals: PackedVector3Array,
	uvs: PackedVector2Array, uv2s: PackedVector2Array, x: float, z: float) -> int:
	var sample := _world_ground(x, z)
	var ex: float = _world_ground(x + 0.1, z).x - _world_ground(x - 0.1, z).x
	var ez: float = _world_ground(x, z + 0.1).x - _world_ground(x, z - 0.1).x
	var idx: int = vertices.size()
	vertices.append(Vector3(x, sample.x, z))
	normals.append(Vector3(-ex, 0.2, -ez).normalized())
	uvs.append(Vector2(0.0, sample.y))
	uv2s.append(Vector2(sample.z, sample.w))
	return idx


func _tri(indices: PackedInt32Array, a: int, b: int, c: int) -> void:
	indices.append(a)
	indices.append(b)
	indices.append(c)


func _build_baked_mesh(key: Vector2i) -> ArrayMesh:
	var origin: Vector2 = key_origin(key)
	var level: int = int(_levels.get(key, 2))
	var div: int = GRID if level == 0 else (16 if level == 1 else 8)
	var inset: float = 0.0 if level == 0 else (0.2 if level == 1 else 0.4)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()
	var start: float = inset
	var side: float = TILE_M - 2.0 * inset
	var stride: float = side / float(div if level == 0 else (14 if level == 1 else 6))
	var cells: int = GRID if level == 0 else (14 if level == 1 else 6)
	# Inner grid. Its exact outer boundary is stitched to the universal
	# high-resolution 10cm tile perimeter for ALL three LODs.
	for iz: int in range(cells + 1):
		for ix: int in range(cells + 1):
			_point(verts, normals, uvs, uv2s, origin.x + start + float(ix) * stride,
				origin.y + start + float(iz) * stride)
	for iz: int in range(cells):
		for ix: int in range(cells):
			var a: int = iz * (cells + 1) + ix
			_tri(indices, a, a + 1, a + cells + 1)
			_tri(indices, a + 1, a + cells + 2, a + cells + 1)
	if level != 0:
		var outer_idx: Array[int] = []
		var inner_idx: Array[int] = []
		var outer_time: Array[float] = []
		var inner_time: Array[float] = []
		for side_id: int in range(4):
			for i: int in range(GRID):
				var t: float = float(i) / float(GRID)
				var q := _perimeter_point(origin, 0.0, side_id, t)
				outer_idx.append(_point(verts, normals, uvs, uv2s, q.x, q.y))
				outer_time.append(float(side_id) + t)
			for i: int in range(cells):
				var t: float = float(i) / float(cells)
				var q := _perimeter_point(origin, inset, side_id, t)
				inner_idx.append(_point(verts, normals, uvs, uv2s, q.x, q.y))
				inner_time.append(float(side_id) + t)
		var ai: int = 0
		var bi: int = 0
		while ai < outer_idx.size() and bi < inner_idx.size():
			var na: float = outer_time[ai + 1] if ai + 1 < outer_idx.size() else 4.0
			var nb: float = inner_time[bi + 1] if bi + 1 < inner_idx.size() else 4.0
			var oa: int = outer_idx[ai]
			var ib: int = inner_idx[bi]
			if na < nb - 0.00001:
				_tri(indices, oa, outer_idx[(ai + 1) % outer_idx.size()], ib)
				ai += 1
			elif nb < na - 0.00001:
				_tri(indices, oa, inner_idx[(bi + 1) % inner_idx.size()], ib)
				bi += 1
			else:
				_tri(indices, oa, outer_idx[(ai + 1) % outer_idx.size()], inner_idx[(bi + 1) % inner_idx.size()])
				_tri(indices, oa, inner_idx[(bi + 1) % inner_idx.size()], ib)
				ai += 1
				bi += 1
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = AABB(Vector3(origin.x, -30.0, origin.y), Vector3(TILE_M, 120.0, TILE_M))
	return mesh


func _perimeter_point(origin: Vector2, inset: float, side_id: int, t: float) -> Vector2:
	var a: float = inset
	var b: float = TILE_M - inset
	match side_id:
		0:
			return origin + Vector2(lerpf(a, b, t), a)
		1:
			return origin + Vector2(b, lerpf(a, b, t))
		2:
			return origin + Vector2(lerpf(b, a, t), b)
		_:
			return origin + Vector2(a, lerpf(b, a, t))


func get_lod_summary() -> Dictionary:
	var tiers := [0, 0, 0]
	for key: Variant in _surface.keys():
		tiers[int(_levels.get(key, 2))] += 1
	return {"l0": tiers[0], "l1": tiers[1], "l2": tiers[2],
		"persistent_tiles": _data.size(), "current_resident": _surface.size()}
