class_name HingedDoor
extends InteractiveArea

## Kinematic hinged door: one angular degree of freedom, swinging inward only
## (towards the sign of open_angle_deg) unless swings_both_ways is set.
##
## The leaf keeps its authored StaticBody3D under the hinge, so Henry collides
## with the visible leaf. Hand pushes, body contacts, wind, damping, soft stops
## and F-driven swings all feed one angular velocity; nothing is a Tween or a
## RigidBody3D (a rigid leaf pressed against its frame explodes out of the joint).
##
## F depends on where Henry stands. Latched: from the push side he cracks it
## open, from the pull side he pulls it wide. Open: he swings it shut, pushing
## the face or pulling the handle, whichever the leaf moves towards, and it
## latches. Walking into an unlatched leaf, his hand plants and pushes it.

signal door_toggled(open: bool)
signal latch_changed(latched: bool)

const OPEN_KEY: String = "HOUSE_DOOR_OPEN"
const CLOSE_KEY: String = "HOUSE_DOOR_CLOSE"
const WEATHER_GROUP: StringName = &"weather_controller"
## Every door joins this group so Henry's hand can find the leaves around him.
const GROUP: StringName = &"hinged_doors"

@export_group("Door")
@export var door_hinge: Node3D
## Farthest swing from closed, degrees. Its sign is the way the leaf opens
## (positive swings towards the hinge's local -Z); that side is "inside".
@export_range(-140.0, 140.0, 1.0) var open_angle_deg: float = 105.0
## Saloon-style: swing to ±open_angle_deg. Off, the frame stops the leaf at 0.
@export var swings_both_ways: bool = false
@export var starts_open: bool = false
## Kept for scene compatibility. It controls the little lever feedback only.
@export_range(0.0, 1.0, 0.05) var hand_delay: float = 0.2
## Kept for older authored scenes; the leaf does not use a Tween.
@export_range(0.1, 1.5, 0.05) var swing_time: float = 0.45
## A shut damaged door still leaks around its frame, but much less than an open
## doorway. One multiplier drives both ThermalZone exposure and BreachDraft VFX.
@export_range(0.0, 1.0, 0.05) var closed_breach_multiplier: float = 0.05
@export var breach: ShelterBreach
@export var opening_size: Vector2 = Vector2(1.5, 2.25)
## Depth of the wall the frame sits in; Henry's traversal and the camera read it.
@export var wall_thickness_m: float = 0.2
@export var latch_audio: AudioStreamPlayer3D

@export_group("Hinge dynamics")
## Effective rotational inertia, not kilograms: higher builds speed slower.
@export_range(0.5, 12.0, 0.1) var angular_inertia: float = 1.8
## Viscous hinge friction in torque per rad/s; sets how far a pushed door coasts.
@export_range(0.0, 30.0, 0.1) var hinge_damping: float = 3.5
## Converts Henry's closing speed at a body collision into force on the leaf.
@export_range(0.0, 30.0, 0.1) var body_push_force_scale: float = 24.0
@export_range(20.0, 360.0, 1.0) var max_angular_speed_deg: float = 180.0
## Hinge stiction and rubbing, torque: a resting leaf ignores anything weaker
## (a breeze, a brush), and a moving one slows to a stop instead of creeping.
@export_range(0.0, 10.0, 0.05) var hinge_friction: float = 1.2
## The last degrees before the open limit only soak up speed: a door stop, not
## a spring, so a fully open door stays open.
@export_range(2.0, 25.0, 0.5) var soft_stop_zone_deg: float = 10.0
@export_range(0.0, 30.0, 0.5) var soft_stop_damping: float = 8.0
@export_range(0.0, 0.5, 0.01) var stop_restitution: float = 0.05
@export_range(0.0, 3.0, 0.05) var rest_velocity_deg: float = 0.25
## Body radius a swinging leaf stops short of when the blocker has no capsule, metres.
@export_range(0.1, 0.8, 0.01) var blocker_radius_m: float = 0.5
## Gap kept between the leaf and the blocker's capsule, metres.
@export_range(0.0, 0.2, 0.01) var blocker_margin_m: float = 0.04

@export_group("Latch / handle")
## Where F leaves a released door once it coasts to rest, degrees.
@export_range(5.0, 25.0, 0.5) var handle_crack_deg: float = 12.0
@export_range(1.0, 10.0, 0.5) var latch_angle_deg: float = 5.0
@export_range(0.5, 6.0, 0.25) var closed_threshold_deg: float = 2.0
@export_range(0.05, 0.35, 0.01) var handle_focus_radius: float = 0.18
## How far F pulls a latched door open from the pull side, degrees.
@export_range(30.0, 120.0, 1.0) var pull_open_deg: float = 85.0
## A leaf reaching the frame faster than this latches by itself, degrees/s.
@export_range(10.0, 360.0, 5.0) var slam_latch_speed_deg: float = 45.0

