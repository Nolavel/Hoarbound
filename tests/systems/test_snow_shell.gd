extends SceneTree

## Covers SnowField, the one answer to how much snow lies where: realistic
## depth, lee piles behind obstacles, none at the water, and Henry wading slower.
## Run: godot --headless --script tests/systems/test_snow_shell.gd

const SHELL_SCRIPT: GDScript = preload("res://scripts/systems/world/snow/snow_shell.gd")

var _failures: int = 0


func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	_test_depth_is_realistic_and_never_negative()
	_test_snow_piles_in_the_lee_of_an_obstacle()
	_test_no_snow_at_or_below_the_water()
	_test_windward_slopes_are_scoured()
	_test_a_recentre_keeps_the_field_on_the_world()
	_test_deeper_snow_is_slower()
	_test_the_world_builds_it()
	_test_the_city_wind_field_varies_depth()
	_test_low_tier_builds_no_window()
	_test_incremental_rebuild_matches_full()
	_test_sliced_rebuild_matches_whole()
	_test_chunk_cover_slices_and_caches()
	_test_tiers_size_the_captures()
	_test_storm_share_rebuilds_in_place()
	_test_a_boot_sinks_over_its_stance()
	_test_wind_crust_is_harder_than_powder()
	if _failures > 0:
		push_error("snow shell: %d check(s) failed" % _failures)
		quit(1)
		return
	print("snow shell: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("snow shell: %s" % message)


func _field(sampler: Callable) -> SnowField:
	var field := SnowField.new()
	field.ground_sampler = sampler
	field.sea_level_m = -100.0
	return field


func _flat(at: Vector2) -> Vector2:
	return Vector2(5.0, 0.0)


func _test_depth_is_realistic_and_never_negative() -> void:
	var field: SnowField = _field(_flat)
	field.rebuild(Vector2(-12.8, -12.8), 1.0, Vector2(0, -1))
	var deepest: float = 0.0
	for tz: int in range(-12, 13):
		for tx: int in range(-12, 13):
			var d: float = field.get_depth(tx, tz)
			_check(d >= 0.0, "negative snow depth at %d,%d" % [tx, tz])
			deepest = maxf(deepest, d)
	_check(deepest > 0.1 and deepest < 0.7, "open-ground depth %.2f m is not a real snowpack" % deepest)
	_check(is_equal_approx(field.get_snow_top(0, 0), 5.0 + field.get_depth(0, 0)), "top is not ground + depth")


func _test_snow_piles_in_the_lee_of_an_obstacle() -> void:
	## A box at z in [-1, 0]; the wind blows towards +z.
	var boxed := func(at: Vector2) -> Vector2:
		return Vector2(0.0, 1.0 if absf(at.x) < 2.0 and at.y > -1.0 and at.y < 0.0 else 0.0)
	var field: SnowField = _field(boxed)
	field.rebuild(Vector2(-12.8, -12.8), 1.0, Vector2(0, 1))
	var lee: float = field.get_depth(0.0, 1.2)
	var upwind: float = field.get_depth(0.0, -3.0)
	_check(lee > upwind + 0.2, "no lee pile: %.2f behind vs %.2f upwind" % [lee, upwind])


func _test_no_snow_at_or_below_the_water() -> void:
	var shore := func(at: Vector2) -> Vector2:
		return Vector2(at.x * 0.2, 0.0)
	var field: SnowField = _field(shore)
	field.sea_level_m = 0.0
	field.rebuild(Vector2(-12.8, -12.8), 1.0, Vector2(0, -1))
	_check(field.get_depth(-3.0, 0.0) == 0.0, "snow lies under the water")
	_check(field.get_depth(0.05, 0.0) < 0.02, "snow does not thin out at the water's edge")
	_check(field.get_depth(8.0, 0.0) > 0.1, "no snow well above the water")


func _test_windward_slopes_are_scoured() -> void:
	## Ground rises towards +z; the wind blows towards +z, into the slope.
	var slope := func(at: Vector2) -> Vector2:
		return Vector2(at.y * 0.6, 0.0)
	var into := _field(slope)
	into.rebuild(Vector2(-12.8, -12.8), 1.0, Vector2(0, 1))
	var away := _field(slope)
	away.rebuild(Vector2(-12.8, -12.8), 1.0, Vector2(0, -1))
	var windward: float = 0.0
	var leeward: float = 0.0
	for tx: int in range(-8, 9):
		windward += into.get_depth(tx, 0.0)
		leeward += away.get_depth(tx, 0.0)
	_check(windward < leeward * 0.8, "the windward face keeps as much snow as the lee face")


func _test_a_recentre_keeps_the_field_on_the_world() -> void:
	var field: SnowField = _field(_flat)
	field.rebuild(Vector2(-12.8, -12.8), 1.0, Vector2(0, -1))
	var before: float = field.get_depth(3.0, 1.0)
	field.rebuild(Vector2(-6.4, -9.6), 1.0, Vector2(0, -1))
	_check(is_equal_approx(field.get_depth(3.0, 1.0), before), "depth at a world point changed when the window moved")


func _test_deeper_snow_is_slower() -> void:
	var shell: SnowShell = SHELL_SCRIPT.new()
	var last: float = 2.0
	for i: int in range(0, 11):
		var m: float = shell.get_speed_multiplier(i * 0.06)
		_check(m <= last, "deeper snow was faster at %.2f m" % (i * 0.06))
		last = m
	_check(is_equal_approx(shell.get_speed_multiplier(0.0), 1.0), "bare ground slows Henry")
	_check(shell.get_speed_multiplier(1.0) < 0.7, "waist-deep snow barely slows Henry")
	shell.free()


func _test_the_world_builds_it() -> void:
	var source: String = FileAccess.get_file_as_string("res://world/world.gd")
	_check(source.contains("snow/deterministic_snow_shell.gd"), "world.gd does not build the snow shell")


func _test_the_city_wind_field_varies_depth() -> void:
	var field := SnowField.new()
	_check(field.wind_factor(Vector2.ZERO) == 1.0, "no wind field should leave depth unchanged")
	_check(field.load_wind_field("res://data/world/key_west/snow_wind.png"), "the Key West wind field did not load")
	## Across the island the wind must scour open ground and bank snow in the lee.
	var lo: float = INF
	var hi: float = -INF
	for i: int in range(400):
		var f: float = field.wind_factor(Vector2(-4000.0 + float(i % 20) * 200.0, -1000.0 + float(i / 20) * 150.0))
		lo = minf(lo, f)
		hi = maxf(hi, f)
	_check(lo < 0.6 and hi > 1.4, "the wind field is flat: %.2f..%.2f" % [lo, hi])
	_check(field.wind_factor(Vector2(-3000.0, -2500.0)) < 0.05, "open sea should hold no settled snow")


func _test_low_tier_builds_no_window() -> void:
	var before: Variant = ProjectSettings.get_setting("hfn/snow/quality", "high")
	ProjectSettings.set_setting("hfn/snow/quality", "low")
	var shell: Node3D = SHELL_SCRIPT.new()
	root.add_child(shell)
	_check(shell.get_child_count() == 0, "the low tier still built the snow window")
	_check(not shell.is_physics_processing(), "the low tier still runs the snow window")
	shell.recentre_to(Vector2(10.0, 10.0))
	shell.free()
	ProjectSettings.set_setting("hfn/snow/quality", before)


## Synthetic ground: a slope, a long wall, a box and a roofed floor.
func _synthetic_ground(at: Vector2) -> Vector2:
	var h: float = 0.3 + at.x * 0.02 + sin(at.y * 0.7) * 0.05
	if at.y > 4.0 and at.y < 4.4 and at.x > -6.0 and at.x < 14.0:
		return Vector2(h + 2.0, 1.0)
	if at.x > 8.0 and at.x < 9.2 and at.y > -3.0 and at.y < -1.6:
		return Vector2(h + 1.0, 1.0)
	if at.x > -9.0 and at.x < -6.0 and at.y > -8.0 and at.y < -5.0:
		return Vector2(h + 3.0, 2.0)
	return Vector2(h, 0.0)


## Moving the window must give the same field as sampling it from scratch there.
func _test_incremental_rebuild_matches_full() -> void:
	var moving := SnowField.new()
	var fresh := SnowField.new()
	for f: SnowField in [moving, fresh]:
		f.ground_sampler = _synthetic_ground
	var wind := Vector2(0.6, -0.8)
	var path: Array[Vector2] = [
		Vector2(-12.8, -12.8), Vector2(-9.6, -12.8), Vector2(-9.6, -9.6),
		Vector2(-6.4, -6.4), Vector2(-9.6, -6.4), Vector2(-9.6, -9.6), Vector2(-3.2, -3.2),
	]
	var worst: float = 0.0
	for o: Vector2 in path:
		moving.rebuild(o, 0.8, wind)
		fresh.invalidate()
		fresh.rebuild(o, 0.8, wind)
		for y: int in range(moving.res):
			for x: int in range(moving.res):
				var a: Color = moving.image.get_pixel(x, y)
				var b: Color = fresh.image.get_pixel(x, y)
				worst = maxf(worst, maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a))))
	_check(worst < 1e-4, "an incremental rebuild drifted from a full one by %.6f" % worst)


