class_name TpsCamera
extends Camera3D

## Third-person over-the-shoulder camera (ADT on-foot camera, rebuilt in #170).
## The mouse owns the control yaw (WASD); automatic turns only offset the view.

## Henry as measured from his loaded model by tools/runtime/measure_henry_metrics.gd.
const DEFAULT_METRICS: HenryMetrics = preload("res://data/characters/henry_metrics.tres")
## Lyra's soft feelers around the boom: yaw and pitch offsets (degrees), weight.
const FEELERS: Array = [[16.0, 0.0, 0.75], [-16.0, 0.0, 0.75], [32.0, 0.0, 0.5], [-32.0, 0.0, 0.5],
	[0.0, 20.0, 1.0], [0.0, -20.0, 0.5]]
## Daedalic's whiskers: booms swung this far either way judge where the room is.
const WHISKERS_DEG: Array = [20.0, 40.0]
## Seconds between searches for an angle with room while the boom stays cramped.
const ROOM_SEARCH_INTERVAL: float = 0.25
const CAMERA_USER_SETTINGS: GDScript = preload("res://scripts/settings/camera_user_settings.gd")

@export var player: CharacterBody3D

@export_group("Look")
@export var look_sensitivity_x: float = 0.65
@export var look_sensitivity_y: float = 0.65
@export var invert_look_x: bool = false
@export var invert_look_y: bool = false
@export var start_pitch_deg: float = -10.0
@export var pitch_min_deg: float = -70.0
@export var pitch_max_deg: float = 60.0
## Vertical look feels heavier than horizontal, as in ADT.
@export_range(0.1, 1.0, 0.05) var pitch_sensitivity_ratio: float = 0.7

@export_group("Body")
## Framing heights: the pivot sits at the shoulder joints, fades read the eyes.
@export var metrics: HenryMetrics = DEFAULT_METRICS
## Orbit pivot between the shoulder joints (0) and the coat over them (1); a framing call.
@export_range(0.0, 1.0, 0.05) var framing_pivot_share: float = 0.0
## Used only when Henry has no capsule to read the feet from.
@export var origin_above_feet: float = 1.0
## How fast the framing follows a crouch, as Lyra's crouch blend.
@export_range(0.5, 20.0, 0.5) var stance_rate: float = 5.0

@export_group("Shoulder")
@export var shoulder_offset: float = 0.85
## Share of the shoulder offset kept in the tightest space; eased by the boom.
@export_range(0.0, 1.0, 0.05) var tight_shoulder_fraction: float = 0.2

@export_group("Lean")
@export var lean_camera_offset: float = 0.45
@export_range(0.5, 20.0, 0.5) var lean_rate: float = 5.0
@export_range(0.5, 20.0, 0.5) var lean_return_rate: float = 8.0

@export_group("Breathing")
## Visual only: gameplay rays use aim_origin()/aim_direction(), which leave it out.
@export var breathing_amplitude_deg: float = 0.4
@export var breathing_speed: float = 0.6

@export_group("Follow")
## Lag of the point the camera orbits, across the ground and in height; mouse look has none.
@export_range(1.0, 40.0, 0.5) var follow_speed: float = 16.0
@export_range(1.0, 40.0, 0.5) var follow_speed_vertical: float = 10.0
@export var lead_distance: float = 0.6
@export_range(0.5, 20.0, 0.5) var lead_smoothing: float = 2.5
@export var sprint_pullback: float = 0.4
@export_range(0.5, 20.0, 0.5) var pullback_smoothing: float = 3.0
## A target jump longer than this in one frame is a teleport: the camera snaps.
@export var teleport_distance: float = 1.5

@export_group("Adaptive distance")
## Boom length in the tightest space and in the open.
@export var near_distance: float = 0.95
@export var far_distance: float = 3.0
## Rods across the camera's half of the circle judge the room behind Henry, every frame.
@export_range(3, 15) var probe_count: int = 7
@export var probe_length: float = 4.0
## A ceiling closer than this above the shoulders pulls the camera in.
@export var ceiling_clearance: float = 3.0
## Above 1 favours closing in: half-open space sits nearer the near distance.
@export_range(0.5, 4.0, 0.1) var openness_exponent: float = 2.0
@export_range(0.1, 20.0, 0.1) var close_in_rate: float = 2.5
@export_range(0.1, 20.0, 0.1) var open_out_rate: float = 1.2
## Looking fully up shortens the boom to this share before the ground cuts it.
@export_range(0.3, 1.0, 0.05) var look_up_distance_scale: float = 0.6

@export_group("Collision")
@export var collision_radius: float = 0.2
## Closest the camera gets to the shoulder; a wall always wins over framing.
@export var collision_min_distance: float = 0.05
@export var collision_surface_margin: float = 0.1
## Seconds to ease toward a feeler's limit, and to ease back out after any wall.
@export_range(0.01, 1.0, 0.01) var blend_in_time: float = 0.1
@export_range(0.01, 2.0, 0.01) var blend_out_time: float = 0.2
@export_flags_3d_physics var collision_mask: int = 0xFFFFFFFF
## Colliders narrower than this in their middle axis never stop the boom: they fade.
@export var thin_extent: float = 0.6

