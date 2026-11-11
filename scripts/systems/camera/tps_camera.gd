class_name TpsCamera
extends Camera3D

## Third-person over-the-shoulder camera: the direct rig. The camera stands behind the view and only the
## player turns the view. The guided rig it replaced is kept in archive/tps_camera_guided.

## Henry as measured from his loaded model by tools/runtime/measure_henry_metrics.gd.
const DEFAULT_METRICS: HenryMetrics = preload("res://data/characters/henry_metrics.tres")
const CAMERA_USER_SETTINGS: GDScript = preload("res://scripts/settings/camera_user_settings.gd")

@export var player: CharacterBody3D

@export_group("Direct rig")
## The shoulder offset as a share of shoulder_offset. It is asked for in full in any space; only walls clip it.
@export_range(0.5, 2.0, 0.05) var direct_side_scale: float = 1.4
## Shoulder offset per metre of boom, its floor and how fast it follows (1/s): 0.4 holds Henry a third of
## the way in from the left edge of a 16:9 frame at any distance; under 0.3 m his body reaches the centre.
@export var direct_side_per_metre: float = 0.4
@export var direct_side_min: float = 0.34
@export var direct_side_rate: float = 3.0
## It closes in at this rate (1/s) when a wall takes its room, and never past this many metres per metre of
## boom: there his head stands at the frame's edge.
@export var direct_side_in_rate: float = 16.0
@export var direct_side_edge: float = 0.7
## Boom lengths between which a close camera rises from his shoulder joints to his eye line, metres.
@export var direct_rise_lengths: Vector2 = Vector2(0.35, 0.9)
## A boom a wall shortened holds for this long after the wall clears, then eases out over this time, seconds.
@export var direct_out_hold: float = 0.35
@export var direct_out_time: float = 0.6
## The "camera behind Henry" key turns the view to his facing at this rate (1/s) and to this pitch; any mouse
## motion takes the view back at once. It is the only recentre on the direct rig, and only on that key.
@export var behind_rate: float = 9.0
@export var behind_pitch_deg: float = -10.0
## On the direct rig only colliders thinner than this fade; pillars and trunks over it turn the boom in
## front of them, eased by the feelers.
@export var direct_thin_extent: float = 0.25
## Henry starts to turn see-through with the camera this close to his body's axis, and is at direct_fade_max at the second, metres.
@export var direct_fade_distances: Vector2 = Vector2(0.36, 0.22)
## Most of Henry the camera may fade: he stays a ghost in frame, the view never reads as first person.
@export_range(0.0, 1.0, 0.05) var direct_fade_max: float = 0.8
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
## Seconds to ease toward a feeler's limit.
@export_range(0.01, 1.0, 0.01) var blend_in_time: float = 0.1
@export_flags_3d_physics var collision_mask: int = 0xFFFFFFFF

@export_group("Aim")
## Drawn into an aim (AimIntentCapability), the boom shortens to this share, on a spring of this
## frequency (Hz) and damping (under 1 overshoots a touch, so the push-in lands softly).
@export_range(0.4, 1.0, 0.05) var aim_boom_scale: float = 0.68
@export_range(0.5, 6.0, 0.1) var aim_spring_hz: float = 2.4
@export_range(0.2, 1.0, 0.05) var aim_spring_damping: float = 0.55
## The camera never sinks closer than this above the settled snow top under it, metres.
@export_range(0.05, 1.0, 0.05) var snow_clearance_m: float = 0.25

@export_group("Fade")
## Render layers of Henry's body; his parts near the camera dither out when it is inside his reach.
@export_flags_3d_render var body_layers: int = 16
## In an authored work frame Henry fades from the first distance to his eyes, full at the second; the
## second is also the closest the camera may stand to his eyes. The shader spares parts over a metre away.
@export var body_fade_start: float = 0.45
@export var body_fade_end: float = 0.2
## How see-through a thin occluder between camera and Henry becomes.
@export_range(0.0, 1.0, 0.05) var occluder_transparency: float = 0.7

@export_group("Work framing")
## How fast the view eases onto a workspace Henry kneels at, and back off it.
@export_range(0.5, 20.0, 0.5) var work_framing_rate: float = 3.0
## How far the mouse may orbit the view round a workspace: yaw and pitch, degrees. Yaw is
## locked: a sideways orbit brings the eye into Henry's head and fades his body out.
@export var work_look_limit_deg: Vector2 = Vector2(0.0, 12.0)

## 0..1 unease that widens the breathing sway; free for survival state to drive.
var tension: float = 0.0

