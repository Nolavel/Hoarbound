class_name MotionCharacterSimulation
extends RefCounted

## Authoritative locomotion simulation: critically damped velocity and facing
## springs (Holden). Yaw 0 faces world +Z; positive yaw turns toward +X.

const LN2 := 0.69314718056
const FUTURE_HORIZONS := [0.2, 0.5, 0.8]

var velocity_halflife: float = 0.27
var facing_halflife: float = 0.27

var position := Vector3.ZERO
var velocity := Vector3.ZERO
var acceleration := Vector3.ZERO
var yaw: float = 0.0
var angular_velocity: float = 0.0


func reset(start_position: Vector3, start_yaw: float) -> void:
	position = Vector3(start_position.x, 0.0, start_position.z)
	velocity = Vector3.ZERO
	acceleration = Vector3.ZERO
	yaw = start_yaw
	angular_velocity = 0.0


## Advances the springs toward the analog intent and returns the new velocity.
func update(dt: float, desired_velocity: Vector3, desired_forward: Vector3) -> Vector3:
	var goal := Vector3(desired_velocity.x, 0.0, desired_velocity.z)
	var state := _velocity_spring(position, velocity, acceleration, goal, dt)
	position = state[0]
	velocity = state[1]
	acceleration = state[2]
	var goal_yaw := _goal_yaw(desired_forward)
	var facing := _facing_spring(yaw, angular_velocity, goal_yaw, dt)
	yaw = facing.x
	angular_velocity = facing.y
	return velocity


## Re-anchors the simulation to the collision-resolved body position.
func sync_position(body_ground_position: Vector3) -> void:
	position = Vector3(body_ground_position.x, 0.0, body_ground_position.z)


## Mirrors a body that another controller moves (the game); the springs are
## not stepped, only their state follows the body.
func mirror(body_position: Vector3, body_velocity: Vector3, body_yaw: float, dt: float) -> void:
	var flat_velocity := Vector3(body_velocity.x, 0.0, body_velocity.z)
	var step := maxf(dt, 0.000001)
	acceleration = (flat_velocity - velocity) / step
	angular_velocity = wrapf(body_yaw - yaw, -PI, PI) / step
	position = Vector3(body_position.x, 0.0, body_position.z)
	velocity = flat_velocity
	yaw = body_yaw


## Future positions/forwards (world) at FUTURE_HORIZONS for the same intent.
func predict(desired_velocity: Vector3, desired_forward: Vector3) -> Dictionary:
	var goal := Vector3(desired_velocity.x, 0.0, desired_velocity.z)
	var goal_yaw := _goal_yaw(desired_forward)
	var positions := PackedVector3Array()
	var forwards := PackedVector3Array()
	for horizon in FUTURE_HORIZONS:
		var t := float(horizon)
		var state := _velocity_spring(position, velocity, acceleration, goal, t)
		positions.append(state[0])
		var facing := _facing_spring(yaw, angular_velocity, goal_yaw, t)
		forwards.append(Vector3(sin(facing.x), 0.0, cos(facing.x)))
	return {"positions": positions, "forwards": forwards}


func basis() -> Basis:
	return Basis(Vector3.UP, yaw)


func _goal_yaw(desired_forward: Vector3) -> float:
	var flat := Vector3(desired_forward.x, 0.0, desired_forward.z)
	if flat.length_squared() < 0.000001:
		return yaw
	return yaw + wrapf(atan2(flat.x, flat.z) - yaw, -PI, PI)


func _velocity_spring(x: Vector3, v: Vector3, a: Vector3, goal: Vector3, dt: float) -> Array:
	var y := _damping(velocity_halflife) * 0.5
	var j0 := v - goal
	var j1 := a + j0 * y
	var decay := exp(-y * dt)
	var new_x := decay * ((-j1) / (y * y) + (-j0 - j1 * dt) / y) + j1 / (y * y) + j0 / y + goal * dt + x
	var new_v := decay * (j0 + j1 * dt) + goal
	var new_a := decay * (a - j1 * y * dt)
	return [new_x, new_v, new_a]


func _facing_spring(x: float, v: float, goal: float, dt: float) -> Vector2:
	var y := _damping(facing_halflife) * 0.5
	var j0 := x - goal
	var j1 := v + j0 * y
	var decay := exp(-y * dt)
	return Vector2(decay * (j0 + j1 * dt) + goal, decay * (v - j1 * y * dt))


func _damping(halflife: float) -> float:
	return (4.0 * LN2) / maxf(halflife, 0.0001)