@export_group("Auto look")
## Seconds the mouse must rest before the camera turns by itself.
@export var auto_look_cooldown: float = 0.9
@export var auto_recenter: bool = true
## Recentring speed behind a sprinting Henry, degrees per second.
@export var recenter_rate_deg: float = 90.0
## Largest view swing the whiskers make away from a wall while Henry moves, degrees.
@export_range(0.0, 60.0, 5.0) var whisker_max_deg: float = 30.0
## Standing still, a boom with less free length than this looks for room.
@export var room_comfort_distance: float = 0.7
## Furthest the room search swings along a wall and rises over Henry, degrees.
@export_range(0.0, 120.0, 5.0) var assist_max_yaw_deg: float = 90.0
@export_range(0.0, 60.0, 5.0) var assist_max_pitch_deg: float = 30.0

@export_group("Passage")
## Boom through a doorway in a wall this deep; a deeper wall takes its extra depth off it.
@export var passage_boom: float = 1.4
@export var passage_boom_min: float = 1.0
@export var passage_reference_wall: float = 0.2
## Share of the opening's free half the shoulder may take; the rest is left for the orbit.
@export_range(0.0, 1.0, 0.05) var passage_shoulder_band_share: float = 0.5
## Pivot lift in a doorway, at most half the room left under the lintel.
@export var passage_rise: float = 0.15
@export_range(0.0, 10.0, 0.5) var passage_fov_deg: float = 5.0
@export var max_fov_deg: float = 80.0
## The mouse eases into a soft stop over this many degrees.
@export_range(1.0, 30.0, 1.0) var passage_look_knee_deg: float = 10.0
## The view looks past the camera body only while Henry stays this far inside the frame edge.
@export_range(0.0, 30.0, 1.0) var passage_look_margin_deg: float = 8.0
## Pre-compress starts this far before the wall face, plus a lead at Henry's speed and
## more on a slanted approach.
@export var passage_approach: float = 1.0
@export var passage_lead_time: float = 0.3
@export_range(0.0, 2.0, 0.1) var passage_angle_lead: float = 0.5
## The frame closes round Henry before the door and opens back out softer after it.
@export_range(0.5, 30.0, 0.5) var passage_compress_rate: float = 8.0
@export_range(0.5, 20.0, 0.5) var passage_release_rate: float = 3.0

@export_group("Recompose")
## Closer than this to his eyes, the boom moves onto the centre line behind Henry when
## that gives it room; the body fade only follows if it still cannot.
@export var recompose_distance: float = 1.1
@export_range(0.0, 10.0, 0.5) var recompose_fov_deg: float = 3.0
@export_range(0.5, 30.0, 0.5) var recompose_in_rate: float = 12.0
@export_range(0.1, 20.0, 0.1) var recompose_out_rate: float = 2.0

@export_group("Fade")
## Render layers of Henry's body; his parts near the camera dither out when it is inside his reach.
@export_flags_3d_render var body_layers: int = 16
## Last resort after recomposing: fades from the first distance to his eyes, full at the
## second; the shader spares parts over a metre from the camera, so his legs stay.
@export var body_fade_start: float = 0.8
@export var body_fade_end: float = 0.25
## How see-through a thin occluder between camera and Henry becomes.
@export_range(0.0, 1.0, 0.05) var occluder_transparency: float = 0.7

## 0..1 unease that widens the breathing sway; free for survival state to drive.
var tension: float = 0.0

## Control look: only the mouse and set_look() change it; WASD turns by its yaw.
var _yaw: float = 0.0
var _pitch_deg: float = -12.0
## View offset from automatic turns, added on top of the control look.
var _auto_yaw: float = 0.0
var _auto_pitch_deg: float = 0.0
## Breathing sway last added to the drawn pitch; gameplay rays take it back out.
var _sway_deg: float = 0.0
## Henry's interpolated transform for this rendered frame.
var _target := Transform3D.IDENTITY
var _pivot_smooth: Vector3 = Vector3.ZERO
var _lead: Vector3 = Vector3.ZERO
var _pullback: float = 0.0
var _openness: float = 1.0
var _boom: float = 3.0
## Crouch share of the framing: 0 standing, 1 crouched.
var _crouch: float = 0.0
## Shares of each boom leg left after walls, Lyra's DistBlockedPct.
var _shoulder_pct: float = 1.0
var _dist_pct: float = 1.0
## Free length behind the shoulder this frame, before the margin.
var _boom_room: float = INF
## View offset the room search glides to while Henry stands: yaw radians, pitch degrees.
var _room_goal: Vector2 = Vector2.ZERO
var _room_active: bool = false
var _room_search_timer: float = 0.0
var _has_position: bool = false
var _lean: float = 0.0
var _noise := FastNoiseLite.new()
var _noise_time: float = 0.0
var _shoulder := TpsShoulderState.new()
var _probe := TpsBoomProbe.new()
var _auto := TpsAutoLook.new()
var _fader := TpsCameraFader.new()
var _capsule: CollisionShape3D
var _input_systems: Node
var _user_mouse_sensitivity_multiplier: float = 1.0
var _user_invert_y: bool = false
## Henry's doorway traversal, read for the frame; looked up once after his _ready.
var _passage: PassageTraversalComponent
var _passage_looked_up: bool = false
var _passage_blend: float = 0.0
var _framing := TpsPassageFraming.new()
## Orbit cone of the camera body in a passage: left and right turn off the axis
## (radians), elevation and depression (degrees). Closes at once, opens softly.
var _cone := Vector4(PI, PI, 90.0, 90.0)
## Share of the shoulder given up for the centre line while the boom is cramped.
var _recompose: float = 0.0
var _last_eye_distance: float = INF
## FOV this camera added for a doorway; others may set the base FOV meanwhile.
var _fov_offset: float = 0.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.frequency = breathing_speed
	_shoulder.right_offset = shoulder_offset
	_shoulder.left_offset = -shoulder_offset
	_pitch_deg = start_pitch_deg
	_boom = far_distance
	if metrics == null:
		metrics = DEFAULT_METRICS
	_input_systems = get_node_or_null(^"/root/InputSystems")
	add_to_group(&"tps_camera_user_settings")
	reload_user_settings()
	if is_instance_valid(player):
		_yaw = player.global_rotation.y
		_find_capsule()
		_fader.set_body(player, body_layers)
	_set_look_capture(true)
	make_current()


