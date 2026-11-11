extends "res://tests/systems/test_doorway_camera.gd"

## The doorway scenarios of test_doorway_camera on the direct rig (the default): no frame step past 0.35 m as
## a jamb or lintel cuts the boom, Henry's head in frame, and a released key leaves him where he stands.
## Fixed frames: the steps it measures sit near their limit and must not depend on the runner's speed.
## ci-args: --fixed-fps 60
## Run: godot --headless --fixed-fps 60 --script tests/systems/test_doorway_camera_direct.gd


func _init() -> void:
	_direct = true
