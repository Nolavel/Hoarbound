class_name SnowClipmap
extends RefCounted
## Nested square rings of a regular grid around Henry, spacing doubling outwards.
## Geometry clipmaps (Losasso & Hoppe 2004) with CDLOD height morph (Strugar 2009).

## Every spacing and its double divide this, so any ring can draw the 2 m chunk triangles exactly.
const FAR_STEP_M: float = 2.0
## Coarsest spacing a ring may use. It is also the snap step, which every ring's
## width must exceed by its morph band.
const MAX_SPACING_M: float = 0.5
## Narrowest ring, so a snap step plus a usable morph band fits in it.
const RING_MIN_WIDTH_M: float = 1.2
## Clear distance between a ring edge and its morph band, beyond the snap offset.
const MORPH_MARGIN_M: float = 0.05

## Spacing and half width of each ring, innermost first.
var spacings: PackedFloat32Array = []
var halves: PackedFloat32Array = []
## Chebyshev distance from Henry where each ring starts and finishes morphing onto twice its spacing.
var morph_bands: PackedVector2Array = []
## The mesh moves in steps of the coarsest spacing, so every vertex stays on its ring's world lattice.
var snap_m: float = 0.25


## Rings from `near_spacing_m` (rounded down to a power-of-two fraction of FAR_STEP_M)
## out to at least `outer_half_m`; the dense core reaches `near_half_m`.
static func plan(near_spacing_m: float, near_half_m: float, outer_half_m: float) -> SnowClipmap:
	var map := SnowClipmap.new()
	var spacing: float = FAR_STEP_M
	while spacing * 0.5 >= near_spacing_m - 0.000001:
		spacing *= 0.5
	var half: float = _ceil_to(maxf(near_half_m, spacing * 8.0), spacing * 2.0)
	map.spacings.append(spacing)
	map.halves.append(half)
	while half < outer_half_m:
		var grown: float = maxf(half * 1.6, half + RING_MIN_WIDTH_M)
		var last: bool = spacing * 2.0 >= MAX_SPACING_M or _ceil_to(outer_half_m, spacing * 4.0) <= grown * 1.25
		spacing *= 2.0
		half = _ceil_to(maxf(outer_half_m, grown) if last else grown, spacing * 2.0)
		map.spacings.append(spacing)
		map.halves.append(half)
		if last:
			break
	map.snap_m = map.spacings[map.spacings.size() - 1]
	var slack: float = map.snap_m * 0.5 + MORPH_MARGIN_M
	for i: int in range(map.spacings.size()):
		var inner: float = map.halves[i - 1] if i > 0 else 0.0
		var finish: float = map.halves[i] - slack
		## A dozen spacings of morph: wide enough to be gradual, few vertices sample three times.
		var start: float = maxf(inner + slack, finish - clampf(map.spacings[i] * 12.0, 0.3, (map.halves[i] - inner) * 0.5))
		if i == map.spacings.size() - 1:
			## The outermost ring never meets a coarser one inside the drawn area.
			map.morph_bands.append(Vector2(1.0e6, 1.0e6 + 1.0))
		else:
			map.morph_bands.append(Vector2(start, maxf(finish, start + 0.01)))
	return map


## Half width of the whole mesh.
func outer_half() -> float:
	return halves[halves.size() - 1]


## World origin for the mesh when Henry stands at `centre`.
func snapped_origin(centre: Vector2) -> Vector2:
	return Vector2(snappedf(centre.x, snap_m), snappedf(centre.y, snap_m))


## Number of vertices `build()` produces.
func vertex_count() -> int:
	var total: int = 0
	for i: int in range(spacings.size()):
		var n: int = roundi(halves[i] * 2.0 / spacings[i]) + 1
		var hole: int = roundi(halves[i - 1] * 2.0 / spacings[i]) - 1 if i > 0 else 0
		total += n * n - maxi(hole, 0) * maxi(hole, 0)
	return total


## One ArrayMesh with every ring. UV holds the ring spacing and index, UV2 its morph band.
## Quads split along the same diagonal as SnowChunkCover, so a fully morphed ring lies on its triangles.
func build() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()
	for ring: int in range(spacings.size()):
		var s: float = spacings[ring]
		var n: int = roundi(halves[ring] * 2.0 / s) + 1
		var hole: float = halves[ring - 1] if ring > 0 else -1.0
		var lookup := PackedInt32Array()
		lookup.resize(n * n)
		lookup.fill(-1)
		for iz: int in range(n - 1):
			for ix: int in range(n - 1):
				var x0: float = -halves[ring] + ix * s
				var z0: float = -halves[ring] + iz * s
				if x0 >= -hole - 0.0001 and x0 + s <= hole + 0.0001 and z0 >= -hole - 0.0001 and z0 + s <= hole + 0.0001:
					continue
				var a: int = _vertex(lookup, n, ix, iz, ring, verts, uvs, uv2s)
				var b: int = _vertex(lookup, n, ix + 1, iz, ring, verts, uvs, uv2s)
				var c: int = _vertex(lookup, n, ix, iz + 1, ring, verts, uvs, uv2s)
				var d: int = _vertex(lookup, n, ix + 1, iz + 1, ring, verts, uvs, uv2s)
				indices.append_array([a, b, c, b, d, c])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	## Up, for the shadow normal bias; snow_ground also sets it per vertex.
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var h: float = outer_half()
	## Heights come from the shader: any ground from below sea level to a mountain top.
	mesh.custom_aabb = AABB(Vector3(-h, -1000.0, -h), Vector3(h * 2.0, 4000.0, h * 2.0))
	return mesh


func _vertex(lookup: PackedInt32Array, n: int, ix: int, iz: int, ring: int,
		verts: PackedVector3Array, uvs: PackedVector2Array, uv2s: PackedVector2Array) -> int:
	var key: int = iz * n + ix
	if lookup[key] >= 0:
		return lookup[key]
	var s: float = spacings[ring]
	lookup[key] = verts.size()
	verts.append(Vector3(-halves[ring] + ix * s, 0.0, -halves[ring] + iz * s))
	uvs.append(Vector2(s, float(ring)))
	uv2s.append(morph_bands[ring])
	return lookup[key]


static func _ceil_to(value: float, step: float) -> float:
	return ceilf(value / step - 0.0001) * step