@export_group("F swing")
## Spring and damping of an F-driven swing: stiffer reaches its angle sooner.
@export_range(5.0, 200.0, 1.0) var drive_stiffness: float = 40.0
@export_range(0.0, 60.0, 0.5) var drive_damping: float = 10.0
## Longest an F-close keeps trying (it waits for Henry to step out of the way), s.
@export_range(0.5, 6.0, 0.1) var close_timeout_s: float = 3.0
## How long F drives a crack and a pull-open, seconds.
@export_range(0.2, 2.0, 0.05) var crack_time_s: float = 0.7
## A pull keeps opening this long, waiting while Henry steps out of its arc, s.
@export_range(0.3, 5.0, 0.05) var pull_time_s: float = 2.5
## Top speed of a pull towards Henry, degrees/s.
@export_range(20.0, 180.0, 5.0) var pull_speed_deg: float = 80.0

@export_group("Hand")
## Gap kept between the leaf face and a pushing palm, metres.
@export_range(0.0, 0.1, 0.005) var hand_clearance_m: float = 0.02
## Seconds Henry's hand stays on the leaf or handle after an F action.
@export_range(0.1, 1.5, 0.05) var hand_hold_s: float = 0.5
## Share of the leaf from the hinge a hand may push on; nearer the hinge it cannot.
@export_range(0.0, 0.8, 0.05) var hand_min_radius_share: float = 0.3

@export_group("Wind")
@export var weather_controller: WeatherController
## Scales v^2 pressure into a deliberately weak atmospheric torque.
@export_range(0.0, 0.03, 0.0005) var wind_torque_scale: float = 0.004

## The body a swinging leaf stops against; DoorPushComponent registers Henry.
static var blocker: CharacterBody3D

var current_angle_rad: float = 0.0
var angular_velocity: float = 0.0

var _leaf: MeshInstance3D
var _latched: bool = true
var _semantic_open: bool = false
var _pending_torque: float = 0.0
## F-driven swing: angle it springs to, until when, whether it latches on
## arrival, and whether it is a pull towards Henry (slower, he steps aside).
var _drive_target: float = 0.0
var _drive_until_ms: int = 0
var _drive_latch: bool = false
var _drive_pull: bool = false
## Hand constraint: the leaf angle that clears Henry's palm, the face he pushes
## from (+1/-1), how fast that angle moves, and the physics tick it was set on.
var _hand_need: float = 0.0
var _hand_side: float = 0.0
var _hand_rate: float = 0.0
var _hand_tick: int = -10
## Hand hold after F, in hinge space: palm point, face normal, and until when.
var _hold_point: Vector3 = Vector3.ZERO
var _hold_normal: Vector3 = Vector3.BACK
var _hold_until_ms: int = 0
## Capsule radius of the current blocker, cached per body.
var _radius_owner: int = 0
var _radius_cache: float = 0.5


func _ready() -> void:
	interaction_type = InteractionType.DOOR
	## The hand IK is the door action; the generic reach clip would root Henry.
	if player_animation_action == &"":
		player_animation_action = &"none"
	add_to_group(GROUP)
	add_to_group(PassageInfo.GROUP)
	_latched = not starts_open
	current_angle_rad = _open_sign() * deg_to_rad(minf(absf(open_angle_deg), 80.0)) if starts_open else 0.0
	angular_velocity = 0.0
	if door_hinge != null:
		_leaf = door_hinge.get_node_or_null(^"DoorLeaf") as MeshInstance3D
		if _leaf == null:
			_leaf = door_hinge.find_child("DoorLeaf", true, false) as MeshInstance3D
		_ensure_two_sided_handles()
		_apply_hinge_angle()
		_add_snow_blockers()
		StylizedEnvironmentMaterial.apply_to_tree(door_hinge)
	if breach != null:
		add_to_group(&"snow_doors")
		breach.boardable = false
		breach.closure = self
		breach.opening_width_m = opening_size.x
		breach.opening_height_m = opening_size.y
		breach.global_transform = global_transform * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	super()
	_semantic_open = is_open()
	_sync_breach_exposure()
	_refresh_prompt()
	call_deferred("_sync_breach")
	call_deferred("_resolve_weather_controller")


func is_open() -> bool:
	return absf(current_angle_rad) > deg_to_rad(closed_threshold_deg)


func is_latched() -> bool:
	return _latched


func get_current_angle_deg() -> float:
	return rad_to_deg(current_angle_rad)


func is_swinging() -> bool:
	return (
		not _latched
		and (
			absf(angular_velocity) > deg_to_rad(rest_velocity_deg)
			or absf(_pending_torque) > 0.001
		)
	)


func can_interact() -> bool:
	return super() and door_hinge != null


## The doorway as a passage for Henry and the camera; null while the leaf is latched.
## An open leaf stands at the hinge jamb and takes its thickness off the opening.
func get_passage_info() -> PassageInfo:
	if _latched or door_hinge == null:
		return null
	var frame: Transform3D = global_transform.orthonormalized()
	var info := PassageInfo.new()
	var axis: Vector3 = frame.basis.z
	axis.y = 0.0
	info.axis = axis.normalized() if axis.length_squared() > 1e-6 else Vector3.FORWARD
	info.center = frame.origin - Vector3.UP * opening_size.y * 0.5
	info.clear_width = opening_size.x
	if _leaf != null and is_open():
		var thickness: float = _half_thickness() * 2.0
		var across: Vector3 = frame.basis.x
		across.y = 0.0
		info.clear_width -= thickness
		info.center -= across.normalized() * signf(door_hinge.position.x) * thickness * 0.5
	info.clear_height = opening_size.y
	info.wall_thickness = wall_thickness_m
	info.authored = true
	info.source_id = get_instance_id()
	return info


