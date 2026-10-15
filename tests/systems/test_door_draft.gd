extends SceneTree

## Actual shelter geometry, live weather scalars and identical sealed/closed/open heat comparisons.
class DirectedWeather:
	extends WeatherController
	var direction: Vector3
	var snowfall: float = 0.95

	func get_wind_direction() -> Vector3:
		return direction

	func get_snowfall_density() -> float:
		return snowfall

var _failures: int = 0


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var scene := (load("res://scenes/world/first_exit/first_exit_blockout.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var house: Node3D = scene.get_node(^"ShelterHouse/House") as Node3D
	var door: HingedDoor = house.get_node(^"HouseDoor") as HingedDoor
	var zone: ThermalZone = house.get_node(^"ShelterZone") as ThermalZone
	var breach: ShelterBreach = zone.get_node(^"Door") as ShelterBreach
	var draft: BreachDraft = breach.get_node(^"Draft") as BreachDraft
	var windows: int = 0
	for opening: ShelterBreach in zone.get_breaches():
		if opening.boardable:
			windows += 1
			opening.board_up()
	_check(windows == 4 and not breach.has_node(^"BoardUp") and not breach.has_node(^"Boards"), "door still has repair geometry or wrong window count")
	var weather := DirectedWeather.new()
	weather.profiles = WeatherController.load_profiles_from("res://resources/weather")
	weather.starting_profile_id = &"blizzard"
	weather.scheduler_enabled = false
	weather.direction = -breach.get_facing()
	root.add_child(weather)
	weather.set_process(false)
	BreachDraft.set_weather(weather)
	var closed_area: float = _area(door.get_draft_regions())
	_check(door.get_draft_regions().size() == 4 and closed_area > 0.0 and closed_area < door.opening_size.x * door.opening_size.y * 0.1, "closed sources are not narrow four-sided gaps")
	var projected: AABB = (breach.global_transform.affine_inverse() * door._leaf.global_transform) * door._leaf.get_aabb()
	for region: AABB in door.get_draft_regions():
		_check(not Rect2(Vector2(region.position.x, region.position.y), Vector2(region.size.x, region.size.y)).intersects(Rect2(Vector2(projected.position.x, projected.position.y), Vector2(projected.size.x, projected.size.y))), "emitter overlaps closed leaf")
	_check(door._leaf.has_node(^"SnowLeafCollider") and door.has_node(^"SnowFrame0"), "particle contact blockers missing")
	var closed_strength: float = draft.get_strength()
	weather.snowfall = 0.0
	draft._process(1.0)
	_check(not draft.is_blowing() and draft.get_strength() == 0.0, "draft snow emitted without snowfall")
	weather.snowfall = 0.95
	weather.direction = breach.get_facing()
	_check(draft.get_strength() == 0.0, "leeward snow blew inward")
	weather.direction = -breach.get_facing()
	var previous_area: float = closed_area
	for angle: float in [30.0, 60.0, 105.0]:
		## The door's angle is its state; the hinge transform and the breach exposure are derived from it.
		door.current_angle_rad = deg_to_rad(angle)
		door._apply_hinge_angle()
		door._sync_breach_exposure()
		var area: float = _area(door.get_draft_regions())
		_check(area > previous_area, "moving aperture did not follow actual leaf")
		previous_area = area
	_check(draft.get_strength() > closed_strength * 10.0, "closed draft did not reduce weather intensity")
	var thermal := ThermalManager.new()
	thermal.weather_controller = weather
	root.add_child(thermal)
	thermal.set_process(false)
	thermal._zones.append(zone)
	zone.add_heat_source()
	breach.set_exposure_multiplier(0.0)
	zone.advance_heating(10.0)
	var sealed: float = thermal._compute_felt_temperature(12.0)
	breach.set_exposure_multiplier(0.05)
	zone.advance_heating(10.0)
	var closed: float = thermal._compute_felt_temperature(12.0)
	breach.set_exposure_multiplier(1.0)
	zone.advance_heating(10.0)
	var opened: float = thermal._compute_felt_temperature(12.0)
	_check(sealed - closed <= 1.0 and sealed > closed and closed > opened, "closed gap exceeded one degree or heat ordering wrong")
	print("door draft: sealed=%.3f closed=%.3f open=%.3f gap_cooling=%.3f C" % [sealed, closed, opened, sealed - closed])
	var saved := ShelterState.new()
	root.add_child(saved)
	var context := WorldContext.new()
	context.world = scene
	saved.on_world_ready(context)
	var data: Dictionary = saved.get_save_data()
	data["boarded"]["ShelterZone/Door"] = true
	saved.load_save_data(data)
	_check(not breach.is_boarded(), "legacy boarded save resurrected door boards")
	print("test_door_draft: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)


func _area(regions: Array[AABB]) -> float:
	var total: float = 0.0
	for region: AABB in regions:
		total += region.size.x * region.size.y
	return total


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("door draft: " + message)