func _exit_tree() -> void:
	_set_look_capture(false)


func reload_user_settings() -> void:
	var values: Dictionary = CAMERA_USER_SETTINGS.load_camera()
	_user_mouse_sensitivity_multiplier = float(values["mouse_sensitivity_multiplier"])
	_user_invert_y = bool(values["invert_y"])


## Runs every rendered frame: look is applied as it arrives, Henry is followed
## at his interpolated pose, so neither steps at the physics rate.
func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	_sync_helpers()
	var target: Transform3D = player.get_global_transform_interpolated()
	if _has_position and target.origin.distance_to(_target.origin) > teleport_distance:
		snap_to_target()
	_target = target
	_update_stance(delta)
	_update_passage(delta)
	_auto.note_look(_apply_look_input(), delta)
	_apply_lean_and_shoulder_input(delta)
	_probe.begin(get_world_3d().direct_space_state, [player.get_rid()])
	_openness = measure_openness()
	var wanted: float = get_target_distance()
	var rate: float = close_in_rate if wanted < _boom else open_out_rate
	_boom = wanted if not _has_position else lerpf(_boom, wanted, _damp(rate, delta))
	_update_rig(delta)


## Control yaw in radians, the one WASD is turned by; automatic turns never move it.
func get_yaw() -> float:
	return _yaw


## Yaw the camera looks along: the control yaw plus any automatic offset.
func get_view_yaw() -> float:
	return wrapf(_yaw + _auto_yaw, -PI, PI)


func get_view_pitch_deg() -> float:
	return clampf(_pitch_deg + _auto_pitch_deg, pitch_min_deg, pitch_max_deg)


## Gameplay ray origin through the screen centre; the sway turns, never moves, it.
static func aim_origin(camera: Camera3D) -> Vector3:
	return camera.project_ray_origin(camera.get_viewport().get_visible_rect().size * 0.5)


## Gameplay ray direction through the screen centre, with the breathing sway
## turned back out about the camera's own right axis.
static func aim_direction(camera: Camera3D) -> Vector3:
	var direction: Vector3 = camera.project_ray_normal(camera.get_viewport().get_visible_rect().size * 0.5).normalized()
	var tps := camera as TpsCamera
	if tps != null and tps._sway_deg != 0.0:
		direction = direction.rotated(camera.global_basis.x.normalized(), -deg_to_rad(tps._sway_deg))
	return direction


## Aims the camera directly, for spawn and tests; clears any automatic offset.
func set_look(yaw: float, pitch_deg: float) -> void:
	_yaw = yaw
	_pitch_deg = clampf(pitch_deg, pitch_min_deg, pitch_max_deg)
	_clear_auto_look()


## Drops all follow and collision memory; the next frame starts on the goal.
func snap_to_target() -> void:
	_has_position = false
	_shoulder_pct = 1.0
	_dist_pct = 1.0
	_lead = Vector3.ZERO
	_pullback = 0.0
	_recompose = 0.0
	_last_eye_distance = INF
	_cone = Vector4(PI, PI, 90.0, 90.0)
	_clear_auto_look()


## 0 away from doorways, 1 with the frame fully closed round Henry in one.
func get_passage_blend() -> float:
	return _passage_blend


## Share of the shoulder given up for the centre line while the boom is cramped.
func get_recompose() -> float:
	return _recompose


## 0 in a tight doorway, 1 in the open; last value from the rods.
func get_openness() -> float:
	return _openness


## Boom length the rods ask for, before walls.
func get_target_distance() -> float:
	return lerpf(near_distance, far_distance, pow(_openness, openness_exponent))


## Current smoothed boom length, before walls.
func get_boom_length() -> float:
	return _boom


## 0 shows Henry, 1 means the camera is inside him and he is dithered out.
func get_body_fade() -> float:
	return _fader.get_body_fade()


func is_body_hidden() -> bool:
	return _fader.get_body_fade() >= 0.99


## Henry's eyes as the camera frames them: measured height, eased between stances.
func get_eye_position() -> Vector3:
	return _feet_position() + Vector3.UP * _eye_height()


## Seconds since the mouse last moved; automatic turns wait for the cooldown.
func get_look_idle_time() -> float:
	return _auto.get_idle_time()


## Casts the rods now and returns 0..1: free room across the camera's half of the
## circle (straight back counts most) times room above Henry. Walls ahead do not count.
func measure_openness() -> float:
	var origin: Vector3 = _safe_origin()
	var view_yaw: float = get_view_yaw()
	var count: int = maxi(probe_count, 2)
	var free_sum: float = 0.0
	var weight_sum: float = 0.0
	for i: int in range(count):
		var offset: float = lerpf(-PI * 0.5, PI * 0.5, float(i) / float(count - 1))
		var dir := Vector3(sin(view_yaw + offset), 0.0, cos(view_yaw + offset))
		var weight: float = 0.5 + 0.5 * cos(offset)
		free_sum += weight * _probe.ray(origin, dir * probe_length)
		weight_sum += weight * probe_length
	var ceiling: float = _probe.ray(origin, Vector3.UP * ceiling_clearance)
	return clampf(free_sum / weight_sum * (ceiling / ceiling_clearance), 0.0, 1.0)


