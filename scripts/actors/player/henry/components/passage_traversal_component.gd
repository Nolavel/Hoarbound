class_name PassageTraversalComponent
extends Node

## Narrow doorways are a short traversal, not free movement: walking at one engages it,
## and once over its threshold Henry is carried clear of the frame along its axis.

## Raycast guess for unmarked geometry: solid walls closer than this form a doorway, metres.
@export var max_gap: float = 1.9
## A wall this close ahead of Henry is searched for a door he is walking toward.
@export var look_ahead: float = 1.6
@export var scan_reach: float = 1.2
## Height of the scan above the feet: over sills and low walls, under lintels.
@export var scan_height: float = 1.3
## Wall depth a raycast guess assumes, metres.
@export var guessed_wall_thickness: float = 0.3

@export_group("Traversal")
## Walking at a passage engages it this far before its wall face, plus a lead at Henry's speed.
@export var approach_distance: float = 1.0
@export var approach_lead_time: float = 0.3
## How far beside the opening's edges the approach still counts, metres.
@export var approach_side_margin: float = 0.6
## A passage is known this much further out than it engages, so a camera leading
## Henry backwards can frame it before he gets there, metres.
@export var discovery_margin: float = 1.5
## Henry's centre this close to the wall face, with a key along the axis, commits the traversal.
@export var commit_margin: float = 0.15
## A committed traversal ends with Henry's capsule this far clear of the wall face, metres.
@export var exit_clearance: float = 0.3
## How hard Henry is pulled onto the centre line, per metre off it.
@export var centering_gain: float = 2.5
## Input more sideways than this share of its length does not push along the passage.
@export_range(0.0, 1.0, 0.05) var min_along_share: float = 0.25
## An approach with no key held lets go after this long, seconds.
@export var idle_release_time: float = 0.5
## A carried Henry who stops moving this long gives up the traversal, seconds.
@export var stall_time: float = 0.5

var body: CharacterBody3D

## The passage Henry is engaged with; kept while he stays in its zone.
var _info: PassageInfo
var _engaged: bool = false
## +1 or -1 along _info.axis while Henry is carried across; 0 otherwise.
var _commit: float = 0.0
## Movement direction steer() last received, and whether it may commit.
var _intent: Vector3 = Vector3.ZERO
var _may_commit: bool = false
var _idle: float = 0.0
var _stall: float = 0.0
var _saw_corridor: bool = false
var _providers: Array[Node] = []
var _providers_age: int = 0
var _probe := TpsBoomProbe.new()
var _capsule: CollisionShape3D


func _ready() -> void:
	if body == null:
		body = get_parent() as CharacterBody3D
	if body != null:
		for child: Node in body.get_children():
			var shape := child as CollisionShape3D
			if shape != null and shape.shape is CapsuleShape3D:
				_capsule = shape
				break


## Runs after Henry's move: finds the passage, then engages, commits or lets go of it.
func _physics_process(delta: float) -> void:
	if body == null or not body.is_inside_tree():
		return
	_probe.begin(body.get_world_3d().direct_space_state, [body.get_rid()])
	var feet: Vector3 = _feet()
	if _info != null and not _in_zone(_info, feet, 0.3):
		_drop()
	## An authored passage lives as long as its node; a freed marker or an unloaded chunk ends it.
	if _info != null and _info.authored and not is_instance_valid(instance_from_id(_info.source_id)):
		_drop()
	var fresh: PassageInfo = _authored_near(feet)
	_saw_corridor = false
	if fresh == null and (_info == null or not _info.authored):
		fresh = _guess(feet)
		if _saw_corridor and _info != null and not _info.authored:
			_drop()
	if fresh != null and (_info == null or not _engaged or fresh.same_passage(_info)):
		_info = fresh
	if _info == null:
		return
	_update_traversal(feet, delta)


## The passage Henry is engaged with, or null.
func get_passage() -> PassageInfo:
	return _info if _engaged else null


## The passage near Henry, engaged or not; null when there is none.
func get_nearby_passage() -> PassageInfo:
	return _info