## The look: only the player and set_look() change it; WASD turns by its yaw.
var _yaw: float = 0.0
var _pitch_deg: float = -12.0
## Breathing sway last added to the drawn pitch; gameplay rays take it back out.
var _sway_deg: float = 0.0
## Henry's interpolated transform for this rendered frame.
var _target := Transform3D.IDENTITY
var _openness: float = 1.0
var _boom: float = 3.0
## Crouch share of the framing: 0 standing, 1 crouched.
var _crouch: float = 0.0
var _has_position: bool = false
var _lean: float = 0.0
var _noise := FastNoiseLite.new()
var _noise_time: float = 0.0
var _shoulder := TpsShoulderState.new()
var _probe := TpsBoomProbe.new()
var _fader := TpsCameraFader.new()
var _capsule: CollisionShape3D
var _input_systems: InputSystemsService
var _user_mouse_sensitivity_multiplier: float = 1.0
var _user_stick_sensitivity_multiplier: float = 1.0
var _user_distance_scale: float = 1.0
var _user_fov_offset: float = 0.0
var _user_left_shoulder: bool = false
var _user_invert_y: bool = false
var _last_eye_distance: float = INF
## Shoulder offset and rise toward the eye line in use, eased, metres.
var _direct_side: float = 0.0
var _direct_rise: float = 0.0
var _behind_active: bool = false
var _behind_yaw: float = 0.0
var _aim: float = 0.0
var _aim_speed: float = 0.0
## Lateral shoulder offset asked for this frame, before walls (for traces).
var _last_side: float = 0.0
## The rig's behaviours, working on one shared frame.
var _frame := TpsRigFrame.new()
var _rig_follow: TpsRigFollow
var _rig_collision: TpsRigCollision
var _rig_work: TpsRigWork


func _init() -> void:
	_rig_follow = TpsRigFollow.new(self)
	_rig_collision = TpsRigCollision.new(self)
	_rig_work = TpsRigWork.new(self)


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
	_input_systems = get_node_or_null(^"/root/InputSystems") as InputSystemsService
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
	_user_stick_sensitivity_multiplier = float(values["stick_sensitivity_multiplier"])
	_user_distance_scale = float(values["distance_scale"])
	## The player's lens rides on the authored one.
	fov += float(values["fov_offset_deg"]) - _user_fov_offset
	_user_fov_offset = float(values["fov_offset_deg"])
	## A default, not a lock: it moves the camera only when the choice itself changes.
	if bool(values["left_shoulder"]) != _user_left_shoulder:
		_user_left_shoulder = bool(values["left_shoulder"])
		if _shoulder.is_right() == _user_left_shoulder:
			_shoulder.toggle()


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
	_apply_look_input()
	_apply_lean_and_shoulder_input(delta)
	_probe.begin(get_world_3d().direct_space_state, [player.get_rid()])
	_openness = measure_openness()
	var wanted: float = get_target_distance()
	var rate: float = close_in_rate if wanted < _boom else open_out_rate
	_boom = wanted if not _has_position else lerpf(_boom, wanted, damp(rate, delta))
	_update_rig(delta)


## The look's yaw in radians, the one WASD is turned by.
func get_yaw() -> float:
	return _yaw


## Yaw the camera looks along. The same as get_yaw(): nothing but the player turns the view.
func get_view_yaw() -> float:
	return _yaw


func get_view_pitch_deg() -> float:
	return _pitch_deg


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


## Aims the camera directly, for spawn and tests.
func set_look(yaw: float, pitch_deg: float) -> void:
	_yaw = yaw
	_pitch_deg = clampf(pitch_deg, pitch_min_deg, pitch_max_deg)


## Drops all follow and collision memory; the next frame starts on the goal.
func snap_to_target() -> void:
	_has_position = false
	_rig_collision.reset()
	_rig_follow.reset()
	_last_eye_distance = INF


## Frames a workspace Henry kneels at: the view eases to `eye` looking at `focus` (world),
## the mouse orbits it a little, and walls between Henry and the eye shorten the boom.
func set_work_framing(focus: Vector3, eye: Vector3) -> void:
	_rig_work.set_framing(focus, eye, Vector2(_yaw, _pitch_deg))


## Hands the view back to the follow rig; it eases there at work_framing_rate.
func clear_work_framing() -> void:
	_rig_work.clear()


## 0 following Henry, 1 fully on the workspace framing.
func get_work_framing_blend() -> float:
	return _rig_work.get_blend()


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
	return get_feet_position() + Vector3.UP * _eye_height()


## The look's pitch in degrees.
func get_control_pitch_deg() -> float:
	return _pitch_deg


## The cast helper the rig's behaviours share, set up for this frame.
func get_probe() -> TpsBoomProbe:
	return _probe


