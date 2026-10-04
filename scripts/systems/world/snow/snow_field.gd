class_name SnowField
extends RefCounted

## The one answer to "how much snow is here": ground, settled depth, drifts and
## lee piles on a grid that follows Henry. Shaders and gameplay read the same data.

## Softness is stored in the image B channel scaled below the 0.5 cut threshold.
const SOFTNESS_SCALE: float = 0.49
## Cells of cached ground kept around the window, so edge cells see real
## neighbours and a window move only samples the newly exposed strips.
const APRON: int = 20
## Rebuild stages: wind-independent grid layers, then depth, then the image.
const STAGE_GROUND: int = 0
const STAGE_ROW1: int = 1
const STAGE_COL1: int = 2
const STAGE_ROW2: int = 3
const STAGE_BED: int = 4
const STAGE_WALL: int = 5
const STAGE_DEPTH: int = 6
const STAGE_OUTPUT: int = 7
const STAGE_NORMAL: int = 8

## Ground height and obstacle flag at a world point, as Vector2(height, 0 or 1).
var ground_sampler: Callable

var window_m: float = 25.6
var res: int = 128
var sea_level_m: float = 0.0
## Settled depth at snow_cover 0 and 1.
var cover_depth_m: Vector2 = Vector2(0.05, 0.25)
## Tallest wind drift and lee pile at snow_cover 1.
var drift_m: float = 0.3
var lee_m: float = 0.6
## Snow rounds off ground detail finer than this, in metres.
var smooth_m: float = 1.0

## R: snow top (world y), G: depth, B: 1 where cut away, A: city wind factor.
var image: Image
## Optional settled-surface normal map, published with the height image.
var normal_image: Image
var build_normal_image: bool = false
var origin: Vector2 = Vector2(INF, INF)

## City-scale wind field (R prevailing, G storm depth factor); null outside a city.
var wind_field: Image
## The same field as a texture, for shaders that sample it per pixel.
var wind_texture: Texture2D
var wind_field_origin: Vector2 = Vector2.ZERO
var wind_field_cell_m: float = 4.0
var wind_field_max: float = 2.5
## Settled ridge orientation is baked, not the current gust direction.
var settled_wind: Vector2 = Vector2(0, -1)
## City chunks and Henry's shell use the same settled height from the baked wind
## field. Local prints still deform it; the window must not create new drifts.
var use_baked_baseline: bool = false
## Share of fresh storm snow over the old prevailing base; set per rebuild.
var storm_share: float = 0.4

static var _wind_cache: Dictionary = {}

var _n: int = 0
var _grid_origin: Vector2 = Vector2(INF, INF)
var _ground: PackedVector2Array = []
var _height: PackedFloat32Array = []
var _row1: PackedFloat32Array = []
var _col1: PackedFloat32Array = []
var _row2: PackedFloat32Array = []
var _bed: PackedFloat32Array = []
var _wall: PackedFloat32Array = []
## Prevailing and storm wind factors per grid cell; mixed by storm_share at depth time.
var _prevail: PackedFloat32Array = []
var _storm: PackedFloat32Array = []
var _grain: PackedFloat32Array = []
var _job_active: bool = false
var _job_stage: int = 0
var _job_cursor: int = 0
var _job_spans: Array[Vector3i] = []
var _job_shift: Vector2i = Vector2i.ZERO
var _job_origin: Vector2 = Vector2.ZERO
var _job_storm: float = 0.4
var _job_cover: float = 0.0
var _job_wind: Vector2 = Vector2(0, -1)
var _job_ahead: Vector2i = Vector2i.ZERO
var _job_upwind: Array[Vector2i] = []
var _job_depth: PackedFloat32Array = []
var _job_weight: PackedFloat32Array = []
var _job_px: PackedFloat32Array = []
var _job_normal_heights: PackedFloat32Array = []
var _job_normal_px: PackedFloat32Array = []
var _noise: FastNoiseLite = FastNoiseLite.new()
var _density_noise: FastNoiseLite = FastNoiseLite.new()


func _init() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.seed = 1901
	_density_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_density_noise.frequency = 0.35
	_density_noise.seed = 2207


