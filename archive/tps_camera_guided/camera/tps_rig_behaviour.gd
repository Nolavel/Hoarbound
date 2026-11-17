class_name TpsRigBehaviour
extends RefCounted

## One behaviour of the TPS rig: it owns its own state and smoothing and works on a
## TpsRigFrame in the order TpsCamera runs them. Tunables stay on the camera (inspector).

var rig: TpsCamera


func _init(camera: TpsCamera) -> void:
	rig = camera


## Drops the behaviour's follow memory, as TpsCamera.snap_to_target does for the rig.
func reset() -> void:
	pass
