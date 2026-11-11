class_name TpsBoomProbe
extends RefCounted

## Casts for the camera boom. Wide static geometry stops it; thin props, moving
## bodies and characters let it through and are listed for fading instead.

## Pass-through colliders one cast may skip; past this the next one counts as a wall,
## so a long chain of props can never hide a wall behind it.
const MAX_PASSES: int = 16

## A collider whose second-largest extent is under this is thin: posts, planks, trunks.
var thin_extent: float = 0.6:
	set(value):
		if not is_equal_approx(value, thin_extent):
			_thin_by_owner.clear()
		thin_extent = value
var collision_mask: int = 0xFFFFFFFF
var radius: float = 0.2
## Colliders the casts of this frame passed through, by instance id.
var passed: Dictionary = {}

var _space: PhysicsDirectSpaceState3D
var _exclude: Array[RID] = []
var _shape := SphereShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()
var _thin_by_owner: Dictionary = {}


## Starts a frame of casts in `space`, never hitting `exclude`.
func begin(space: PhysicsDirectSpaceState3D, exclude: Array[RID]) -> void:
	_space = space
	_exclude = exclude
	passed.clear()


## Free length of a sphere sweep; with `pass_thin`, thin and moving colliders
## are skipped and recorded instead of stopping it.
func sweep(from: Vector3, motion: Vector3, pass_thin: bool = true) -> float:
	var length: float = motion.length()
	if _space == null or length < 0.001:
		return length
	var exclude: Array[RID] = _exclude.duplicate()
	for attempt: int in range(MAX_PASSES + 1):
		_prepare(from, motion, exclude)
		var result: PackedFloat32Array = _space.cast_motion(_query)
		if result.is_empty() or result[0] >= 1.0:
			return length
		if not pass_thin:
			return length * result[0]
		_prepare(from + motion * result[1], Vector3.ZERO, exclude)
		var info: Dictionary = _space.get_rest_info(_query)
		if info.is_empty():
			return length * result[0]
		var collider: Object = instance_from_id(info["collider_id"])
		if attempt == MAX_PASSES or not passes(collider, int(info["shape"])):
			return length * result[0]
		passed[info["collider_id"]] = collider
		exclude.append(info["rid"])
	return length


## Free length of a ray, skipping and recording pass-through colliders.
func ray(from: Vector3, motion: Vector3) -> float:
	var length: float = motion.length()
	if _space == null or length < 0.001:
		return length
	var exclude: Array[RID] = _exclude.duplicate()
	for attempt: int in range(MAX_PASSES + 1):
		var query := PhysicsRayQueryParameters3D.create(from, from + motion, collision_mask, exclude)
		var hit: Dictionary = _space.intersect_ray(query)
		if hit.is_empty():
			return length
		if attempt == MAX_PASSES or not passes(hit["collider"], int(hit["shape"])):
			return from.distance_to(hit["position"])
		passed[hit["collider_id"]] = hit["collider"]
		exclude.append(hit["rid"])
	return length


## True if the sphere at `point` overlaps a collider that stops the boom; thin
## ones it overlaps are only recorded, so they fade and never move the camera.
func overlaps(point: Vector3) -> bool:
	if _space == null:
		return false
	_prepare(point, Vector3.ZERO, _exclude)
	var blocked: bool = false
	for hit: Dictionary in _space.intersect_shape(_query, MAX_PASSES):
		if passes(hit["collider"], int(hit["shape"])):
			passed[hit["collider_id"]] = hit["collider"]
		else:
			blocked = true
	return blocked


## Characters, moving bodies and thin colliders do not hold the boom back.
func passes(collider: Object, shape_index: int) -> bool:
	if collider is CharacterBody3D:
		return true
	if collider is RigidBody3D and not (collider as RigidBody3D).freeze:
		return true
	var body := collider as CollisionObject3D
	if body == null:
		return false
	var owner_id: int = body.shape_find_owner(shape_index)
	var key: String = "%d:%d" % [body.get_instance_id(), owner_id]
	if not _thin_by_owner.has(key):
		## Streamed chunks come and go; a bounded cache never holds stale bodies for long.
		if _thin_by_owner.size() > 4096:
			_thin_by_owner.clear()
		_thin_by_owner[key] = _is_thin(body, owner_id)
	return _thin_by_owner[key]


func _is_thin(body: CollisionObject3D, owner_id: int) -> bool:
	if body.shape_owner_get_shape_count(owner_id) == 0:
		return false
	var shape: Shape3D = body.shape_owner_get_shape(owner_id, 0)
	var size: Vector3 = _shape_size(shape)
	var owner_node := body.shape_owner_get_owner(owner_id) as Node3D
	if owner_node != null:
		size *= owner_node.global_basis.get_scale().abs()
	var sorted: Array[float] = [size.x, size.y, size.z]
	sorted.sort()
	return sorted[1] < thin_extent


## Local extents of a shape; unbounded or unknown shapes read as huge.
func _shape_size(shape: Shape3D) -> Vector3:
	if shape is BoxShape3D:
		return (shape as BoxShape3D).size
	if shape is SphereShape3D:
		return Vector3.ONE * (shape as SphereShape3D).radius * 2.0
	if shape is CylinderShape3D:
		var cylinder := shape as CylinderShape3D
		return Vector3(cylinder.radius * 2.0, cylinder.height, cylinder.radius * 2.0)
	if shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		return Vector3(capsule.radius * 2.0, capsule.height, capsule.radius * 2.0)
	if shape is ConvexPolygonShape3D:
		return _points_size((shape as ConvexPolygonShape3D).points)
	if shape is ConcavePolygonShape3D:
		return _points_size((shape as ConcavePolygonShape3D).get_faces())
	return Vector3.ONE * INF


static func _points_size(points: PackedVector3Array) -> Vector3:
	if points.is_empty():
		return Vector3.ONE * INF
	var box := AABB(points[0], Vector3.ZERO)
	for point: Vector3 in points:
		box = box.expand(point)
	return box.size


func _prepare(at: Vector3, motion: Vector3, exclude: Array[RID]) -> void:
	_shape.radius = radius
	_query.shape = _shape
	_query.transform = Transform3D(Basis.IDENTITY, at)
	_query.motion = motion
	_query.collision_mask = collision_mask
	_query.collide_with_areas = false
	_query.exclude = exclude
