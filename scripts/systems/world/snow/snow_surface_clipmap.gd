class_name SnowSurfaceClipmap
extends RefCounted

## Three concentric, world-lattice-anchored LOD zones on a square cover.
## L0 (boot) 8 cm, L1 (trail) 16 cm, L2 (outer) 32 cm at HIGH.
## Each 32 cm *world-aligned* tile chooses its LOD by radial distance.
## All tile boundaries are stitched against their coarsest neighbour:
## no T-junctions, no overlapping opaque rings, no moving polar vertices.
## The square perimeter is only the SnowChunkCover ownership contract;
## all three resolution boundaries are radial (quantized to L2 tiles).

const DEFAULT_L0_HALF_M: float = 3.84
const DEFAULT_L1_RADIUS_M: float = 7.68
const DEFAULT_L0_SPACING_M: float = 0.08
const DEFAULT_L1_SPACING_M: float = 0.16
const DEFAULT_L2_SPACING_M: float = 0.32


static func build(
	window_m: float,
	l0_radius_m: float = DEFAULT_L0_HALF_M,
	l0_spacing_m: float = DEFAULT_L0_SPACING_M,
	l1_spacing_m: float = DEFAULT_L1_SPACING_M,
	l2_spacing_m: float = DEFAULT_L2_SPACING_M,
	l1_radius_m: float = DEFAULT_L1_RADIUS_M
) -> ArrayMesh:
	var cells: int = maxi(8, roundi(window_m / l2_spacing_m))
	var tile_m: float = window_m / float(cells)
	var fine_div: int = maxi(2, roundi(tile_m / l0_spacing_m))
	var medium_div: int = maxi(1, roundi(tile_m / l1_spacing_m))
	## Per-tile stitching currently supports 4->2->1. The tier spacings
	## supplied by DeterministicSnowShell use exactly those ratios.
	assert(fine_div == 4 and medium_div == 2, "snow radial clipmap needs L0:L1:L2 4:2:1 spacing")
	var half: float = window_m * 0.5
	var radii: Vector2 = Vector2(l0_radius_m, minf(l1_radius_m, half - tile_m))
	var lods := PackedInt32Array()
	lods.resize(cells * cells)
	for iz: int in range(cells):
		for ix: int in range(cells):
			var p := Vector2(-half + (float(ix) + 0.5) * tile_m, -half + (float(iz) + 0.5) * tile_m)
			var distance_m: float = p.length()
			lods[iz * cells + ix] = 4 if distance_m < radii.x else (2 if distance_m < radii.y else 1)

	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for iz: int in range(cells):
		for ix: int in range(cells):
			var own: int = lods[iz * cells + ix]
			var top_div: int = mini(own, lods[(iz - 1) * cells + ix]) if iz > 0 else own
			var right_div: int = mini(own, lods[iz * cells + ix + 1]) if ix < cells - 1 else own
			var bottom_div: int = mini(own, lods[(iz + 1) * cells + ix]) if iz < cells - 1 else own
			var left_div: int = mini(own, lods[iz * cells + ix - 1]) if ix > 0 else own
			_append_tile(vertices, indices, -half + float(ix) * tile_m, -half + float(iz) * tile_m,
				tile_m, own, [top_div, right_div, bottom_div, left_div])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func describe(
	window_m: float,
	l0_radius_m: float = DEFAULT_L0_HALF_M,
	l0_spacing_m: float = DEFAULT_L0_SPACING_M,
	l1_spacing_m: float = DEFAULT_L1_SPACING_M,
	l2_spacing_m: float = DEFAULT_L2_SPACING_M,
	l1_radius_m: float = DEFAULT_L1_RADIUS_M
) -> Dictionary:
	var mesh: ArrayMesh = build(window_m, l0_radius_m, l0_spacing_m, l1_spacing_m, l2_spacing_m, l1_radius_m)
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	return {
		"window_m": window_m,
		"l0_radius_m": l0_radius_m,
		"l1_radius_m": l1_radius_m,
		"l0_spacing_m": l0_spacing_m,
		"l1_spacing_m": l1_spacing_m,
		"l2_spacing_m": l2_spacing_m,
		"vertices": vertices.size(),
		"triangles": indices.size() / 3,
	}


