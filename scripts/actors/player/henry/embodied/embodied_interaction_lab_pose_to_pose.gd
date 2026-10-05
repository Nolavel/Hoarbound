class_name EmbodiedInteractionLabPoseToPose
extends EmbodiedInteractionLabV6

## Concrete V6 lab driver.
##
## Legacy V2 body movement refused to move until a hand was already committed.
## Pose-to-pose V6 intentionally aligns the body before choosing a hand, so this
## driver removes that historical coupling while keeping CharacterBody collision
## authoritative. This is lab-only and does not replace production movement.


func _move_body_toward_goal(delta: float) -> void:
	var planar := Vector3(_body_goal.x - global_position.x, 0.0, _body_goal.z - global_position.z)
	var distance: float = planar.length()
	rotation.y = lerp_angle(rotation.y, _body_goal_yaw, clampf(delta * BODY_TURN_RATE, 0.0, 1.0))
	if distance <= BODY_ALIGN_TOLERANCE_M:
		velocity = Vector3.ZERO
		_body_aligned = true
		_body_error_m = distance
		return
	var speed: float = minf(BODY_SPEED_MPS, distance / maxf(delta, 0.001))
	velocity = planar.normalized() * speed
	move_and_slide()
	if get_slide_collision_count() > 0:
		_body_collision_seen = true
	_body_error_m = Vector2(global_position.x - _body_goal.x, global_position.z - _body_goal.z).length()
	_body_aligned = _body_error_m <= BODY_ALIGN_TOLERANCE_M
