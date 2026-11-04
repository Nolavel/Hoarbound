class_name TpsRigWork
extends TpsRigBehaviour

## Workspace framing (stove door): the view eases to an authored eye looking at a focus, the
## mouse orbits it a little, and walls between Henry and the eye shorten the boom.

## Look target and preferred eye, world space; the control look it started from bounds the
## mouse orbit. The blend runs 0 (follow) to 1 (framed).
var lock_look: bool = false
var _work_active: bool = false
var _work_focus: Vector3 = Vector3.ZERO
var _work_eye: Vector3 = Vector3.ZERO
var _work_look0: Vector2 = Vector2.ZERO
var _work_blend: float = 0.0


func is_active() -> bool:
	return _work_active


func get_blend() -> float:
	return _work_blend


## Starts or moves the framing; the control look it starts from is kept for the orbit bounds.
func set_framing(focus: Vector3, eye: Vector3, look: Vector2) -> void:
	if not _work_active:
		_work_look0 = look
	_work_active = true
	_work_focus = focus
	_work_eye = eye


func clear() -> void:
	_work_active = false
	lock_look = false


## Bounds the control look (yaw radians, pitch degrees) to the orbit round the start look.
func clamp_look(look: Vector2) -> Vector2:
	if lock_look and _work_active:
		return _work_look0
	var off: float = clampf(angle_difference(_work_look0.x, look.x), -deg_to_rad(rig.work_look_limit_deg.x), deg_to_rad(rig.work_look_limit_deg.x))
	return Vector2(wrapf(_work_look0.x + off, -PI, PI),
		clampf(look.y, _work_look0.y - rig.work_look_limit_deg.y, _work_look0.y + rig.work_look_limit_deg.y))


## Eases frame.camera and frame.view toward the workspace view by the blend.
func apply(frame: TpsRigFrame) -> void:
	_work_blend = move_toward(_work_blend, 1.0 if _work_active else 0.0, rig.work_framing_rate * frame.delta * 0.5)
	if _work_blend <= 0.001:
		return
	var work: Transform3D = _work_view(frame.safe)
	var weight: float = smoothstep(0.0, 1.0, _work_blend)
	frame.camera = frame.camera.lerp(work.origin, weight)
	frame.view = frame.view.get_rotation_quaternion().slerp(work.basis.get_rotation_quaternion(), weight)


## The workspace view: the authored eye orbited by the mouse's offset from the starting
## look, its boom swept from Henry's safe point so a wall beside the stove shortens it.
func _work_view(safe: Vector3) -> Transform3D:
	var offset: Vector3 = _work_eye - _work_focus
	offset = offset.rotated(Vector3.UP, angle_difference(_work_look0.x, rig.get_yaw()))
	var right: Vector3 = (-offset).cross(Vector3.UP).normalized()
	if right.length_squared() > 0.5:
		offset = offset.rotated(right, deg_to_rad(rig.get_control_pitch_deg() - _work_look0.y))
	var eye: Vector3 = _work_focus + offset
	var reach: Vector3 = eye - safe
	var free: float = rig.get_probe().sweep(safe, reach) - rig.collision_surface_margin
	if free < reach.length():
		eye = safe + reach.normalized() * maxf(free, rig.collision_min_distance)
	return Transform3D(Basis.looking_at(_work_focus - eye, Vector3.UP), eye)
