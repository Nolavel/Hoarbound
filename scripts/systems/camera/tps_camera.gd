class_name TpsCamera
extends Camera3D

## Third-person over-the-shoulder camera (ADT on-foot camera, rebuilt in #170).
## The mouse owns the control yaw (WASD); automatic turns only offset the view.

## Henry as measured from his loaded model by tools/runtime/measure_henry_metrics.gd.
const DEFAULT_METRICS: HenryMetrics = preload("res://data/characters/henry_metrics.tres")
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
## Seconds the camera lifted over the shoulder holds before it eases back down (Cinemachine
## Deoccluder's Smoothing Time). Off: in the 727 trace any hold kept the camera in Henry longer.
@export_range(0.0, 2.0, 0.05) var collision_hold_time: float = 0.0
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
@export_range(0.5, 30.0, 0.5) var recompose_in_rate: float = 4.0
@export_range(0.1, 20.0, 0.1) var recompose_out_rate: float = 1.5
## A new recompose goal must differ by this much before the shoulder moves again.
@export_range(0.0, 1.0, 0.05) var recompose_hysteresis: float = 0.35
## Eye distance at which the shoulder has fully given way to the centre line.
@export var recompose_full_distance: float = 0.8

@export_group("Body guard")
## The mouse stops turning the camera where it would come closer than this to Henry's eyes,
## and starts to resist at the soft distance; turning back out is always free (Nesky's soft wall).
@export var guard_eye_distance: float = 0.6
@export var guard_soft_distance: float = 0.8

@export_group("Composition")
## Tight-space framing (author's reference, Grossman's framing): Henry's eyes at this share
## of the screen width from the left, on the right shoulder; mirrored on the left one.
@export_range(0.05, 0.5, 0.01) var composition_eye_screen_x: float = 0.27
## Room all round Henry (measure_room, eased like the boom) below which the composition is full.
@export_range(0.05, 1.0, 0.05) var composition_open_share: float = 0.85
## Henry's eyes at this share of the screen height from the top in the composition: the
## camera rises along its own up axis by what that needs (Grossman's framing, vertical).
@export_range(0.2, 0.7, 0.01) var composition_eye_screen_y: float = 0.5
@export_range(0.1, 20.0, 0.1) var composition_rate: float = 1.5
## Above this composition the space is tight: no room search and no whiskers turn the view.
@export_range(0.0, 1.0, 0.05) var tight_auto_look_cutoff: float = 0.3

@export_group("Auto shoulder")
## With the player's shoulder side walled off and the other side free, the camera crosses to
## the other shoulder and comes back once its own side is clear (Sifu; a Borderlands 4 camera
## mod). Ghost Recon Breakpoint players turn theirs off, so it waits, holds and stays out of doorways.
@export var auto_shoulder_swap: bool = true
## Crosses when the player's side has less than swap_blocked_share of the shoulder offset free
## and the other side has at least swap_margin more; comes back above swap_free_share.
@export_range(0.0, 1.0, 0.05) var swap_blocked_share: float = 0.7
@export_range(0.0, 1.0, 0.05) var swap_margin: float = 0.35
@export_range(0.0, 1.0, 0.05) var swap_free_share: float = 0.85
## Seconds the player's side must stay walled off before crossing, and clear before coming back.
@export var swap_after_s: float = 0.4
@export var swap_back_after_s: float = 1.0
@export var swap_duration_s: float = 0.35

