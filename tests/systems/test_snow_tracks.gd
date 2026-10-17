extends SceneTree

## Snow deformation that leaves the window is kept in world tiles and comes back
## filled in for its age. Persistence v3 keeps all four deformation channels.
## Run: godot --headless --script tests/systems/test_snow_tracks.gd

var _failures: int = 0


func _process(_delta: float) -> bool:
	_test_a_trail_comes_back_filled_for_its_age()
	_test_the_staying_window_is_not_filed()
	_test_tracks_survive_a_save()
	_test_legacy_signed_tiles_still_load()
	_test_v2_rg_tiles_still_load()
	_test_broken_crust_and_density_survive()
	_test_the_shell_saves_its_tracks()
	if _failures > 0:
		push_error("snow tracks: %d check(s) failed" % _failures)
		quit(1)
		return true
	print("snow tracks: all checks passed")
	quit(0)
	return true


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("snow tracks: %s" % message)


## A 25.6 m window at 1024 texels. Compression occupies one band, displaced
## powder another, with an overlap proving R and G survive independently.
func _trail() -> Image:
	var img := Image.create_empty(1024, 1024, false, Image.FORMAT_RGF)
	for y: int in range(1024):
		for x: int in range(200, 280):
			var compression: float = 0.3 if x < 260 else 0.0
			var displaced: float = 0.08 if x >= 230 else 0.0
			img.set_pixel(x, y, Color(compression, displaced, 0.0, 1.0))
	return img


func _test_a_trail_comes_back_filled_for_its_age() -> void:
	var store := SnowTrackStore.new()
	var origin := Vector2(-12.8, -12.8)
	store.store(_trail(), origin, 25.6, Rect2())
	var fresh: Image = store.restore(origin, 25.6, 256)
	_check(fresh.get_format() == Image.FORMAT_RGBAF, "restore is not an RGBA deformation image")
	var compression_only: Color = fresh.get_pixel(52, 128)
	var overlap: Color = fresh.get_pixel(60, 128)
	var displaced_only: Color = fresh.get_pixel(67, 128)
	_check(absf(compression_only.r - 0.3) < 0.012, "fresh compression came back %.3f m, not 0.3" % compression_only.r)
	_check(compression_only.g < 0.008, "displaced mass leaked into compression-only texel")
	_check(absf(overlap.r - 0.3) < 0.012 and absf(overlap.g - 0.08) < 0.012,
		"R+G overlap did not survive: %.3f/%.3f" % [overlap.r, overlap.g])
	_check(displaced_only.r < 0.008 and absf(displaced_only.g - 0.08) < 0.012,
		"displaced-only texel did not survive: %.3f/%.3f" % [displaced_only.r, displaced_only.g])
	_check(fresh.get_pixel(150, 128).r < 0.005 and fresh.get_pixel(150, 128).g < 0.005,
		"deformation appeared off the trail")
	for i: int in range(600):
		store.advance(0.001)
	var aged: Color = store.restore(origin, 25.6, 256).get_pixel(60, 128)
	var left: float = pow(0.999, 600)
	_check(absf(aged.r - 0.3 * left) < 0.012, "aged compression %.3f has wrong fill" % aged.r)
	_check(absf(aged.g - 0.08 * left) < 0.012, "aged displaced mass %.3f has wrong fill" % aged.g)


func _test_the_staying_window_is_not_filed() -> void:
	var store := SnowTrackStore.new()
	var origin := Vector2(0.0, 0.0)
	store.store(_trail(), origin, 25.6, Rect2(Vector2(9.6, 0.0), Vector2(25.6, 25.6)))
	var keys: Array = store.tiles.keys()
	_check(not keys.is_empty(), "the tiles leaving the window were not filed")
	for key: Vector2i in keys:
		_check(key.x < 3, "tile %s is still on screen but was filed" % key)


func _test_tracks_survive_a_save() -> void:
	var store := SnowTrackStore.new()
	var origin := Vector2(-12.8, -12.8)
	store.store(_trail(), origin, 25.6, Rect2())
	store.advance(0.3)
	var save: Dictionary = store.get_save_data()
	_check(int(save.get("format_version", 0)) == SnowTrackStore.FORMAT_VERSION, "save did not advertise persistence v3")
	_check(int(save.get("channels", 0)) == 4, "save did not advertise four deformation channels")
	var copy := SnowTrackStore.new()
	copy.load_save_data(JSON.parse_string(JSON.stringify(save)))
	_check(copy.tiles.size() == store.tiles.size(), "tiles were lost in a save")
	_check(is_equal_approx(copy.clock, store.clock), "the fill clock was lost in a save")
	var a: Color = store.restore(origin, 25.6, 256).get_pixel(60, 128)
	var b: Color = copy.restore(origin, 25.6, 256).get_pixel(60, 128)
	_check(absf(a.r - b.r) < 0.001 and absf(a.g - b.g) < 0.001,
		"loaded R+G deformation differs from saved state")


