extends SceneTree

## Seated reach (#42): Henry sitting picks the F target by where his head looks
## (towards the view, within the neck limit), up to 2 m, and never walks to it.
## Run: godot --headless --script tests/systems/test_seated_aim.gd

const BODY: String = """extends CharacterBody3D
var view: Vector3 = Vector3.FORWARD
func get_view_direction() -> Vector3:
	return view
"""
const AREA_SCENE: String = "res://scenes/environment/interactive/InteractiveArea.tscn"

var _failures: int = 0
var _frame: int = 0
var _body: CharacterBody3D
var _interact: InteractComponent
var _rest: RestComponent
var _left: InteractiveArea
var _right: InteractiveArea


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		1:
			_build()
		4:
			_interact.detect_target()
			_check(_interact.current_target != _left or not _interact.is_target_in_reach(),
				"standing Henry reaches the target 1.8 m away")
			_rest.sit(_seat())
			_body.set(&"view", Vector3(-1.0, 0.0, -1.0).normalized())
			_interact.detect_target()
			_check(_interact.current_target == _left and _interact.is_target_in_reach(),
				"seated, looking left did not pick the left target in reach")
			_body.set(&"view", Vector3(1.0, 0.0, -0.3).normalized())
			_interact.detect_target()
			_check(_interact.current_target == _right, "seated, looking right did not pick the right target")
			## Looking back-right, the head stops at its limit and still faces right.
			_body.set(&"view", Vector3(0.5, 0.0, 1.0).normalized())
			_interact.detect_target()
			_check(_interact.current_target == _right, "seated, looking back-right did not keep the right target")
			print("test_seated_aim: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
			quit(1 if _failures > 0 else 0)
	return false


func _build() -> void:
	var script := GDScript.new()
	script.source_code = BODY
	script.reload()
	_body = CharacterBody3D.new()
	_body.set_script(script)
	_body.add_to_group(&"player")
	_interact = InteractComponent.new()
	_interact.name = "InteractComponent"
	_body.add_child(_interact)
	_rest = RestComponent.new()
	_rest.name = "RestComponent"
	_body.add_child(_rest)
	root.add_child(_body)
	_left = _area(Vector3(-1.2, 0.0, -1.3))
	_right = _area(Vector3(0.6, 0.0, -0.2))


func _seat() -> Node3D:
	var seat := Node3D.new()
	root.add_child(seat)
	return seat


func _area(at: Vector3) -> InteractiveArea:
	var area := (load(AREA_SCENE) as PackedScene).instantiate() as InteractiveArea
	area.set(&"interactable_scene", null)
	area.interactive_mesh = MeshInstance3D.new()
	area.add_child(area.interactive_mesh)
	area.position = at
	root.add_child(area)
	return area


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
