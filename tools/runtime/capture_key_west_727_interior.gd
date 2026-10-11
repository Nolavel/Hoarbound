extends SceneTree

## Captures the 727 Fort St shelter inside the real Key West Reality game scene: approach, a
## roofless cutaway of the furnished plan, room interiors and Henry by the stove (game camera).
## Run: xvfb-run godot --path . --rendering-driver vulkan --script res://tools/runtime/capture_key_west_727_interior.gd -- [out_dir]

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
const WARMUP_FRAMES: int = 240
const SETTLE_FRAMES: int = 12
## [name, eye (u, y above floor, v), target (u, y, v)] in the shelter's plan frame.
const SHOTS: Array = [
	["approach_fort_st", Vector3(9.5, 1.7, 17.0), Vector3(6.2, 1.6, 3.1)],
	["porch_door", Vector3(6.6, 1.6, 7.6), Vector3(6.2, 1.2, 3.1)],
	["cutaway_plan", Vector3(0.6, 30.0, 1.5), Vector3(0.5, 0.0, 1.4)],
	["cutaway_oblique", Vector3(-14.0, 17.0, 17.0), Vector3(1.0, 0.0, 0.5)],
	["lobby_from_door", Vector3(6.2, 1.6, 2.4), Vector3(1.0, 1.0, 1.4)],
	["waiting_stove", Vector3(-4.8, 1.7, 9.4), Vector3(-1.2, 0.6, 6.4)],
	["waiting_to_lobby", Vector3(-4.6, 1.7, 3.0), Vector3(3.5, 1.2, 1.6)],
	["corridor", Vector3(-12.3, 1.6, -0.7), Vector3(13.0, 1.4, -0.7)],
	["exam_room", Vector3(-6.4, 1.7, -2.1), Vector3(-4.5, 0.6, -5.6)],
	["dental", Vector3(-7.6, 1.7, -2.2), Vector3(-10.2, 0.6, -5.0)],
	["storage_benches", Vector3(9.0, 1.7, -2.1), Vector3(11.5, 0.6, -5.0)],
]
## Henry stands in the waiting room facing the stove for the game-camera shot.
const HENRY_UV: Vector2 = Vector2(1.3, 8.6)

var _out: String = "user://shots/key_west_727"
var _world: Node3D
var _house: Node3D
var _floor_y: float = 0.15
var _camera: Camera3D
var _frame: int = 0
var _shot: int = -1
var _wait: int = 0
var _hidden: Array[Node3D] = []


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out) if _out.begins_with("user://") else _out)
	_world = (load(SCENE) as PackedScene).instantiate() as Node3D
	_world.set(&"spawn_at_shelter", true)
	root.add_child(_world)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < WARMUP_FRAMES:
		return false
	if _house == null:
		var shelter: KeyWest727Shelter = _world.find_child("Shelter727", true, false) as KeyWest727Shelter
		if shelter == null:
			push_error("727 capture: Shelter727 is not in the scene")
			quit(1)
			return true
		_house = shelter.get_node(^"House") as Node3D
		_floor_y = float(shelter.interior["floor_y"])
		_camera = Camera3D.new()
		_camera.fov = 70.0
		_camera.near = 0.05
		_camera.far = 2000.0
		root.add_child(_camera)
	if _wait > 0:
		_wait -= 1
		return false
	if _shot >= 0:
		_save(String(SHOTS[_shot][0]) if _shot < SHOTS.size() else "henry_by_stove_game_camera")
	_shot += 1
	if _shot > SHOTS.size():
		print("727 capture: done -> ", _out)
		quit(0)
		return true
	if _shot == SHOTS.size():
		_henry_shot()
	else:
		_free_shot(SHOTS[_shot])
	_wait = SETTLE_FRAMES if _shot < SHOTS.size() else 90
	return false


func _free_shot(shot: Array) -> void:
	_set_cutaway(String(shot[0]).begins_with("cutaway"))
	_camera.make_current()
	_camera.look_at_from_position(_plan(shot[1]), _plan(shot[2]))


## Henry inside, the real TPS camera behind him.
func _henry_shot() -> void:
	_set_cutaway(false)
	var player: Node3D = _world.get(&"player") as Node3D
	var game_camera: Camera3D = (_world.get(&"camera") as Node).find_child("*", true, false) as Camera3D if _world.get(&"camera") is Node else null
	if player == null:
		return
	var stove: Vector3 = _plan(Vector3(-1.2, 0.0, 6.4))
	player.global_position = _plan(Vector3(HENRY_UV.x, 0.05, HENRY_UV.y))
	player.look_at(Vector3(stove.x, player.global_position.y, stove.z), Vector3.UP)
	if _world.get(&"camera") is Camera3D:
		(_world.get(&"camera") as Camera3D).make_current()
	elif game_camera != null:
		game_camera.make_current()


## Plan point (u, height above the floor, v) in world space.
func _plan(p: Vector3) -> Vector3:
	return _house.global_transform * Vector3(p.x, _floor_y + p.y, p.z)


## Hides the shell's roof and ceiling (and the stove pipe) so the furnished plan shows from above.
func _set_cutaway(on: bool) -> void:
	if on and _hidden.is_empty():
		var centre: Vector3 = _house.global_position
		for node: Node in root.find_children("*", "Node3D", true, false):
			var n3: Node3D = node as Node3D
			if n3.name in [&"Roof", &"Ceiling", &"StovePipe"] and n3.global_position.distance_to(centre) < 40.0 and n3.visible:
				n3.visible = false
				_hidden.append(n3)
	elif not on:
		for n3: Node3D in _hidden:
			n3.visible = true
		_hidden.clear()


func _save(shot_name: String) -> void:
	var path: String = _out.path_join(shot_name + ".png")
	root.get_viewport().get_texture().get_image().save_png(path)
	print("727 capture: ", path)