func _on_interaction_performed() -> void:
	var henry: Vector3 = _henry_position()
	var side: float = side_of(henry)
	if _latched:
		_set_latched(false)
		## The way the leaf opens from Henry's side: away from him he cracks it and
		## walks it open; towards him he pulls it wide and steps out of its arc.
		var away: float = -side
		if swings_both_ways or is_equal_approx(away, _open_sign()):
			_hold_hand_on_handle(side)
			_drive(away * deg_to_rad(handle_crack_deg), crack_time_s, false, false)
		else:
			_hold_hand_on_handle(side, 0.3)
			var wide: float = _open_sign() * deg_to_rad(minf(pull_open_deg, absf(open_angle_deg)))
			_drive(wide, pull_time_s, false, true)
			_step_clear_of_arc(0.0, wide)
		_refresh_prompt()
		return
	if absf(current_angle_rad) <= deg_to_rad(latch_angle_deg):
		_hold_hand_on_handle(side)
		_set_latched(true)
		return
	## Swing it shut and latch. Moving away from Henry he pushes the face; towards
	## him he pulls the handle, and the leaf waits if he stands in its way.
	var toward_zero: float = -signf(current_angle_rad)
	_drive(0.0, close_timeout_s, true, false)
	if is_equal_approx(toward_zero, side):
		_hold_hand_on_handle(side, 0.3)
		_step_clear_of_arc(current_angle_rad, 0.0)
	else:
		_hold_hand_on_face(side, 0.7)


## Springs the leaf towards `target` for `seconds`; `latch` seats it at the frame.
func _drive(target: float, seconds: float, latch: bool, pull: bool) -> void:
	_drive_target = clampf(target, _limits().x, _limits().y)
	_drive_until_ms = Time.get_ticks_msec() + int(seconds * 1000.0)
	_drive_latch = latch
	_drive_pull = pull


func _driving() -> bool:
	return Time.get_ticks_msec() < _drive_until_ms


## True while F pulls the leaf towards Henry; his walk must not push it back.
func is_pulling() -> bool:
	return _driving() and _drive_pull


func _stop_drive() -> void:
	_drive_until_ms = 0
	_drive_latch = false
	_drive_pull = false


func _get_interaction_text() -> String:
	return "[%s] %s" % [_interact_key_label(), tr(OPEN_KEY if _latched else CLOSE_KEY)]


func _physics_process(delta: float) -> void:
	if door_hinge == null or delta <= 0.0:
		return
	if _latched:
		current_angle_rad = 0.0
		angular_velocity = 0.0
		_pending_torque = 0.0
		_apply_hinge_angle()
		return

	var before: float = current_angle_rad
	## Torque that would move the leaf, then the torque that only resists motion.
	var applied: float = _pending_torque + _wind_torque()
	_pending_torque = 0.0
	var driving: bool = _driving()
	var damping: float = hinge_damping + _soft_stop_damping()
	if driving:
		applied += (_drive_target - current_angle_rad) * drive_stiffness
		damping += drive_damping
	elif _drive_latch or _drive_pull:
		_stop_drive()
	## Stiction can park an F-close a degree short of the frame; it still latches.
	if driving and _drive_latch and absf(current_angle_rad) <= deg_to_rad(latch_angle_deg):
		_set_latched(true)
		return
	var hand_on: bool = Engine.get_physics_frames() - _hand_tick <= 1
	var resting: bool = absf(angular_velocity) < deg_to_rad(rest_velocity_deg)
	if resting and absf(applied) <= hinge_friction and not hand_on:
		angular_velocity = 0.0
		return
	var rub: float = signf(angular_velocity) if not resting else signf(applied)
	var torque: float = applied - rub * hinge_friction - angular_velocity * damping
	var was: float = angular_velocity
	angular_velocity += (torque / maxf(angular_inertia, 0.001)) * delta
	## Rubbing brings a leaf to rest; it never pushes it back the other way.
	if not resting and signf(angular_velocity) != signf(was) and absf(applied) <= hinge_friction:
		angular_velocity = 0.0
	var max_speed: float = deg_to_rad(max_angular_speed_deg)
	if driving and _drive_pull:
		max_speed = minf(max_speed, deg_to_rad(pull_speed_deg))
	angular_velocity = clampf(angular_velocity, -max_speed, max_speed)
	var next: float = current_angle_rad + angular_velocity * delta
	if hand_on:
		next = _keep_clear_of_hand(next)
	else:
		next = _stop_at_blocker(current_angle_rad, next)
	current_angle_rad = next
	if _hit_frame(before):
		return
	_enforce_angle_limits()

	if driving and _drive_latch:
		var crossed: bool = signf(before) != signf(current_angle_rad) and not is_zero_approx(before)
		if crossed or absf(current_angle_rad) <= deg_to_rad(latch_angle_deg):
			_set_latched(true)
			return

	_apply_hinge_angle()
	_sync_breach_exposure()
	_update_semantic_open()


