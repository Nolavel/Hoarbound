extends SceneTree

## The 727's open furniture through F as a player meets it (#42 record 03), with Henry's own TPS camera:
## - the view on the open shelves makes F search them, not shut the leaf beside them;
## - the view on an open leaf still makes F shut it.
## Run: godot --headless --path . --fixed-fps 30 --script res://tests/systems/test_open_container_focus.gd
## ci-args: --fixed-fps 30

const SHELL: String = "res://assets/world/key_west/landmarks/kw_727_fort_st.glb"
const PLAYER: String = "res://scenes/actors/player/player.tscn"
const CAMERA: String = "res://scenes/game/systems/camera/tps_camera.tscn"
## [container key, its ways in]; each holds something.
const CASES: Array = [
	["KitchenCupboard", ["KitchenCupboard/left", "KitchenCupboard/right"]],
	["Dresser/top", ["Dresser/top"]],
	["Dresser/middle", ["Dresser/middle"]],
	["Chest", ["Chest/lid"]],
]
const STAND_M: float = 0.8

var _failures: int = 0
var _shelter: KeyWest727Shelter
var _player: Player
var _camera: TpsCamera
var _interact: InteractComponent


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
	_camera = (load(CAMERA) as PackedScene).instantiate() as TpsCamera
	_camera.player = _player
	root.add_child(_camera)
	_camera.make_current()
	_interact = _player.get_node(^"InteractComponent") as InteractComponent
	await _frames(10)
	for case: Array in CASES:
		await _try(case[0], case[1])
	if _failures > 0:
		push_error("open container focus: %d check(s) failed" % _failures)
		quit(1)
		return
	print("open container focus: all checks passed")
	quit(0)


func _try(key: String, ways: Array) -> void:
	var shelves: ItemContainer = _shelter.furniture_containers[key]
	var search := shelves.get_node(^"Search") as ContainerSearch
	var face: Array = shelves.front()
	var stand: Vector3 = (face[0] as Vector3) + (face[1] as Vector3) * STAND_M
	stand.y = _shelter.global_position.y + float(_shelter.interior["floor_y"]) + 0.05
	_player.global_position = stand
	_player.velocity = Vector3.ZERO
	_player.face_work_target(face[0])
	for way: String in ways:
		(_shelter.furniture_openers[way] as InteractiveArea).interact()
	await _frames(40)
	_check(search.can_interact(), "%s: open, it offers no search" % key)
	await _aim_at(search.get_focus_point(_camera.global_position))
	var target: InteractiveArea = _interact.get_active_target()
	_check(target == search, "%s: the view on its open shelves makes F act on %s, not the search" % [key, _name(target)])
	print("open container focus: %s, view on the shelves -> F on %s" % [key, _name(target)])
	for way: String in ways:
		var leaf := _shelter.furniture_openers[way] as Opener
		await _aim_at(leaf.get_focus_point(_camera.global_position))
		target = _interact.get_active_target()
		_check(target is Opener and shelves.all_openers().has(target), "%s: the view on its open leaf %s makes F act on %s, not shut it"
			% [key, way, _name(target)])
		print("open container focus: %s, view on the leaf %s -> F on %s" % [key, way, _name(target)])
	for way: String in ways:
		(_shelter.furniture_openers[way] as InteractiveArea).interact()
	await _frames(40)


## Turns Henry's camera until its aim runs through `point` (the aim origin moves with the view, so twice).
func _aim_at(point: Vector3) -> void:
	var yaw: float = 0.0
	var pitch: float = 0.0
	for k: int in 12:
		var camera: Camera3D = _camera.get_viewport().get_camera_3d()
		var look: Vector3 = (point - TpsCamera.aim_origin(camera)).normalized()
		var aim: Vector3 = TpsCamera.aim_direction(camera)
		if k == 0:
			yaw = atan2(-look.x, -look.z)
			pitch = rad_to_deg(asin(look.y))
		else:
			yaw += wrapf(atan2(-look.x, -look.z) - atan2(-aim.x, -aim.z), -PI, PI)
			pitch += rad_to_deg(asin(look.y) - asin(aim.y))
		_camera.set_look(yaw, pitch)
		_camera.snap_to_target()
		await _frames(4)
	_interact.detect_target(0.0)


func _name(area: InteractiveArea) -> String:
	return String(area.name) if area != null else "nothing"


func _frames(count: int) -> void:
	for _i: int in count:
		await process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("open container focus: %s" % message)