func _update_rig(delta: float) -> void:
	var speed_ratio: float = _player_speed_ratio()
	_pullback = lerpf(_pullback, speed_ratio * sprint_pullback, _damp(pullback_smoothing, delta))
	var planar := Vector3(player.velocity.x, 0.0, player.velocity.z)
	var move_dir: Vector3 = planar.normalized() if planar.length() > 0.05 else Vector3.ZERO
	_lead = _lead.lerp(move_dir * speed_ratio * lead_distance, _damp(lead_smoothing, delta))
	## Framing heights ride on the followed feet, so each is smoothed once.
	var pivot: Vector3 = _follow_pivot(delta, _feet_position() + _lead)
	pivot += Vector3.UP * (_pivot_height() + _passage_rise() * _passage_blend)
	var safe: Vector3 = _safe_origin()
	_update_auto_look(delta, safe, speed_ratio)

	## The view is where the player looks; the orbit is where the camera body may stand.
	var view_yaw: float = get_view_yaw()
	var view_pitch: float = get_view_pitch_deg()
	var want: float = (_boom + _pullback) * _look_up_scale(view_pitch)
	var roominess: float = clampf(inverse_lerp(near_distance, far_distance, _boom), 0.0, 1.0)
	var side: float = _shoulder.update(delta) * lerpf(tight_shoulder_fraction, 1.0, roominess) + _lean * lean_camera_offset
	var orbit_yaw: float = view_yaw
	var orbit_pitch: float = view_pitch
	if _framing.has_passage() and _passage_blend > 0.001:
		var blend: float = _passage_blend
		want = lerpf(want, minf(want, _passage_boom()), blend)
		side = lerpf(side, _passage_side(pivot, side), blend)
		var axis_yaw: float = _framing.axis_yaw()
		var limits: Vector2 = _view_yaw_limits()
		var off: float = angle_difference(axis_yaw, view_yaw)
		view_yaw = wrapf(axis_yaw + lerpf(off, clampf(off, -limits.x, limits.y), blend), -PI, PI)
		var pitch_range: Vector2 = _passage_pitch_range()
		view_pitch = lerpf(view_pitch, clampf(view_pitch, pitch_range.x, pitch_range.y), blend)
		_update_cone(delta, pivot + _framing.right() * side, want, view_yaw, view_pitch)
		off = angle_difference(axis_yaw, view_yaw)
		orbit_yaw = wrapf(axis_yaw + lerpf(off, clampf(off, -_cone.x, _cone.y), blend), -PI, PI)
		orbit_pitch = lerpf(view_pitch, clampf(view_pitch, -_cone.z, _cone.w), blend)
	else:
		_cone = Vector4(PI, PI, 90.0, 90.0)
	var right := Vector3(cos(orbit_yaw), 0.0, -sin(orbit_yaw))
	var back: Vector3 = _back(orbit_yaw, orbit_pitch)
	side *= 1.0 - _update_recompose(delta, safe, pivot, right * side, back, want)
	_apply_fov_offset(_passage_fov() * _passage_blend + recompose_fov_deg * _recompose)
	var shoulder: Vector3 = _sweep_shoulder(delta, safe, pivot + right * side)
	var camera: Vector3 = shoulder + back * want * _blend_boom(delta, shoulder, back, want)
	## Safety net for a camera left inside a blocking body; thin ones still pass.
	if _probe.overlaps(camera):
		var hard: float = _probe.sweep(shoulder, back * want) - collision_surface_margin
		camera = shoulder + back * clampf(hard, collision_min_distance, want)
	_has_position = true

	_noise_time += delta
	_sway_deg = _noise.get_noise_1d(_noise_time * 20.0) * breathing_amplitude_deg * (0.4 + tension)
	h_offset = 0.0
	global_position = camera
	global_rotation = Vector3(deg_to_rad(view_pitch + _sway_deg), view_yaw, 0.0)
	_last_eye_distance = camera.distance_to(get_eye_position())
	_update_fades(delta, camera)


## The cone the camera body may orbit in at this pass of the doorway: it closes at once
## as Henry walks into it and opens at the release rate, so a cone never snaps open.
func _update_cone(delta: float, shoulder: Vector3, want: float, view_yaw: float, view_pitch: float) -> void:
	var yaw: Vector2 = _framing.yaw_limits(shoulder, want * cos(deg_to_rad(view_pitch)))
	var off: float = clampf(angle_difference(_framing.axis_yaw(), view_yaw), -yaw.x, yaw.y)
	var pitch: Vector2 = _framing.pitch_limits(shoulder, want, off)
	var goal := Vector4(yaw.x, yaw.y, pitch.x, pitch.y)
	var opening: float = _damp(passage_release_rate, delta)
	for i: int in range(4):
		_cone[i] = goal[i] if goal[i] < _cone[i] or not _has_position else lerpf(_cone[i], goal[i], opening)


