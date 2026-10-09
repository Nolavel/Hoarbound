extends SceneTree

## Seated reach (#42): sitting Henry acts on what the player's view is on, up to 2 m,
## and never walks to it. F acts on that thing; with nothing in reach F opens Wait.
## Run: godot --headless --script tests/systems/test_seated_aim.gd

const AREA_SCENE: String = "res://scenes/environment/interactive/InteractiveArea.tscn"
## A seated-table thing (food, a stove ring) that counts its uses.
const THING_SOURCE: String = """extends InteractiveArea
var uses: int = 0
func _on_interaction_performed() -> void:
	uses += 1
"""

var _failures: int = 0
var _body: CharacterBody3D
var _interact: InteractComponent
var _rest: RestComponent
var _camera: Camera3D
var _left: InteractiveArea
var _right: InteractiveArea


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_build()
	await _frames(2)
	_aim(_left)
	await _frames(2)
	_check(not _interact.is_active_target_in_reach(), "standing Henry reaches the target 1.8 m away")
	_rest.sit(_seat())
	await _frames(2)
	_check(_interact.get_active_target() == _left and _interact.is_active_target_in_reach(),
		"seated, viewing left did not pick the left target in reach")
	_check(_rest._reachable_target() == _left, "seated, Wait would steal F from the food in reach")
	_press(&"interact")
	await _frames(1)
	_check((_left.get("uses") as int) == 1, "seated F did not act on the food in front of Henry")
	_check(_rest.is_sitting(), "seated F on the food stood Henry up")
	_aim(_right)
	await _frames(2)
	_check(_interact.get_active_target() == _right, "seated, viewing right did not pick the right target")
	## The view on empty space: nothing is in reach, so F belongs to Wait.
	_camera.look_at(_camera.global_position + Vector3(0.0, 0.6, 1.0), Vector3.UP)
	await _frames(12)
	_check(_interact.get_active_target() == null and _rest._reachable_target() == null,
		"seated, an empty view still offered a target")
	var used: int = (_left.get("uses") as int) + (_right.get("uses") as int)
	_press(&"interact")
	await _frames(1)
	_check((_left.get("uses") as int) + (_right.get("uses") as int) == used, "seated F with nothing in reach acted on a target")
	print("test_seated_aim: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _build() -> void:
	_body = CharacterBody3D.new()
	_body.add_to_group(&"player")
	_interact = InteractComponent.new()
	_interact.name = "InteractComponent"
	_body.add_child(_interact)
	_rest = RestComponent.new()
	_rest.name = "RestComponent"
	_body.add_child(_rest)
	root.add_child(_body)
	_camera = Camera3D.new()
	_camera.current = true
	root.add_child(_camera)
	_camera.global_position = Vector3(0.0, 0.62, 0.0)
	_left = _area(Vector3(-1.2, 0.0, -1.3))
	_right = _area(Vector3(0.6, 0.0, -0.2))


func _aim(area: InteractiveArea) -> void:
	_camera.look_at(area.get_focus_point(_body.global_position), Vector3.UP)


func _seat() -> Node3D:
	var seat := Node3D.new()
	root.add_child(seat)
	return seat


func _area(at: Vector3) -> InteractiveArea:
	var script := GDScript.new()
	script.source_code = THING_SOURCE
	script.reload()
	var area := (load(AREA_SCENE) as PackedScene).instantiate() as InteractiveArea
	area.set_script(script)
	area.set(&"interactable_scene", null)
	area.interactive_mesh = MeshInstance3D.new()
	area.add_child(area.interactive_mesh)
	area.position = at
	root.add_child(area)
	return area


func _press(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	root.push_input(event)
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	root.push_input(event)


func _frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
