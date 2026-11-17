class_name StickLook
extends RefCounted

## Turns a raw look stick into an angular speed: a radial dead zone, a power curve for fine aim near
## the centre, and a ramp of extra turn speed while the stick is held at its rim.

## Stick travel ignored round the centre and at the rim, as shares of full travel.
var dead_zone: float = 0.15
var outer_zone: float = 0.95
## Response curve: speed share = travel ^ exponent. 1 is linear; 2 gives fine aim.
var exponent: float = 2.0
## Full-deflection turn speeds, degrees per second.
var yaw_speed_deg: float = 200.0
var pitch_speed_deg: float = 120.0
## Held past rim_share for ramp_delay seconds, the turn gains up to ramp_boost more over ramp_time.
var rim_share: float = 0.92
var ramp_delay: float = 0.2
var ramp_time: float = 0.5
var ramp_boost: float = 0.6

var _held: float = 0.0


## Angular speed for `raw` (x right, y down, each -1..1), radians per second.
func update(raw: Vector2, delta: float) -> Vector2:
	var travel: float = shaped_travel(raw.length())
	if travel <= 0.0:
		_held = 0.0
		return Vector2.ZERO
	_held = _held + delta if travel >= rim_share else 0.0
	var boost: float = 1.0 + ramp_boost * clampf((_held - ramp_delay) / maxf(ramp_time, 0.001), 0.0, 1.0)
	var share: Vector2 = raw.normalized() * pow(travel, exponent) * boost
	return Vector2(share.x * deg_to_rad(yaw_speed_deg), share.y * deg_to_rad(pitch_speed_deg))


## Stick travel with both dead zones taken out, 0..1.
func shaped_travel(length: float) -> float:
	return clampf(inverse_lerp(dead_zone, outer_zone, length), 0.0, 1.0)


func reset() -> void:
	_held = 0.0
