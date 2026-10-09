class_name PickupAffordance
extends RefCounted

## Cheap geometric gate for a pickup: a body spot Henry can walk to in a straight
## line and stand in, from which the item lies inside his arm envelope.
## Hand choice, IK and clips are presentation and never decide validity.

## Body rings around the contact, metres from it; nearest first.
const RING_DISTANCES: Array[float] = [0.55, 0.65, 0.75, 0.85, 0.95]
const DIRECTIONS: int = 12
## Highest floor step a straight scripted walk climbs, metres.
const MAX_STEP: float = 0.35
## Steepest floor Henry may stand on, as the up component of its normal.
const MIN_FLOOR_UP: float = 0.75
## Context only: a surface this close below the focus point counts as the item's support.
const SUPPORT_DEPTH: float = 0.6
## Physics queries keep this clearance from the floor and from grazed walls, metres.
const SKIN: float = 0.03
## Stances the envelope may use, as pelvis drop below standing (m) and hip hinge
## limit (deg): stand, crouch, kneel, deep squat for an item at the toes.
const STANCES: Array[Vector2] = [Vector2(0.0, 60.0), Vector2(0.25, 65.0), Vector2(0.5, 70.0), Vector2(0.6, 80.0)]
const HINGE_STEPS: int = 4
## UAL rest measurements, relative to the feet, used when Henry has no rig.
const DEFAULT_PROFILE: Dictionary = {
	"shoulder_height": 1.441,
	"shoulder_half_width": 0.192,
	"shoulder_back": 0.065,
	"pelvis_height": 0.917,
	"arm_length": 0.627,
}
## Share of the arm's length the envelope uses; the rest is never stretched.
const MAX_EXTENSION: float = 0.95
## Before the floor is known, spots this far outside the envelope are skipped; it
## covers a full MAX_STEP of floor height change.
const PREFILTER_RATIO: float = 1.6

var valid: bool = false
var in_place: bool = false
var body_position: Vector3 = Vector3.ZERO
var body_yaw: float = 0.0
var contact: Vector3 = Vector3.ZERO
## Presentation hint for the reach clip: &"left" or &"right". Never a gate.
var preferred_hand: StringName = &""
var reach_ratio: float = INF
var reason: StringName = &""
## Context, not a gate: an item overhanging a bench edge is still taken.
var supported: bool = false


## Finds where Henry can stand to take the target, preferring his current side.
static func solve(body: CharacterBody3D, target: InteractiveArea, profile: Dictionary) -> PickupAffordance:
	var result := PickupAffordance.new()
	var capsule: Dictionary = capsule_of(body)
	var space: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	result.contact = target.get_focus_point(body.global_position)
	result.supported = _has_support(space, body, result.contact)
	var feet_y: float = body.global_position.y - float(capsule["center_above_feet"])
	var ratio: float = envelope_ratio(Vector3(body.global_position.x, feet_y, body.global_position.z), result.contact, profile)
	if ratio <= 1.0:
		result._accept(body.global_position, ratio)
		result.in_place = true
		return result
	var away: Vector3 = body.global_position - result.contact
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.BACK
	var candidates: Array = []
	for ring: float in RING_DISTANCES:
		for step: int in range(DIRECTIONS):
			var turn: float = TAU * float(step) / float(DIRECTIONS)
			var side: float = absf(wrapf(turn, -PI, PI))
			var spot: Vector3 = result.contact + away.rotated(Vector3.UP, turn) * ring
			spot.y = body.global_position.y
			## Prefer Henry's side and a short walk; a far ring costs a little more.
			candidates.append([body.global_position.distance_to(spot) + side * 0.6 + ring * 0.3, spot])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	result.reason = &"no_body_spot"
	for entry: Array in candidates:
		var spot: Vector3 = entry[1]
		## Pure arithmetic first: most spots fail the envelope before any physics query.
		if envelope_ratio(Vector3(spot.x, feet_y, spot.z), result.contact, profile) > PREFILTER_RATIO:
			result.reason = &"out_of_reach"
			continue
		var floor_y: float = _floor_at(space, body, spot, feet_y)
		if is_nan(floor_y):
			continue
		var stand: Vector3 = Vector3(spot.x, floor_y + float(capsule["center_above_feet"]), spot.z)
		ratio = envelope_ratio(Vector3(spot.x, floor_y, spot.z), result.contact, profile)
		if ratio > 1.0:
			result.reason = &"out_of_reach"
			continue
		if not _capsule_fits(space, body, capsule, stand):
			result.reason = &"body_blocked"
			continue
		if not _walk_is_clear(space, body, capsule, stand):
			result.reason = &"path_blocked"
			continue
		result._accept(stand, ratio)
		return result
	return result


