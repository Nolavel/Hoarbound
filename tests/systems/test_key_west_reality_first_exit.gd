extends SceneTree

## Reality First Exit: every template pickup keeps id, count and world_id, rests on a real surface out of
## walls with room for Henry beside it; the spawn stands clear of the bunker. Uses the generated chunks.

const CONTENT: String = "res://scenes/world/key_west/key_west_reality_content.tscn"
const TEMPLATE: String = "res://scenes/world/first_exit/first_exit_blockout.tscn"
const CHUNK_DIR: String = "res://scenes/world/key_west/generated/chunks"
const CHUNK_M: float = 512.0
const HENRY_RADIUS: float = 0.5
const HENRY_HEIGHT: float = 2.0
const MAX_LIFT_M: float = 0.6
const WALL_PROBE_M: float = 0.12
const STAND_RINGS: Array[float] = [0.9, 1.3, 1.8]

var _failures: int = 0
var _physics_start: int = 0
var _overlay: KeyWestRealityFirstExit
var _content: Node3D
var _space: PhysicsDirectSpaceState3D


func _initialize() -> void:
	_content = (load(CONTENT) as PackedScene).instantiate() as Node3D
	root.add_child(_content)
	_overlay = _content.get_node(^"FirstExitGameplay") as KeyWestRealityFirstExit


## Chunks load on the first frame, once the content's global transforms are valid.
func _load_chunks() -> void:
	var cells: Dictionary = {}
	for pickup: ItemPickup in _overlay.pickups:
		cells[_cell(pickup.global_position)] = true
	cells[_cell(_spawn().global_position)] = true
	for cell: Vector2i in cells:
		var path: String = CHUNK_DIR.path_join("Chunk_%d_%d.scn" % [cell.x, cell.y])
		if not ResourceLoader.exists(path):
			_check(false, "chunk %s is not generated" % path)
			continue
		var chunk: Node3D = KeyWestChunkGenerator.instantiate_assembled(path)
		var centre: Array = chunk.get_meta("centre_local")
		chunk.position = Vector3(float(centre[0]), 0.0, float(centre[1]))
		root.add_child(chunk)
	_physics_start = maxi(Engine.get_physics_frames(), 1)


func _process(_delta: float) -> bool:
	if _physics_start == 0:
		_load_chunks()
		return false
	if Engine.get_physics_frames() - _physics_start < 3:
		return false  # let the physics server register chunk collision
	_space = _content.get_world_3d().direct_space_state
	_check_audit()
	for pickup: ItemPickup in _overlay.pickups:
		_check_pickup(pickup)
	_check_spawn()
	if _failures > 0:
		push_error("reality first exit: %d check(s) failed" % _failures)
		quit(1)
	else:
		print("reality first exit: %d pickups placed; all checks passed" % _overlay.pickups.size())
		quit(0)
	return true


## Same pickups as the template: names, catalog ids, counts and persistence ids.
func _check_audit() -> void:
	var template: Node = (load(TEMPLATE) as PackedScene).instantiate()
	var expected: Dictionary = {}
	for child: Node in template.get_children():
		if child is ItemPickup:
			var p: ItemPickup = child as ItemPickup
			expected[String(p.name)] = [p.item_id, p.count, p.world_id]
	template.free()
	var seen: Dictionary = {}
	for p: ItemPickup in _overlay.pickups:
		var key: String = String(p.name)
		seen[key] = true
		_check(expected.has(key), "%s is not a template pickup" % key)
		if expected.has(key):
			_check(expected[key] == [p.item_id, p.count, p.world_id], "%s changed: %s -> %s" % [key, expected[key], [p.item_id, p.count, p.world_id]])
		_check(p.is_inside_tree(), "%s is not in the world" % key)
	for key: String in expected:
		_check(seen.has(key), "template pickup %s was dropped" % key)