func _test_legacy_signed_tiles_still_load() -> void:
	var bytes := PackedByteArray()
	bytes.resize(SnowTrackStore.LEGACY_TILE_TEX * SnowTrackStore.LEGACY_TILE_TEX)
	bytes.fill(SnowTrackStore.ZERO_BYTE)
	bytes[16 * SnowTrackStore.LEGACY_TILE_TEX + 16] = SnowTrackStore.ZERO_BYTE + 20
	bytes[16 * SnowTrackStore.LEGACY_TILE_TEX + 20] = SnowTrackStore.ZERO_BYTE - 10
	var legacy := {
		"clock": 0.0,
		"zero_byte": SnowTrackStore.ZERO_BYTE,
		"tiles": {"0:0": [0.0, Marshalls.raw_to_base64(bytes)]},
	}
	var store := SnowTrackStore.new()
	store.load_save_data(legacy)
	var restored: Image = store.restore(Vector2.ZERO, 25.6, 256)
	var packed: Color = restored.get_pixel(16, 16)
	var heap: Color = restored.get_pixel(20, 16)
	_check(absf(packed.r - 0.1) < 0.008 and packed.g < 0.005, "legacy compression did not migrate")
	_check(heap.r < 0.005 and absf(heap.g - 0.05) < 0.008, "legacy displaced byte did not migrate")


func _test_broken_crust_and_density_survive() -> void:
	var img := Image.create_empty(256, 256, false, Image.FORMAT_RGBAF)
	for y: int in range(40, 130):
		for x: int in range(40, 130):
			img.set_pixel(x, y, Color(0.10, 0.035, 0.73, 0.61))
	var store := SnowTrackStore.new()
	store.store(img, Vector2.ZERO, 25.6, Rect2())
	var fresh: Color = store.restore(Vector2.ZERO, 25.6, 256).get_pixel(80, 80)
	_check(absf(fresh.r - 0.10) < 0.008, "v3 compression missing")
	_check(absf(fresh.g - 0.035) < 0.008, "v3 displaced mass missing")
	_check(absf(fresh.b - 0.73) < 0.015, "v3 broken crust missing")
	_check(absf(fresh.a - 0.61) < 0.015, "v3 compacted density missing")
	store.advance(0.3)
	var aged: Color = store.restore(Vector2.ZERO, 25.6, 256).get_pixel(80, 80)
	var age: float = store.clock
	_check(absf(aged.b - 0.73 * exp(-age * 0.72)) < 0.015, "broken crust wrong aging")
	_check(absf(aged.a - 0.61 * exp(-age * 0.42)) < 0.015, "density wrong aging")
	var copy := SnowTrackStore.new()
	copy.load_save_data(JSON.parse_string(JSON.stringify(store.get_save_data())))
	var replay: Color = copy.restore(Vector2.ZERO, 25.6, 256).get_pixel(80, 80)
	_check(absf(replay.b - aged.b) < 0.001 and absf(replay.a - aged.a) < 0.001,
		"v3 B/A changed across save/load")


func _test_v2_rg_tiles_still_load() -> void:
	var bytes := PackedByteArray()
	bytes.resize(SnowTrackStore.LEGACY_TILE_TEX * SnowTrackStore.LEGACY_TILE_TEX * 2)
	bytes[0] = 30
	bytes[1] = 8
	var save := {
		"format_version": 2,
		"channels": 2,
		"clock": 0.0,
		"tiles": {"0:0": [0.0, Marshalls.raw_to_base64(bytes)]},
	}
	var store := SnowTrackStore.new()
	store.load_save_data(save)
	var pixel: Color = store.restore(Vector2.ZERO, 25.6, 256).get_pixel(0, 0)
	_check(pixel.r > 0.1 and pixel.g > 0.02, "v2 R/G migration dropped deformation")
	_check(pixel.b < 0.001 and pixel.a < 0.001, "v2 migration invented missing B/A")


func _test_the_shell_saves_its_tracks() -> void:
	var shell: Node = load("res://scripts/systems/world/snow/snow_shell.gd").new()
	_check(SaveManager.implements_save_contract(shell), "the snow shell is not a save participant")
	shell.free()