## Cramped closer than recompose_distance to the eyes, the shoulder gives way to the
## centre line if that gives the boom more room. Same-frame casts, one damp; returns the share.
func _update_recompose(delta: float, safe: Vector3, pivot: Vector3, offset: Vector3, back: Vector3, want: float) -> float:
	var goal: float = 0.0
	var centre_worse: bool = false
	if _last_eye_distance < recompose_distance + 0.3 and offset.length() > 0.05:
		var eye: Vector3 = get_eye_position()
		var near: float = _free_eye_distance(safe, pivot + offset, back, want, eye)
		var centre: float = _free_eye_distance(safe, pivot, back, want, eye)
		if near < recompose_distance and centre > near + 0.05:
			goal = clampf(inverse_lerp(recompose_distance, body_fade_start, near), 0.0, 1.0)
		centre_worse = centre < near - 0.02  # back to a wall: the centre line would bring the camera closer
	var rate: float = recompose_in_rate if goal > _recompose or centre_worse else recompose_out_rate
	_recompose = goal if not _has_position else lerpf(_recompose, goal, _damp(rate, delta))
	return _recompose


## Distance from the eyes a camera would get on a boom from `shoulder`, walls applied,
## without touching any smoothing state.
func _free_eye_distance(safe: Vector3, shoulder: Vector3, back: Vector3, want: float, eye: Vector3) -> float:
	var leg: Vector3 = shoulder - safe
	var start: Vector3 = shoulder
	if leg.length() > 0.001:
		start = safe + leg * clampf((_probe.sweep(safe, leg, false) - 0.05) / leg.length(), 0.0, 1.0)
	var room: float = _probe.sweep(start, back * want) - collision_surface_margin
	return (start + back * clampf(room, collision_min_distance, want)).distance_to(eye)


## Sets how much FOV this camera adds over the base, capped at max_fov_deg.
func _apply_fov_offset(offset: float) -> void:
	var base: float = fov - _fov_offset
	offset = clampf(offset, 0.0, maxf(max_fov_deg - base, 0.0))
	fov = base + offset
	_fov_offset = offset


## Lyra's penetration blend: the centre sweep snaps the boom in, the feelers ease
## it in, and any release eases it back out. Returns the share of `want` kept.
func _blend_boom(delta: float, shoulder: Vector3, back: Vector3, want: float) -> float:
	var min_pct: float = clampf(collision_min_distance / maxf(want, 0.001), 0.0, 1.0)
	_boom_room = _probe.sweep(shoulder, back * want)
	var hard_pct: float = clampf((_boom_room - collision_surface_margin) / want, min_pct, 1.0)
	var soft_pct: float = 1.0
	var right: Vector3 = back.cross(Vector3.UP).normalized()
	for feeler: Array in FEELERS:
		var dir: Vector3 = back.rotated(Vector3.UP, deg_to_rad(feeler[0]))
		if right.length_squared() > 0.0:
			dir = dir.rotated(right, deg_to_rad(feeler[1]))
		var hit: float = _probe.ray(shoulder, dir * want) / want
		soft_pct = minf(soft_pct, hit + (1.0 - hit) * (1.0 - float(feeler[2])))
	soft_pct = maxf(soft_pct, min_pct)
	var this_frame: float = minf(hard_pct, soft_pct)
	if not _has_position:
		_dist_pct = this_frame
	elif _dist_pct < this_frame:
		_dist_pct = lerpf(_dist_pct, this_frame, _damp(1.0 / blend_out_time, delta))
	elif _dist_pct > hard_pct:
		_dist_pct = hard_pct
	elif _dist_pct > soft_pct:
		_dist_pct = lerpf(_dist_pct, soft_pct, _damp(1.0 / blend_in_time, delta))
	return _dist_pct


## First leg of the rig: from inside Henry to the shoulder point. Thin props do
## not pass here; the shoulder snaps in and eases back out.
func _sweep_shoulder(delta: float, safe: Vector3, goal: Vector3) -> Vector3:
	var leg: Vector3 = goal - safe
	var length: float = leg.length()
	if length < 0.001:
		return goal
	var free: float = _probe.sweep(safe, leg, false)
	var pct: float = clampf((free - 0.05) / length, 0.0, 1.0)
	if not _has_position or pct < _shoulder_pct:
		_shoulder_pct = pct
	else:
		_shoulder_pct = lerpf(_shoulder_pct, pct, _damp(1.0 / blend_out_time, delta))
	return safe + leg * _shoulder_pct


## Turns the player did not make, once the mouse rests: room search while Henry
## stands cramped, recentring and whiskers while he moves. They only offset the view.
## A doorway owns the framing: any offset glides out and none starts.
func _update_auto_look(delta: float, safe: Vector3, speed_ratio: float) -> void:
	if _passage_blend > 0.01:
		_room_active = false
		_auto_yaw = move_toward(_auto_yaw, 0.0, deg_to_rad(_auto.room_rate_deg) * delta)
		_auto_pitch_deg = move_toward(_auto_pitch_deg, 0.0, _auto.room_rate_deg * delta)
		return
	if not _auto.is_active():
		return
	var want: float = _boom + _pullback
	var goal := Vector2(_auto_yaw, _auto_pitch_deg)
	var rate_deg: float = _auto.room_rate_deg
	if speed_ratio < 0.05:
		_room_search_timer -= delta
		if not _room_active and _boom_room < minf(room_comfort_distance, want) and _room_search_timer <= 0.0:
			_room_search_timer = ROOM_SEARCH_INTERVAL
			var turn: Vector2 = _find_room(safe, want)
			if turn != Vector2.ZERO:
				_room_goal = Vector2(_auto_yaw + turn.x, _auto_pitch_deg + turn.y)
				_room_active = true
		if _room_active:
			goal = _room_goal
	else:
		_room_active = false
		var move_axis: Vector2 = _input_systems.call(&"get_move_axis") if _input_systems != null else Vector2.ZERO
		var heading: float = atan2(-player.velocity.x, -player.velocity.z)
		var recenter: float = _auto.recenter_offset(angle_difference(_yaw, heading), move_axis)
		var lower: float = _whisker_room(safe, want, _yaw + recenter, -1.0)
		var higher: float = _whisker_room(safe, want, _yaw + recenter, 1.0)
		goal = Vector2(recenter + _auto.whisker_offset(lower, higher), 0.0)
		rate_deg = recenter_rate_deg * maxf(speed_ratio, 0.3)
	var step: float = deg_to_rad(rate_deg) * delta
	_auto_yaw = wrapf(_auto_yaw + clampf(angle_difference(_auto_yaw, goal.x), -step, step), -PI, PI)
	_auto_pitch_deg = move_toward(_auto_pitch_deg, goal.y, rate_deg * delta)


