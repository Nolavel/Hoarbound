class_name TpsPassageFraming
extends RefCounted

## Doorway composition from the passage's real size, as pure geometry: how far the
## frame closes, and the cone the camera body may orbit in so its boom stays in the opening.

## Camera sphere radius plus the gap kept from surfaces, metres.
var clearance: float = 0.3
## Henry's capsule radius, for how close he is to the wall face.
var body_radius: float = 0.5
## The camera starts closing in over this much space before the frame is reached.
var ramp: float = 0.5
var info: PassageInfo
## Unit horizontal across the door plane toward the camera's side.
var back_axis: Vector3 = Vector3.BACK

var _side: float = 0.0


## Takes the passage Henry is engaged with. A new one keeps the camera's side when it faces
## the same way (doors along one corridor wall), else picks its side afresh.
func set_passage(passage: PassageInfo) -> void:
	if info == null or not passage.same_passage(info):
		var along: float = back_axis.dot(passage.axis) if info != null else 0.0
		_side = signf(along) if absf(along) > 0.7 else 0.0
	info = passage


func has_passage() -> bool:
	return info != null


func clear() -> void:
	info = null
	_side = 0.0


## Puts the camera's side of the door plane where the view's boom points; it changes
## only once the view clearly turns, and never while `locked` (Henry inside the doorway).
func update_side(view_back: Vector3, locked: bool = false) -> void:
	var along: float = view_back.dot(info.axis)
	if _side == 0.0 or (absf(along) > 0.2 and not locked):
		_side = 1.0 if along >= 0.0 else -1.0
	back_axis = info.axis * _side


## View yaw whose boom runs straight along the passage axis.
func axis_yaw() -> float:
	return atan2(back_axis.x, back_axis.z)


## Unit horizontal a positive orbit turn swings the boom toward: the camera's right.
func right() -> Vector3:
	return Vector3.UP.cross(back_axis).normalized()


## Half the opening the camera centre may use either side of the centre line.
func band() -> float:
	return maxf(info.clear_width * 0.5 - clearance, 0.0)


## Highest a camera centre may pass under the lintel, world Y.
func top_y() -> float:
	return info.center.y + info.clear_height - clearance


## Lateral offset of a point from the centre line, positive to the camera's right.
func lateral(point: Vector3) -> float:
	return Vector3(point.x - info.center.x, 0.0, point.z - info.center.z).dot(right())


## How closed the frame should be: 1 while Henry or the boom to the camera is in the
## frame, falling to 0 over `approach` metres of space between them and the wall.
## Before Henry engages, only a boom running along the passage into its opening counts.
func goal(feet: Vector3, view_back: Vector3, boom_h: float, approach: float, engaged: bool) -> float:
	var face: float = info.half_depth()
	var henry: float = _u(feet)
	var camera: float = henry + boom_h
	var gap: float = 0.0
	if henry > face:
		if not engaged:
			return 0.0
		gap = henry - face - body_radius
	else:
		if not engaged:
			var lat: float = lateral(feet) + view_back.dot(right()) * boom_h
			if absf(view_back.dot(info.axis)) < 0.5 or absf(lat) > info.clear_width * 0.5:
				return 0.0
		if camera < -face:
			gap = -face - camera - clearance
	return 1.0 - smoothstep(0.05, maxf(approach, 0.1), gap)


## Largest orbit turns off the axis, radians (x toward the left, y toward the right),
## that keep a boom of horizontal length `boom_h` from `shoulder` inside the opening.
func yaw_limits(shoulder: Vector3, boom_h: float) -> Vector2:
	var reach: float = _reach(shoulder, boom_h)
	if reach <= 0.0:
		return Vector2(PI, PI)
	var depth: float = _depth(shoulder)
	var lat: float = lateral(shoulder)
	var left: float = _limit(band() + lat, depth, boom_h)
	var right_limit: float = _limit(band() - lat, depth, boom_h)
	return Vector2(lerpf(PI, left, reach), lerpf(PI, right_limit, reach))


## Largest orbit elevation and depression, degrees, that keep a boom of length `boom`
## from `shoulder` under the lintel and over the floor; `yaw_off` is the orbit's turn.
func pitch_limits(shoulder: Vector3, boom: float, yaw_off: float) -> Vector2:
	var reach: float = _reach(shoulder, boom)
	if reach <= 0.0:
		return Vector2(90.0, 90.0)
	var depth: float = _depth(shoulder) / maxf(cos(yaw_off), 0.2)
	var up: float = rad_to_deg(_limit(top_y() - shoulder.y, depth, boom))
	var down: float = rad_to_deg(_limit(shoulder.y - info.center.y - clearance, depth, boom))
	return Vector2(lerpf(90.0, up, reach), lerpf(90.0, down, reach))


## 0 while the boom stops short of the frame, rising to 1 as its tip reaches it, so the
## cone closes in over `ramp` metres instead of in one frame.
func _reach(shoulder: Vector3, boom_h: float) -> float:
	var face: float = info.half_depth() + clearance
	var at: float = _u(shoulder)
	if at >= face:
		return 0.0
	var entry: float = maxf(-face - at, 0.0)
	return clampf((boom_h - entry + ramp) / ramp, 0.0, 1.0)


## Run from the shoulder to the far face of the frame along the axis, metres.
func _depth(shoulder: Vector3) -> float:
	return maxf(info.half_depth() + clearance - _u(shoulder), 0.01)


func _u(point: Vector3) -> float:
	return Vector3(point.x - info.center.x, 0.0, point.z - info.center.z).dot(back_axis)


## Largest angle off the axis at which a boom keeps within `room` of its start sideways:
## through the far face at `depth`, or, if shorter, at its tip `length`.
static func _limit(room: float, depth: float, length: float) -> float:
	if room <= 0.0:
		return 0.0
	return maxf(atan2(room, depth), asin(clampf(room / maxf(length, 0.01), 0.0, 1.0)))
