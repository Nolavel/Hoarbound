class_name TpsAutoLook
extends RefCounted

## Camera turns the player did not make, as targets for the view offset over the
## control yaw: WASD never follows them. All wait for the mouse to rest.

## Seconds the mouse must rest before any automatic turn starts.
var cooldown: float = 0.9
var recenter_enabled: bool = true
## Heading offsets beyond this are left alone: Henry walks at the camera.
var recenter_max_angle_deg: float = 110.0
## Largest view swing away from a wall at the boom's side, degrees.
var whisker_max_deg: float = 30.0
## How fast the view glides to an angle with room, degrees per second.
var room_rate_deg: float = 120.0

var _idle: float = 0.0


## Feeds this frame's mouse travel; any travel restarts the cooldown.
func note_look(look: Vector2, delta: float) -> void:
	if look.length_squared() > 1e-12:
		_idle = 0.0
	else:
		_idle += delta


func is_active() -> bool:
	return _idle >= cooldown


func get_idle_time() -> float:
	return _idle


## View offset that puts the camera behind a walk Henry is not steered through
## (an F approach). Any movement key means the player steers: no offset then.
func recenter_offset(control_to_heading: float, move_axis: Vector2) -> float:
	if not recenter_enabled or move_axis.length_squared() > 0.01:
		return 0.0
	if absf(control_to_heading) > deg_to_rad(recenter_max_angle_deg):
		return 0.0
	return control_to_heading


## View offset toward the side whose whiskers see more room; rooms are 0..1 for
## booms swung to lower and to higher yaw.
func whisker_offset(lower_room: float, higher_room: float) -> float:
	var push: float = higher_room - lower_room
	if absf(push) < 0.15:
		return 0.0
	return signf(push) * deg_to_rad(whisker_max_deg) * minf(absf(push), 1.0)