## Doorways recompose the frame round Henry before he reaches them: the blend rises
## while he or the boom behind him nears the frame, and falls softly once both are clear.
func _update_passage(delta: float) -> void:
	if not _passage_looked_up:
		_passage_looked_up = true
		_passage = player.get_node_or_null(^"PassageTraversalComponent") as PassageTraversalComponent
	var passage: PassageInfo = _passage.get_nearby_passage() if _passage != null else null
	if passage != null:
		_framing.set_passage(passage)
	var goal: float = 0.0
	if _framing.has_passage():
		_framing.clearance = collision_radius + collision_surface_margin
		_framing.body_radius = _capsule_radius()
		_framing.update_side(_back(get_view_yaw(), 0.0))
	if passage != null:
		var view_back: Vector3 = _back(get_view_yaw(), 0.0)
		var off: float = minf(absf(angle_difference(_framing.axis_yaw(), get_view_yaw())), PI / 3.0)
		## The boom the frame will have, not the one it has, so the blend never feeds itself.
		var boom_h: float = _passage_boom() * cos(deg_to_rad(get_view_pitch_deg())) * cos(off)
		var speed: float = Vector2(player.velocity.x, player.velocity.z).length()
		var approach: float = (passage_approach + speed * passage_lead_time) * (1.0 + passage_angle_lead * (1.0 - cos(off)))
		goal = _framing.goal(_feet_position(), view_back, boom_h, approach, _passage.get_passage() != null)
	var rate: float = passage_compress_rate if goal > _passage_blend else passage_release_rate
	_passage_blend = goal if not _has_position else lerpf(_passage_blend, goal, _damp(rate, delta))
	if passage == null and _passage_blend <= 0.001:
		_passage_blend = 0.0
		_framing.clear()


## Shoulder in a doorway: the player's side, or the one the passage asks for, kept within
## a share of the opening round its centre line, so it slides inward or across as Henry is off it.
func _passage_side(pivot: Vector3, side: float) -> float:
	var wanted: float = side
	var forced: int = _framing.info.shoulder
	if forced == PassageInfo.Shoulder.LEFT:
		wanted = -absf(side)
	elif forced == PassageInfo.Shoulder.RIGHT:
		wanted = absf(side)
	elif forced == PassageInfo.Shoulder.CENTRE:
		wanted = 0.0
	var room: float = _framing.band() * passage_shoulder_band_share
	var lateral: float = _framing.lateral(pivot)
	return clampf(lateral + wanted, -room, room) - lateral


## Boom through the doorway: authored, or passage_boom less any wall depth past the reference.
func _passage_boom() -> float:
	var info: PassageInfo = _framing.info
	if info == null:
		return passage_boom
	if info.camera_distance > 0.0:
		return info.camera_distance
	return maxf(passage_boom - maxf(info.wall_thickness - passage_reference_wall, 0.0), passage_boom_min)


## Pivot lift in a doorway: passage_rise, or half the room left under the lintel if less.
func _passage_rise() -> float:
	if not _framing.has_passage():
		return 0.0
	var room: float = _framing.top_y() - (_feet_position().y + _pivot_height())
	return clampf(room * 0.5, 0.0, passage_rise)


func _passage_fov() -> float:
	var info: PassageInfo = _framing.info
	return info.fov_offset_deg if info != null and info.fov_offset_deg >= 0.0 else passage_fov_deg


## Soft stops of the view off the passage axis, radians (left, right): past the orbit
## cone only as far as Henry stays inside the frame, or an authored limit if tighter.
func _view_yaw_limits() -> Vector2:
	var past: float = deg_to_rad(maxf(_half_fov_deg(true) - passage_look_margin_deg, 0.0))
	var limits := Vector2(_cone.x + past, _cone.y + past)
	var info: PassageInfo = _framing.info
	if info != null and info.yaw_limit_deg > 0.0:
		var authored: float = deg_to_rad(info.yaw_limit_deg)
		limits = Vector2(minf(limits.x, authored), minf(limits.y, authored))
	return limits


## Soft range of the view pitch in a doorway, degrees: past the orbit cone only as far
## as Henry stays inside the frame.
func _passage_pitch_range() -> Vector2:
	var past: float = maxf(_half_fov_deg(false) - passage_look_margin_deg, 0.0)
	return Vector2(-(_cone.z + past), _cone.w + past)


## Half the field of view across or up the screen, degrees.
func _half_fov_deg(horizontal: bool) -> float:
	var size: Vector2 = get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(16.0, 9.0)
	var aspect: float = size.x / maxf(size.y, 1.0)
	var half: float = deg_to_rad(fov * 0.5)
	if keep_aspect == Camera3D.KEEP_WIDTH:
		return rad_to_deg(half if horizontal else atan(tan(half) / aspect))
	return rad_to_deg(atan(tan(half) * aspect) if horizontal else half)