## Loads a baked wind field (PNG + JSON beside it); false when absent.
func load_wind_field(png_path: String) -> bool:
	var meta_path: String = png_path.get_basename() + ".json"
	if not FileAccess.file_exists(png_path) or not FileAccess.file_exists(meta_path):
		return false
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
	if typeof(meta) != TYPE_DICTIONARY:
		return false
	## Every SnowField shares one CPU copy; the image alone is ~65 MiB.
	if not _wind_cache.has(png_path):
		var tex := load(png_path) as Texture2D
		if tex == null:
			return false
		var img: Image = tex.get_image()
		if img.is_compressed():
			img.decompress()
		_wind_cache[png_path] = [tex, img]
	wind_texture = _wind_cache[png_path][0]
	wind_field = _wind_cache[png_path][1]
	var o: Array = (meta as Dictionary).get("origin", [0, 0])
	wind_field_origin = Vector2(float(o[0]), float(o[1]))
	wind_field_cell_m = float((meta as Dictionary).get("cell_m", 4.0))
	wind_field_max = float((meta as Dictionary).get("factor_max", 2.5))
	var from: float = deg_to_rad(float((meta as Dictionary).get("prevailing_from_deg", 0.0)))
	settled_wind = Vector2(-sin(from), cos(from))
	return true


## Wind ridge crest 0..1; mirrors snow_ridge() in snow_surface.gdshaderinc bit for bit.
static func ridge_at(xz: Vector2, wind: Vector2) -> float:
	var side := Vector2(-wind.y, wind.x)
	var q := Vector2(xz.dot(wind) * 0.16, xz.dot(side) * 0.55)
	var n: float = _vnoise(q) * 0.7 + _vnoise(q * 2.0 + Vector2(11.0, 5.0)) * 0.3
	return smoothstep(0.45, 0.85, n)


static func _ihash(x: int, y: int) -> float:
	const M: int = 0xFFFFFFFF
	var h: int = ((x & M) * 374761393 + (y & M) * 668265263) & M
	h = ((h ^ (h >> 13)) * 1274126177) & M
	h ^= h >> 16
	return float(h & 65535) / 65535.0


static func _vnoise(p: Vector2) -> float:
	var i := Vector2i(floori(p.x), floori(p.y))
	var f := p - Vector2(i)
	var u := f * f * (Vector2(3.0, 3.0) - 2.0 * f)
	return lerpf(
		lerpf(_ihash(i.x, i.y), _ihash(i.x + 1, i.y), u.x),
		lerpf(_ihash(i.x, i.y + 1), _ihash(i.x + 1, i.y + 1), u.x),
		u.y
	)


## 1 where the wind runs free enough to cut ridges, 0 in sheltered drift banks.
static func ridge_openness(city: float) -> float:
	return 1.0 - smoothstep(0.85, 1.35, city)


## Drift crest height for a snow_cover value.
func drift_amplitude(cover: float) -> float:
	return pow(clampf(cover, 0.0, 1.0), 1.5) * drift_m


## True on the high and medium tiers: Henry's deformable window and chunk-wide depth.
## Low keeps shader cover, frost and footprint decals only.
static func high_quality() -> bool:
	return quality() != &"low"


## The snow tier from hfn/snow/quality: high, medium or low.
static func quality() -> StringName:
	return StringName(ProjectSettings.get_setting("hfn/snow/quality", "high"))


## Settled depth for a snow_cover value, before the city's wind reshapes it.
func settled_depth(cover: float) -> float:
	return lerpf(cover_depth_m.x, cover_depth_m.y, clampf(cover, 0.0, 1.0))


## True inside a mapped building footprint (snow lies on its roof, not here).
func is_building(at: Vector2) -> bool:
	if wind_field == null:
		return false
	var p := Vector2i(((at - wind_field_origin) / wind_field_cell_m).floor())
	if p.x < 0 or p.y < 0 or p.x >= wind_field.get_width() or p.y >= wind_field.get_height():
		return false
	return wind_field.get_pixel(p.x, p.y).a > 0.5


## How the city's wind scales settled snow here: under 1 scoured, over 1 deposited.
func wind_factor(at: Vector2) -> float:
	var both: Vector2 = wind_factors(at)
	return lerpf(both.x, both.y, storm_share)