func _check_pickup(p: ItemPickup) -> void:
	var at: Vector3 = p.global_position
	var floor_y: float = _floor_under(at)
	if is_nan(floor_y):
		_check(false, "%s at %s has no surface under it" % [p.name, at])
		return
	_check(at.y - floor_y >= -0.02 and at.y - floor_y <= MAX_LIFT_M, "%s at %s is %.2f m off the surface" % [p.name, at, at.y - floor_y])
	var probe: SphereShape3D = SphereShape3D.new()
	probe.radius = WALL_PROBE_M
	## The origin is the visual's resting point; the probe sits just above it.
	var body: Vector3 = at + Vector3.UP * (WALL_PROBE_M + 0.03)
	_check(_overlaps(probe, Transform3D(Basis.IDENTITY, body)).is_empty(), "%s at %s is inside a wall or prop" % [p.name, at])
	var box: AABB = _visual_box(p)
	if box.size != Vector3.ZERO:
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = (box.size - Vector3(0.04, 0.06, 0.04)).max(Vector3.ONE * 0.01)
		var xf: Transform3D = p.global_transform * Transform3D(Basis.IDENTITY, box.get_center() + Vector3.UP * 0.03)
		_check(_overlaps(shape, xf).is_empty(), "%s visual %s pokes into a wall or prop" % [p.name, box.size])
	_check(_stand_spot(at) != Vector3.INF, "%s at %s has no room for Henry beside it" % [p.name, at])


## Bounds of the pickup's visuals in its own space (Area3D children only, no labels/sprites).
func _visual_box(p: ItemPickup) -> AABB:
	var out: AABB = AABB()
	var first: bool = true
	for node: Node in p.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		var box: AABB = p.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


## A spot within reach where Henry's capsule fits and sees the item.
func _stand_spot(at: Vector3) -> Vector3:
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = HENRY_RADIUS
	capsule.height = HENRY_HEIGHT
	for ring: float in STAND_RINGS:
		for k: int in range(12):
			var dir: Vector3 = Vector3(cos(TAU * k / 12.0), 0.0, sin(TAU * k / 12.0))
			var foot: Vector3 = at + dir * ring
			var ground: float = _floor_under(Vector3(foot.x, at.y + 0.5, foot.z))
			if is_nan(ground) or absf(ground - (at.y - 0.3)) > 0.9:
				continue
			var centre: Vector3 = Vector3(foot.x, ground + HENRY_HEIGHT * 0.5 + 0.05, foot.z)
			if not _overlaps(capsule, Transform3D(Basis.IDENTITY, centre)).is_empty():
				continue
			if _ray(centre + Vector3.UP * 0.5, at + Vector3.UP * 0.1).is_empty():
				return centre
	return Vector3.INF


func _check_spawn() -> void:
	var spawn: Marker3D = _spawn()
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = HENRY_RADIUS
	capsule.height = HENRY_HEIGHT
	var at: Vector3 = spawn.global_position
	var ground: float = _floor_under(at + Vector3.UP)
	_check(not is_nan(ground) and absf(at.y - ground) < 0.4, "spawn %s is not on the ground (%.2f)" % [at, ground])
	_check(_overlaps(capsule, Transform3D(Basis.IDENTITY, Vector3(at.x, ground + 1.05, at.z))).is_empty(), "spawn %s is inside geometry" % at)
	var forward: Vector3 = -spawn.global_basis.z
	var door: Vector3 = (_overlay.get_node(^"BunkerPortal") as Node3D).global_position
	_check(forward.dot(Vector3(at.x - door.x, 0.0, at.z - door.z).normalized()) > 0.9, "spawn does not face out of the bunker door")


func _floor_under(at: Vector3) -> float:
	var hit: Dictionary = _ray(at + Vector3.UP * 1.0, at + Vector3.DOWN * 4.0)
	return float((hit["position"] as Vector3).y) if not hit.is_empty() else NAN


func _ray(a: Vector3, b: Vector3) -> Dictionary:
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(a, b)
	q.collide_with_areas = false
	return _space.intersect_ray(q)


func _overlaps(shape: Shape3D, xf: Transform3D) -> Array[Dictionary]:
	var q: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = xf
	q.collide_with_areas = false
	return _space.intersect_shape(q, 4)


func _spawn() -> Marker3D:
	return _content.get_node(^"SpawnPoint") as Marker3D


func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CHUNK_M), floori(p.z / CHUNK_M))


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("reality first exit: %s" % message)
