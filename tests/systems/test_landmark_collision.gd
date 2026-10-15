extends SceneTree

## Fort Zachary Taylor collision: the simplified Blender copy (tools/blender/landmark_collision.py) is the only
## surface body, small, and walks like the exact visual surface on a 1 m ray grid.

const FORT: String = "res://assets/world/key_west/landmarks/kw_fort_zachary_taylor.glb"
const MAX_COLLISION_FACES: int = 10000
const EXACT_LAYER: int = 1 << 15

var _failures: int = 0


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var fort := (load(FORT) as PackedScene).instantiate() as Node3D
	root.add_child(fort)
	var visual := fort.find_child("FortSurface", true, false) as MeshInstance3D
	var collision := fort.find_child("FortSurfaceCollision", true, false) as StaticBody3D
	_check(visual != null, "fort has no FortSurface mesh")
	_check(collision != null, "fort has no simplified FortSurfaceCollision body")
	if visual == null or collision == null:
		_finish()
		return
	_check(visual.find_children("*", "StaticBody3D", true, false).is_empty(), "the visual fort surface builds its own trimesh body again")
	var faces: int = 0
	for shape_node: Node in collision.find_children("*", "CollisionShape3D", true, false):
		faces += ((shape_node as CollisionShape3D).shape as ConcavePolygonShape3D).get_faces().size() / 3
	_check(faces > 0 and faces <= MAX_COLLISION_FACES, "fort surface collision has %d faces (max %d)" % [faces, MAX_COLLISION_FACES])
	await _check_against_exact(fort, visual)
	_finish()


## Rays down on a 1 m grid: the simplified body against an exact trimesh of the visual surface.
func _check_against_exact(fort: Node3D, visual: MeshInstance3D) -> void:
	var exact := StaticBody3D.new()
	exact.collision_layer = EXACT_LAYER
	var shape := CollisionShape3D.new()
	shape.shape = visual.mesh.create_trimesh_shape()
	exact.add_child(shape)
	root.add_child(exact)
	for i: int in range(3):
		await physics_frame
	var space: PhysicsDirectSpaceState3D = fort.get_world_3d().direct_space_state
	var aabb: AABB = visual.get_aabb()
	var offsets: Array[float] = []
	var misses: int = 0
	var x: float = aabb.position.x
	while x < aabb.end.x:
		var z: float = aabb.position.z
		while z < aabb.end.z:
			var query := PhysicsRayQueryParameters3D.create(Vector3(x, 50.0, z), Vector3(x, -20.0, z), EXACT_LAYER)
			var reference: Dictionary = space.intersect_ray(query)
			if not reference.is_empty():
				query.collision_mask = 1
				var hit: Dictionary = space.intersect_ray(query)
				if hit.is_empty():
					misses += 1
				else:
					offsets.append(absf((hit["position"] as Vector3).y - (reference["position"] as Vector3).y))
			z += 1.0
		x += 1.0
	offsets.sort()
	_check(offsets.size() > 4000, "too few fort samples: %d" % offsets.size())
	if offsets.is_empty():
		return
	var p99: float = offsets[int(offsets.size() * 0.99)]
	var far: int = offsets.filter(func(d: float) -> bool: return d > 0.3).size()
	_check(p99 <= 0.1, "fort collision p99 offset %.3f m > 0.1 m" % p99)
	_check(far <= offsets.size() / 200, "%d samples off by more than 0.3 m" % far)
	_check(misses <= offsets.size() / 1000, "%d samples fall through the fort collision" % misses)
	print("landmark collision: %d samples, p99 %.3f m, %d over 0.3 m, %d misses" % [offsets.size(), p99, far, misses])


func _finish() -> void:
	if _failures > 0:
		push_error("landmark collision: %d check(s) failed" % _failures)
		quit(1)
		return
	print("landmark collision: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("landmark collision: " + message)
