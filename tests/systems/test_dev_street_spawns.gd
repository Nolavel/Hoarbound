extends SceneTree

## Dev street spawns: World.dev_spawn_street lists the ten streets of dev_street_spawns.json, each point lies on land
## outside every building outline of its generated chunk, and a chosen street holds Henry there until the ground is live.
## Run: godot --headless --script tests/systems/test_dev_street_spawns.gd

const CHUNK_SCENE: String = "res://scenes/world/key_west/generated/chunks/Chunk_%d_%d.scn"
const CHUNK_M: float = 512.0
const STREET_COUNT: int = 10

var _failures: int = 0


func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	var world: World = World.new()
	var names: PackedStringArray = world.dev_street_names()
	_check(names.size() == STREET_COUNT + 1 and names[0] == "Scenario spawn", "dropdown is not scenario + %d streets: %s" % [STREET_COUNT, names])
	_check(world.dev_spawn().is_empty(), "the default entry is not the scenario spawn")
	var areas: Dictionary = {}
	for i: int in range(1, names.size()):
		world.dev_spawn_street = i
		var street: Dictionary = world.dev_spawn()
		_check(street.get("name", "") == names[i], "%s has no entry in the spawn file" % names[i])
		if street.is_empty():
			continue
		areas[street["area"]] = true
		_check_open_land(street)
	_check(areas.size() == STREET_COUNT, "streets share areas; want ten parts of the island: %s" % [areas.keys()])
	_check_hold(world)
	world.free()
	if _failures > 0:
		push_error("dev street spawns: %d check(s) failed" % _failures)
		quit(1)
		return
	print("dev street spawns: all checks passed")
	quit(0)


## The point's own chunk answers live ground above sea level there, and no building outline covers it.
func _check_open_land(street: Dictionary) -> void:
	var at: Vector2 = street["at"]
	var key: Vector2i = Vector2i(floori(at.x / CHUNK_M), floori(at.y / CHUNK_M))
	var path: String = CHUNK_SCENE % [key.x, key.y]
	if not ResourceLoader.exists(path):
		_check(false, "%s: chunk %s is not generated" % [street["name"], key])
		return
	var chunk: Node3D = (load(path) as PackedScene).instantiate()
	root.add_child(chunk)
	var centre: Array = chunk.get_meta("centre_local")
	chunk.global_position = Vector3(float(centre[0]), 0.0, float(centre[1]))  # as the streamer places it
	var ground: KeyWestRealityGround = KeyWestRealityGround.new()
	root.add_child(ground)
	ground._index(chunk)
	_check(ground.has_ground_at(at.x, at.y), "%s: no ground at %s" % [street["name"], at])
	_check(ground.get_height(at.x, at.y) > 0.0, "%s: %s is under sea level (%.2f m)" % [street["name"], at, ground.get_height(at.x, at.y)])
	_check(not ground.has_snow_obstacle_at(at), "%s: %s is inside a building" % [street["name"], at])
	ground.free()
	chunk.free()


## With a street chosen, the waypoints move Henry onto it at once and hold him with his physics off until ground is live.
func _check_hold(world: World) -> void:
	world.dev_spawn_street = 2
	var player: CharacterBody3D = CharacterBody3D.new()
	root.add_child(player)
	var waypoints: KeyWestDevWaypoints = KeyWestDevWaypoints.new()
	root.add_child(waypoints)
	var context: WorldContext = WorldContext.new()
	context.player = player
	context.world = world
	waypoints.on_world_ready(context)
	var at: Vector2 = world.dev_spawn()["at"]
	_check(Vector2(player.global_position.x, player.global_position.z).distance_to(at) < 0.01, "Henry was not moved to %s" % world.dev_spawn()["name"])
	_check(waypoints.is_teleporting() and not player.is_physics_processing(), "Henry is not held while the street's ground is missing")
	waypoints.free()
	player.free()


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