@export_group("Shoulder lift")
## Back to a wall or in a corner, the camera body climbs the orbit over Henry's shoulder and
## looks down at him instead of pressing into him (GoW / TLOU close quarters).
## How far the camera body climbs the orbit at full lift, and how far the view tilts down
## with it: less, so Henry sits low in the frame and the room ahead stays in view.
@export_range(0.0, 85.0, 1.0) var shoulder_lift_pitch_deg: float = 70.0
@export_range(0.0, 60.0, 1.0) var shoulder_lift_view_deg: float = 35.0
## Extra pivot height at full lift, capped by the ceiling, metres.
@export var shoulder_lift_rise: float = 0.3
## Over the shoulder, Henry's eyes stay at least this far inside the frame's lower edge, degrees.
@export_range(0.0, 30.0, 1.0) var shoulder_lift_frame_margin_deg: float = 12.0
## Free room behind Henry (level, along the view) at which the lift is full and at which it is gone.
@export var shoulder_lift_full_room: float = 0.3
@export var shoulder_lift_free_room: float = 1.0
@export_range(0.1, 20.0, 0.1) var shoulder_lift_in_rate: float = 3.0
@export_range(0.1, 20.0, 0.1) var shoulder_lift_out_rate: float = 1.5

@export_group("Fade")
## Render layers of Henry's body; his parts near the camera dither out when it is inside his reach.
@export_flags_3d_render var body_layers: int = 16
## Last resort after recomposing: fades from the first distance to his eyes, full at the
## second; the shader spares parts over a metre from the camera, so his legs stay.
## Henry fades only as an emergency, with the camera already at his head: the body guard
## keeps the mouse from turning it there (author: no see-through Henry in play).
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
var _openness: float = 1.0
## Room all round Henry, view-independent: drives the tight-space composition.
var _room: float = 1.0
var _boom: float = 3.0
## Crouch share of the framing: 0 standing, 1 crouched.
var _crouch: float = 0.0
## Shares of each boom leg left after walls, Lyra's DistBlockedPct.
## Seconds since the lift last climbed.
## Free length behind the shoulder this frame, before the margin.
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
var _last_eye_distance: float = INF
## FOV this camera added for a doorway; others may set the base FOV meanwhile.
var _fov_offset: float = 0.0
## Last rig inputs, for the body guard's prediction: pivot, orbit pitch lift (degrees).
var _last_pivot: Vector3 = Vector3.ZERO
var _last_lift_pitch: float = 0.0
## Lateral shoulder offset asked for this frame, before walls (for traces).
var _last_side: float = 0.0
## The rig's behaviours, run in this order on one frame (#240 stage 2).
var _frame := TpsRigFrame.new()
var _rig_follow: TpsRigFollow
var _rig_swap: TpsRigAutoSwap
var _rig_composition: TpsRigComposition
var _rig_passage: TpsRigPassage
var _rig_lift: TpsRigShoulderLift
var _rig_recompose: TpsRigRecompose
var _rig_collision: TpsRigCollision
var _rig_work: TpsRigWork


func _init() -> void:
	_rig_follow = TpsRigFollow.new(self)
	_rig_swap = TpsRigAutoSwap.new(self)
	_rig_composition = TpsRigComposition.new(self)
	_rig_passage = TpsRigPassage.new(self)
	_rig_lift = TpsRigShoulderLift.new(self)
	_rig_recompose = TpsRigRecompose.new(self)
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
	_rig_passage.update(delta)
	_auto.note_look(_apply_look_input(), delta)
	_apply_lean_and_shoulder_input(delta)
	_probe.begin(get_world_3d().direct_space_state, [player.get_rid()])
	_openness = measure_openness()
	_room = measure_room()
	var wanted: float = get_target_distance()
	var rate: float = close_in_rate if wanted < _boom else open_out_rate
	_boom = wanted if not _has_position else lerpf(_boom, wanted, damp(rate, delta))
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
	_rig_collision.reset()
	_rig_follow.reset()
	_rig_recompose.reset()
	_last_eye_distance = INF
	_rig_passage.reset()
	_clear_auto_look()


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


## 0 away from doorways, 1 with the frame fully closed round Henry in one.
func get_passage_blend() -> float:
	return _rig_passage.get_blend()


## Share of the shoulder given up for the centre line while the boom is cramped.
func get_recompose() -> float:
	return _rig_recompose.get_recompose()


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


## Seconds since the mouse last moved; automatic turns wait for the cooldown.
func get_look_idle_time() -> float:
	return _auto.get_idle_time()


## Control pitch in degrees, without the automatic offset.
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