## A rebuild spread over many tiny frame budgets lands on the same field, and the
## old field stays live until it does.
func _test_sliced_rebuild_matches_whole() -> void:
	var whole := SnowField.new()
	var sliced := SnowField.new()
	for f: SnowField in [whole, sliced]:
		f.ground_sampler = _synthetic_ground
		f.rebuild(Vector2(-12.8, -12.8), 0.7, Vector2(0.6, -0.8))
	whole.rebuild(Vector2(-9.6, -12.8), 0.7, Vector2(0.6, -0.8))
	sliced.begin_rebuild(Vector2(-9.6, -12.8), 0.7, Vector2(0.6, -0.8))
	var frames: int = 0
	var early_origin: Vector2 = sliced.origin
	while not sliced.step_rebuild(1):
		frames += 1
	_check(frames > 10, "a 1 µs budget finished in %d frames; it is not slicing" % frames)
	_check(early_origin.is_equal_approx(Vector2(-12.8, -12.8)), "the old window was not live during the rebuild")
	_check(sliced.origin.is_equal_approx(Vector2(-9.6, -12.8)), "the sliced rebuild did not switch the window")
	var worst: float = 0.0
	for y: int in range(whole.res):
		for x: int in range(whole.res):
			var a: Color = whole.image.get_pixel(x, y)
			var b: Color = sliced.image.get_pixel(x, y)
			worst = maxf(worst, maxf(absf(a.r - b.r), absf(a.g - b.g)))
	_check(worst < 1e-6, "a sliced rebuild drifted from a whole one by %.7f" % worst)


