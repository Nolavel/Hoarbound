class_name MotionMatchingLab
extends CharacterBody3D

## Phase 1 motion-matching lab. Physics follows the continuous camera-space query;
## the matcher searches a directional sample set independently, so the debug view
## shows approximation error instead of hiding it behind an eight-way state machine.

const SAMPLE_DIRECTIONS: Array[Dictionary] = [
	{"name": &"Idle", "direction": Vector2.ZERO},
	{"name": &"F", "direction": Vector2(0.0, -1.0)},
	{"name": &"FR", "direction": Vector2(0.70710678, -0.70710678)},
	{"name": &"R", "direction": Vector2(1.0, 0.0)},
	{"name": &"BR", "direction": Vector2(0.70710678, 0.70710678)},
	{"name": &"B", "direction": Vector2(0.0, 1.0)},
	{"name": &"BL", "direction": Vector2(-0.70710678, 0.70710678)},
	{"name": &"L", "direction": Vector2(-1.0, 0.0)},
	{"name": &"FL", "direction": Vector2(-0.70710678, -0.70710678)},
]

@export_group("Movement")
@export var walk_speed: float = 1.8
@export var acceleration: float = 9.0
@export var turn_rate: float = 10.0
@export var gravity: float = 20.0

@export_group("Search weights")
@export var direction_weight: float = 1.0
@export var speed_weight: float = 0.35
@export var facing_weight: float = 0.15
@export var continuity_penalty: float = 0.08

@onready var animation_component: HenryUALAnimation = $HenryUALVisual as HenryUALAnimation
@onready var camera: TpsCamera = get_node_or_null(^"../PlayerCamera") as TpsCamera
@onready var desired_arrow: Node3D = get_node_or_null(^"../Debug/DesiredVelocity") as Node3D
@onready var selected_arrow: Node3D = get_node_or_null(^"../Debug/SelectedSample") as Node3D
@onready var facing_arrow: Node3D = get_node_or_null(^"../Debug/Facing") as Node3D
@onready var debug_label: Label3D = get_node_or_null(^"../Debug/Readout") as Label3D

var desired_local_velocity: Vector2 = Vector2.ZERO
var selected_local_velocity: Vector2 = Vector2.ZERO
var selected_sample: StringName = &"Idle"
var selected_cost: float = 0.0
var _capture_override_enabled: bool = false
var _capture_input: Vector2 = Vector2.ZERO


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if camera != null:
		camera.player = self


func _physics_process(delta: float) -> void:
	var input_vector := _capture_input if _capture_override_enabled else Input.get_vector(
		&"move_left", &"move_right", &"move_forward", &"move_backward"
	)
	if input_vector.length_squared() > 1.0:
		input_vector = input_vector.normalized()

	desired_local_velocity = input_vector * walk_speed
	_run_search(input_vector)

	var desired_world := _camera_local_to_world(desired_local_velocity)
	velocity.x = move_toward(velocity.x, desired_world.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, desired_world.z, acceleration * delta)
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
	move_and_slide()

	var planar := Vector3(velocity.x, 0.0, velocity.z)
	if planar.length_squared() > 0.01:
		var target_yaw := atan2(-planar.x, -planar.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-turn_rate * delta))

	if animation_component != null:
		animation_component.update_animation_blend(delta)
		animation_component.update_animation_state(false, false)
	_update_debug()


func set_capture_input(value: Vector2) -> void:
	_capture_override_enabled = true
	_capture_input = value.limit_length(1.0)


func clear_capture_input() -> void:
	_capture_override_enabled = false
	_capture_input = Vector2.ZERO


func get_debug_snapshot() -> Dictionary:
	return {
		"desired_local_velocity": [desired_local_velocity.x, desired_local_velocity.y],
		"selected_local_velocity": [selected_local_velocity.x, selected_local_velocity.y],
		"selected_sample": String(selected_sample),
		"cost": selected_cost,
		"speed_mps": Vector2(velocity.x, velocity.z).length(),
		"position": [global_position.x, global_position.y, global_position.z],
	}