## 0..1 free room all round Henry, from this frame's rods.
func get_room() -> float:
	return _room


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


## Casts the rods now and returns 0..1: free room all round Henry, evenly weighted, times
## room above him. It ignores the view, so turning the camera never changes the composition.
func measure_room() -> float:
	var origin: Vector3 = _safe_origin()
	var count: int = maxi(probe_count * 2, 4)
	var free_sum: float = 0.0
	for i: int in range(count):
		var angle: float = TAU * float(i) / float(count)
		free_sum += _probe.ray(origin, Vector3(sin(angle), 0.0, cos(angle)) * probe_length)
	var ceiling: float = _probe.ray(origin, Vector3.UP * ceiling_clearance)
	return clampf(free_sum / (probe_length * float(count)) * (ceiling / ceiling_clearance), 0.0, 1.0)


## One frame of the rig: the behaviours run in order on a shared TpsRigFrame, then the
## camera takes its result (#240 stage 2: the same arithmetic, split by owner).
func _update_rig(delta: float) -> void:
	var frame: TpsRigFrame = _frame
	frame.delta = delta
	var speed_ratio: float = _player_speed_ratio()
	_rig_follow.apply(frame, speed_ratio)
	frame.pivot += Vector3.UP * (get_pivot_height() + _rig_passage.rise() * _rig_passage.get_blend())
	frame.safe = _safe_origin()
	_update_auto_look(delta, frame.safe, speed_ratio)

	## The view is where the player looks; the orbit is where the camera body may stand.
	frame.view_yaw = get_view_yaw()
	frame.view_pitch = get_view_pitch_deg()
	frame.want = (_boom + _rig_follow.get_pullback()) * _look_up_scale(frame.view_pitch)
	var roominess: float = clampf(inverse_lerp(near_distance, far_distance, _boom), 0.0, 1.0)
	var shoulder_now: float = _shoulder.update(delta)
	shoulder_now *= _rig_swap.update(frame, shoulder_now)
	frame.side = shoulder_now * lerpf(tight_shoulder_fraction, 1.0, roominess)
	_rig_composition.frame_side(frame, shoulder_now)
	_rig_passage.orbit(frame)
	_rig_lift.apply(frame)
	_rig_composition.rise(frame)
	_last_pivot = frame.pivot
	_last_lift_pitch = frame.lift * shoulder_lift_pitch_deg
	frame.right = Vector3(cos(frame.orbit_yaw), 0.0, -sin(frame.orbit_yaw))
	frame.back = back_dir(frame.orbit_yaw, frame.orbit_pitch)
	_rig_recompose.apply(frame)
	_last_side = frame.side
	_apply_fov_offset(_rig_passage.fov() * _rig_passage.get_blend() + recompose_fov_deg * _rig_recompose.get_recompose())
	_rig_collision.apply(frame)
	_has_position = true

	_noise_time += delta
	_sway_deg = _noise.get_noise_1d(_noise_time * 20.0) * breathing_amplitude_deg * (0.4 + tension)
	h_offset = 0.0
	_rig_lift.keep_eyes(frame)
	frame.view = Basis.from_euler(Vector3(deg_to_rad(frame.view_pitch + _sway_deg), frame.view_yaw, 0.0))
	_rig_work.apply(frame)
	global_position = frame.camera
	global_basis = frame.view
	_last_eye_distance = frame.camera.distance_to(get_eye_position())
	_update_fades(delta, frame.camera)


## Distance from the eyes a camera would get on a boom from `shoulder`, walls applied,
## without touching any smoothing state.
func free_eye_distance(safe: Vector3, shoulder: Vector3, back: Vector3, want: float, eye: Vector3) -> float:
	var leg: Vector3 = shoulder - safe
	var start: Vector3 = shoulder
	if leg.length() > 0.001:
		start = safe + leg * clampf((_probe.sweep(safe, leg, false) - 0.05) / leg.length(), 0.0, 1.0)
	var room: float = _probe.sweep(start, back * want) - collision_surface_margin
	return (start + back * clampf(room, collision_min_distance, want)).distance_to(eye)