## Prevailing and storm depth factors at a world point, each 1.0 outside the city.
func wind_factors(at: Vector2) -> Vector2:
	if wind_field == null:
		return Vector2.ONE
	var p: Vector2 = (at - wind_field_origin) / wind_field_cell_m - Vector2(0.5, 0.5)
	## Outside the baked city the wind leaves settled snow as it fell.
	if p.x < 0.0 or p.y < 0.0 or p.x > wind_field.get_width() - 1 or p.y > wind_field.get_height() - 1:
		return Vector2.ONE
	var x0: int = clampi(floori(p.x), 0, wind_field.get_width() - 2)
	var y0: int = clampi(floori(p.y), 0, wind_field.get_height() - 2)
	var f := Vector2(clampf(p.x - float(x0), 0.0, 1.0), clampf(p.y - float(y0), 0.0, 1.0))
	var top: Color = wind_field.get_pixel(x0, y0).lerp(wind_field.get_pixel(x0 + 1, y0), f.x)
	var bottom: Color = wind_field.get_pixel(x0, y0 + 1).lerp(wind_field.get_pixel(x0 + 1, y0 + 1), f.x)
	var c: Color = top.lerp(bottom, f.y)
	return Vector2(c.r, c.g) * wind_field_max


func texel_m() -> float:
	return window_m / float(res)


## Rebuilds the field for a window whose minimum corner is `new_origin`, all at once.
func rebuild(new_origin: Vector2, cover: float, wind: Vector2) -> void:
	begin_rebuild(new_origin, cover, wind)
	while not step_rebuild(1 << 60):
		pass


## Starts a rebuild that `step_rebuild` finishes over several frames. Cached ground
## work is reused across window moves; only newly exposed strips are sampled.
func begin_rebuild(new_origin: Vector2, cover: float, wind: Vector2) -> void:
	## A half-finished job left some grid layers moved but not recomputed.
	if _job_active:
		invalidate()
	_job_origin = new_origin
	_job_cover = clampf(cover, 0.0, 1.0)
	_job_storm = clampf(storm_share, 0.0, 1.0)
	_job_wind = wind.normalized() if wind.length_squared() > 0.0001 else Vector2(0, -1)
	var grid_origin: Vector2 = new_origin - Vector2(APRON, APRON) * texel_m()
	var n: int = res + 2 * APRON
	var shift := Vector2i(n, n)
	if _n == n and _grid_origin.x != INF:
		var d: Vector2 = (grid_origin - _grid_origin) / texel_m()
		var whole := Vector2i(roundi(d.x), roundi(d.y))
		if d.distance_to(Vector2(whole)) < 0.001 and absi(whole.x) < n and absi(whole.y) < n:
			shift = whole
	_start_grid(grid_origin, shift)
	_job_stage = 0
	_job_cursor = 0
	_job_spans = _stage_spans(0)
	_job_active = true


## Advances the running rebuild for about `budget_usec`; true once the new field
## is live (origin and image switch together).
func step_rebuild(budget_usec: int) -> bool:
	if not _job_active:
		return true
	var deadline: int = Time.get_ticks_usec() + budget_usec
	while true:
		if _job_stage <= STAGE_WALL:
			if _job_cursor < _job_spans.size():
				_grid_span(_job_stage, _job_spans[_job_cursor])
				_job_cursor += 1
			else:
				_next_stage()
		elif _job_stage == STAGE_DEPTH:
			if _job_cursor == 0:
				_begin_assemble()
			if _job_cursor < res + 2:
				_assemble_row(_job_cursor)
				_job_cursor += 1
			else:
				_next_stage()
		elif _job_stage == STAGE_OUTPUT:
			if _job_cursor == 0:
				if not use_baked_baseline:
					var r: int = maxi(1, roundi(0.25 / texel_m()))
					_job_depth = _blur(_job_depth, res + 2, r)
					_job_weight = _blur(_job_weight, res + 2, r)
				_job_px.resize(res * res * 4)
			if _job_cursor < res:
				_output_row(_job_cursor)
				_job_cursor += 1
			elif build_normal_image:
				_next_stage()
			else:
				_finish()
				return true
		elif _job_stage == STAGE_NORMAL:
			if _job_cursor == 0:
				_begin_normal_image()
			if _job_cursor < (res >> 1):
				_normal_row(_job_cursor)
				_job_cursor += 1
			else:
				_finish()
				return true
		if Time.get_ticks_usec() >= deadline:
			return false
	return false


func is_rebuilding() -> bool:
	return _job_active


## Forgets the cached ground, so the next rebuild samples every cell again.
func invalidate() -> void:
	_grid_origin = Vector2(INF, INF)


## Snow top at a world point (bilinear), or -INF outside the window.
func get_snow_top(x: float, z: float) -> float:
	return _sample(x, z).x