## Each world-anchored L2 tile owns exactly one rectangle. Its outer edge
## adopts the neighbour's subdivision; the fine interior is stitched through
## a transition collar. L0 and L1 radial boundaries never expose T-junctions.
static func _append_tile(
	vertices: PackedVector3Array,
	indices: PackedInt32Array,
	x: float,
	z: float,
	size_m: float,
	divisions: int,
	edge_divisions: Array[int]
) -> void:
	var outline: Dictionary = _square_loop(x, z, x + size_m, z + size_m, edge_divisions)
	var ring: PackedVector3Array = outline["points"]
	if divisions == 1:
		var a: int = _v(vertices, ring[0])
		var b: int = _v(vertices, ring[1])
		var c: int = _v(vertices, ring[2])
		var d: int = _v(vertices, ring[3])
		_append_tri(indices, a, b, c)
		_append_tri(indices, a, c, d)
		return
	if divisions == 2:
		var center: int = _v(vertices, Vector3(x + size_m * 0.5, 0.0, z + size_m * 0.5))
		var perimeter := PackedInt32Array()
		for v: Vector3 in ring:
			perimeter.append(_v(vertices, v))
		for i: int in range(perimeter.size()):
			_append_tri(indices, perimeter[i], perimeter[(i + 1) % perimeter.size()], center)
		return
	## Four fine subdivisions: 2x2 regular interior plus a zipper-stitched
	## outer collar. The collar is one fine cell wide even beside coarse tiles.
	var h: float = size_m / 4.0
	_append_grid_rect(vertices, indices, x + h, x + size_m - h, z + h, z + size_m - h, h)
	var inner: Dictionary = _square_loop(x + h, z + h, x + size_m - h, z + size_m - h, [2, 2, 2, 2])
	_stitch_loops(vertices, indices, outline, inner)


static func _square_loop(x0: float, z0: float, x1: float, z1: float, edges: Array[int]) -> Dictionary:
	var points := PackedVector3Array()
	var times := PackedFloat32Array()
	for side: int in range(4):
		for i: int in range(edges[side]):
			var t: float = float(i) / float(edges[side])
			var at := Vector3.ZERO
			match side:
				0:
					at = Vector3(lerpf(x0, x1, t), 0.0, z0)
				1:
					at = Vector3(x1, 0.0, lerpf(z0, z1, t))
				2:
					at = Vector3(lerpf(x1, x0, t), 0.0, z1)
				3:
					at = Vector3(x0, 0.0, lerpf(z1, z0, t))
			points.append(at)
			times.append(float(side) + t)
	return {"points": points, "times": times}


static func _stitch_loops(vertices: PackedVector3Array, indices: PackedInt32Array, outer: Dictionary, inner: Dictionary) -> void:
	var op: PackedVector3Array = outer["points"]
	var ip: PackedVector3Array = inner["points"]
	var ot: PackedFloat32Array = outer["times"]
	var it: PackedFloat32Array = inner["times"]
	var oi := PackedInt32Array()
	var ii := PackedInt32Array()
	for p: Vector3 in op:
		oi.append(_v(vertices, p))
	for p: Vector3 in ip:
		ii.append(_v(vertices, p))
	var a: int = 0
	var b: int = 0
	while a < op.size() and b < ip.size():
		var na: float = ot[a + 1] if a + 1 < op.size() else 4.0
		var nb: float = it[b + 1] if b + 1 < ip.size() else 4.0
		var oa: int = oi[a]
		var ib: int = ii[b]
		if na < nb - 0.00001:
			_append_tri(indices, oa, oi[(a + 1) % oi.size()], ib)
			a += 1
		elif nb < na - 0.00001:
			_append_tri(indices, oa, ii[(b + 1) % ii.size()], ib)
			b += 1
		else:
			_append_tri(indices, oa, oi[(a + 1) % oi.size()], ii[(b + 1) % ii.size()])
			_append_tri(indices, oa, ii[(b + 1) % ii.size()], ib)
			a += 1
			b += 1


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
