class_name SnowSurfaceClipmap
extends RefCounted

## Two-level near-snow geometry proof. L0 keeps boot-scale triangles around Henry;
## L1 covers the rest of SnowShell with a coarser grid. The one-cell transition
## collapses fine edge vertices onto the coarse lattice without overlapping opaque
## surfaces or leaving T-junction cracks.

const DEFAULT_L0_HALF_M: float = 3.84
const DEFAULT_L0_SPACING_M: float = 0.08
const DEFAULT_L1_SPACING_M: float = 0.16


static func build(
	window_m: float,
	l0_half_m: float = DEFAULT_L0_HALF_M,
	l0_spacing_m: float = DEFAULT_L0_SPACING_M,
	l1_spacing_m: float = DEFAULT_L1_SPACING_M
) -> ArrayMesh:
	var half: float = maxf(window_m * 0.5, 0.5)
	var coarse: float = clampf(l1_spacing_m, 0.04, half * 0.25)
	var ratio: int = maxi(2, roundi(coarse / maxf(l0_spacing_m, 0.01)))
	var fine: float = coarse / float(ratio)
	var max_core: float = maxf(coarse * 2.0, half - coarse * 2.0)
	var core: float = minf(maxf(l0_half_m, coarse * 2.0), max_core)
	core = floorf(core / coarse + 0.0001) * coarse
	var transition: float = core + coarse
	if transition >= half:
		core = maxf(coarse * 2.0, half - coarse * 2.0)
		core = floorf(core / coarse + 0.0001) * coarse
		transition = core + coarse

	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()

	## L0 core.
	_append_grid_rect(vertices, indices, -core, core, -core, core, fine)

	## L1 exterior, split into four non-overlapping rectangles around the hole.
	_append_grid_rect(vertices, indices, -half, half, -half, -transition, coarse)
	_append_grid_rect(vertices, indices, -half, half, transition, half, coarse)
	_append_grid_rect(vertices, indices, -half, -transition, -transition, transition, coarse)
	_append_grid_rect(vertices, indices, transition, half, -transition, transition, coarse)

	## One coarse cell stitches L0 to L1. The outer edge only has coarse vertices;
	## the inner edge keeps every fine vertex, so displacement cannot open a crack.
	_append_top_transition(vertices, indices, core, transition, fine, coarse, ratio)
	_append_bottom_transition(vertices, indices, core, transition, fine, coarse, ratio)
	_append_left_transition(vertices, indices, core, transition, fine, coarse, ratio)
	_append_right_transition(vertices, indices, core, transition, fine, coarse, ratio)
	_append_transition_corners(vertices, indices, core, transition)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func describe(
	window_m: float,
	l0_half_m: float = DEFAULT_L0_HALF_M,
	l0_spacing_m: float = DEFAULT_L0_SPACING_M,
	l1_spacing_m: float = DEFAULT_L1_SPACING_M
) -> Dictionary:
	var mesh: ArrayMesh = build(window_m, l0_half_m, l0_spacing_m, l1_spacing_m)
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	return {
		"window_m": window_m,
		"l0_half_m": l0_half_m,
		"l0_spacing_m": l0_spacing_m,
		"l1_spacing_m": l1_spacing_m,
		"vertices": vertices.size(),
		"triangles": indices.size() / 3,
	}


static func _append_grid_rect(
	vertices: PackedVector3Array,
	indices: PackedInt32Array,
	x0: float,
	x1: float,
	z0: float,
	z1: float,
	step: float
) -> void:
	if x1 <= x0 + 0.00001 or z1 <= z0 + 0.00001:
		return
	var nx: int = maxi(1, roundi((x1 - x0) / step))
	var nz: int = maxi(1, roundi((z1 - z0) / step))
	var sx: float = (x1 - x0) / float(nx)
	var sz: float = (z1 - z0) / float(nz)
	var base: int = vertices.size()
	for iz: int in range(nz + 1):
		for ix: int in range(nx + 1):
			vertices.append(Vector3(x0 + sx * ix, 0.0, z0 + sz * iz))
	var row: int = nx + 1
	for iz: int in range(nz):
		for ix: int in range(nx):
			var a: int = base + iz * row + ix
			_append_tri(indices, a, a + 1, a + row)
			_append_tri(indices, a + 1, a + row + 1, a + row)


static func _append_top_transition(
	vertices: PackedVector3Array,
	indices: PackedInt32Array,
	core: float,
	outer: float,
	fine: float,
	coarse: float,
	ratio: int
) -> void:
	var segments: int = roundi(core * 2.0 / coarse)
	for i: int in range(segments):
		var x0: float = -core + coarse * i
		var a: int = _v(vertices, Vector3(x0, 0.0, -outer))
		var b: int = _v(vertices, Vector3(x0 + coarse, 0.0, -outer))
		var inner: Array[int] = []
		for j: int in range(ratio + 1):
			inner.append(_v(vertices, Vector3(x0 + fine * j, 0.0, -core)))
		_append_tri(indices, a, b, inner[ratio])
		for j: int in range(ratio, 0, -1):
			_append_tri(indices, a, inner[j], inner[j - 1])