## Settled depth at a world point (bilinear), 0 outside the window.
## How far a foot can press the snow here, 0.4 wind crust to 1.0 loose powder:
## scoured ground is packed hard, lee drifts are soft, with patches between.
func softness(at: Vector2, city: float) -> float:
	var patch: float = _density_noise.get_noise_2d(at.x, at.y) * 0.25
	return clampf(0.7 + (city - 1.0) * 0.35 + patch, 0.4, 1.0)


## Softness stored in the field image (0 outside the window or on cut cells).
func get_softness(x: float, z: float) -> float:
	if image == null:
		return 0.0
	var p := Vector2i(((Vector2(x, z) - origin) / texel_m()).floor())
	if p.x < 0 or p.y < 0 or p.x >= res or p.y >= res:
		return 0.0
	var b: float = image.get_pixel(p.x, p.y).b
	return 0.0 if b > 0.5 else b / SOFTNESS_SCALE


func get_depth(x: float, z: float) -> float:
	return _sample(x, z).y


func _sample(x: float, z: float) -> Vector2:
	if image == null:
		return Vector2(-INF, 0.0)
	var p: Vector2 = (Vector2(x, z) - origin) / texel_m() - Vector2(0.5, 0.5)
	if p.x < 0.0 or p.y < 0.0 or p.x > res - 1 or p.y > res - 1:
		return Vector2(-INF, 0.0)
	var i := Vector2i(mini(floori(p.x), res - 2), mini(floori(p.y), res - 2))
	var f: Vector2 = p - Vector2(i)
	var a: Color = image.get_pixel(i.x, i.y)
	var b: Color = image.get_pixel(i.x + 1, i.y)
	var c: Color = image.get_pixel(i.x, i.y + 1)
	var d: Color = image.get_pixel(i.x + 1, i.y + 1)
	var top: float = lerpf(lerpf(a.r, b.r, f.x), lerpf(c.r, d.r, f.x), f.y)
	var depth: float = lerpf(lerpf(a.g, b.g, f.x), lerpf(c.g, d.g, f.x), f.y)
	return Vector2(top, depth)


func _grid_world(i: int, j: int) -> Vector2:
	return _grid_origin + (Vector2(i, j) + Vector2(0.5, 0.5)) * texel_m()


## Moves every cached grid layer by `shift` cells; a shift of the full grid size
## means nothing can be kept and every cell is recomputed.
func _start_grid(grid_origin: Vector2, shift: Vector2i) -> void:
	var n: int = res + 2 * APRON
	if _n != n:
		_n = n
		for layer: String in ["_height", "_row1", "_col1", "_row2", "_bed", "_wall", "_prevail", "_storm", "_grain"]:
			var arr := PackedFloat32Array()
			arr.resize(n * n)
			set(layer, arr)
		_ground.resize(n * n)
		shift = Vector2i(n, n)
	elif shift != Vector2i.ZERO and shift.x < n:
		_ground = _shifted_v2(_ground, shift)
		_height = _shifted(_height, shift)
		_row1 = _shifted(_row1, shift)
		_col1 = _shifted(_col1, shift)
		_row2 = _shifted(_row2, shift)
		_bed = _shifted(_bed, shift)
		_wall = _shifted(_wall, shift)
		_prevail = _shifted(_prevail, shift)
		_storm = _shifted(_storm, shift)
		_grain = _shifted(_grain, shift)
	_grid_origin = grid_origin
	_job_shift = shift


## Cells each grid layer recomputes: every cell except those still (rx, ry) inside
## the old grid, the reach of that layer's blur passes.
func _stage_spans(stage: int) -> Array[Vector3i]:
	var rb: int = _bed_radius()
	match stage:
		STAGE_GROUND:
			return _spans(_job_shift, 0, 0)
		STAGE_ROW1:
			return _spans(_job_shift, rb, 0)
		STAGE_COL1:
			return _spans(_job_shift, rb, rb)
		STAGE_ROW2:
			return _spans(_job_shift, 2 * rb, rb)
		STAGE_BED:
			return _spans(_job_shift, 2 * rb, 2 * rb)
		_:
			return _spans(_job_shift, 1, 1)