## Production contact seam. Player.gd calls this only after move_and_slide(), so
## merely holding W near the door cannot create torque without a real collision.
static func apply_character_collisions(body: CharacterBody3D, attempted_velocity: Vector3) -> void:
	if body == null:
		return
	var seen: Dictionary = {}
	for index: int in range(body.get_slide_collision_count()):
		var collision: KinematicCollision3D = body.get_slide_collision(index)
		if collision == null:
			continue
		var door: HingedDoor = _door_from_collider(collision.get_collider())
		if door == null:
			continue
		var id: int = door.get_instance_id()
		if seen.has(id):
			continue
		seen[id] = true
		door.apply_body_contact(
			body,
			collision.get_position(),
			attempted_velocity,
			collision.get_normal()
		)


static func _door_from_collider(collider: Variant) -> HingedDoor:
	var node := collider as Node
	while node != null:
		if node is HingedDoor:
			return node as HingedDoor
		node = node.get_parent()
	return null


## Converts one actual CharacterBody contact into torque around the hinge.
func apply_body_contact(
		_body: CharacterBody3D,
		contact_point: Vector3,
		attempted_velocity: Vector3,
		collision_normal: Vector3
	) -> void:
	if _latched or door_hinge == null:
		return
	var normal: Vector3 = collision_normal
	normal.y = 0.0
	if normal.length_squared() < 0.0001:
		return
	normal = normal.normalized()
	var velocity_flat: Vector3 = attempted_velocity
	velocity_flat.y = 0.0
	var closing_speed: float = maxf(0.0, -velocity_flat.dot(normal))
	if closing_speed <= 0.01:
		return
	var force: Vector3 = -normal * closing_speed * body_push_force_scale
	var lever: Vector3 = contact_point - door_hinge.global_position
	lever.y = 0.0
	var axis: Vector3 = door_hinge.global_basis.y.normalized()
	_pending_torque += lever.cross(force).dot(axis)


## Deterministic seam for tests and authored environment impulses.
func apply_external_torque(torque: float) -> void:
	if not _latched:
		_pending_torque += torque


# --- Hand ---------------------------------------------------------------------

## +1 or -1: which face of the leaf a world point stands in front of.
func side_of(point: Vector3) -> float:
	var v: Vector2 = _to_plane(point)
	var delta: float = wrapf(atan2(v.y, v.x) - current_angle_rad, -PI, PI)
	return 1.0 if delta >= 0.0 else -1.0


## Where a flat ray from `origin` along `direction` meets the leaf face on `side`:
## {point, normal, distance, radius} or empty when it misses the pushable part.
func leaf_ray(origin: Vector3, direction: Vector3, side: float) -> Dictionary:
	if door_hinge == null or _leaf == null or _latched:
		return {}
	var frame: Transform3D = _frame()
	var o: Vector2 = _to_plane(origin)
	var dq: Vector3 = frame.basis.inverse() * direction
	var d := Vector2(dq.x, -dq.z)
	if d.length_squared() < 0.0001:
		return {}
	d = d.normalized()
	var u := Vector2(cos(current_angle_rad), sin(current_angle_rad))
	var n := Vector2(-u.y, u.x) * side
	if d.dot(n) >= -0.05:
		return {}
	var p: Vector2 = n * _half_thickness()
	var denom: float = d.x * u.y - d.y * u.x
	if absf(denom) < 0.05:
		return {}
	var w: Vector2 = p - o
	var distance: float = (w.x * u.y - w.y * u.x) / denom
	var radius: float = (w.x * d.y - w.y * d.x) / denom
	var span: Vector2 = _leaf_span()
	if distance <= 0.0 or radius < lerpf(span.x, span.y, hand_min_radius_share) or radius > span.y - 0.03:
		return {}
	var at: Vector2 = p + u * radius
	var rise: Vector2 = _leaf_height()
	var height: float = clampf((frame.affine_inverse() * origin).y, rise.x + 0.1, rise.y - 0.1)
	return {
		"point": frame * Vector3(at.x, height, -at.y),
		"normal": (frame.basis * Vector3(n.x, 0.0, -n.y)).normalized(),
		"distance": distance,
		"radius": radius,
	}


## A palm at `hand` pushing the `side` face: from the next tick the leaf stays
## clear of it and carries its speed on after the hand lets go.
func push_with_hand(hand: Vector3, side: float, delta: float) -> void:
	if _latched or door_hinge == null:
		return
	var v: Vector2 = _to_plane(hand)
	var r: float = v.length()
	var span: Vector2 = _leaf_span()
	if r < lerpf(span.x, span.y, hand_min_radius_share) or r > span.y + 0.05:
		return
	var phi: float = current_angle_rad + wrapf(atan2(v.y, v.x) - current_angle_rad, -PI, PI)
	var margin: float = (_half_thickness() + hand_clearance_m) / maxf(r, 0.1)
	var need: float = clampf(phi - side * margin, _limits().x, _limits().y)
	var tick: int = Engine.get_physics_frames()
	var rate: float = 0.0
	if tick - _hand_tick <= 1 and is_equal_approx(side, _hand_side) and delta > 0.0:
		rate = (need - _hand_need) / delta
	_hand_rate = lerpf(_hand_rate, rate, 0.5)
	_hand_need = need
	_hand_side = side
	_hand_tick = tick
	_stop_drive()


