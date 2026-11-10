extends SceneTree

## The searchable furniture of the 727 shelter, in the real shell (kw_727_fort_st.glb) with Henry:
## - each piece (kitchen cupboard, dresser, chest) stands clear of the shell's walls and of the other furniture;
## - opened, each one holding something offers the search; F on it cuts to the working frame, where no mesh of the
##   pack passes into the furniture, the walls or the floor, every item and the pack show, and the pack's opening
##   faces the view; closing stands Henry up. The empty bottom drawer offers nothing.
## Run: godot --headless --path . --fixed-fps 30 --script res://tests/systems/test_727_furniture.gd
## ci-args: --fixed-fps 30

const SHELL: String = "res://assets/world/key_west/landmarks/kw_727_fort_st.glb"
const PLAYER: String = "res://scenes/actors/player/player.tscn"
const CHECKS: GDScript = preload("res://tests/systems/container_search_checks.gd")
## [container key, its ways in, holds something].
const CASES: Array = [
	["KitchenCupboard", ["KitchenCupboard/left", "KitchenCupboard/right"], true],
	["Dresser/top", ["Dresser/top"], true],
	["Dresser/middle", ["Dresser/middle"], true],
	["Dresser/bottom", ["Dresser/bottom"], false],
	["Chest", ["Chest/lid"], true],
]
const STAND_M: float = 0.9

var _failures: int = 0
var _shelter: KeyWest727Shelter
var _player: Player
var _hub: PlayerHubComponent


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_shelter = KeyWest727Shelter.new()
	_shelter.build()
	root.add_child(_shelter)
	var shell := (load(SHELL) as PackedScene).instantiate() as Node3D
	shell.position = _shelter.position
	root.add_child(shell)
	_player = (load(PLAYER) as PackedScene).instantiate() as Player
	root.add_child(_player)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.make_current()
	_hub = _player.get_node(^"PlayerHubComponent") as PlayerHubComponent
	await _frames(10)
	_check(_shelter.furniture_containers.size() == 5, "the shelter built %d furniture containers, not 5" % _shelter.furniture_containers.size())
	for node_name: String in ["KitchenCupboard", "Dresser", "Chest"]:
		_check_stands_clear(node_name)
	for case: Array in CASES:
		await _try(case[0], case[1], case[2])
	if _failures > 0:
		push_error("727 furniture: %d check(s) failed" % _failures)
		quit(1)
		return
	print("727 furniture: all checks passed")
	quit(0)


## The piece touches no other furniture (its solid box against their bodies) and no wall: rays from its middle
## out of its back and sides (the shell's walls are triangle meshes, which a box inside a wall would not touch)
## meet a wall no nearer than its own faces.
func _check_stands_clear(node_name: String) -> void:
	var piece := _shelter.get_node(NodePath("House/" + node_name)) as Node3D
	var solid := piece.get_node(^"Solid") as StaticBody3D
	var shape := solid.get_child(0) as CollisionShape3D
	var box: BoxShape3D = shape.shape as BoxShape3D
	var space: PhysicsDirectSpaceState3D = root.get_viewport().world_3d.direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var smaller := box.duplicate() as BoxShape3D
	smaller.size -= Vector3.ONE * 0.004  # resting on the floor is touching, not passing in
	query.shape = smaller
	query.transform = shape.global_transform
	query.exclude = [solid.get_rid()]
	var names: Array[String] = []
	for hit: Dictionary in space.intersect_shape(query, 8):
		names.append(String((hit["collider"] as Node).name))
	_check(names.is_empty(), "%s passes into %s" % [node_name, ", ".join(names)])
	var gaps: Array[String] = []
	for way: Vector3 in [Vector3.BACK * -1.0, Vector3.RIGHT, Vector3.LEFT]:
		var reach: float = absf((box.size * 0.5).dot(way))
		var from: Vector3 = shape.global_transform.origin
		var ray := PhysicsRayQueryParameters3D.create(from, from + piece.global_basis * way * (reach + 2.0))
		ray.exclude = [solid.get_rid()]
		var hit: Dictionary = space.intersect_ray(ray)
		if hit.is_empty():
			continue
		var gap: float = from.distance_to(hit["position"]) - reach
		gaps.append("%s %.2f m" % [["back", "right", "left"][[Vector3.BACK * -1.0, Vector3.RIGHT, Vector3.LEFT].find(way)], gap])
		_check(gap > -0.001, "%s passes %.3f m into %s" % [node_name, -gap, (hit["collider"] as Node).name])
	print("727 furniture: %s stands clear (furniture: %s; walls: %s)" % [node_name, "none" if names.is_empty() else ", ".join(names), ", ".join(gaps)])


func _try(key: String, ways: Array, full: bool) -> void:
	var shelves: ItemContainer = _shelter.furniture_containers[key]
	var search := shelves.get_node(^"Search") as ContainerSearch
	var face: Array = shelves.front()
	var stand: Vector3 = (face[0] as Vector3) + (face[1] as Vector3) * STAND_M
	stand.y = _shelter.global_position.y + float(_shelter.interior["floor_y"]) + 0.05
	_player.global_position = stand
	_player.velocity = Vector3.ZERO
	_player.face_work_target(face[0])
	await _frames(8)
	_check(not search.can_interact(), "%s: shut, it offers a search" % key)
	await _toggle(ways)
	if not full:
		_check(not search.can_interact(), "%s: empty, it offers a search" % key)
		print("727 furniture: %s empty, nothing offered" % key)
		await _toggle(ways)
		return
	_check(search.can_interact(), "%s: open with something inside, it offers no search" % key)
	search.interact()
	var hands: PackHandling = null
	for _i: int in 150:
		hands = _hub.get_pack_hands()
		if hands != null and hands.enabled:
			break
		await _frames(1)
	_check(hands != null and hands.enabled, "%s: the view never cut to the working frame" % key)
	if hands != null and hands.enabled:
		await _frames(45)
		var failures: Array[String] = CHECKS.frame_failures(key, shelves, hands.camera, root)
		failures.append_array(CHECKS.world_failures(key, shelves, root))
		for failure: String in failures:
			_check(false, failure)
		print("727 furniture: %s searched (%d failures, %d items)" % [key, failures.size(), shelves.items.size()])
	_hub.close()
	await _frames(40)
	_check(not _hub.is_open() and not _player.is_work_crouching(), "%s: closing the pack did not stand Henry up" % key)
	await _toggle(ways)


func _toggle(ways: Array) -> void:
	for way: String in ways:
		(_shelter.furniture_openers[way] as InteractiveArea).interact()
	await _frames(40)


func _frames(count: int) -> void:
	for _i: int in count:
		await process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("727 furniture: %s" % message)