func _next_stage() -> void:
	## The baked city factor already contains lee deposition and wind scour.
	## Rebuilding those from nearby live colliders would make settled snow move.
	_job_stage = STAGE_DEPTH if use_baked_baseline and _job_stage == STAGE_GROUND else _job_stage + 1
	_job_cursor = 0
	if _job_stage <= STAGE_WALL:
		_job_spans = _stage_spans(_job_stage)


func _bed_radius() -> int:
	return maxi(1, roundi(smooth_m / texel_m() * 0.5))


## One row span of one wind-independent grid layer.
func _grid_span(stage: int, span: Vector3i) -> void:
	var n: int = _n
	var j: int = span.x
	var rb: int = _bed_radius()
	var w: float = float(2 * rb + 1)
	for i: int in range(span.y, span.z):
		var k: int = j * n + i
		match stage:
			STAGE_GROUND:
				var at: Vector2 = _grid_world(i, j)
				var g: Vector2 = ground_sampler.call(at)
				_ground[k] = g
				_height[k] = g.x
				var both: Vector2 = wind_factors(at)
				_prevail[k] = both.x
				_storm[k] = both.y
				_grain[k] = _noise.get_noise_2d(at.x * 1.3, at.y * 1.3)
			STAGE_ROW1:
				var sum: float = 0.0
				for d: int in range(-rb, rb + 1):
					sum += _height[j * n + clampi(i + d, 0, n - 1)]
				_row1[k] = sum / w
			STAGE_COL1:
				var sum: float = 0.0
				for d: int in range(-rb, rb + 1):
					sum += _row1[clampi(j + d, 0, n - 1) * n + i]
				_col1[k] = sum / w
			STAGE_ROW2:
				var sum: float = 0.0
				for d: int in range(-rb, rb + 1):
					sum += _col1[j * n + clampi(i + d, 0, n - 1)]
				_row2[k] = sum / w
			STAGE_BED:
				var sum: float = 0.0
				for d: int in range(-rb, rb + 1):
					sum += _row2[clampi(j + d, 0, n - 1) * n + i]
				## Snow settles on the blurred ground, never below it.
				_bed[k] = maxf(sum / w, _height[k])
			_:
				_wall[k] = _wall_share(i, j)


## Row spans (row, from, to) of cells to recompute after `shift`: every cell except
## those still at least (rx, ry) cells inside the old grid.
func _spans(shift: Vector2i, rx: int, ry: int) -> Array[Vector3i]:
	var n: int = _n
	var x0: int = clampi(-shift.x + rx, 0, n)
	var x1: int = clampi(n - shift.x - rx, 0, n)
	var y0: int = clampi(-shift.y + ry, 0, n)
	var y1: int = clampi(n - shift.y - ry, 0, n)
	var out: Array[Vector3i] = []
	for j: int in range(n):
		if j >= y0 and j < y1 and x0 < x1:
			if x0 > 0:
				out.append(Vector3i(j, 0, x0))
			if x1 < n:
				out.append(Vector3i(j, x1, n))
		else:
			out.append(Vector3i(j, 0, n))
	return out


## `arr` moved by `shift` cells; cells that come from outside are zero.
func _shifted(arr: PackedFloat32Array, shift: Vector2i) -> PackedFloat32Array:
	var n: int = _n
	var pad := PackedFloat32Array()
	pad.resize(absi(shift.x))
	var blank := PackedFloat32Array()
	blank.resize(n)
	var out := PackedFloat32Array()
	for j: int in range(n):
		var sj: int = j + shift.y
		if sj < 0 or sj >= n:
			out.append_array(blank)
		elif shift.x >= 0:
			out.append_array(arr.slice(sj * n + shift.x, sj * n + n))
			out.append_array(pad)
		else:
			out.append_array(pad)
			out.append_array(arr.slice(sj * n, sj * n + n + shift.x))
	return out


func _shifted_v2(arr: PackedVector2Array, shift: Vector2i) -> PackedVector2Array:
	var n: int = _n
	var pad := PackedVector2Array()
	pad.resize(absi(shift.x))
	var blank := PackedVector2Array()
	blank.resize(n)
	var out := PackedVector2Array()
	for j: int in range(n):
		var sj: int = j + shift.y
		if sj < 0 or sj >= n:
			out.append_array(blank)
		elif shift.x >= 0:
			out.append_array(arr.slice(sj * n + shift.x, sj * n + n))
			out.append_array(pad)
		else:
			out.append_array(pad)
			out.append_array(arr.slice(sj * n, sj * n + n + shift.x))
	return out


