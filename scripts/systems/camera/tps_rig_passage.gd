class_name TpsRigPassage
extends TpsRigBehaviour

## Doorways: the frame closes round Henry before he reaches one, the camera body orbits in a
## cone through it, and the view eases into soft stops while he traverses it.

## Henry's doorway traversal, read for the frame; looked up once after his _ready.
var _passage: PassageTraversalComponent
var _passage_looked_up: bool = false
var _passage_blend: float = 0.0
var _framing := TpsPassageFraming.new()
## Orbit cone of the camera body in a passage: left and right turn off the axis
## (radians), elevation and depression (degrees). Closes at once, opens softly.
var _cone := Vector4(PI, PI, 90.0, 90.0)


func reset() -> void:
	_cone = Vector4(PI, PI, 90.0, 90.0)


## 0 away from doorways, 1 with the frame fully closed round Henry in one.
func get_blend() -> float:
	return _passage_blend


func get_framing() -> TpsPassageFraming:
	return _framing


## Doorways recompose the frame round Henry before he reaches them: the blend rises
## while he or the boom behind him nears the frame, and falls softly once both are clear.
func update(delta: float) -> void:
	if not _passage_looked_up:
		_passage_looked_up = true
		_passage = rig.player.get_node_or_null(^"PassageTraversalComponent") as PassageTraversalComponent
	var passage: PassageInfo = _passage.get_nearby_passage() if _passage != null else null
	if passage != null:
		_framing.set_passage(passage)
	var goal: float = 0.0
	if _framing.has_passage():
		_framing.clearance = rig.collision_radius + rig.collision_surface_margin
		_framing.body_radius = rig.get_capsule_radius()
		_framing.update_side(TpsCamera.back_dir(rig.get_view_yaw(), 0.0))
	if passage != null:
		var view_back: Vector3 = TpsCamera.back_dir(rig.get_view_yaw(), 0.0)
		var off: float = minf(absf(angle_difference(_framing.axis_yaw(), rig.get_view_yaw())), PI / 3.0)
		## The boom the frame will have, not the one it has, so the blend never feeds itself.
		var boom_h: float = boom() * cos(deg_to_rad(rig.get_view_pitch_deg())) * cos(off)
		var speed: float = Vector2(rig.player.velocity.x, rig.player.velocity.z).length()
		var approach: float = (rig.passage_approach + speed * rig.passage_lead_time) * (1.0 + rig.passage_angle_lead * (1.0 - cos(off)))
		goal = _framing.goal(rig.get_feet_position(), view_back, boom_h, approach, _passage.get_passage() != null)
	var rate: float = rig.passage_compress_rate if goal > _passage_blend else rig.passage_release_rate
	_passage_blend = goal if not rig.is_placed() else lerpf(_passage_blend, goal, TpsCamera.damp(rate, delta))
	if passage == null and _passage_blend <= 0.001:
		_passage_blend = 0.0
		_framing.clear()


## In a doorway: shortens the boom, slides the shoulder into the opening, soft-stops the view
## off the axis and keeps the camera body inside the orbit cone. Sets the orbit either way.
func orbit(frame: TpsRigFrame) -> void:
	frame.orbit_yaw = frame.view_yaw
	frame.orbit_pitch = frame.view_pitch
	if not (_framing.has_passage() and _passage_blend > 0.001):
		_cone = Vector4(PI, PI, 90.0, 90.0)
		return
	var blend: float = _passage_blend
	frame.want = lerpf(frame.want, minf(frame.want, boom()), blend)
	frame.side = lerpf(frame.side, _side(frame.pivot, frame.side), blend)
	var axis_yaw: float = _framing.axis_yaw()
	var limits: Vector2 = view_yaw_limits()
	var off: float = angle_difference(axis_yaw, frame.view_yaw)
	var look_blend: float = blend * traversal()
	frame.view_yaw = wrapf(axis_yaw + lerpf(off, clampf(off, -limits.x, limits.y), look_blend), -PI, PI)
	var pitch_range: Vector2 = pitch_range()
	frame.view_pitch = lerpf(frame.view_pitch, clampf(frame.view_pitch, pitch_range.x, pitch_range.y), look_blend)
	_update_cone(frame.delta, frame.pivot + _framing.right() * frame.side, frame.want, frame.view_yaw, frame.view_pitch)
	off = angle_difference(axis_yaw, frame.view_yaw)
	frame.orbit_yaw = wrapf(axis_yaw + lerpf(off, clampf(off, -_cone.x, _cone.y), blend), -PI, PI)
	frame.orbit_pitch = lerpf(frame.view_pitch, clampf(frame.view_pitch, -_cone.z, _cone.w), blend)