## 0 in the open, 1 with Henry framed low at the side of a tight space.
func get_composition() -> float:
	return _rig_composition.get_composition()


## Framing state of the last frame, for tools/runtime/trace_camera_tight.gd.
func get_debug_state() -> Dictionary:
	return {"yaw": _yaw, "view_yaw": get_view_yaw(), "pitch": get_view_pitch_deg(),
		"auto_yaw_deg": rad_to_deg(_auto_yaw), "auto_pitch_deg": _auto_pitch_deg,
		"openness": _openness, "room": _room, "boom": _boom, "side": _last_side, "shoulder_pct": _rig_collision.get_shoulder_share(),
		"recompose": _rig_recompose.get_recompose(), "composition": _rig_composition.get_composition(), "lift": _rig_lift.get_lift(),
		"body_fade": get_body_fade(), "swap": _rig_swap.get_swap(), "swap_own": _rig_swap.get_rooms().x, "swap_other": _rig_swap.get_rooms().y,
		"eye_distance": _last_eye_distance, "passage_blend": _rig_passage.get_blend(),
		"traversal": _rig_passage.traversal() if is_instance_valid(player) else 0.0}


## Share of a mouse turn to let through: 1 unless it takes the camera closer to Henry's eyes
## than guard_soft_distance, 0 at guard_eye_distance. Turning out of trouble is always free.
func _body_guard(yaw_step: float, pitch_step: float) -> float:
	if (yaw_step == 0.0 and pitch_step == 0.0) or not _has_position or not is_instance_valid(player):
		return 1.0
	if _last_eye_distance > guard_soft_distance + 0.4:
		return 1.0
	var yaw: float = get_view_yaw()
	var pitch: float = get_view_pitch_deg()
	var next: float = _predicted_eye_distance(yaw + yaw_step, pitch + pitch_step)
	if next >= guard_soft_distance or next >= _predicted_eye_distance(yaw, pitch) - 0.002:
		return 1.0
	return clampf(inverse_lerp(guard_eye_distance, guard_soft_distance, next), 0.0, 1.0)


## Eye distance the rig would reach looking along yaw / pitch, walls applied, from the last
## frame's pivot, shoulder offset and lift; stateless (same casts as recompose).
func _predicted_eye_distance(yaw: float, pitch_deg: float) -> float:
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var back: Vector3 = back_dir(yaw, clampf(pitch_deg - _last_lift_pitch, -85.0, pitch_max_deg))
	var want: float = (_boom + _rig_follow.get_pullback()) * _look_up_scale(pitch_deg)
	return free_eye_distance(_safe_origin(), _last_pivot + right * _last_side, back, want, get_eye_position())


## Tangents of the half view angles (x, y).
func half_tangents() -> Vector2:
	var aspect: float = get_viewport().get_visible_rect().size.aspect() if is_inside_tree() else 16.0 / 9.0
	var t: float = tan(deg_to_rad(fov) * 0.5)
	return Vector2(t * aspect, t) if keep_aspect == KEEP_HEIGHT else Vector2(t, t / maxf(aspect, 0.01))


## Sets how much FOV this camera adds over the base, capped at max_fov_deg.
func _apply_fov_offset(offset: float) -> void:
	var base: float = fov - _fov_offset
	offset = clampf(offset, 0.0, maxf(max_fov_deg - base, 0.0))
	fov = base + offset
	_fov_offset = offset


