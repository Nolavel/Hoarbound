extends SceneTree

## Developer diorama map runtime gate, M-toggle and follow camera contract.

var _failures: int = 0


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_check(InputMap.has_action(&"toggle_dev_map"), "toggle_dev_map action is missing")
	_check(_action_has_m(), "toggle_dev_map is not bound to physical M")

	await _test_disabled_world_ignores_toggle()
	await _test_enabled_world_toggles_and_follows()

	if _failures > 0:
		push_error("dev diorama map: %d check(s) failed" % _failures)
		quit(1)
		return
	print("dev diorama map: all checks passed")
	quit(0)


func _test_disabled_world_ignores_toggle() -> void:
	var fixture: Dictionary = await _make_fixture(false)
	var map := fixture["map"] as DevDioramaMap
	map._on_toggle_requested()
	_check(not map.is_runtime_toggle_enabled(), "disabled world enabled runtime map")
	_check(not map.is_map_open(), "M opened map while world flag was false")
	_check(not map.visible, "disabled runtime map became visible")
	_dispose(fixture["world"] as Node)
	_dispose(map)


func _test_enabled_world_toggles_and_follows() -> void:
	var fixture: Dictionary = await _make_fixture(true)
	var map := fixture["map"] as DevDioramaMap
	var player := fixture["player"] as Node3D
	var main_camera := fixture["camera"] as Camera3D

	_check(map.is_runtime_toggle_enabled(), "enabled world did not authorize runtime map")
	_check(not map.is_map_open(), "authorized map starts open instead of waiting for M")

	map._on_toggle_requested()
	await process_frame  # containers lay out a frame after they are shown
	_check(map.is_map_open() and map.visible, "first M did not open authorized map")
	_check(is_equal_approx(map.get_height_m(), 90.0), "map height is not fixed at 90 m")
	_check(map.get_focus_world().distance_to(player.global_position) < 0.01, "map did not center on Henry")
	_check((main_camera.cull_mask & DevDioramaMap.MAP_LABEL_MASK) == 0, "TPS camera still sees map-only labels")
	_check((map.get_map_cull_mask() & RenderLayers.SCREEN_PASS) == 0, "map camera draws the player camera's fullscreen pass")
	_check_live_viewport_projection(map)
	_check_marker_tracks_ground_position(map, player)

	map.set_process(false)
	player.global_position += Vector3(20.0, 0.0, -10.0)
	for _i: int in range(20):
		map._process(0.05)
	_check(map.get_focus_world().distance_to(player.global_position) < 0.5, "follow camera did not track Henry")

	map._on_toggle_requested()
	_check(not map.is_map_open() and not map.visible, "second M did not hide authorized map")
	_dispose(fixture["world"] as Node)
	_dispose(map)


func _check_live_viewport_projection(map: DevDioramaMap) -> void:
	var projected_focus: Vector2 = map._project_world_to_map(map.get_focus_world())
	var expected_center: Vector2 = map._map_container.position + map._map_container.size * 0.5
	_check(
		projected_focus.distance_to(expected_center) < 1.0,
		"map camera target is not projected to the displayed map center"
	)


func _check_marker_tracks_ground_position(map: DevDioramaMap, player: Node3D) -> void:
	var fallback_point: Vector3 = map._marker_world_point()
	_check(
		Vector2(fallback_point.x, fallback_point.z).distance_to(Vector2(player.global_position.x, player.global_position.z)) < 0.001,
		"marker X/Z does not match Henry"
	)
	_check(is_equal_approx(fallback_point.y, player.global_position.y - 1.0), "marker fallback is not at capsule ground")

	var terrain := IslandTerrain.new()
	terrain.heightmap = _constant_heightmap(0.75)
	map._terrain = terrain

	for offset: Vector3 in [Vector3(14.0, 0.0, 0.0), Vector3(0.0, 0.0, -11.0)]:
		player.global_position += offset
		var point: Vector3 = map._marker_world_point()
		_check(
			Vector2(point.x, point.z).distance_to(Vector2(player.global_position.x, player.global_position.z)) < 0.001,
			"marker stopped matching Henry X/Z after movement"
		)
		_check(is_equal_approx(point.y, 0.75), "marker is not projected onto terrain height")


func _constant_heightmap(height_m: float) -> IslandHeightmap:
	var map := IslandHeightmap.new()
	map.origin = Vector2(-1000.0, -1000.0)
	map.metres_per_px = 2000.0
	map.width = 2
	map.height = 2
	map.height_min = height_m
	map.height_span = 0.0
	map._data = PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0])
	return map


func _make_fixture(enabled: bool) -> Dictionary:
	var packed := load("res://scenes/ui/debug/dev_diorama_map.tscn") as PackedScene
	var map := packed.instantiate() as DevDioramaMap
	root.add_child(map)
	await process_frame

	var world := World.new()
	world.name = "World"
	world.enable_runtime_dev_map = enabled
	root.add_child(world)
	var player := CharacterBody3D.new()
	player.name = "Player"
	world.add_child(player)
	player.global_position = Vector3(12.0, 2.0, -8.0)
	var collision := CollisionShape3D.new()
	collision.name = "Main_Collision"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.5
	capsule.height = 2.0
	collision.shape = capsule
	player.add_child(collision)
	var main_camera := Camera3D.new()
	world.add_child(main_camera)

	var context := WorldContext.new()
	context.world = world
	context.player = player
	context.camera = main_camera
	map.on_world_ready(context)
	return {"map": map, "world": world, "player": player, "camera": main_camera}


func _action_has_m() -> bool:
	for event: InputEvent in InputMap.action_get_events(&"toggle_dev_map"):
		var key := event as InputEventKey
		if key != null and key.physical_keycode == KEY_M:
			return true
	return false


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("dev diorama map: %s" % message)


func _dispose(node: Node) -> void:
	if node == null:
		return
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()