func is_active() -> bool:
	return _engaged


## True while Henry is carried across; get_commit_sign() says which way along the axis.
func is_committed() -> bool:
	return _commit != 0.0


func get_commit_sign() -> float:
	return _commit


## Bends a movement direction through the passage. Committed, only the push along the
## axis counts and an empty one is carried on to the far side; elsewhere unchanged.
func steer(world_dir: Vector3, may_commit: bool = true) -> Vector3:
	var length: float = world_dir.length()
	_intent = world_dir
	_may_commit = may_commit
	if not may_commit:
		_commit = 0.0
	if _info == null or not _engaged:
		return world_dir
	var axis: Vector3 = _info.axis
	var along_in: float = world_dir.dot(axis)
	var pushes: bool = length > 0.01 and absf(along_in) >= min_along_share * length
	var feet: Vector3 = _feet()
	var centring: Vector3 = -_info.across() * _info.lateral_of(feet) * centering_gain
	if _commit != 0.0:
		if pushes and signf(along_in) != _commit:
			_commit = -_commit
		return (axis * _commit + centring).normalized() * (length if length > 0.01 else 1.0)
	if not pushes:
		return world_dir
	var face: float = _info.half_depth()
	var weight: float = 1.0 - smoothstep(face + 0.3, _exit_distance() + 0.2, absf(_info.along_of(feet)))
	var through: Vector3 = (axis * signf(along_in) + centring).normalized()
	return (world_dir / length).slerp(through, weight) * length


## Engages on a walk at the passage or inside its frame, commits over the threshold,
## and ends a carry once Henry is clear of the wall, or blocked.
func _update_traversal(feet: Vector3, delta: float) -> void:
	var along: float = _info.along_of(feet)
	var face: float = _info.half_depth()
	var radius: float = _radius()
	var inside: bool = absf(along) <= face + radius and absf(_info.lateral_of(feet)) <= _info.clear_width * 0.5
	var length: float = _intent.length()
	var along_in: float = _intent.dot(_info.axis)
	var pushes: bool = length > 0.01 and absf(along_in) >= min_along_share * length
	var toward: bool = pushes and (absf(along) <= face or signf(along_in) != signf(along))
	if inside or (toward and absf(along) <= _reach(_info)):
		_engaged = true
	if length > 0.01 or _commit != 0.0 or inside:
		_idle = 0.0
	else:
		_idle += delta
		if _idle >= idle_release_time:
			_engaged = false
	if _engaged and _commit == 0.0 and _may_commit and pushes and absf(along) <= face + commit_margin:
		_commit = signf(along_in)
	if _commit == 0.0:
		return
	var speed: float = Vector2(body.velocity.x, body.velocity.z).length()
	_stall = _stall + delta if length < 0.01 and speed < 0.05 else 0.0
	if along * _commit >= _exit_distance() or _stall >= stall_time:
		_commit = 0.0
		_stall = 0.0


func _drop() -> void:
	_info = null
	_engaged = false
	_commit = 0.0
	_idle = 0.0
	_stall = 0.0


## Past the wall face, Henry's capsule plus the clearance: where a carry ends.
func _exit_distance() -> float:
	return _info.half_depth() + _radius() + exit_clearance


## How far from the door plane a walk at it engages, at Henry's current speed.
func _reach(info: PassageInfo) -> float:
	var speed: float = Vector2(body.velocity.x, body.velocity.z).length() if body != null else 0.0
	return info.half_depth() + _radius() + approach_distance + speed * approach_lead_time


## Henry is near enough to know the passage: within its reach plus discovery_margin.
func _in_zone(info: PassageInfo, feet: Vector3, slack: float) -> bool:
	return absf(info.along_of(feet)) <= _reach(info) + discovery_margin + slack \
		and absf(info.lateral_of(feet)) <= info.clear_width * 0.5 + approach_side_margin + slack \
		and absf(feet.y - info.center.y) < 1.0