static func _append_bottom_transition(
	vertices: PackedVector3Array,
	indices: PackedInt32Array,
	core: float,
	outer: float,
	fine: float,
	coarse: float,
	ratio: int
) -> void:
	var segments: int = roundi(core * 2.0 / coarse)
	for i: int in range(segments):
		var x0: float = -core + coarse * i
		var a: int = _v(vertices, Vector3(x0, 0.0, outer))
		var b: int = _v(vertices, Vector3(x0 + coarse, 0.0, outer))
		var inner: Array[int] = []
		for j: int in range(ratio + 1):
			inner.append(_v(vertices, Vector3(x0 + fine * j, 0.0, core)))
		for j: int in range(ratio):
			_append_tri(indices, a, inner[j], inner[j + 1])
		_append_tri(indices, a, inner[ratio], b)


static func _append_left_transition(
	vertices: PackedVector3Array,
	indices: PackedInt32Array,
	core: float,
	outer: float,
	fine: float,
	coarse: float,
	ratio: int
) -> void:
	var segments: int = roundi(core * 2.0 / coarse)
	for i: int in range(segments):
		var z0: float = -core + coarse * i
		var a: int = _v(vertices, Vector3(-outer, 0.0, z0))
		var b: int = _v(vertices, Vector3(-outer, 0.0, z0 + coarse))
		var inner: Array[int] = []
		for j: int in range(ratio + 1):
			inner.append(_v(vertices, Vector3(-core, 0.0, z0 + fine * j)))
		for j: int in range(ratio):
			_append_tri(indices, a, inner[j], inner[j + 1])
		_append_tri(indices, a, inner[ratio], b)


static func _append_right_transition(
	vertices: PackedVector3Array,
	indices: PackedInt32Array,
	core: float,
	outer: float,
	fine: float,
	coarse: float,
	ratio: int
) -> void:
	var segments: int = roundi(core * 2.0 / coarse)
	for i: int in range(segments):
		var z0: float = -core + coarse * i
		var a: int = _v(vertices, Vector3(outer, 0.0, z0))
		var b: int = _v(vertices, Vector3(outer, 0.0, z0 + coarse))
		var inner: Array[int] = []
		for j: int in range(ratio + 1):
			inner.append(_v(vertices, Vector3(core, 0.0, z0 + fine * j)))
		for j: int in range(ratio):
			_append_tri(indices, a, inner[j + 1], inner[j])
		_append_tri(indices, a, b, inner[ratio])


static func _append_transition_corners(
	vertices: PackedVector3Array,
	indices: PackedInt32Array,
	core: float,
	outer: float
) -> void:
	## top-left
	var o: int = _v(vertices, Vector3(-outer, 0.0, -outer))
	var t: int = _v(vertices, Vector3(-core, 0.0, -outer))
	var l: int = _v(vertices, Vector3(-outer, 0.0, -core))
	var i: int = _v(vertices, Vector3(-core, 0.0, -core))
	_append_tri(indices, o, t, l)
	_append_tri(indices, t, i, l)
	## top-right
	t = _v(vertices, Vector3(core, 0.0, -outer))
	o = _v(vertices, Vector3(outer, 0.0, -outer))
	var r: int = _v(vertices, Vector3(outer, 0.0, -core))
	i = _v(vertices, Vector3(core, 0.0, -core))
	_append_tri(indices, t, o, i)
	_append_tri(indices, o, r, i)
	## bottom-left
	l = _v(vertices, Vector3(-outer, 0.0, core))
	i = _v(vertices, Vector3(-core, 0.0, core))
	var b: int = _v(vertices, Vector3(-core, 0.0, outer))
	o = _v(vertices, Vector3(-outer, 0.0, outer))
	_append_tri(indices, l, i, o)
	_append_tri(indices, i, b, o)
	## bottom-right
	i = _v(vertices, Vector3(core, 0.0, core))
	r = _v(vertices, Vector3(outer, 0.0, core))
	o = _v(vertices, Vector3(outer, 0.0, outer))
	b = _v(vertices, Vector3(core, 0.0, outer))
	_append_tri(indices, i, r, b)
	_append_tri(indices, r, o, b)


static func _v(vertices: PackedVector3Array, at: Vector3) -> int:
	var index: int = vertices.size()
	vertices.append(at)
	return index


static func _append_tri(indices: PackedInt32Array, a: int, b: int, c: int) -> void:
	indices.append(a)
	indices.append(b)
	indices.append(c)