## A chunk built in slices matches one built whole, and a cached copy is the same mesh.
func _test_chunk_cover_slices_and_caches() -> void:
	var terrain := IslandTerrain.new()
	SnowChunkCover.clear_cache()
	var origin := Vector2(-64.0, -64.0)
	var job: SnowChunkCover.Job = SnowChunkCover.begin(terrain, origin, 64.0)
	var frames: int = 0
	while not SnowChunkCover.step(job, 1):
		frames += 1
	_check(frames > 10, "a chunk at a 1 µs budget finished in %d frames" % frames)
	var sliced: MeshInstance3D = SnowChunkCover.finish(job)
	_check(SnowChunkCover.is_cached(origin), "a finished chunk was not cached")
	var again: MeshInstance3D = SnowChunkCover.cached(origin)
	_check(sliced == null or again.mesh == sliced.mesh, "the cache rebuilt the mesh")
	SnowChunkCover.clear_cache()
	var whole: MeshInstance3D = SnowChunkCover.build(terrain, origin, 64.0)
	if sliced != null and whole != null:
		var a: Array = sliced.mesh.surface_get_arrays(0)
		var b: Array = whole.mesh.surface_get_arrays(0)
		_check(a[Mesh.ARRAY_VERTEX] == b[Mesh.ARRAY_VERTEX] and a[Mesh.ARRAY_INDEX] == b[Mesh.ARRAY_INDEX]
			and a[Mesh.ARRAY_TEX_UV] == b[Mesh.ARRAY_TEX_UV], "a sliced chunk differs from a whole one")
	else:
		_check(sliced == whole, "sliced and whole chunks disagree on holding snow")
	for f: MeshInstance3D in [sliced, again, whole]:
		if f != null:
			f.free()
	terrain.free()
	SnowChunkCover.clear_cache()


