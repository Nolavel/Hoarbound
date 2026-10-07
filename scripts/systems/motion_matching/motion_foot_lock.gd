class_name MotionFootLock
extends RefCounted

## Contact locking after Holden's Motion-Matching `contact_update`: a planted
## ankle holds its ground point; lock and unlock blend by inertialization.

## Farthest a lock holds against the animation (Holden's 0.2 m); past it the point
## is dragged along, as SnowFootModifier's lock reach, instead of snapping free.
const LEASH_RADIUS := 0.2
## Standing still the animation's feet say nothing about where the boots are:
## a held foot keeps its spot up to a leg's reach (the leg solve pulls past it).
const HOLD_LEASH_RADIUS := 0.5
## Halflife of the offset decay after a lock or unlock transition, seconds.
const BLEND_HALFLIFE := 0.1
const LN2 := 0.69314718056

var _initialized: Array[bool] = [false, false]
var _contact: Array[bool] = [false, false]
var _locked: Array[bool] = [false, false]
var _position: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _point: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _input: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _offset: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _offset_velocity: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var leash_frames := 0


## Forgets every lock, e.g. after a teleport.
func reset() -> void:
	_initialized = [false, false]
	_locked = [false, false]


## Presented ankle position for `side` from the animated one. Only the ground
## plane is held; height stays the animation's, so heel and toe roll survive.
func update(side: int, animated: Vector3, contact: bool, dt: float, leash: float = LEASH_RADIUS) -> Vector3:
	var flat := Vector3(animated.x, 0.0, animated.z)
	if not _initialized[side]:
		_initialized[side] = true
		_input[side] = flat
		_position[side] = flat
		_offset[side] = Vector3.ZERO
		_offset_velocity[side] = Vector3.ZERO
		_contact[side] = contact
		_locked[side] = contact
		_point[side] = flat
		return animated
	var input_velocity := (flat - _input[side]) / maxf(dt, 0.000001)
	_input[side] = flat
	_decay(side, dt)
	if _locked[side] and _point[side].distance_to(flat) > leash:
		_point[side] = flat + (_point[side] - flat).normalized() * leash
		leash_frames += 1
	var source := _point[side] if _locked[side] else flat
	_position[side] = source + _offset[side]
	if contact and not _contact[side]:
		_locked[side] = true
		_point[side] = _position[side]
		_offset[side] = flat + _offset[side] - _point[side]
		_offset_velocity[side] += input_velocity
	elif _locked[side] and not contact:
		_locked[side] = false
		_offset[side] = _point[side] + _offset[side] - flat
		_offset_velocity[side] -= input_velocity
	_contact[side] = contact
	return Vector3(_position[side].x, animated.y, _position[side].z)


## Drags a lock point by the ground-plane part of `shortfall` (world) when the
## leg cannot reach it, so the boot slides with the hip instead of over-reaching.
func pull(side: int, shortfall: Vector3) -> void:
	if _locked[side]:
		_point[side] += Vector3(shortfall.x, 0.0, shortfall.z)


func is_locked(side: int) -> bool:
	return _locked[side]


func get_lock_point(side: int) -> Vector3:
	return _point[side]


## Critically damped decay of the transition offset (Holden decay_spring_damper_exact).
func _decay(side: int, dt: float) -> void:
	var y := 2.0 * LN2 / (BLEND_HALFLIFE + 0.00001)
	var j := _offset_velocity[side] + _offset[side] * y
	var e := exp(-y * dt)
	_offset[side] = e * (_offset[side] + j * dt)
	_offset_velocity[side] = e * (_offset_velocity[side] - j * y * dt)