## Wind- and cover-dependent depth over the window plus a one-cell rim, a row at
## a time. Everything it reads is already cached in the grid.
func _begin_assemble() -> void:
	var m: int = res + 2
	var step: int = maxi(1, roundi(0.35 / texel_m()))
	_job_ahead = Vector2i(roundi(_job_wind.x * step), roundi(_job_wind.y * step))
	_job_upwind.clear()
	for k: int in range(1, 9):
		_job_upwind.append(Vector2i(roundi(_job_wind.x * step * k), roundi(_job_wind.y * step * k)))
	_job_depth = PackedFloat32Array()
	_job_depth.resize(m * m)
	_job_weight = PackedFloat32Array()
	_job_weight.resize(m * m)


func _assemble_row(lj: int) -> void:
	var n: int = _n
	var m: int = res + 2
	var j: int = APRON - 1 + lj
	var settled: float = settled_depth(_job_cover)
	var amp: float = drift_amplitude(_job_cover)
	var step: int = maxi(1, roundi(0.35 / texel_m()))
	var scour_span: float = 0.35 * float(step) * texel_m()
	for li: int in range(m):
		var i: int = APRON - 1 + li
		var k: int = j * n + i
		var g: Vector2 = _ground[k]
		if g.y > 0.5:
			continue
		var at: Vector2 = _grid_world(i, j)
		var city: float = lerpf(_prevail[k], _storm[k], _job_storm)
		if use_baked_baseline:
			var shore: float = smoothstep(sea_level_m + 0.05, sea_level_m + 0.8, g.x)
			_job_depth[lj * m + li] = settled * city * shore
			_job_weight[lj * m + li] = 1.0
			continue
		var drift: float = amp * ridge_at(at, _job_wind) * minf(city, 1.5) * ridge_openness(city)
		var lee: float = _job_cover * lee_m * _lee(i, j, _job_upwind, _job_ahead)
		## Wind scours the face that rises into it and fills hollows.
		var bed: float = _bed[k]
		var rise: float = _bed[clampi(j + _job_ahead.y, 0, n - 1) * n + clampi(i + _job_ahead.x, 0, n - 1)] - bed
		var scour: float = clampf(1.0 - rise / scour_span * 0.5, 0.35, 1.25)
		var depth: float = (settled * city + maxf(drift, lee) + minf(drift, lee) * 0.3) * scour
		depth += settled * 0.15 * _grain[k]
		## Snow thins to nothing at the water's edge and never lies below it.
		var shore: float = smoothstep(sea_level_m + 0.05, sea_level_m + 0.8, g.x)
		_job_depth[lj * m + li] = maxf(depth * shore, 0.0)
		_job_weight[lj * m + li] = 1.0


## One output row; wind never leaves one-cell spikes (the depth was softened over
## ~0.5 m, ignoring cells nothing lies on so snow still meets walls at full height).
func _output_row(ty: int) -> void:
	var n: int = _n
	var m: int = res + 2
	for tx: int in range(res):
		var k: int = (APRON + ty) * n + APRON + tx
		var l: int = (ty + 1) * m + tx + 1
		var o: int = (ty * res + tx) * 4
		var g: Vector2 = _ground[k]
		if g.y > 0.5:
			_job_px[o] = g.x
			_job_px[o + 1] = 0.0
			_job_px[o + 2] = 1.0
			_job_px[o + 3] = 0.0
			continue
		var depth: float = _job_depth[l] / maxf(_job_weight[l], 0.0001)
		var shore: float = smoothstep(sea_level_m + 0.05, sea_level_m + 0.8, g.x)
		## Depth is measured from the real ground, so the shader's ground stays true.
		var top: float = g.x + depth if use_baked_baseline else _bed[k] * shore + g.x * (1.0 - shore) + depth
		_job_px[o] = top
		_job_px[o + 1] = top - g.x
		## B: 1 where snow is cut away, else softness scaled below 0.5.
		var city: float = lerpf(_prevail[k], _storm[k], _job_storm)
		_job_px[o + 2] = 1.0 if g.x < sea_level_m + 0.02 else softness(_grid_world(APRON + tx, APRON + ty), city) * SOFTNESS_SCALE
		_job_px[o + 3] = lerpf(_prevail[k], _storm[k], _job_storm)