## Medium captures contact at half resolution but keeps the packed field; high keeps both.
func _test_tiers_size_the_captures() -> void:
	var before: Variant = ProjectSettings.get_setting("hfn/snow/quality", "high")
	for tier: String in ["high", "medium"]:
		ProjectSettings.set_setting("hfn/snow/quality", tier)
		var shell: Node3D = SHELL_SCRIPT.new()
		root.add_child(shell)
		var contact: SubViewport = shell.get_node("SnowContact")
		var packed: SubViewport = shell.get_node("SnowPacked0")
		var want: int = 1024 if tier == "high" else 512
		_check(contact.size == Vector2i(want, want), "%s contact capture is %s" % [tier, contact.size])
		_check(packed.size == Vector2i(896, 896), "%s packed field is %s" % [tier, packed.size])
		shell.free()
	ProjectSettings.set_setting("hfn/snow/quality", before)


## Changing the storm share and rebuilding in place lands on the field built fresh
## at that share: prevailing and storm factors are cached apart.
func _test_storm_share_rebuilds_in_place() -> void:
	var cached := SnowField.new()
	var fresh := SnowField.new()
	cached.load_wind_field("res://data/world/key_west/snow_wind.png")
	fresh.load_wind_field("res://data/world/key_west/snow_wind.png")
	for f: SnowField in [cached, fresh]:
		f.ground_sampler = _synthetic_ground
	var o := Vector2(-3225.0, 1148.0)
	cached.storm_share = 0.1
	cached.rebuild(o, 0.8, Vector2(0.6, -0.8))
	cached.storm_share = 0.9
	cached.rebuild(o, 0.8, Vector2(0.6, -0.8))
	fresh.storm_share = 0.9
	fresh.rebuild(o, 0.8, Vector2(0.6, -0.8))
	var worst: float = 0.0
	for y: int in range(cached.res):
		for x: int in range(cached.res):
			var a: Color = cached.image.get_pixel(x, y)
			var b: Color = fresh.image.get_pixel(x, y)
			worst = maxf(worst, maxf(absf(a.g - b.g), absf(a.a - b.a)))
	_check(worst < 1e-5, "an in-place storm rebuild drifted from a fresh one by %.6f" % worst)


## Snow has weight: a planted boot presses in over its stance, never at once,
## and never past what the snow gives.
func _test_a_boot_sinks_over_its_stance() -> void:
	var give: float = 0.3
	var last: float = 0.0
	for i: int in range(1, 30):
		var s: float = SHELL_SCRIPT.sink_after(float(i) * 0.03, give, 0.22)
		_check(s >= last and s <= give, "sink went %.3f -> %.3f past %.2f" % [last, s, give])
		last = s
	_check(SHELL_SCRIPT.sink_after(0.03, give, 0.22) < give * 0.2, "a boot dropped to the bottom at once")
	_check(SHELL_SCRIPT.sink_after(1.0, give, 0.22) > give * 0.95, "a long stance never reached the bottom")


## Scoured ground is wind crust that holds a boot; lee drifts are powder.
func _test_wind_crust_is_harder_than_powder() -> void:
	var field := SnowField.new()
	var crust: float = 0.0
	var powder: float = 0.0
	for i: int in range(40):
		var at := Vector2(float(i) * 3.7, float(i) * -2.3)
		crust += field.softness(at, 0.3)
		powder += field.softness(at, 1.8)
		_check(field.softness(at, 1.0) >= 0.4 and field.softness(at, 1.0) <= 1.0, "softness left 0.4..1")
	_check(crust < powder - 4.0, "wind crust gives as much as powder")
	field.ground_sampler = _synthetic_ground
	field.rebuild(Vector2(-12.8, -12.8), 0.8, Vector2(0, -1))
	var s: float = field.get_softness(10.0, 0.0)
	_check(s >= 0.4 and s <= 1.0, "the field image lost its softness: %.2f" % s)
