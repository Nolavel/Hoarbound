extends SceneTree

## The legacy island; the game's main scene is Key West Reality (test_startup_presentation checks that).
const LEGACY_SCENE: String = "res://scenes/world/key_west/key_west.tscn"

var _failures: int = 0

func _initialize() -> void:
	var main := (load(LEGACY_SCENE) as PackedScene).instantiate() as World
	_check(main.world_profile != null and main.world_profile.id == &"key_west_test", "main scene does not pin Key West")
	var terrain := main.get_node(^"IslandTerrain") as IslandTerrain
	_check(terrain.heightmap_image_path == main.world_profile.terrain_image_path, "main terrain and profile disagree")
	main.free()
	var profile := load("res://data/world_profiles/key_west_test.tres") as WorldProfile
	_check(profile != null, "Key West profile failed to load")
	if profile != null:
		_check(profile.initial_weather_profile_id == &"blizzard", "Key West does not start in blizzard")
		_check(profile.prewarm_before_first_frame, "Key West weather can pop in after first frame")
		_check(is_equal_approx(profile.wind_direction_override_deg, 8.0), "coast-to-city wind bearing changed")
		_check(profile.world_data_path == "", "Key West must use runtime chunks")
		_check(profile.content_scene_path.ends_with("key_west_first_exit.tscn"), "Key West content scene is not selected")
	var content := KeyWestFirstExit.new()
	_check(content.get_route_distance_m() > 680.0 and content.get_route_distance_m() < 740.0, "Whitehead to Fort Street route is no longer about 700 m")
	_check(content.get_bunker_xz().distance_to(Vector2(-3452.88, 2273.84)) < 0.1, "Whitehead Spit anchor changed")
	_check(content.get_shelter_xz().distance_to(Vector2(-3579.85, 1574.51)) < 0.1, "Fort Street shelter anchor changed")
	_check_lot_is_clear(content)
	var weather := WeatherController.new()
	weather.profiles = WeatherController.load_profiles_from("res://resources/weather")
	weather.apply_world_profile(profile)
	weather.initialize()
	_check(weather.get_current_profile() != null and weather.get_current_profile().id == &"blizzard", "WeatherController did not activate blizzard before runtime")
	var expected := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(8.0))
	_check(weather.get_wind_direction().dot(expected) > 0.96, "initial wind is not sea to city")
	weather.free()
	content.free()
	if _failures == 0:
		print("key west first exit: all checks passed")
		quit()
	else:
		push_error("key west first exit: %d checks failed" % _failures)
		quit(1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error(message)


## The chosen lot holds no OSM building or road inside the fenced yard.
func _check_lot_is_clear(content: KeyWestFirstExit) -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/key_west/city_preview.json"))
	if not data is Dictionary:
		_check(false, "city data failed to load")
		return
	var yaw: float = deg_to_rad(KeyWestFirstExit.SHELTER_YAW_DEG)
	var yard := PackedVector2Array()
	for corner: Vector2 in [Vector2(-8, -10), Vector2(10, -10), Vector2(10, 14), Vector2(-8, 14)]:
		yard.append(content.get_shelter_xz() + corner.rotated(-yaw))
	var blocking: int = 0
	for building: Dictionary in data["buildings"]:
		var polygon: PackedVector2Array = KeyWestCityVisuals.normalized_footprint(building["footprint"])
		if polygon.size() >= 3 and polygon[0].distance_to(content.get_shelter_xz()) < 120.0:
			if not Geometry2D.intersect_polygons(polygon, yard).is_empty():
				blocking += 1
	_check(blocking == 0, "%d city buildings stand inside the shelter yard" % blocking)
	for road: Dictionary in data["roads"]:
		for point: Array in road["points"]:
			var p := Vector2(float(point[0]), float(point[1]))
			if p.distance_to(content.get_shelter_xz()) < 60.0 and Geometry2D.is_point_in_polygon(p, yard):
				_check(false, "road %s runs through the shelter yard" % road.get("name", "?"))
				return
