extends SceneTree

## ADT head look on the UAL mannequin: standing, the head follows the camera
## the same amount either way up to its limit; walking, it lets go. Henry's
## attention follows the same clamped look, starts at his head and keeps it walking.
## Run: godot --headless --script tests/systems/test_head_look.gd

const VISUAL: String = "res://scenes/actors/player/HenryUALVisual.tscn"
## A body that reports a view direction and drives the head look each tick.
const BODY_SOURCE: String = """extends CharacterBody3D
var view_direction: Vector3 = Vector3.FORWARD
func get_view_direction() -> Vector3:
	return view_direction
func _physics_process(delta: float) -> void:
	get_node("HenryUALVisual").update_head_look(delta)
"""
const SETTLE_FRAMES: int = 90

var _failures: int = 0
var _frame: int = 0
var _body: CharacterBody3D
var _visual: HenryUALAnimation
var _probe: BoneAttachment3D
var _readings: Dictionary = {}


## Stages step on physics frames, where the modifier runs.
func _physics_process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		1:
			_build()
			_look(45.0)
		SETTLE_FRAMES:
			_readings[&"left45"] = _head_yaw()
			_readings[&"att_left45"] = _attention_yaw()
			_look(-45.0)
		SETTLE_FRAMES * 2:
			_readings[&"right45"] = _head_yaw()
			_readings[&"att_right45"] = _attention_yaw()
			_look(90.0)
		SETTLE_FRAMES * 3:
			_readings[&"left90"] = _head_yaw()
			_readings[&"att_left90"] = _attention_yaw()
			_look(-90.0)
		SETTLE_FRAMES * 4:
			_readings[&"right90"] = _head_yaw()
			_readings[&"att_right90"] = _attention_yaw()
			_body.velocity = Vector3(0.0, 0.0, -3.0)
		SETTLE_FRAMES * 5:
			_readings[&"att_walk"] = _attention_yaw()
			_readings[&"origin_gap"] = _visual.get_attention_origin().distance_to(_probe.global_position)
			_check_and_finish()
	return false


func _build() -> void:
	var script := GDScript.new()
	script.source_code = BODY_SOURCE
	script.reload()
	_body = CharacterBody3D.new()
	_body.set_script(script)
	_visual = (load(VISUAL) as PackedScene).instantiate() as HenryUALAnimation
	_visual.rotation.y = PI
	_body.add_child(_visual)
	root.add_child(_body)
	_probe = BoneAttachment3D.new()
	_probe.bone_name = _visual.head_bone
	_visual.skeleton.add_child(_probe)


## Positive degrees turn the view to Henry's left (he faces -Z).
func _look(degrees: float) -> void:
	_body.set(&"view_direction", Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(degrees)))


func _head_yaw() -> float:
	var forward: Vector3 = _probe.global_transform.basis.z
	forward.y = 0.0
	return rad_to_deg(Vector3.FORWARD.signed_angle_to(forward.normalized(), Vector3.UP))


func _attention_yaw() -> float:
	return rad_to_deg(Vector3.FORWARD.signed_angle_to(_visual.get_attention_direction(), Vector3.UP))


func _check_and_finish() -> void:
	var limit: float = _visual.head_look_primary_limit_deg
	_check(absf(_readings[&"left45"] - 45.0) < 8.0, "head at %.0f for a 45° left look" % _readings[&"left45"])
	_check(absf(_readings[&"right45"] + 45.0) < 8.0, "head at %.0f for a 45° right look" % _readings[&"right45"])
	_check(absf(_readings[&"left90"] - limit) < 8.0, "left limit %.0f, want %.0f" % [_readings[&"left90"], limit])
	_check(absf(_readings[&"right90"] + limit) < 8.0, "right limit %.0f, want %.0f" % [_readings[&"right90"], -limit])
	_check(_visual._head_influence < 0.01, "the head look did not let go while walking")
	_check(absf(_readings[&"att_left45"] - 45.0) < 2.0, "attention at %.1f for a 45° left look" % _readings[&"att_left45"])
	_check(absf(_readings[&"att_right45"] + 45.0) < 2.0, "attention at %.1f for a 45° right look" % _readings[&"att_right45"])
	_check(absf(_readings[&"att_left90"] - limit) < 2.0, "attention left limit %.1f, want %.0f" % [_readings[&"att_left90"], limit])
	_check(absf(_readings[&"att_right90"] + limit) < 2.0, "attention right limit %.1f, want %.0f" % [_readings[&"att_right90"], -limit])
	_check(absf(_readings[&"att_walk"] + limit) < 2.0, "walking collapsed attention to the torso (%.1f)" % _readings[&"att_walk"])
	_check(_readings[&"origin_gap"] < 0.08, "attention origin %.2f m from the head bone" % _readings[&"origin_gap"])
	if _failures > 0:
		push_error("head look: %d check(s) failed" % _failures)
		quit(1)
		return
	print("head look: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("head look: %s" % message)