## False until the rig has placed the camera once since the last snap.
func is_placed() -> bool:
	return _has_position


## Camera-to-eyes distance the last frame ended at.
func get_last_eye_distance() -> float:
	return _last_eye_distance


## The player's lean, -1..1.
func get_lean() -> float:
	return _lean


## Share of the wanted boom the walls left last frame.
func get_boom_share() -> float:
	return _rig_collision.get_boom_share()


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


## One frame of the rig: orbit = view, walls shorten the boom (Lyra's blend) and clip the shoulder.
## Nothing here turns, lifts or tilts the view.
func _update_rig(delta: float) -> void:
	var frame: TpsRigFrame = _frame
	frame.delta = delta
	_rig_follow.apply(frame, _player_speed_ratio())
	frame.pivot += Vector3.UP * get_pivot_height()
	frame.safe = _safe_origin()
	_turn_behind(delta)
	frame.view_yaw = _yaw
	frame.view_pitch = _pitch_deg
	frame.orbit_yaw = _yaw
	frame.orbit_pitch = _pitch_deg
	_update_aim(delta)
	frame.want = (_boom + _rig_follow.get_pullback()) * _look_up_scale(frame.view_pitch) * lerpf(1.0, aim_boom_scale, _aim) * _user_distance_scale
	## The shoulder is never squeezed toward the centre: Henry stands left of the view's centre in any space
	## and the centre stays clear of him. Walls clip the offset (the shoulder sweep).
	## It follows the boom's own length (last frame's, eased, so it cannot feed itself): the same share of
	## the screen at 3 m and at half a metre, never so little that his body covers the centre.
	var behind: float = _rig_collision.get_boom_share() * frame.want
	frame.right = Vector3(cos(frame.orbit_yaw), 0.0, -sin(frame.orbit_yaw))
	var handed: float = _shoulder.update(delta) / maxf(shoulder_offset, 0.001)
	## Close in, the offset stops where his head would leave the frame's edge: he stays in the picture.
	## Closer still (his back on a wall) it stays beside his head, never in it: he leaves the frame instead.
	var clear: float = body_fade_end + 0.05
	var floor_side: float = maxf(minf(direct_side_min, behind * direct_side_edge), sqrt(maxf(clear * clear - behind * behind, 0.0)))
	var side_goal: float = clampf(behind * direct_side_per_metre, floor_side, shoulder_offset * direct_side_scale)
	var room: float = _rig_collision.lateral_room(frame.safe, frame.pivot, frame.right, side_goal * signf(handed))
	if room < side_goal - 0.001:
		side_goal = maxf(room - 0.08, 0.0)
	var side_rate: float = direct_side_in_rate if side_goal < _direct_side else direct_side_rate
	_direct_side = lerpf(_direct_side, side_goal, damp(side_rate, delta)) if _has_position else side_goal
	frame.side = handed * _direct_side + _lean * lean_camera_offset
	## Close in, the camera also comes up from his shoulder joints toward his eye line, or his head leaves
	## the top of the frame. Added after the walls, by the same eased length, so it cannot feed back.
	var rise_goal: float = maxf(_eye_height() - get_pivot_height(), 0.0) * (1.0 - smoothstep(direct_rise_lengths.x, direct_rise_lengths.y, behind))
	_direct_rise = lerpf(_direct_rise, rise_goal, damp(direct_side_rate, delta)) if _has_position else rise_goal
	_last_side = frame.side
	frame.right = Vector3(cos(frame.orbit_yaw), 0.0, -sin(frame.orbit_yaw))
	frame.back = back_dir(frame.orbit_yaw, frame.orbit_pitch)
	_rig_collision.apply(frame)
	## Jammed on every side, the rise would stand the camera in his head: it is given back first.
	var eye: Vector3 = get_eye_position()
	var flat: float = Vector2(frame.camera.x - eye.x, frame.camera.z - eye.z).length()
	var keep: float = body_fade_end + 0.01
	var lowest: float = sqrt(maxf(keep * keep - flat * flat, 0.0))
	frame.camera.y += clampf(eye.y - lowest - frame.camera.y, 0.0, _direct_rise)
	_has_position = true
	_noise_time += delta
	_sway_deg = _noise.get_noise_1d(_noise_time * 20.0) * breathing_amplitude_deg * (0.4 + tension)
	h_offset = 0.0
	frame.view = Basis.from_euler(Vector3(deg_to_rad(frame.view_pitch + _sway_deg), frame.view_yaw, 0.0))
	_rig_work.apply(frame)
	frame.camera.y = maxf(frame.camera.y, snow_floor(frame.camera))
	global_position = frame.camera
	global_basis = frame.view
	_last_eye_distance = frame.camera.distance_to(get_eye_position())
	_update_fades(delta, frame.camera)