## How far the contact sits inside Henry's arm envelope from feet at this spot,
## facing it: at most 1 is reachable by either arm in some stance and hip hinge.
static func envelope_ratio(feet: Vector3, point: Vector3, profile: Dictionary) -> float:
	var forward: Vector3 = point - feet
	forward.y = 0.0
	var reach: float = float(profile["arm_length"]) * MAX_EXTENSION
	forward = forward.normalized() if forward.length() > 0.001 else Vector3.FORWARD
	var right: Vector3 = forward.cross(Vector3.UP)
	var girdle: float = float(profile["shoulder_height"]) - float(profile["pelvis_height"])
	var best: float = INF
	for stance: Vector2 in STANCES:
		var pelvis_y: float = feet.y + float(profile["pelvis_height"]) - stance.x
		for step: int in range(HINGE_STEPS):
			var hinge: float = deg_to_rad(stance.y) * float(step) / float(HINGE_STEPS - 1)
			var shoulder_ahead: float = sin(hinge) * girdle - cos(hinge) * float(profile["shoulder_back"])
			var shoulder_y: float = pelvis_y + cos(hinge) * girdle
			for side: float in [-1.0, 1.0]:
				var shoulder: Vector3 = Vector3(feet.x, shoulder_y, feet.z) + forward * shoulder_ahead \
					+ right * side * float(profile["shoulder_half_width"])
				best = minf(best, shoulder.distance_to(point) / reach)
	return best


## Henry's capsule radius, height and centre height above the feet.
static func capsule_of(body: CharacterBody3D) -> Dictionary:
	var shape_node := body.get_node_or_null(^"Main_Collision") as CollisionShape3D
	if shape_node == null:
		for child: Node in body.get_children():
			if child is CollisionShape3D:
				shape_node = child
				break
	var capsule := shape_node.shape as CapsuleShape3D if shape_node != null else null
	var radius: float = capsule.radius if capsule != null else 0.5
	var height: float = capsule.height if capsule != null else 2.0
	var offset: float = shape_node.position.y if shape_node != null else 0.0
	return {"radius": radius, "height": height, "center_above_feet": height * 0.5 - offset, "offset": offset}


## Whether Henry, standing where he is now, still holds the solved spot.
func holds_from(body: CharacterBody3D, profile: Dictionary) -> bool:
	var capsule: Dictionary = capsule_of(body)
	var feet: Vector3 = body.global_position - Vector3.UP * float(capsule["center_above_feet"])
	return envelope_ratio(feet, contact, profile) <= 1.0


func _accept(stand: Vector3, ratio: float) -> void:
	valid = true
	reason = &""
	body_position = stand
	reach_ratio = ratio
	var to_contact: Vector3 = contact - stand
	body_yaw = atan2(-to_contact.x, -to_contact.z)
	var right: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, body_yaw).cross(Vector3.UP)
	preferred_hand = &"right" if to_contact.dot(right) >= 0.0 else &"left"


static func _has_support(space: PhysicsDirectSpaceState3D, body: CharacterBody3D, point: Vector3) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.05, point + Vector3.DOWN * SUPPORT_DEPTH)
	ray.exclude = [body.get_rid()]
	return not space.intersect_ray(ray).is_empty()


## Floor height under a body spot within a walkable step of the feet, or NAN.
static func _floor_at(space: PhysicsDirectSpaceState3D, body: CharacterBody3D, spot: Vector3, feet_y: float) -> float:
	var ray := PhysicsRayQueryParameters3D.create(Vector3(spot.x, feet_y + MAX_STEP + 0.4, spot.z),
		Vector3(spot.x, feet_y - MAX_STEP - 0.4, spot.z))
	ray.exclude = [body.get_rid()]
	var hit: Dictionary = space.intersect_ray(ray)
	if hit.is_empty() or (hit["normal"] as Vector3).y < MIN_FLOOR_UP:
		return NAN
	var floor_y: float = (hit["position"] as Vector3).y
	return floor_y if absf(floor_y - feet_y) <= MAX_STEP else NAN


static func _capsule_query(capsule: Dictionary, at: Vector3, body: CharacterBody3D) -> PhysicsShapeQueryParameters3D:
	var shape := CapsuleShape3D.new()
	shape.radius = float(capsule["radius"]) - SKIN
	shape.height = float(capsule["height"]) - SKIN * 2.0
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * (float(capsule["offset"]) + SKIN * 2.0))
	query.exclude = [body.get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return query


static func _capsule_fits(space: PhysicsDirectSpaceState3D, body: CharacterBody3D, capsule: Dictionary, at: Vector3) -> bool:
	return space.intersect_shape(_capsule_query(capsule, at, body), 1).is_empty()


## The straight line Player.move_to_position walks, swept with Henry's capsule.
static func _walk_is_clear(space: PhysicsDirectSpaceState3D, body: CharacterBody3D, capsule: Dictionary, to: Vector3) -> bool:
	var query := _capsule_query(capsule, body.global_position, body)
	var motion: Vector3 = to - body.global_position
	motion.y = maxf(motion.y, 0.0)
	query.motion = motion
	var fractions: PackedFloat32Array = space.cast_motion(query)
	return fractions.size() > 0 and fractions[0] >= 0.999
