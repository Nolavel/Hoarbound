extends SceneTree

## A real 1 m x 2 m CharacterBody walks from the foot of the shelter steps,
## over the veranda and through the opened door. Geometry-presence tests cannot
## catch a low roof or a decorative staircase that still blocks movement.
## Run: godot --headless --script tests/systems/test_first_exit_entry_traversal.gd

const BLOCKOUT: String = "res://scenes/world/first_exit/first_exit_blockout.tscn"

var _failures: int = 0
var _state: int = 0
var _elapsed: float = 0.0
var _scene: Node3D
var _house: Node3D
var _door: InteractiveArea
var _body: CharacterBody3D
var _travel_direction: Vector3


func _physics_process(delta: float) -> bool:
	_elapsed += delta
	match _state:
		0:
			_build()
			_elapsed = 0.0
			_state = 1
		1:
			if _elapsed >= 0.9:
				_spawn_body()
				_elapsed = 0.0
				_state = 2
		2:
			_walk(delta)
			if _elapsed >= 7.0:
				var local: Vector3 = _house.to_local(_body.global_position)
				var blocker: String = "none"
				if _body.get_slide_collision_count() > 0:
					var hit: KinematicCollision3D = _body.get_slide_collision(0)
					blocker = str(hit.get_collider().get_path()) if hit.get_collider() is Node else str(hit.get_collider())
				_check(local.z < 3.5,
					"Henry stopped before entering; local position %s, last blocker %s, door %.1f deg"
					% [local, blocker, rad_to_deg(float(_door.get(&"door_hinge").rotation.y))])
				_check(local.y > 1.6 and local.y < 2.2,
					"Henry did not finish standing on the interior floor; local y is %.2f" % local.y)
				_finish()
	return false


func _build() -> void:
	_scene = (load(BLOCKOUT) as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	_house = _scene.get_node(^"ShelterHouse/House") as Node3D
	_door = _house.get_node(^"HouseDoor") as InteractiveArea
	_check(_door != null and _door.has_method(&"is_open"), "shelter has no working door")
	if _door != null:
		_door.interact()


func _spawn_body() -> void:
	var ramp := _house.get_node(^"EntrySteps/EntryRamp") as MeshInstance3D
	var box := ramp.mesh as BoxMesh
	var outer_surface: Vector3 = ramp.to_global(Vector3(0.0, box.size.y * 0.5 + 0.02, box.size.z * 0.5 - 0.08))
	_body = CharacterBody3D.new()
	_body.name = "HenryAccessProbe"
	_body.floor_max_angle = deg_to_rad(45.0)
	_body.floor_snap_length = 0.2
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.5
	capsule.height = 2.0
	collision.shape = capsule
	_body.add_child(collision)
	root.add_child(_body)
	_body.global_position = outer_surface + Vector3.UP * 1.02
	_travel_direction = -_house.global_transform.basis.z
	_travel_direction.y = 0.0
	_travel_direction = _travel_direction.normalized()


func _walk(delta: float) -> void:
	if not _body.is_on_floor():
		_body.velocity.y -= 9.8 * delta
	else:
		_body.velocity.y = -0.5
	_body.velocity.x = _travel_direction.x * 1.5
	_body.velocity.z = _travel_direction.z * 1.5
	var attempted_door_push_velocity: Vector3 = _body.velocity
	_body.move_and_slide()
	HingedDoor.apply_character_collisions(_body, attempted_door_push_velocity)


func _finish() -> void:
	if _failures > 0:
		push_error("first exit entry traversal: %d check(s) failed" % _failures)
		quit(1)
		return
	print("first exit entry traversal: PASS (Henry climbed the veranda and entered)")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("first exit entry traversal: %s" % message)