## Hand hold after an F action, in world space: {point, normal}, or empty.
func get_hand_hold() -> Dictionary:
	if door_hinge == null or Time.get_ticks_msec() > _hold_until_ms:
		return {}
	return {
		"point": door_hinge.global_transform * _hold_point,
		"normal": (door_hinge.global_basis * _hold_normal).normalized(),
	}


func _hold_hand_on_handle(side: float, seconds: float = -1.0) -> void:
	var handle: Node3D = _handle_on(side)
	if handle == null:
		_hold_hand_on_face(side, 0.85)
		return
	_hold_point = handle.position + Vector3(0.0, 0.0, -side * 0.03)
	_hold_normal = Vector3(0.0, 0.0, -side)
	_hold_until_ms = Time.get_ticks_msec() + int((hand_hold_s if seconds < 0.0 else seconds) * 1000.0)


func _hold_hand_on_face(side: float, share: float) -> void:
	var span: Vector2 = _leaf_span()
	_hold_point = Vector3(lerpf(span.x, span.y, share), 0.1, -side * (_half_thickness() + hand_clearance_m))
	_hold_normal = Vector3(0.0, 0.0, -side)
	_hold_until_ms = Time.get_ticks_msec() + int(hand_hold_s * 1000.0)


## Handle on the face that looks towards `side`; the side-s face is local -s·Z.
func _handle_on(side: float) -> Node3D:
	for handle_name: StringName in [&"HandleOutside", &"HandleInside"]:
		var handle := door_hinge.get_node_or_null(NodePath(handle_name)) as Node3D
		if handle != null and signf(handle.position.z) == -side:
			return handle
	return null


## The leaf never swings through the palm that pushes it, and keeps its speed.
func _keep_clear_of_hand(next: float) -> float:
	if (next - _hand_need) * _hand_side <= 0.0:
		return next
	var max_speed: float = deg_to_rad(max_angular_speed_deg)
	var rate: float = clampf(_hand_rate, -max_speed, max_speed)
	if _hand_side > 0.0:
		angular_velocity = minf(angular_velocity, rate)
	else:
		angular_velocity = maxf(angular_velocity, rate)
	return _hand_need


## A swinging leaf stops against Henry's body instead of passing through him.
func _stop_at_blocker(from: float, to: float) -> float:
	if not is_instance_valid(blocker) or is_equal_approx(from, to):
		return to
	var v: Vector2 = _to_plane(blocker.global_position)
	var r: float = v.length()
	var span: Vector2 = _leaf_span()
	var radius: float = _blocker_radius()
	if r > span.y + radius or r < 0.05:
		return to
	var half: float = asin(clampf(radius / r, 0.0, 1.0)) + _half_thickness() / r
	var gap: float = wrapf(atan2(v.y, v.x) - from, -PI, PI)
	var moving: float = signf(to - from)
	if signf(gap) != moving:
		return to
	if absf(gap) <= half:
		angular_velocity = 0.0
		return from
	var stop: float = from + gap - moving * half
	if (to - stop) * moving > 0.0:
		angular_velocity = 0.0
		return stop
	return to


## Hinge space with the leaf's swing removed: X along the closed leaf, Y up.
func _frame() -> Transform3D:
	var parent := door_hinge.get_parent() as Node3D
	var base: Transform3D = parent.global_transform if parent != null else Transform3D.IDENTITY
	return base * Transform3D(Basis.IDENTITY, door_hinge.position)


## A world point in the hinge plane: x along the closed leaf, y towards +angle.
func _to_plane(point: Vector3) -> Vector2:
	var q: Vector3 = _frame().affine_inverse() * point
	return Vector2(q.x, -q.z)


## Radius from the hinge where the leaf starts and ends, metres.
func _leaf_span() -> Vector2:
	if _leaf == null:
		return Vector2(0.0, opening_size.x)
	var bounds: AABB = _leaf.get_aabb()
	var start: float = _leaf.position.x + bounds.position.x
	return Vector2(maxf(start, 0.0), start + bounds.size.x)


## Bottom and top of the leaf in hinge space, metres.
func _leaf_height() -> Vector2:
	if _leaf == null:
		return Vector2(-opening_size.y * 0.5, opening_size.y * 0.5)
	var bounds: AABB = _leaf.get_aabb()
	return Vector2(_leaf.position.y + bounds.position.y, _leaf.position.y + bounds.end.y)


func _half_thickness() -> float:
	return _leaf.get_aabb().size.z * 0.5 if _leaf != null else 0.04


## Radius a swinging leaf keeps from the blocker: its capsule plus a margin.
func _blocker_radius() -> float:
	if not is_instance_valid(blocker):
		return blocker_radius_m + blocker_margin_m
	if blocker.get_instance_id() != _radius_owner:
		_radius_owner = blocker.get_instance_id()
		_radius_cache = blocker_radius_m
		for child: Node in blocker.get_children():
			var shape_node := child as CollisionShape3D
			if shape_node != null and not shape_node.disabled and shape_node.shape is CapsuleShape3D:
				_radius_cache = (shape_node.shape as CapsuleShape3D).radius * shape_node.global_basis.get_scale().x
				break
	return _radius_cache + blocker_margin_m


