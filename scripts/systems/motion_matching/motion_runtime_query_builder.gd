class_name MotionRuntimeQueryBuilder
extends RefCounted

## Live query in the baker's feature space, measured from the posed skeleton;
## the future is the simulation's path localized to the animated root.



func capture(skeleton: Skeleton3D) -> Dictionary:
	var pelvis := skeleton.find_bone("pelvis")
	var foot_l := skeleton.find_bone("foot_l")
	var foot_r := skeleton.find_bone("foot_r")
	if pelvis < 0 or foot_l < 0 or foot_r < 0:
		return {}
	var model := skeleton.global_transform.orthonormalized()
	return {
		"model": model,
		"pelvis": model * skeleton.get_bone_global_pose(pelvis).origin,
		"foot_l": model * skeleton.get_bone_global_pose(foot_l).origin,
		"foot_r": model * skeleton.get_bone_global_pose(foot_r).origin,
	}


func build(previous: Dictionary, current: Dictionary, dt: float, prediction: Dictionary) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	if previous.is_empty() or current.is_empty() or dt <= 0.000001:
		return values
	var model: Transform3D = current["model"]
	var previous_model: Transform3D = previous["model"]
	var to_model := model.affine_inverse()
	var root_velocity := to_model.basis * ((model.origin - previous_model.origin) / dt)
	values.append(root_velocity.x)
	values.append(root_velocity.z)
	values.append(angular_velocity(previous_model, model, dt))
	for key in ["pelvis", "foot_l", "foot_r"]:
		_append_vec3(values, to_model * (current[key] as Vector3))
		_append_vec3(values, to_model.basis * (((current[key] as Vector3) - (previous[key] as Vector3)) / dt))
	for position in prediction["positions"]:
		var local: Vector3 = to_model * (position as Vector3)
		values.append(local.x)
		values.append(local.z)
	for forward in prediction["forwards"]:
		var local_forward := _flat(to_model.basis * (forward as Vector3))
		values.append(local_forward.x)
		values.append(local_forward.z)
	for key in ["foot_l", "foot_r"]:
		var foot_model := to_model * (current[key] as Vector3)
		var foot_velocity := to_model.basis * (((current[key] as Vector3) - (previous[key] as Vector3)) / dt)
		var planted := foot_model.y < MotionDatabaseBaker.CONTACT_ANKLE_HEIGHT and Vector2(foot_velocity.x, foot_velocity.z).length() < MotionDatabaseBaker.CONTACT_SPEED
		values.append(1.0 if planted else 0.0)
	return values


static func angular_velocity(previous_model: Transform3D, model: Transform3D, dt: float) -> float:
	var a := previous_model.basis * Vector3.BACK
	var b := model.basis * Vector3.BACK
	return wrapf(atan2(b.x, b.z) - atan2(a.x, a.z), -PI, PI) / maxf(dt, 0.000001)


func _flat(value: Vector3) -> Vector3:
	var flat := Vector3(value.x, 0.0, value.z)
	return flat.normalized() if flat.length_squared() > 0.000001 else Vector3.BACK


func _append_vec3(values: PackedFloat32Array, value: Vector3) -> void:
	values.append(value.x)
	values.append(value.y)
	values.append(value.z)