## Starts the turn of the "camera behind Henry" key, to where he faces now.
func turn_behind() -> void:
	if player == null:
		return
	_behind_yaw = player.global_rotation.y
	_behind_active = true


## The "camera behind Henry" key: the control yaw and pitch ease to his facing, then the key's turn is over.
func _turn_behind(delta: float) -> void:
	if not _behind_active:
		return
	var goal: float = _behind_yaw
	var step: float = damp(behind_rate, delta)
	_yaw = lerp_angle(_yaw, goal, step)
	_pitch_deg = lerpf(_pitch_deg, clampf(behind_pitch_deg, pitch_min_deg, pitch_max_deg), step)
	if absf(angle_difference(_yaw, goal)) < deg_to_rad(0.3) and absf(_pitch_deg - behind_pitch_deg) < 0.3:
		_behind_active = false


## The archived guided rig framed Henry aside in tight rooms and the HUD made way by this share.
## The direct rig holds him at one place in every space, so it is always 0.
func get_composition() -> float:
	return 0.0


## Framing state of the last frame, for tools/runtime/trace_camera_tight.gd.
func get_debug_state() -> Dictionary:
	return {"yaw": _yaw, "view_yaw": _yaw, "pitch": _pitch_deg, "openness": _openness, "boom": _boom,
		"side": _last_side, "shoulder_pct": _rig_collision.get_shoulder_share(), "body_fade": get_body_fade(),
		"eye_distance": _last_eye_distance, "lead": _rig_follow.get_lead(), "boom_share": _rig_collision.get_boom_share()}


## Tangents of the half view angles (x, y).
func half_tangents() -> Vector2:
	var aspect: float = get_viewport().get_visible_rect().size.aspect() if is_inside_tree() else 16.0 / 9.0
	var t: float = tan(deg_to_rad(fov) * 0.5)
	return Vector2(t * aspect, t) if keep_aspect == KEEP_HEIGHT else Vector2(t, t / maxf(aspect, 0.01))


## Lowest the camera may stand at point: the settled snow top plus clearance. The snow is not
## collision, so the boom's own sweep cannot keep the lens out of it.
func snow_floor(point: Vector3) -> float:
	var shell: SnowShell = SnowShell.active
	if not is_instance_valid(shell):
		return -INF
	return shell.field.get_snow_top(point.x, point.z) + snow_clearance_m


## Springs the aim push-in toward the player's aim weight.
func _update_aim(delta: float) -> void:
	var omega: float = TAU * aim_spring_hz
	var goal: float = AimIntentCapability.weight(player)
	## Stepped at 120 Hz at most: one explicit step over a hitched frame (80 ms and up) blew the spring up
	## and threw the boom out of the world.
	var steps: int = clampi(ceili(delta * 120.0), 1, 30)
	var step: float = minf(delta, 0.25) / float(steps)
	for i: int in range(steps):
		_aim_speed += (omega * omega * (goal - _aim) - 2.0 * aim_spring_damping * omega * _aim_speed) * step
		_aim += _aim_speed * step
	_aim = clampf(_aim, -0.25, 1.25)


## Half the field of view across or up the screen, degrees.
func half_fov_deg(horizontal: bool) -> float:
	var size: Vector2 = get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(16.0, 9.0)
	var aspect: float = size.x / maxf(size.y, 1.0)
	var half: float = deg_to_rad(fov * 0.5)
	if keep_aspect == Camera3D.KEEP_WIDTH:
		return rad_to_deg(half if horizontal else atan(tan(half) / aspect))
	return rad_to_deg(atan(tan(half) * aspect) if horizontal else half)


func _update_fades(delta: float, camera: Vector3) -> void:
	if not is_current():
		_fader.update_body(0.0, delta)
		_fader.update_occluders([], delta)
		return
	var eye: Vector3 = get_eye_position()
	## Beside him the camera sees past Henry: he fades only when it stands against his body, measured to
	## his axis from crown to knees. An authored work frame (the stove) fades by its distance to his eyes.
	var crown: Vector3 = eye + Vector3.UP * 0.12
	var near: Vector3 = Geometry3D.get_closest_point_to_segment(camera, crown, crown - Vector3.UP * 1.2)
	var close: float = clampf(inverse_lerp(direct_fade_distances.x, direct_fade_distances.y, camera.distance_to(near)), 0.0, direct_fade_max)
	var framed: float = clampf(inverse_lerp(body_fade_start, body_fade_end, camera.distance_to(eye)), 0.0, 1.0)
	var fade: float = lerpf(close, framed, get_work_framing_blend())
	_fader.update_body(fade, delta)
	_probe.passed.clear()
	_probe.overlaps(camera)
	_probe.ray(camera, eye - camera)
	_fader.update_occluders(_probe.passed.values(), delta)