## A leaf swinging towards Henry from `from` to `to`: if he stands in the arc it
## sweeps, he takes the shortest step out of it and the leaf follows.
func _step_clear_of_arc(from: float, to: float) -> void:
	if not is_instance_valid(blocker) or not blocker.has_method(&"move_to_position"):
		return
	var v: Vector2 = _to_plane(blocker.global_position)
	var r: float = v.length()
	var radius: float = _blocker_radius()
	var clear: float = _leaf_span().y + radius + 0.06
	if r >= clear:
		return
	var phi: float = atan2(v.y, v.x)
	var pad: float = asin(clampf(radius / r, 0.0, 1.0)) if r > 0.01 else PI
	if phi < minf(from, to) - pad or phi > maxf(from, to) + pad:
		return
	## Shortest way out: away from the hinge past the leaf's tip, or sideways off
	## an edge of the arc he only overlaps.
	var middle: float = (from + to) * 0.5
	var step: Vector2 = (v / r if r > 0.05 else Vector2(cos(middle), sin(middle)))
	var length: float = clear - r
	var low: float = minf(from, to)
	var high: float = maxf(from, to)
	for edge: float in [low, high]:
		var off: float = wrapf(phi - edge, -PI, PI)
		var beyond: bool = (is_equal_approx(edge, high) and off > 0.0) or (is_equal_approx(edge, low) and off < 0.0)
		if not beyond or absf(off) >= PI * 0.5:
			continue
		var need: float = radius + 0.06 - r * sin(absf(off))
		if need > 0.0 and need < length:
			length = need
			step = Vector2(-sin(edge), cos(edge)) * signf(off)
	var at: Vector2 = v + step * length
	var target: Vector3 = _frame() * Vector3(at.x, 0.0, -at.y)
	target.y = blocker.global_position.y
	blocker.call(&"move_to_position", target)


func _henry_position() -> Vector3:
	if is_instance_valid(player_reference):
		return player_reference.global_position
	if is_instance_valid(blocker):
		return blocker.global_position
	return global_position + global_basis.z


# --- Forces -------------------------------------------------------------------

func _wind_torque() -> float:
	if _latched or not is_instance_valid(weather_controller) or door_hinge == null or _leaf == null:
		return 0.0
	var speed: float = maxf(weather_controller.get_wind_speed_mps(), 0.0)
	if speed < 0.1:
		return 0.0
	var wind: Vector3 = weather_controller.get_wind_direction()
	wind.y = 0.0
	if wind.length_squared() < 0.0001:
		return 0.0
	wind = wind.normalized()
	var normal: Vector3 = door_hinge.global_basis.z
	normal.y = 0.0
	if normal.length_squared() < 0.0001:
		return 0.0
	normal = normal.normalized()
	var incidence: float = wind.dot(normal)
	if absf(incidence) < 0.01:
		return 0.0
	var bounds: AABB = _leaf.get_aabb()
	var centre: Vector3 = _leaf.to_global(bounds.get_center())
	var lever: Vector3 = centre - door_hinge.global_position
	lever.y = 0.0
	var force: Vector3 = normal * incidence * speed * speed * wind_torque_scale
	return lever.cross(force).dot(door_hinge.global_basis.y.normalized())


## Extra damping in the last degrees before the open limit, moving outward only.
func _soft_stop_damping() -> float:
	var maximum: float = deg_to_rad(absf(open_angle_deg))
	var start: float = maximum - minf(deg_to_rad(soft_stop_zone_deg), maximum)
	if absf(current_angle_rad) <= start or angular_velocity * signf(current_angle_rad) <= 0.0:
		return 0.0
	return soft_stop_damping * (absf(current_angle_rad) - start) / maxf(maximum - start, 0.001)


func _enforce_angle_limits() -> void:
	var limits: Vector2 = _limits()
	if current_angle_rad > limits.y:
		current_angle_rad = limits.y
		if angular_velocity > 0.0:
			angular_velocity = -angular_velocity * stop_restitution
	elif current_angle_rad < limits.x:
		current_angle_rad = limits.x
		if angular_velocity < 0.0:
			angular_velocity = -angular_velocity * stop_restitution


## The frame stops a one-way leaf at closed; arriving fast enough it latches.
## Returns true when it latched.
func _hit_frame(before: float) -> bool:
	if swings_both_ways:
		return false
	var open_sign: float = _open_sign()
	if current_angle_rad * open_sign > 0.0:
		return false
	current_angle_rad = 0.0
	var speed: float = -angular_velocity * open_sign
	if before * open_sign > 0.0 and speed >= deg_to_rad(slam_latch_speed_deg):
		_set_latched(true)
		return true
	if speed > 0.0:
		angular_velocity = speed * stop_restitution * open_sign
	return false


## Lowest and highest leaf angle, radians.
func _limits() -> Vector2:
	var maximum: float = deg_to_rad(absf(open_angle_deg))
	if swings_both_ways:
		return Vector2(-maximum, maximum)
	return Vector2(0.0, maximum) if _open_sign() > 0.0 else Vector2(-maximum, 0.0)


func _open_sign() -> float:
	return -1.0 if open_angle_deg < 0.0 else 1.0


func _apply_hinge_angle() -> void:
	if door_hinge == null:
		return
	door_hinge.rotation.y = current_angle_rad
	if door_hinge.is_inside_tree():
		door_hinge.force_update_transform()