## 1 while Henry is in a doorway or walking at it, 0 while he stands beside one: only a
## traversal may soft-stop the mouse (Nesky, GDC 2014: honour the player's intent).
func traversal() -> float:
	if _passage != null and _passage.get_passage() != null:
		return 1.0
	return smoothstep(0.2, 1.0, Vector2(rig.player.velocity.x, rig.player.velocity.z).length())


## Boom through the doorway: authored, or passage_boom less any wall depth past the reference.
func boom() -> float:
	var info: PassageInfo = _framing.info
	if info == null:
		return rig.passage_boom
	if info.camera_distance > 0.0:
		return info.camera_distance
	return maxf(rig.passage_boom - maxf(info.wall_thickness - rig.passage_reference_wall, 0.0), rig.passage_boom_min)


## Pivot lift in a doorway: passage_rise, or half the room left under the lintel if less.
func rise() -> float:
	if not _framing.has_passage():
		return 0.0
	var room: float = _framing.top_y() - (rig.get_feet_position().y + rig.get_pivot_height())
	return clampf(room * 0.5, 0.0, rig.passage_rise)


func fov() -> float:
	var info: PassageInfo = _framing.info
	return info.fov_offset_deg if info != null and info.fov_offset_deg >= 0.0 else rig.passage_fov_deg


## Soft stops of the view off the passage axis, radians (left, right): past the orbit
## cone only as far as Henry stays inside the frame, or an authored limit if tighter.
func view_yaw_limits() -> Vector2:
	var past: float = deg_to_rad(maxf(rig.half_fov_deg(true) - rig.passage_look_margin_deg, 0.0))
	var limits := Vector2(_cone.x + past, _cone.y + past)
	var info: PassageInfo = _framing.info
	if info != null and info.yaw_limit_deg > 0.0:
		var authored: float = deg_to_rad(info.yaw_limit_deg)
		limits = Vector2(minf(limits.x, authored), minf(limits.y, authored))
	return limits


## Soft range of the view pitch in a doorway, degrees: past the orbit cone only as far
## as Henry stays inside the frame.
func pitch_range() -> Vector2:
	var past: float = maxf(rig.half_fov_deg(false) - rig.passage_look_margin_deg, 0.0)
	return Vector2(-(_cone.z + past), _cone.w + past)


## The cone the camera body may orbit in at this pass of the doorway: it closes at once
## as Henry walks into it and opens at the release rate, so a cone never snaps open.
func _update_cone(delta: float, shoulder: Vector3, want: float, view_yaw: float, view_pitch: float) -> void:
	var yaw: Vector2 = _framing.yaw_limits(shoulder, want * cos(deg_to_rad(view_pitch)))
	var off: float = clampf(angle_difference(_framing.axis_yaw(), view_yaw), -yaw.x, yaw.y)
	var pitch: Vector2 = _framing.pitch_limits(shoulder, want, off)
	var goal := Vector4(yaw.x, yaw.y, pitch.x, pitch.y)
	var opening: float = TpsCamera.damp(rig.passage_release_rate, delta)
	for i: int in range(4):
		_cone[i] = goal[i] if goal[i] < _cone[i] or not rig.is_placed() else lerpf(_cone[i], goal[i], opening)


## Shoulder in a doorway: the player's side, or the one the passage asks for, kept within
## a share of the opening round its centre line, so it slides inward or across as Henry is off it.
func _side(pivot: Vector3, side: float) -> float:
	var wanted: float = side
	var forced: int = _framing.info.shoulder
	if forced == PassageInfo.Shoulder.LEFT:
		wanted = -absf(side)
	elif forced == PassageInfo.Shoulder.RIGHT:
		wanted = absf(side)
	elif forced == PassageInfo.Shoulder.CENTRE:
		wanted = 0.0
	var room: float = _framing.band() * rig.passage_shoulder_band_share
	var lateral: float = _framing.lateral(pivot)
	return clampf(lateral + wanted, -room, room) - lateral