func _clear_auto_look() -> void:
	_auto_yaw = 0.0
	_auto_pitch_deg = 0.0
	_room_active = false


## Mean free share of booms swung to one side of `base_yaw`, 0..1.
func _whisker_room(safe: Vector3, want: float, base_yaw: float, side: float) -> float:
	var room: float = 0.0
	for angle: float in WHISKERS_DEG:
		var back: Vector3 = _back(base_yaw + deg_to_rad(angle) * side, get_view_pitch_deg())
		room += _probe.ray(safe, back * want) / want
	return room / float(WHISKERS_DEG.size())


## Smallest turn of the view (yaw radians, pitch degrees) that gives the boom room,
## rising over Henry before swinging along a wall; zero if nothing is better.
func _find_room(safe: Vector3, want: float) -> Vector2:
	var need: float = minf(room_comfort_distance, want)
	var best_cost: float = INF
	var pick := Vector2.ZERO
	var current: float = _boom_room
	for yaw_step: int in range(0, int(assist_max_yaw_deg) + 1, 15):
		for side: float in [1.0, -1.0]:
			if yaw_step == 0 and side < 0.0:
				continue
			for pitch_step: int in range(0, int(assist_max_pitch_deg) + 1, 15):
				if yaw_step == 0 and pitch_step == 0:
					continue
				var yaw: float = get_view_yaw() + deg_to_rad(float(yaw_step)) * side
				var pitch: float = clampf(get_view_pitch_deg() - float(pitch_step), pitch_min_deg, pitch_max_deg)
				var room: float = _probe.sweep(safe, _back(yaw, pitch) * want)
				var cost: float = float(yaw_step) + 0.8 * float(pitch_step)
				if room >= need and room > current + 0.1 and cost < best_cost:
					best_cost = cost
					pick = Vector2(deg_to_rad(float(yaw_step)) * side, -float(pitch_step))
	return pick


## Fades only while this camera draws the frame; another camera (the Hub's
## inspection view) must see Henry and the props whole.
func _update_fades(delta: float, camera: Vector3) -> void:
	if not is_current():
		_fader.update_body(0.0, delta)
		_fader.update_occluders([], delta)
		return
	var eye: Vector3 = get_eye_position()
	var fade: float = clampf(inverse_lerp(body_fade_start, body_fade_end, camera.distance_to(eye)), 0.0, 1.0)
	_fader.update_body(fade, delta)
	_probe.passed.clear()
	_probe.overlaps(camera)
	_probe.ray(camera, eye - camera)
	_fader.update_occluders(_probe.passed.values(), delta)


## Mouse look on the control yaw. Moving the mouse takes over the view the player
## sees: an automatic offset folds into the control look, so nothing jumps.
func _apply_look_input() -> Vector2:
	if _input_systems == null:
		return Vector2.ZERO
	var look: Vector2 = _input_systems.call(&"consume_look_delta")
	if look.length_squared() > 1e-12 and (_auto_yaw != 0.0 or _auto_pitch_deg != 0.0):
		_yaw = get_view_yaw()
		_pitch_deg = get_view_pitch_deg()
		_clear_auto_look()
	var x_sign: float = -1.0 if invert_look_x else 1.0
	var effective_invert_y: bool = invert_look_y != _user_invert_y
	var y_sign: float = -1.0 if effective_invert_y else 1.0
	var yaw_step: float = -look.x * look_sensitivity_x * _user_mouse_sensitivity_multiplier * x_sign
	var pitch_step: float = (
		-rad_to_deg(look.y)
		* look_sensitivity_y
		* _user_mouse_sensitivity_multiplier
		* pitch_sensitivity_ratio
		* y_sign
	)
	## In a doorway the mouse eases into a soft stop instead of a wall; back in is always free.
	var weight: float = _passage_blend if _framing.has_passage() else 0.0
	if weight > 0.001 and yaw_step != 0.0:
		var axis_yaw: float = _framing.axis_yaw()
		var turn: float = signf(yaw_step)
		var limits: Vector2 = _view_yaw_limits()
		var off: float = angle_difference(axis_yaw, _yaw) * turn
		var limit: float = limits.y if turn > 0.0 else limits.x
		off = _soft_step(off, absf(yaw_step), limit, deg_to_rad(passage_look_knee_deg), weight)
		_yaw = wrapf(axis_yaw + off * turn, -PI, PI)
	else:
		_yaw = wrapf(_yaw + yaw_step, -PI, PI)
	if weight > 0.001 and pitch_step != 0.0:
		var pitch_range: Vector2 = _passage_pitch_range()
		if pitch_step < 0.0:
			_pitch_deg = -_soft_step(-_pitch_deg, -pitch_step, -pitch_range.x, passage_look_knee_deg, weight)
		else:
			_pitch_deg = _soft_step(_pitch_deg, pitch_step, pitch_range.y, passage_look_knee_deg, weight)
	else:
		_pitch_deg += pitch_step
	_pitch_deg = clampf(_pitch_deg, pitch_min_deg, pitch_max_deg)
	return look


## Moves `value` up by `step` toward a soft stop at `limit`: free until `knee` short of
## it, then easing in for good; `weight` 0 removes the stop. Steps down are always free.
static func _soft_step(value: float, step: float, limit: float, knee: float, weight: float) -> float:
	var free: float = value + step
	if step <= 0.0 or weight <= 0.0:
		return free
	var soft: float = value
	if value < limit:
		var start: float = limit - knee
		var before_knee: float = maxf(start - value, 0.0)
		if step <= before_knee:
			soft = free
		else:
			var at: float = maxf(value, start)
			soft = limit - (limit - at) * exp(-(step - before_knee) / maxf(knee, 0.001))
	return lerpf(free, soft, weight)