func _set_latched(value: bool) -> void:
	if _latched == value:
		return
	_latched = value
	_stop_drive()
	if _latched:
		current_angle_rad = 0.0
		angular_velocity = 0.0
		_pending_torque = 0.0
		_apply_hinge_angle()
		_sync_breach_exposure()
	_update_semantic_open()
	_refresh_prompt()
	_pulse_handles(_latched)
	if is_instance_valid(latch_audio):
		latch_audio.play()
	latch_changed.emit(_latched)


func _update_semantic_open() -> void:
	var now_open: bool = is_open()
	if now_open == _semantic_open:
		return
	_semantic_open = now_open
	_refresh_prompt()
	door_toggled.emit(_semantic_open)


func _resolve_weather_controller() -> void:
	if is_instance_valid(weather_controller) or not is_inside_tree():
		return
	weather_controller = get_tree().get_first_node_in_group(WEATHER_GROUP) as WeatherController


func set_weather_controller(controller: WeatherController) -> void:
	weather_controller = controller


## Small lever snap is the visual latch feedback.
func _pulse_handles(latched: bool) -> void:
	if door_hinge == null or not is_inside_tree():
		return
	for handle_name: StringName in [&"HandleOutside", &"HandleInside"]:
		var handle := door_hinge.get_node_or_null(NodePath(handle_name)) as Node3D
		if handle == null:
			continue
		var lever := handle.get_node_or_null(^"Lever") as Node3D
		if lever == null:
			continue
		var side: float = signf(handle.position.z)
		lever.rotation.z = deg_to_rad((10.0 if latched else -12.0) * side)
		var tween := create_tween()
		tween.tween_property(lever, ^"rotation:z", 0.0, maxf(hand_delay, 0.08)) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Focus sits on the handle nearest the observer, not on the large Area origin.
func get_focus_point(observer: Vector3) -> Vector3:
	return get_preferred_handle_position(observer)


func get_preferred_handle_position(from: Vector3) -> Vector3:
	if door_hinge == null:
		return global_position
	var outside := door_hinge.get_node_or_null(^"HandleOutside") as Node3D
	var inside := door_hinge.get_node_or_null(^"HandleInside") as Node3D
	if outside == null:
		return inside.global_position if inside != null else global_position
	if inside == null:
		return outside.global_position
	return outside.global_position if from.distance_squared_to(outside.global_position) <= from.distance_squared_to(inside.global_position) else inside.global_position


## Ray/sphere test around the actual near-side handle. InteractComponent uses this
## instead of accepting a ray anywhere on the large door interaction Area.
func get_handle_aim_distance(from: Vector3, direction: Vector3) -> float:
	if door_hinge == null or direction.length_squared() < 0.0001:
		return INF
	var ray: Vector3 = direction.normalized()
	var best: float = INF
	for handle_name: StringName in [&"HandleOutside", &"HandleInside"]:
		var handle := door_hinge.get_node_or_null(NodePath(handle_name)) as Node3D
		if handle == null:
			continue
		var offset: Vector3 = handle.global_position - from
		var distance_along: float = offset.dot(ray)
		if distance_along < 0.0:
			continue
		var closest: Vector3 = from + ray * distance_along
		if closest.distance_to(handle.global_position) <= handle_focus_radius:
			best = minf(best, distance_along)
	return best


## Save seam: a partly open, unlatched door is kept without physics nodes.
## Loaded angular speed is clamped so a load never spawns a slamming leaf.
func get_door_save_data() -> Dictionary:
	return {
		"angle_deg": rad_to_deg(current_angle_rad),
		"angular_velocity_deg": rad_to_deg(angular_velocity),
		"latched": _latched,
	}


func load_door_save_data(data: Dictionary) -> void:
	_latched = bool(data.get("latched", true))
	_stop_drive()
	current_angle_rad = clampf(deg_to_rad(float(data.get("angle_deg", 0.0))), _limits().x, _limits().y)
	var safe_speed: float = max_angular_speed_deg * 0.35
	angular_velocity = deg_to_rad(clampf(float(data.get("angular_velocity_deg", 0.0)), -safe_speed, safe_speed))
	if _latched:
		current_angle_rad = 0.0
		angular_velocity = 0.0
	_pending_torque = 0.0
	_apply_hinge_angle()
	_semantic_open = is_open()
	_sync_breach_exposure()
	_refresh_prompt()


func _sync_breach() -> void:
	_sync_breach_exposure()
	_refresh_prompt()


func _sync_breach_exposure() -> void:
	if breach != null and door_hinge != null:
		var aperture: float = 1.0 - clampf(cos(current_angle_rad), 0.0, 1.0)
		breach.set_exposure_multiplier(lerpf(closed_breach_multiplier, 1.0, aperture))


