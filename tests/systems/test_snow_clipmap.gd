extends SceneTree

## SnowClipmap layout and the vertex morph (emulated as snow_ground computes it) that keeps
## a world point's height continuous while the rings snap. Run headless with --script.

var _failures: int = 0


func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	for tier: Vector2 in [Vector2(0.03, 1.5), Vector2(0.03, 2.25), Vector2(0.03, 2.75)]:
		var map: SnowClipmap = SnowClipmap.plan(tier.x, tier.y, 6.6)
		_test_layout(map)
		_test_mesh_sits_on_lattices(map)
		_test_surface_is_continuous_across_a_snap(map)
		_test_rings_meet_without_cracks(map)
		_test_the_chunk_triangles_are_drawn_exactly(map)
	_test_detail_stays_inside_the_window()
	if _failures > 0:
		push_error("snow clipmap: %d check(s) failed" % _failures)
		quit(1)
		return
	print("snow clipmap: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("snow clipmap: %s" % message)


func _test_layout(map: SnowClipmap) -> void:
	_check(map.outer_half() >= 6.6, "rings reach the requested half width")
	_check(map.vertex_count() < 60000, "vertex budget below 60k (got %d)" % map.vertex_count())
	var slack: float = map.snap_m * 0.5
	for i: int in range(map.spacings.size()):
		var s: float = map.spacings[i]
		_check(is_zero_approx(fmod(SnowClipmap.FAR_STEP_M, s * 2.0)), "ring %d doubled spacing divides the chunk step" % i)
		if i > 0:
			_check(is_equal_approx(s, map.spacings[i - 1] * 2.0), "ring %d doubles the spacing" % i)
			_check(is_zero_approx(fmod(map.halves[i - 1], s)), "ring %d hole lies on its lattice" % i)
		_check(is_zero_approx(fmod(map.halves[i], s)), "ring %d edge lies on its lattice" % i)
		if i < map.spacings.size() - 1:
			var band: Vector2 = map.morph_bands[i]
			_check(band.y <= map.halves[i] - slack, "ring %d finishes morphing before a snap can expose its edge" % i)
			var inner: float = map.halves[i - 1] if i > 0 else 0.0
			_check(i == 0 or band.x >= inner + slack, "ring %d starts morphing only past the finer ring" % i)
			_check(map.morph_bands[i + 1].x >= map.halves[i] + slack or i + 1 == map.spacings.size() - 1,
				"ring %d is unmorphed where ring %d hands over" % [i + 1, i])


func _test_mesh_sits_on_lattices(map: SnowClipmap) -> void:
	var mesh: ArrayMesh = map.build()
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	_check(verts.size() == map.vertex_count(), "vertex_count() matches the mesh")
	var off: int = 0
	for i: int in range(verts.size()):
		var s: float = uvs[i].x
		var q := Vector2(verts[i].x, verts[i].z) / s
		if not (is_zero_approx(q.x - roundf(q.x)) and is_zero_approx(q.y - roundf(q.y))):
			off += 1
	_check(off == 0, "every vertex sits on its ring's lattice (%d off)" % off)
	## The first triangle of each quad is (x0, z0), (x0 + s, z0), (x0, z0 + s): the chunk cover's diagonal.
	var a: Vector3 = verts[indices[0]]
	var b: Vector3 = verts[indices[1]]
	var c: Vector3 = verts[indices[2]]
	var s0: float = uvs[indices[0]].x
	_check(b.is_equal_approx(a + Vector3(s0, 0, 0)) and c.is_equal_approx(a + Vector3(0, 0, s0)), "quads split along the chunk diagonal")


func _test_surface_is_continuous_across_a_snap(map: SnowClipmap) -> void:
	## Henry steps a hair across a snap boundary: the mesh jumps a whole snap, the surface must not.
	var c1 := Vector2(-51.3, 50.3)
	c1.x = snappedf(c1.x, map.snap_m) + map.snap_m * 0.5 - 0.00005
	var c2 := c1 + Vector2(0.0001, 0.00007)
	_check(map.snapped_origin(c1) != map.snapped_origin(c2), "the probe crosses a snap boundary")
	var worst: float = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var reach: float = map.outer_half() - map.snap_m - 0.05
	for i: int in range(4000):
		var q := c1 + Vector2(rng.randf_range(-reach, reach), rng.randf_range(-reach, reach))
		var h1: float = _surface(map, map.snapped_origin(c1), c1, q, _detail)
		var h2: float = _surface(map, map.snapped_origin(c2), c2, q, _detail)
		worst = maxf(worst, absf(h1 - h2))
	_check(worst < 0.0005, "a fixed world point keeps its height across a snap (worst %.5f m)" % worst)


func _test_rings_meet_without_cracks(map: SnowClipmap) -> void:
	var c := Vector2(10.3, -4.7)
	var o: Vector2 = map.snapped_origin(c)
	var worst: float = 0.0
	for i: int in range(map.halves.size() - 1):
		var edge: float = map.halves[i]
		for k: int in range(200):
			var t: float = -edge + (edge * 2.0) * (float(k) + 0.37) / 200.0
			var inside: float = _surface(map, o, c, o + Vector2(t, edge - 0.00001), _detail)
			var outside: float = _surface(map, o, c, o + Vector2(t, edge + 0.00001), _detail)
			worst = maxf(worst, absf(inside - outside))
	_check(worst < 0.0005, "neighbouring rings share their boundary heights (worst %.5f m)" % worst)


func _test_the_chunk_triangles_are_drawn_exactly(map: SnowClipmap) -> void:
	var c := Vector2(-40.2, 13.9)
	var o: Vector2 = map.snapped_origin(c)
	var worst: float = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var reach: float = map.outer_half() - 0.1
	for i: int in range(3000):
		var q := o + Vector2(rng.randf_range(-reach, reach), rng.randf_range(-reach, reach))
		worst = maxf(worst, absf(_surface(map, o, c, q, _chunk) - _chunk(q)))
	_check(worst < 0.00001, "every ring reproduces the 2 m chunk triangles (worst %.6f m)" % worst)


func _test_detail_stays_inside_the_window() -> void:
	var shell: SnowShell = load("res://scripts/systems/world/snow/snow_shell.gd").new()
	var reach: float = shell.detail_reach_m()
	_check(shell.deform_fade_m.y <= reach and shell.far_fade_m.y <= reach, "fades finish inside the window's reach (%.2f m)" % reach)
	_check(shell.cut_radius_m + SnowShell.LOD_OVERLAP_M <= reach, "the chunk handoff lies inside the window's reach")
	_check(shell.far_fade_m.y <= shell.cut_radius_m - SnowShell.LOD_OVERLAP_M, "the surface is the chunk's before the chunk draws")
	shell.free()


## Drawn height at world point `q`: the containing triangle of the ring under it,
## with each corner morphed as snow_ground's vertex() does.
func _surface(map: SnowClipmap, o: Vector2, henry: Vector2, q: Vector2, h: Callable) -> float:
	var local: Vector2 = q - o
	var cheb: float = maxf(absf(local.x), absf(local.y))
	var ring: int = 0
	while ring < map.halves.size() - 1 and cheb >= map.halves[ring]:
		ring += 1
	var s: float = map.spacings[ring]
	var half: float = map.halves[ring]
	var p: Vector2 = (local + Vector2.ONE * half) / s
	var cell := Vector2(floorf(p.x), floorf(p.y))
	var f: Vector2 = p - cell
	var corner: Vector2 = o - Vector2.ONE * half + cell * s
	if f.x + f.y <= 1.0:
		return _vertex(map, ring, corner, henry, h) * (1.0 - f.x - f.y) \
			+ _vertex(map, ring, corner + Vector2(s, 0), henry, h) * f.x \
			+ _vertex(map, ring, corner + Vector2(0, s), henry, h) * f.y
	return _vertex(map, ring, corner + Vector2(s, s), henry, h) * (f.x + f.y - 1.0) \
		+ _vertex(map, ring, corner + Vector2(0, s), henry, h) * (1.0 - f.x) \
		+ _vertex(map, ring, corner + Vector2(s, 0), henry, h) * (1.0 - f.y)


func _vertex(map: SnowClipmap, ring: int, p: Vector2, henry: Vector2, h: Callable) -> float:
	var s: float = map.spacings[ring]
	var band: Vector2 = map.morph_bands[ring]
	var d: float = maxf(absf(p.x - henry.x), absf(p.y - henry.y))
	var top: float = h.call(p)
	var morph: float = smoothstep(band.x, band.y, d)
	if morph <= 0.0:
		return top
	var parity := Vector2(posmod(roundi(p.x / s), 2), posmod(roundi(p.y / s), 2))
	var coarse: float = top
	if parity.x > 0.5 and parity.y > 0.5:
		coarse = 0.5 * (float(h.call(p + Vector2(s, -s))) + float(h.call(p + Vector2(-s, s))))
	elif parity.x > 0.5:
		coarse = 0.5 * (float(h.call(p - Vector2(s, 0))) + float(h.call(p + Vector2(s, 0))))
	elif parity.y > 0.5:
		coarse = 0.5 * (float(h.call(p - Vector2(0, s))) + float(h.call(p + Vector2(0, s))))
	return lerpf(top, coarse, morph)


## Rough snow with detail finer than every ring but the first.
func _detail(p: Vector2) -> float:
	return 0.3 * sin(p.x * 1.7) + 0.2 * cos(p.y * 2.3) + 0.05 * sin((p.x + p.y) * 31.0) + 0.02 * cos(p.x * 57.0 - p.y * 43.0)


## A surface made of the chunk cover's 2 m triangles over arbitrary vertex heights.
func _chunk(p: Vector2) -> float:
	var g: Vector2 = p / SnowClipmap.FAR_STEP_M
	var cell := Vector2(floorf(g.x), floorf(g.y))
	var f: Vector2 = g - cell
	if f.x + f.y <= 1.0:
		return _lattice(cell) * (1.0 - f.x - f.y) + _lattice(cell + Vector2(1, 0)) * f.x + _lattice(cell + Vector2(0, 1)) * f.y
	return _lattice(cell + Vector2(1, 1)) * (f.x + f.y - 1.0) + _lattice(cell + Vector2(0, 1)) * (1.0 - f.x) + _lattice(cell + Vector2(1, 0)) * (1.0 - f.y)


func _lattice(cell: Vector2) -> float:
	return fposmod(sin(cell.x * 12.9898 + cell.y * 78.233) * 43758.5453, 1.0) * 0.4
