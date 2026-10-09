extends SceneTree

## Henry's look depth is fast-in, slow-out: an aim ray slipping past a bench edge
## onto the floor for a few ticks barely moves his attention, while a sustained
## look into the distance still gets there. The ray comes from a shoulder camera,
## so depth decides the direction from the head.
## Run: godot --headless --script tests/systems/test_attention_depth.gd

const VISUAL: String = "res://scenes/actors/player/HenryUALVisual.tscn"
const BODY_SOURCE: String = """extends CharacterBody3D
var depth: float = 3.0
func get_view_ray() -> Array:
	## A camera 0.85 m right of and 2 m behind Henry, aiming forward and down.
	var from: Vector3 = global_position + Vector3(0.85, 0.9, 2.0)
	return [from, Vector3(-0.25, -0.35, -1.0).normalized(), depth]
func _physics_process(delta: float) -> void:
	get_node("HenryUALVisual").update_head_look(delta)
"""

var _failures: int = 0
var _body: CharacterBody3D
var _visual: HenryUALAnimation


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var script := GDScript.new()
	script.source_code = BODY_SOURCE
	script.reload()
	_body = CharacterBody3D.new()
	_body.set_script(script)
	_visual = (load(VISUAL) as PackedScene).instantiate() as HenryUALAnimation
	_visual.rotation.y = PI
	_body.add_child(_visual)
	root.add_child(_body)
	await _ticks(60)
	var near: float = _yaw()
	_body.set(&"depth", 6.5)
	await _ticks(3)
	var slipped: float = _yaw()
	_body.set(&"depth", 3.0)
	await _ticks(30)
	## Inside the pickup switch margin, a slip can never swap the dominant pickup.
	var probe := InteractComponent.new()
	var margin: float = probe.switch_margin_deg
	probe.free()
	_check(absf(slipped - near) < margin, "a 3-tick slip past an edge turned attention %.1f°, beyond the %.0f° switch margin" % [absf(slipped - near), margin])
	_check(absf(_yaw() - near) < 0.5, "attention did not settle back on the near point")
	_body.set(&"depth", 6.5)
	await _ticks(180)
	var far: float = _yaw()
	_check(absf(far - near) > 5.0, "a sustained far look never moved attention (%.1f°)" % absf(far - near))
	print("test_attention_depth: near %.1f°, slip %.1f°, far %.1f°" % [near, slipped, far])
	if _failures > 0:
		print("test_attention_depth: %d FAILED" % _failures)
		quit(1)
		return
	print("attention depth: all checks passed")
	quit(0)


func _yaw() -> float:
	return rad_to_deg(Vector3.FORWARD.signed_angle_to(_visual.get_attention_direction(), Vector3.UP))


func _ticks(count: int) -> void:
	for _i: int in range(count):
		await physics_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("attention depth: %s" % message)