func _begin_normal_image() -> void:
	var half: int = res >> 1
	var height_image := Image.create_empty(res, res, false, Image.FORMAT_RGBAF)
	height_image.set_data(res, res, false, Image.FORMAT_RGBAF, _job_px.to_byte_array())
	height_image.resize(half, half, Image.INTERPOLATE_BILINEAR)
	_job_normal_heights = height_image.get_data().to_float32_array()
	_job_normal_px.resize(half * half * 4)


## Normal rows share the same rebuild budget as the settled height rows.
func _normal_row(z: int) -> void:
	var n: int = res >> 1
	var lo_z: int = maxi(z - 1, 0)
	var hi_z: int = mini(z + 1, n - 1)
	var step_m: float = window_m / float(n)
	for x: int in range(n):
		var lo_x: int = maxi(x - 1, 0)
		var hi_x: int = mini(x + 1, n - 1)
		var dx: float = (_job_normal_heights[(z * n + hi_x) * 4] - _job_normal_heights[(z * n + lo_x) * 4]) / (float(hi_x - lo_x) * step_m)
		var dz: float = (_job_normal_heights[(hi_z * n + x) * 4] - _job_normal_heights[(lo_z * n + x) * 4]) / (float(hi_z - lo_z) * step_m)
		var normal: Vector3 = Vector3(-dx, 1.0, -dz).normalized()
		var i: int = (z * n + x) * 4
		_job_normal_px[i] = normal.x * 0.5 + 0.5
		_job_normal_px[i + 1] = normal.y * 0.5 + 0.5
		_job_normal_px[i + 2] = normal.z * 0.5 + 0.5
		_job_normal_px[i + 3] = 1.0


func _finish() -> void:
	if image == null or image.get_width() != res:
		image = Image.create_empty(res, res, false, Image.FORMAT_RGBAF)
	image.set_data(res, res, false, Image.FORMAT_RGBAF, _job_px.to_byte_array())
	if build_normal_image:
		var half: int = res >> 1
		if normal_image == null or normal_image.get_width() != half:
			normal_image = Image.create_empty(half, half, false, Image.FORMAT_RGBAF)
		normal_image.set_data(half, half, false, Image.FORMAT_RGBAF, _job_normal_px.to_byte_array())
	origin = _job_origin
	_job_active = false


## Box blur of a square m×m grid, rows then columns, clamped at its edge.
func _blur(src: PackedFloat32Array, m: int, r: int) -> PackedFloat32Array:
	var w: float = float(2 * r + 1)
	var tmp := PackedFloat32Array()
	tmp.resize(m * m)
	for y: int in range(m):
		for x: int in range(m):
			var sum: float = 0.0
			for d: int in range(-r, r + 1):
				sum += src[y * m + clampi(x + d, 0, m - 1)]
			tmp[y * m + x] = sum / w
	var out := PackedFloat32Array()
	out.resize(m * m)
	for y: int in range(m):
		for x: int in range(m):
			var sum: float = 0.0
			for d: int in range(-r, r + 1):
				sum += tmp[clampi(y + d, 0, m - 1) * m + x]
			out[y * m + x] = sum / w
	return out


## Only walls shelter a lee; a roofed floor is cut away but piles nothing.
func _is_wall(i: int, j: int) -> bool:
	var kind: float = _ground[j * _n + i].y
	return kind > 0.5 and kind < 1.5


## Share of wall around a cell: a lone fence post shelters far less than a wall.
func _wall_share(i: int, j: int) -> float:
	var walls: int = 0
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			if _is_wall(clampi(i + dx, 0, _n - 1), clampi(j + dy, 0, _n - 1)):
				walls += 1
	return clampf(float(walls) / 3.0, 0.0, 1.0)


## 0..1: how much an obstacle upwind shelters this point.
func _lee(i: int, j: int, upwind: Array[Vector2i], ahead: Vector2i) -> float:
	var n: int = _n
	var pile: float = 0.0
	for k: int in range(8):
		var sx: int = i - upwind[k].x
		var sy: int = j - upwind[k].y
		if sx < 0 or sy < 0 or sx >= n or sy >= n:
			break
		var kk: float = float(k + 1)
		pile = maxf(pile, _wall[sy * n + sx] * smoothstep(0.0, 1.5, kk) * (1.0 - kk / 9.0))
	var fx: int = clampi(i + ahead.x, 0, n - 1)
	var fy: int = clampi(j + ahead.y, 0, n - 1)
	pile = maxf(pile, 0.6 * _wall[fy * n + fx])
	return pile
