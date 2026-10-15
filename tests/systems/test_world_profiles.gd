extends SceneTree

## Dataset profiles retain the Graciosa default and gate Key West runtime
## readiness on real terrain files rather than configured paths alone.

var _failures: int = 0
var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _run() -> void:
	var graciosa: WorldProfile = WorldProfileCatalog.load_profile(&"graciosa")
	_check(graciosa != null, "Graciosa profile does not load")
	if graciosa != null:
		_check(graciosa.id == &"graciosa", "wrong Graciosa id")
		_check(graciosa.terrain_image_path == IslandHeightmap.DEFAULT_IMAGE, "Graciosa image path changed")
		_check(graciosa.terrain_meta_path == IslandHeightmap.DEFAULT_META, "Graciosa metadata path changed")
		_check(graciosa.world_data_path == StreamingSystem.DEFAULT_WORLD_DATA, "Graciosa world data path changed")
		_check(graciosa.is_runtime_ready(), "existing Graciosa profile is not runtime-ready")

	var key_west: WorldProfile = WorldProfileCatalog.load_profile(&"key_west_reality")
	_check(key_west != null, "Key West Reality profile does not load")
	if key_west != null:
		_check(not key_west.terrain_is_configured(), "Key West Reality chunks carry their own terrain, no heightmap")
		_check(key_west.content_scene_exists(), "Key West Reality content scene does not exist")
		_check(key_west.world_data_exists(), "Key West Reality streamed world data is missing")
	_check(not ResourceLoader.exists("res://data/world_profiles/key_west_test.tres"), "the deleted legacy Key West profile is back")

	var missing_terrain := WorldProfile.new()
	missing_terrain.id = &"missing_terrain"
	missing_terrain.terrain_image_path = "res://tests/missing_noaa_terrain.png"
	missing_terrain.terrain_meta_path = "res://tests/missing_noaa_terrain.json"
	_check(not missing_terrain.is_runtime_ready(), "configured missing terrain must not be runtime-ready")

	var terrain := IslandTerrain.new()
	_check(terrain.heightmap_image_path == IslandHeightmap.DEFAULT_IMAGE, "IslandTerrain no longer defaults to Graciosa image")
	_check(terrain.heightmap_meta_path == IslandHeightmap.DEFAULT_META, "IslandTerrain no longer defaults to Graciosa metadata")
	terrain.free()

	if _failures > 0:
		push_error("world profiles: %d check(s) failed" % _failures)
		quit(1)
		return
	print("world profiles: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("world profiles: %s" % message)