func _run_search(input_vector: Vector2) -> void:
	var strength := input_vector.length()
	if strength < 0.05:
		selected_sample = &"Idle"
		selected_local_velocity = Vector2.ZERO
		selected_cost = strength * speed_weight
		return

	var query_dir := input_vector / strength
	var facing_local := _facing_camera_local()
	var best_name: StringName = &""
	var best_dir := Vector2.ZERO
	var best_cost := INF

	for sample in SAMPLE_DIRECTIONS:
		var sample_dir: Vector2 = sample["direction"]
		if sample_dir.is_zero_approx():
			continue
		var direction_error := 1.0 - clampf(query_dir.dot(sample_dir), -1.0, 1.0)
		var speed_error := absf(strength - 1.0)
		var facing_error := 1.0 - clampf(facing_local.dot(sample_dir), -1.0, 1.0)
		var continuity := 0.0 if StringName(sample["name"]) == selected_sample else continuity_penalty
		var cost := (
			direction_error * direction_weight
			+ speed_error * speed_weight
			+ facing_error * facing_weight
			+ continuity
		)
		if cost < best_cost:
			best_cost = cost
			best_name = StringName(sample["name"])
			best_dir = sample_dir

	selected_sample = best_name
	selected_local_velocity = best_dir * walk_speed * strength
	selected_cost = best_cost


func _camera_local_to_world(local_velocity: Vector2) -> Vector3:
	var yaw := camera.get_yaw() if camera != null else 0.0
	return Basis(Vector3.UP, yaw) * Vector3(local_velocity.x, 0.0, local_velocity.y)


func _facing_camera_local() -> Vector2:
	var world_forward := -global_transform.basis.z
	var yaw := camera.get_yaw() if camera != null else 0.0
	var camera_local := Basis(Vector3.UP, -yaw) * world_forward
	var result := Vector2(camera_local.x, camera_local.z)
	return result.normalized() if result.length_squared() > 0.0001 else Vector2(0.0, -1.0)


func _update_debug() -> void:
	var base := global_position + Vector3(0.0, -0.92, 0.0)
	_place_arrow(desired_arrow, base + Vector3(0.0, 0.04, 0.0), _camera_local_to_world(desired_local_velocity), 1.0)
	_place_arrow(selected_arrow, base + Vector3(0.0, 0.10, 0.0), _camera_local_to_world(selected_local_velocity), 1.0)
	_place_arrow(facing_arrow, base + Vector3(0.0, 0.16, 0.0), -global_transform.basis.z * 1.3, 1.0)
	if debug_label != null:
		debug_label.global_position = global_position + Vector3(0.0, 1.35, 0.0)
		debug_label.text = "query  %+.2f %+.2f\nmatch  %-4s  cost %.3f\nspeed  %.2f m/s" % [
			desired_local_velocity.x,
			desired_local_velocity.y,
			String(selected_sample),
			selected_cost,
			Vector2(velocity.x, velocity.z).length(),
		]


func _place_arrow(arrow: Node3D, origin: Vector3, world_vector: Vector3, scale_factor: float) -> void:
	if arrow == null:
		return
	var flat := Vector3(world_vector.x, 0.0, world_vector.z)
	var length := flat.length() * scale_factor
	arrow.visible = length > 0.03
	if not arrow.visible:
		return
	arrow.global_position = origin
	arrow.global_rotation = Vector3(0.0, atan2(flat.x, flat.z), 0.0)
	var shaft := arrow.get_node_or_null(^"Shaft") as MeshInstance3D
	var head := arrow.get_node_or_null(^"Head") as MeshInstance3D
	if shaft != null:
		shaft.position = Vector3(0.0, 0.0, length * 0.5)
		shaft.scale = Vector3(1.0, 1.0, maxf(length, 0.04))
	if head != null:
		head.position = Vector3(0.0, 0.0, length + 0.10)