## Turns the player did not make, once the mouse rests: room search while Henry
## stands cramped, recentring and whiskers while he moves. They only offset the view.
## A doorway or a tight space owns the framing: any offset glides out and none starts
## (Nesky, GDC 2014: never push the camera against the player in closed spaces).
func _update_auto_look(delta: float, safe: Vector3, speed_ratio: float) -> void:
	if _rig_passage.get_blend() > 0.01 or _rig_composition.get_composition() > tight_auto_look_cutoff:
		_room_active = false
		_auto_yaw = move_toward(_auto_yaw, 0.0, deg_to_rad(_auto.room_rate_deg) * delta)
		_auto_pitch_deg = move_toward(_auto_pitch_deg, 0.0, _auto.room_rate_deg * delta)
		return
	if not _auto.is_active():
		return
	var want: float = _boom + _rig_follow.get_pullback()
	var goal := Vector2(_auto_yaw, _auto_pitch_deg)
	var rate_deg: float = _auto.room_rate_deg
	if speed_ratio < 0.05:
		_room_search_timer -= delta
		if not _room_active and _rig_collision.get_boom_room() < minf(room_comfort_distance, want) and _room_search_timer <= 0.0:
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


## Half the field of view across or up the screen, degrees.
func half_fov_deg(horizontal: bool) -> float:
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
		var back: Vector3 = back_dir(base_yaw + deg_to_rad(angle) * side, get_view_pitch_deg())
		room += _probe.ray(safe, back * want) / want
	return room / float(WHISKERS_DEG.size())


## Smallest turn of the view (yaw radians, pitch degrees) that gives the boom room,
## rising over Henry before swinging along a wall; zero if nothing is better.
func _find_room(safe: Vector3, want: float) -> Vector2:
	var need: float = minf(room_comfort_distance, want)
	var best_cost: float = INF
	var pick := Vector2.ZERO
	var current: float = _rig_collision.get_boom_room()
	for yaw_step: int in range(0, int(assist_max_yaw_deg) + 1, 15):
		for side: float in [1.0, -1.0]:
			if yaw_step == 0 and side < 0.0:
				continue
			for pitch_step: int in range(0, int(assist_max_pitch_deg) + 1, 15):
				if yaw_step == 0 and pitch_step == 0:
					continue
				var yaw: float = get_view_yaw() + deg_to_rad(float(yaw_step)) * side
				var pitch: float = clampf(get_view_pitch_deg() - float(pitch_step), pitch_min_deg, pitch_max_deg)
				var room: float = _probe.sweep(safe, back_dir(yaw, pitch) * want)
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
	yaw_step *= _body_guard(yaw_step, 0.0)
	pitch_step *= _body_guard(0.0, pitch_step)
	## In a doorway the mouse eases into a soft stop instead of a wall; back in is always free.
	var weight: float = _rig_passage.get_blend() * _rig_passage.traversal() if _rig_passage.get_framing().has_passage() else 0.0
	if weight > 0.001 and yaw_step != 0.0:
		var axis_yaw: float = _rig_passage.get_framing().axis_yaw()
		var turn: float = signf(yaw_step)
		var limits: Vector2 = _rig_passage.view_yaw_limits()
		var off: float = angle_difference(axis_yaw, _yaw) * turn
		var limit: float = limits.y if turn > 0.0 else limits.x
		off = _soft_step(off, absf(yaw_step), limit, deg_to_rad(passage_look_knee_deg), weight)
		_yaw = wrapf(axis_yaw + off * turn, -PI, PI)
	else:
		_yaw = wrapf(_yaw + yaw_step, -PI, PI)
	if weight > 0.001 and pitch_step != 0.0:
		var pitch_range: Vector2 = _rig_passage.pitch_range()
		if pitch_step < 0.0:
			_pitch_deg = -_soft_step(-_pitch_deg, -pitch_step, -pitch_range.x, passage_look_knee_deg, weight)
		else:
			_pitch_deg = _soft_step(_pitch_deg, pitch_step, pitch_range.y, passage_look_knee_deg, weight)
	else:
		_pitch_deg += pitch_step
	_pitch_deg = clampf(_pitch_deg, pitch_min_deg, pitch_max_deg)
	if _rig_work.is_active():
		var bounded: Vector2 = _rig_work.clamp_look(Vector2(_yaw, _pitch_deg))
		_yaw = bounded.x
		_pitch_deg = bounded.y
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
static func damp(rate: float, delta: float) -> float:
	return 1.0 - exp(-rate * delta)