func _apply_lean_and_shoulder_input(delta: float) -> void:
	if _input_systems == null:
		return
	if _input_systems.call(&"consume_switch_shoulder"):
		_shoulder.toggle()
	var axis: float = _input_systems.call(&"get_lean_axis")
	if axis != 0.0:
		_lean = clampf(_lean + axis * lean_rate * delta, -1.0, 1.0)
	else:
		_lean = lerpf(_lean, 0.0, _damp(lean_return_rate, delta))


## Henry's feet from his capsule, so crouching keeps them on the ground.
func _feet_position() -> Vector3:
	if _capsule == null:
		return _target.origin - Vector3.UP * origin_above_feet
	var capsule := _capsule.shape as CapsuleShape3D
	return _target.origin + Vector3.UP * (_capsule.position.y - capsule.height * 0.5)


## Lyra's safe point: on the capsule axis, below its top by the probe radius,
## so a cast from it never starts inside a wall or a low ceiling.
func _safe_origin() -> Vector3:
	var feet: Vector3 = _feet_position()
	var top: float = lerpf(metrics.capsule_height, metrics.crouch_capsule_height, _crouch)
	if _capsule != null:
		top = (_capsule.shape as CapsuleShape3D).height
	var low: float = collision_radius + 0.05
	var height: float = clampf(_pivot_height(), low, maxf(low, top - collision_radius - 0.05))
	return feet + Vector3.UP * height


## The orbit centre trails Henry: lag across the ground, softer lag in height.
func _follow_pivot(delta: float, pivot: Vector3) -> Vector3:
	if not _has_position:
		_pivot_smooth = pivot
		return pivot
	var flat: Vector2 = Vector2(_pivot_smooth.x, _pivot_smooth.z).lerp(Vector2(pivot.x, pivot.z), _damp(follow_speed, delta))
	var height: float = lerpf(_pivot_smooth.y, pivot.y, _damp(follow_speed_vertical, delta))
	_pivot_smooth = Vector3(flat.x, height, flat.y)
	return _pivot_smooth


## Crouch share from the capsule's height between its measured standing and crouch heights.
func _update_stance(delta: float) -> void:
	var goal: float = 0.0
	var span: float = metrics.capsule_height - metrics.crouch_capsule_height
	if _capsule != null and span > 0.0:
		goal = clampf((metrics.capsule_height - (_capsule.shape as CapsuleShape3D).height) / span, 0.0, 1.0)
	_crouch = goal if not _has_position else lerpf(_crouch, goal, _damp(stance_rate, delta))


## Height of the orbit pivot above the feet: by default Henry's shoulder joints, far enough
## under the eyes that a camera pressed to the shoulder stays out of the head.
func _pivot_height() -> float:
	var standing: float = lerpf(metrics.standing_shoulder, metrics.standing_shoulder_top, framing_pivot_share)
	var crouched: float = lerpf(metrics.crouch_shoulder, metrics.crouch_shoulder_top, framing_pivot_share)
	return lerpf(standing, crouched, _crouch)


func _capsule_radius() -> float:
	if _capsule == null:
		return metrics.capsule_radius
	return (_capsule.shape as CapsuleShape3D).radius


func _eye_height() -> float:
	return lerpf(metrics.standing_eye, metrics.crouch_eye, _crouch)


func _find_capsule() -> void:
	for child: Node in player.get_children():
		var shape := child as CollisionShape3D
		if shape != null and shape.shape is CapsuleShape3D:
			_capsule = shape
			var height: float = (shape.shape as CapsuleShape3D).height
			if not is_equal_approx(height, metrics.capsule_height):
				push_warning("TpsCamera: Henry's capsule is %.2f m, HenryMetrics says %.2f m; re-run measure_henry_metrics.gd" % [height, metrics.capsule_height])
			return


## Unit vector from the shoulder to the camera for a view yaw and pitch.
static func _back(yaw: float, pitch_deg: float) -> Vector3:
	var pitch: float = deg_to_rad(pitch_deg)
	return Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch))


func _look_up_scale(pitch_deg: float) -> float:
	if pitch_deg <= 0.0:
		return 1.0
	return lerpf(1.0, look_up_distance_scale, smoothstep(0.0, pitch_max_deg, pitch_deg))


## Copies tunables into the helpers, so inspector edits apply while running.
func _sync_helpers() -> void:
	_probe.radius = collision_radius
	_probe.collision_mask = collision_mask
	_probe.thin_extent = thin_extent
	_auto.cooldown = auto_look_cooldown
	_auto.recenter_enabled = auto_recenter
	_auto.whisker_max_deg = whisker_max_deg
	_fader.occluder_transparency = occluder_transparency


func _player_speed_ratio() -> float:
	if player.has_method(&"get_locomotion_speed_ratio"):
		return float(player.call(&"get_locomotion_speed_ratio"))
	return 0.0


func _set_look_capture(active: bool) -> void:
	var input_systems: Node = get_node_or_null(^"/root/InputSystems")
	if input_systems != null and input_systems.has_method(&"set_look_capture"):
		input_systems.call(&"set_look_capture", active)


## Frame-rate independent exponential damping, as ADT's Smoothing.damp_factor.
static func _damp(rate: float, delta: float) -> float:
	return 1.0 - exp(-rate * delta)
