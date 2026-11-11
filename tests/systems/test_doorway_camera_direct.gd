extends "res://tests/systems/test_doorway_camera.gd"

## The doorway scenarios of test_doorway_camera on the direct rig (the default): no pop past 0.25 m as a jamb
## or lintel cuts the boom, Henry's head in frame, and a released key leaves him where he stands.
## Run: godot --headless --script tests/systems/test_doorway_camera_direct.gd


func _init() -> void:
	_direct = true