## The nearest authored passage Henry is near: a NarrowPassage or an open HingedDoor.
func _authored_near(feet: Vector3) -> PassageInfo:
	_providers_age -= 1
	if _providers_age <= 0:
		_providers = body.get_tree().get_nodes_in_group(PassageInfo.GROUP)
		_providers_age = 30
	var best: PassageInfo = null
	var best_along: float = INF
	for node: Node in _providers:
		if not is_instance_valid(node):
			continue
		var spot := node as Node3D
		if spot == null or not spot.has_method(&"get_passage_info"):
			continue
		if spot.global_position.distance_squared_to(feet) > 64.0:
			continue
		var info := spot.call(&"get_passage_info") as PassageInfo
		if info == null or not _in_zone(info, feet, 0.0):
			continue
		var along: float = absf(info.along_of(feet))
		if along < best_along:
			best = info
			best_along = along
	return best


## Unmarked geometry: a short gap between two solid walls at or ahead of Henry.
func _guess(feet: Vector3) -> PassageInfo:
	var forward := Vector3(body.velocity.x, 0.0, body.velocity.z)
	if forward.length() < 0.3:
		forward = -body.global_basis.z
		forward.y = 0.0
	forward = forward.normalized()
	var height: float = minf(scan_height, _top() - 0.1)
	var best: Array = _narrowest(feet + Vector3.UP * height)
	if best.is_empty():
		best = _door_ahead(feet, forward, height)
	if best.is_empty():
		return null
	if not _is_short(best[1], best[2], height):
		_saw_corridor = true
		return null
	var middle: Vector3 = best[1]
	var axis: Vector3 = best[2]
	## The same opening as last tick keeps its measured plane and depth.
	if _info != null and not _info.authored and absf(axis.dot(_info.axis)) > 0.95 \
			and absf(_info.lateral_of(middle)) < 0.15 and absf(_info.along_of(middle)) <= _info.half_depth() + 0.1:
		return _info
	var depth: Array = _jamb_depth(middle, axis)
	var info := PassageInfo.new()
	var plane: Vector3 = depth[0]
	info.center = Vector3(plane.x, feet.y, plane.z)
	info.axis = axis
	info.clear_width = best[0]
	info.clear_height = 0.3 + _probe.ray(info.center + Vector3.UP * 0.3, Vector3.UP * 3.0)
	info.wall_thickness = depth[1]
	return info


## Where the jambs either side of `middle` start and end along `axis`, in 5 cm steps:
## [midpoint of the jambs, their depth]. Depth falls back to guessed_wall_thickness.
func _jamb_depth(middle: Vector3, axis: Vector3) -> Array:
	var across: Vector3 = axis.cross(Vector3.UP).normalized()
	var ends: Array[float] = [0.0, 0.0]
	for i: int in range(2):
		var side: float = -1.0 if i == 0 else 1.0
		for step: int in range(1, 25):
			var point: Vector3 = middle + axis * side * float(step) * 0.05
			if _probe.ray(point, across * scan_reach) + _probe.ray(point, -across * scan_reach) > max_gap:
				break
			ends[i] = side * float(step) * 0.05
	var depth: float = ends[1] - ends[0] + 0.05
	if depth < 0.1:
		return [middle, guessed_wall_thickness]
	return [middle + axis * (ends[0] + ends[1]) * 0.5, depth]


## The narrowest pair of opposite rays at `point` that both meet solid walls
## within max_gap: [gap, midpoint, axis]. Empty if none does.
func _narrowest(point: Vector3) -> Array:
	var best: Array = []
	for step: int in range(6):
		var found: Array = _gap_at(point, deg_to_rad(30.0 * float(step)))
		if not found.is_empty() and (best.is_empty() or found[0] < best[0]):
			best = found
	if best.is_empty():
		return best
	## Refine the angle so the gap is the true width and the axis is square.
	var angle: float = best[3]
	for nudge: float in [-10.0, -5.0, 5.0, 10.0]:
		var found: Array = _gap_at(point, angle + deg_to_rad(nudge))
		if not found.is_empty() and found[0] < best[0]:
			best = found
	return best.slice(0, 3)


