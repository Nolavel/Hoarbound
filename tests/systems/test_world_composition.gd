extends SceneTree

## Covers the composition root and the contracts it depends on: the
## on_world_ready hook, WorldContext lookup, and the save contract's
## all-or-nothing check.
## Run: godot --headless --script tests/systems/test_world_composition.gd

var _failures: int = 0


## Nodes added to root during _initialize() are not in the tree yet, and
## global_position and _ready both depend on that. Running from the first
## frame puts the suite in the same conditions as the running game.
func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	_test_context_finds_systems_by_class()
	_test_world_builds_its_systems_once()
	_test_world_ready_reaches_every_category()
	_test_world_places_the_player_and_drops_the_marker()
	_test_save_contract_is_all_or_nothing()
	_test_unknown_save_versions_are_refused()
	_test_save_manager_adopts_the_systems_list()
	_test_the_thermal_stack_is_wired_and_follows_the_player()
	_test_a_scene_with_its_own_floor_streams_nothing()
	_test_first_exit_bearings_follow_the_key_west_profile()
	if _failures > 0:
		push_error("world: %d check(s) failed" % _failures)
		quit(1)
		return
	print("world: all checks passed")
	quit(0)


## Writes a file, failing the suite with the reason rather than crashing on a
## null handle when user:// is not writable.
func _write(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check(false, "cannot write %s (error %d); is user:// writable?"
			% [path, FileAccess.get_open_error()])
		return false
	file.store_string(text)
	file.close()
	return true


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("world: %s" % message)


func _expected_systems(world: World) -> int:
	var count: int = World.WORLD_SYSTEM_SCRIPTS.size()
	if world.world_profile == null or world.world_profile.id != World.FIRST_EXIT_PROFILE_ID:
		count -= 1
	return count


## The stub world is not Key West, so it must not grow the 727 compass.
## A profile with that id must.
func _test_first_exit_bearings_follow_the_key_west_profile() -> void:
	var bearings_script: GDScript = load("res://scripts/world/first_exit_bearings.gd")
	var plain := _make_world()
	plain.initialize()
	_check(
		plain.get_context().get_system(bearings_script) == null,
		"First Exit bearings were built for a world that is not Key West"
	)
	_dispose(plain)
	var key_west := _make_world()
	var profile := WorldProfile.new()
	profile.id = World.FIRST_EXIT_PROFILE_ID
	key_west.world_profile = profile
	key_west.initialize()
	_check(
		key_west.get_context().get_system(bearings_script) != null,
		"Key West did not build First Exit bearings"
	)
	_check(
		key_west.get_context().systems.size() == World.WORLD_SYSTEM_SCRIPTS.size(),
		"Key West dropped a system other than the compass"
	)
	_dispose(key_west)


func _dispose(node: Node) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()


## Builds a World with a player, camera and spawn marker already in place,
## the way the island scene supplies them.
func _make_world() -> World:
	var world := World.new()
	var container := Node3D.new()
	container.name = "StreamContainer"
	world.add_child(container)

	var player := Node3D.new()
	player.name = "Player"
	world.add_child(player)

	var camera := Camera3D.new()
	camera.name = "PlayerCamera"
	world.add_child(camera)

	var marker := Marker3D.new()
	marker.name = "FirstSpawner"
	marker.position = Vector3(10.0, 4.0, -6.0)
	world.add_child(marker)
	world.first_spawner_marker = marker

	root.add_child(world)
	return world


func _test_context_finds_systems_by_class() -> void:
	var context := WorldContext.new()
	var weather := WeatherController.new()
	var save := SaveManager.new()
	context.systems = [weather, save]

	_check(context.get_system(WeatherController) == weather, "get_system missed WeatherController")
	_check(context.get_system(SaveManager) == save, "get_system missed SaveManager")
	_check(context.get_system(ThermalManager) == null, "get_system invented a missing system")
	_check(not context.is_complete(), "an empty context reported itself complete")

	weather.free()
	save.free()


func _test_world_builds_its_systems_once() -> void:
	var world := _make_world()
	world.initialize()
	var context: WorldContext = world.get_context()
	_check(context != null, "initialize() produced no context")
	var expected: int = _expected_systems(world)
	_check(
		context.systems.size() == expected,
		"built %d systems, expected %d"
		% [context.systems.size(), expected]
	)
	_check(context.is_complete(), "the context is missing player, camera or container")

	## Idempotent: a second call must not double every system.
	world.initialize()
	_check(
		world.get_context().systems.size() == _expected_systems(world),
		"a second initialize() rebuilt the systems"
	)
	_dispose(world)


func _test_world_ready_reaches_every_category() -> void:
	var world := _make_world()
	world.initialize()
	var context: WorldContext = world.get_context()

	var save := context.get_system(SaveManager) as SaveManager
	_check(save != null, "SaveManager was not built by the composition root")

	## Every system in the list must have been offered the hook; SaveManager
	## proves it by having adopted the systems list.
	_check(
		save._registered.size() > 0,
		"on_world_ready did not reach the systems, so nothing registered for saving"
	)
	_dispose(world)


func _test_world_places_the_player_and_drops_the_marker() -> void:
	var world := _make_world()
	var expected: Vector3 = world.first_spawner_marker.position + Vector3(0.0, World.SPAWN_CLEARANCE, 0.0)
	world.initialize()

	_check(
		world.player.global_position.is_equal_approx(expected),
		"the player did not land on the spawn marker: %s" % str(world.player.global_position)
	)
	_check(world.first_spawner_marker == null, "the spawn marker was not released")
	_dispose(world)


## A half-implemented contract is skipped, not half-saved.
func _test_save_contract_is_all_or_nothing() -> void:
	var complete := ThermalManager.new()
	_check(
		SaveManager.implements_save_contract(complete),
		"ThermalManager does not implement the whole save contract"
	)
	complete.free()

	var partial := Node.new()
	_check(
		not SaveManager.implements_save_contract(partial),
		"a plain Node was accepted as a save participant"
	)
	partial.free()


func _test_unknown_save_versions_are_refused() -> void:
	var manager := SaveManager.new()
	root.add_child(manager)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://saves"))

	var path: String = "user://saves/slot_5.json"
	if not _write(path, JSON.stringify({"version": 999, "payload": {}, "metadata": {}})):
		_dispose(manager)
		return

	_check(manager.read_slot(5).is_empty(), "a save from a newer build was accepted")
	_check(
		manager.get_last_error().contains("newer build"),
		"the refusal did not explain itself: '%s'" % manager.get_last_error()
	)

	if not _write(path, JSON.stringify({"payload": {}})):
		_dispose(manager)
		return
	_check(manager.read_slot(5).is_empty(), "a save with no version field was accepted")

	manager.delete_slot(5)
	_dispose(manager)


func _test_save_manager_adopts_the_systems_list() -> void:
	var manager := SaveManager.new()
	root.add_child(manager)
	var weather := WeatherController.new()
	root.add_child(weather)

	var context := WorldContext.new()
	context.systems = [weather, manager]
	manager.on_world_ready(context)

	_check(
		manager._registered.has(weather),
		"on_world_ready did not adopt a saveable system from the context"
	)
	_check(
		not manager._registered.has(manager),
		"SaveManager registered itself as a save participant"
	)
	_dispose(weather)
	_dispose(manager)


## The systems existed and were tested long before anything drove them. This
## is the check that the composition root now does.
func _test_the_thermal_stack_is_wired_and_follows_the_player() -> void:
	var world := _make_world()
	## world.player is resolved by initialize(), so the scene node is the only
	## handle that exists this early.
	var player: Node3D = world.get_node("Player") as Node3D
	_check(player != null, "the test world has no Player node")
	if player == null:
		_dispose(world)
		return
	var day_night := DayNightManager.new()
	day_night.name = "DayNightManager"
	player.add_child(day_night)
	var bio := BioMonitorManager.new()
	bio.name = "BioMonitorManager"
	player.add_child(bio)
	var equipment := EquipmentComponent.new()
	equipment.layout = load("res://data/equipment/player_layout.tres") as EquipmentLayout
	player.add_child(equipment)
	world.initialize()
	var context: WorldContext = world.get_context()

	var thermal := context.get_system(ThermalManager) as ThermalManager
	var sleep := context.get_system(SleepController) as SleepController
	_check(thermal != null, "ThermalManager is not in the composition root")
	_check(sleep != null, "SleepController is not in the composition root")
	if thermal == null or sleep == null:
		_dispose(world)
		return

	_check(thermal.day_night_manager == day_night, "the thermal model found no clock")
	_check(thermal.equipment == equipment, "the thermal model found no equipment")
	_check(thermal.zone_probe != null, "the thermal model has no zone probe, so no shelter counts")
	_check(sleep.thermal_manager == thermal, "sleeping was not handed the thermal model")
	_check(sleep.bio_monitor == bio, "sleeping was not handed the biomonitor")
	_check(sleep.save_manager != null, "sleeping was not handed the save manager")

	## The model reads the world where Henry stands, not at the origin.
	_check(
		thermal.global_position.is_equal_approx(world.player.global_position),
		"the thermal model sits at %s, the player at %s"
		% [str(thermal.global_position), str(world.player.global_position)]
	)
	world.player.global_position = Vector3(40.0, 2.0, 12.0)
	thermal._process(0.016)
	_check(
		thermal.global_position.is_equal_approx(world.player.global_position),
		"the thermal model did not follow the player"
	)
	_dispose(world)


## TestScene brings its own floor; the island's chunks must not land on it.
func _test_a_scene_with_its_own_floor_streams_nothing() -> void:
	var world := _make_world()
	world.streaming_enabled = false
	world.initialize()
	var streaming := world.get_context().get_system(StreamingSystem) as StreamingSystem
	_check(streaming != null, "the streaming system was not built at all")
	if streaming != null:
		_check(not streaming._initialized, "streaming started in a scene that turned it off")
	var composition_entities: int = World.WORLD_3D_ENTITY_SCENES.size()
	_check(
		world.stream_container.get_child_count() == composition_entities,
		"%d unexpected streaming child(ren) appeared in a scene with its own floor"
		% (world.stream_container.get_child_count() - composition_entities)
	)
	_dispose(world)