## Four non-overlapping strips subtract the projected leaf from the actual doorway.
func get_draft_regions() -> Array[AABB]:
	var result: Array[AABB] = []
	if breach == null or _leaf == null:
		return result
	var opening := AABB(Vector3(-opening_size.x * 0.5, -opening_size.y * 0.5, -0.075), Vector3(opening_size.x, opening_size.y, 0.01))
	var leaf_bounds: AABB = (breach.global_transform.affine_inverse() * _leaf.global_transform) * _leaf.get_aabb()
	var left: float = clampf(leaf_bounds.position.x, opening.position.x, opening.end.x)
	var right: float = clampf(leaf_bounds.end.x, left, opening.end.x)
	var bottom: float = clampf(leaf_bounds.position.y, opening.position.y, opening.end.y)
	var top: float = clampf(leaf_bounds.end.y, bottom, opening.end.y)
	_append_region(result, Vector3(opening.position.x, opening.position.y, opening.position.z), Vector3(left - opening.position.x, opening.size.y, opening.size.z))
	_append_region(result, Vector3(right, opening.position.y, opening.position.z), Vector3(opening.end.x - right, opening.size.y, opening.size.z))
	_append_region(result, Vector3(left, opening.position.y, opening.position.z), Vector3(right - left, bottom - opening.position.y, opening.size.z))
	_append_region(result, Vector3(left, top, opening.position.z), Vector3(right - left, opening.end.y - top, opening.size.z))
	return result


func _append_region(regions: Array[AABB], at: Vector3, size: Vector3) -> void:
	if size.x > 0.006 and size.y > 0.006:
		regions.append(AABB(at + Vector3(0.003, 0.003, 0.0), size - Vector3(0.006, 0.006, 0.0)))


func _add_snow_blockers() -> void:
	if _leaf == null or breach == null:
		return
	if not _leaf.has_node(^"SnowLeafCollider"):
		var collider := GPUParticlesCollisionBox3D.new()
		collider.name = "SnowLeafCollider"
		collider.size = _leaf.get_aabb().size
		collider.position = _leaf.get_aabb().get_center()
		_leaf.add_child(collider)
	if has_node(^"SnowFrame0"):
		return
	var frame_sizes: Array[Vector3] = [Vector3(0.12, opening_size.y + 0.12, 0.20), Vector3(0.12, opening_size.y + 0.12, 0.20), Vector3(opening_size.x, 0.12, 0.20)]
	var frame_positions: Array[Vector3] = [Vector3(-(opening_size.x + 0.12) * 0.5, 0.0, 0.0), Vector3((opening_size.x + 0.12) * 0.5, 0.0, 0.0), Vector3(0.0, (opening_size.y + 0.12) * 0.5, 0.0)]
	for index: int in range(3):
		var frame := GPUParticlesCollisionBox3D.new()
		frame.name = "SnowFrame%d" % index
		frame.size = frame_sizes[index]
		frame.position = frame_positions[index]
		add_child(frame)


func _refresh_prompt() -> void:
	set_item_name(tr(OPEN_KEY if _latched else CLOSE_KEY))
	var damaged_and_closed: bool = breach != null and not is_open() and not breach.is_boarded()
	set_description(tr("HOUSE_DOOR_DRAFTING") if damaged_and_closed else "")
	if info_label != null and info_label.visible:
		info_label.text = _get_interaction_text()


func _ensure_two_sided_handles() -> void:
	if door_hinge == null or _leaf == null or _leaf.mesh == null:
		return
	var bounds := _leaf.get_aabb()
	var free_edge_x: float = _leaf.position.x + bounds.position.x + bounds.size.x - 0.18
	var face_z: float = maxf(bounds.size.z * 0.5 + 0.025, 0.065)
	if not door_hinge.has_node(^"HandleOutside"):
		_make_handle_side(&"HandleOutside", free_edge_x, face_z)
	if not door_hinge.has_node(^"HandleInside"):
		_make_handle_side(&"HandleInside", free_edge_x, -face_z)


func _make_handle_side(node_name: StringName, x: float, z: float) -> void:
	var root := Node3D.new()
	root.name = node_name
	root.position = Vector3(x, 0.0, z)
	door_hinge.add_child(root)
	var brass := StylizedEnvironmentMaterial.make(
		Color(0.40, 0.31, 0.16),
		0.38,
		false,
		false,
		0.65
	)
	var plate := MeshInstance3D.new()
	plate.name = "Plate"
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(0.16, 0.28, 0.025)
	plate.mesh = plate_mesh
	plate.material_override = brass
	root.add_child(plate)
	var lever := MeshInstance3D.new()
	lever.name = "Lever"
	lever.position = Vector3(-0.11, 0.0, signf(z) * 0.035)
	var lever_mesh := BoxMesh.new()
	lever_mesh.size = Vector3(0.28, 0.055, 0.055)
	lever.mesh = lever_mesh
	lever.material_override = brass
	root.add_child(lever)


## Both snowfall layers and aperture drafts share the current leaf/frame transforms.
func apply_snow_barrier(material: ShaderMaterial) -> void:
	material.set_shader_parameter("snow_door_enabled", is_instance_valid(_leaf))
	if not is_instance_valid(_leaf):
		return
	var bounds: AABB = _leaf.get_aabb()
	material.set_shader_parameter("snow_leaf_inverse", _leaf.global_transform.affine_inverse())
	material.set_shader_parameter("snow_leaf_min", bounds.position)
	material.set_shader_parameter("snow_leaf_max", bounds.end)
	material.set_shader_parameter("snow_frame_inverse", global_transform.affine_inverse())
	material.set_shader_parameter("snow_opening_size", opening_size)