## Two jambs: opposite rays that both meet solid faces turned toward each other,
## so two hits on one wall through an opening never pass for a gap.
func _gap_at(point: Vector3, angle: float) -> Array:
	var dir := Vector3(sin(angle), 0.0, cos(angle))
	var hit_a: Dictionary = _solid_hit(point, point + dir * scan_reach)
	var hit_b: Dictionary = _solid_hit(point, point - dir * scan_reach)
	if hit_a.is_empty() or hit_b.is_empty():
		return []
	if (hit_a["normal"] as Vector3).dot(hit_b["normal"]) > -0.7:
		return []
	var a: float = point.distance_to(hit_a["position"])
	var b: float = point.distance_to(hit_b["position"])
	if a + b > max_gap:
		return []
	return [a + b, point + dir * (a - b) * 0.5, dir.cross(Vector3.UP).normalized(), angle]


## Henry walking at a wall: the nearest gap in it that reaches the floor and is
## door-wide, as [gap, midpoint, axis], refined from inside it. Empty if none.
func _door_ahead(feet: Vector3, forward: Vector3, height: float) -> Array:
	var origin: Vector3 = feet + Vector3.UP * height
	var hit: Dictionary = _solid_hit(origin, origin + forward * look_ahead)
	if hit.is_empty():
		return []
	var normal: Vector3 = hit["normal"]
	normal.y = 0.0
	if normal.length() < 0.5:
		return []
	normal = normal.normalized()
	var along: Vector3 = normal.cross(Vector3.UP).normalized()
	var face: Vector3 = hit["position"]
	var run_start: float = INF
	var runs: Array = []
	for step: int in range(-12, 13):
		var k: float = float(step) * 0.2
		var point: Vector3 = face + along * k + normal * 0.15
		var through: bool = _solid_hit(point, point - normal * 0.8).is_empty()
		if through and run_start == INF:
			run_start = k
		elif not through and run_start != INF:
			runs.append([run_start, k - 0.2])
			run_start = INF
	for run: Array in runs:
		var width: float = run[1] - run[0] + 0.2
		var middle: Vector3 = face + along * (run[0] + run[1]) * 0.5
		if width < 0.7 or width > max_gap:
			continue
		var low := Vector3(middle.x, feet.y + 0.4, middle.z) + normal * 0.15
		if not _solid_hit(low, low - normal * 0.8).is_empty():
			continue
		var inside: Array = _narrowest(Vector3(middle.x, origin.y, middle.z) - normal * 0.1)
		if not inside.is_empty():
			return inside
	return []


## The first collider that stops the boom between two points, as intersect_ray
## gives it; thin props are skipped. Empty if the line is clear.
func _solid_hit(from: Vector3, to: Vector3) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	var exclude: Array[RID] = [body.get_rid()]
	for attempt: int in range(TpsBoomProbe.MAX_PASSES + 1):
		var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, exclude))
		if hit.is_empty() or attempt == TpsBoomProbe.MAX_PASSES or not _probe.passes(hit["collider"], int(hit["shape"])):
			return hit
		exclude.append(hit["rid"])
	return {}


## A doorway opens up within a step on at least one side; a corridor does not.
func _is_short(center: Vector3, axis: Vector3, height: float) -> bool:
	var across: Vector3 = axis.cross(Vector3.UP).normalized()
	var reach: float = scan_reach * 1.5
	for side: float in [-1.0, 1.0]:
		var point := Vector3(center.x, _feet().y + height, center.z) + axis * side * 0.9
		var gap: float = _probe.ray(point, across * reach) + _probe.ray(point, -across * reach)
		if gap > max_gap * 1.3:
			return true
	return false


func _feet() -> Vector3:
	if _capsule == null:
		return body.global_position - Vector3.UP
	var capsule := _capsule.shape as CapsuleShape3D
	return body.global_position + Vector3.UP * (_capsule.position.y - capsule.height * 0.5)


func _top() -> float:
	if _capsule == null:
		return 2.0
	return (_capsule.shape as CapsuleShape3D).height


func _radius() -> float:
	if _capsule == null:
		return 0.5
	return (_capsule.shape as CapsuleShape3D).radius