## Mouse and stick look. Nothing slows or stops it but the pitch limits and a work frame.
func _apply_look_input() -> void:
	if _input_systems == null:
		return
	var look: Vector2 = _input_systems.consume_look_delta()
	## The stick comes as radians already turned; it shares the mouse's inversion, not its sensitivity.
	var stick: Vector2 = _input_systems.consume_stick_look() * _user_stick_sensitivity_multiplier
	if look.length_squared() + stick.length_squared() > 1e-12:
		_behind_active = false
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
	yaw_step -= stick.x * x_sign
	pitch_step -= rad_to_deg(stick.y) * y_sign
	_yaw = wrapf(_yaw + yaw_step, -PI, PI)
	_pitch_deg += pitch_step
	_pitch_deg = clampf(_pitch_deg, pitch_min_deg, pitch_max_deg)
	if _rig_work.is_active():
		var bounded: Vector2 = _rig_work.clamp_look(Vector2(_yaw, _pitch_deg))
		_yaw = bounded.x
		_pitch_deg = bounded.y


func _apply_lean_and_shoulder_input(delta: float) -> void:
	if _input_systems == null:
		return
	if _input_systems.consume_switch_shoulder():
		_shoulder.toggle()
	if _input_systems.consume_camera_behind():
		turn_behind()
	var axis: float = _input_systems.get_lean_axis()
	if axis != 0.0:
		_lean = clampf(_lean + axis * lean_rate * delta, -1.0, 1.0)
	else:
		_lean = lerpf(_lean, 0.0, damp(lean_return_rate, delta))


## Henry's feet from his capsule, so crouching keeps them on the ground.
func get_feet_position() -> Vector3:
	if _capsule == null:
		return _target.origin - Vector3.UP * origin_above_feet
	var capsule := _capsule.shape as CapsuleShape3D
	return _target.origin + Vector3.UP * (_capsule.position.y - capsule.height * 0.5)


## Lyra's safe point: on the capsule axis, below its top by the probe radius,
## so a cast from it never starts inside a wall or a low ceiling.
func _safe_origin() -> Vector3:
	var feet: Vector3 = get_feet_position()
	var top: float = lerpf(metrics.capsule_height, metrics.crouch_capsule_height, _crouch)
	if _capsule != null:
		top = (_capsule.shape as CapsuleShape3D).height
	var low: float = collision_radius + 0.05
	var height: float = clampf(get_pivot_height(), low, maxf(low, top - collision_radius - 0.05))
	return feet + Vector3.UP * height


## Crouch share from the capsule's height between its measured standing and crouch heights.
func _update_stance(delta: float) -> void:
	var goal: float = 0.0
	var span: float = metrics.capsule_height - metrics.crouch_capsule_height
	if _capsule != null and span > 0.0:
		goal = clampf((metrics.capsule_height - (_capsule.shape as CapsuleShape3D).height) / span, 0.0, 1.0)
	_crouch = goal if not _has_position else lerpf(_crouch, goal, damp(stance_rate, delta))


## Height of the orbit pivot above the feet: by default Henry's shoulder joints, far enough
## under the eyes that a camera pressed to the shoulder stays out of the head.
func get_pivot_height() -> float:
	var standing: float = lerpf(metrics.standing_shoulder, metrics.standing_shoulder_top, framing_pivot_share)
	var crouched: float = lerpf(metrics.crouch_shoulder, metrics.crouch_shoulder_top, framing_pivot_share)
	return lerpf(standing, crouched, _crouch)


func get_capsule_radius() -> float:
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
static func back_dir(yaw: float, pitch_deg: float) -> Vector3:
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
	_probe.thin_extent = direct_thin_extent
	_fader.occluder_transparency = occluder_transparency


func _player_speed_ratio() -> float:
	return float(LocomotionReadoutCapability.read(player, &"speed_ratio", 0.0))


func _set_look_capture(active: bool) -> void:
	var input_systems := get_node_or_null(^"/root/InputSystems") as InputSystemsService
	if input_systems != null:
		input_systems.set_look_capture(active)


## Frame-rate independent exponential damping, as ADT's Smoothing.damp_factor.
static func damp(rate: float, delta: float) -> float:
	return 1.0 - exp(-rate * delta)
