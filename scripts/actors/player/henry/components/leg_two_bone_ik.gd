class_name LegTwoBoneIK
extends RefCounted

## Two-bone leg solve shared by snow feet and Motion Matching foot locking:
## the knee bends in its own plane and the boot keeps its orientation.


## Moves the ankle by `offset` (skeleton space), writing rotations only; returns
## how far the ankle really moved. `length_buffer` keeps the knee off full lock
## but never shortens a leg the animation already holds straighter.
static func reach(skeleton: Skeleton3D, thigh: int, calf: int, foot: int, offset: Vector3, length_buffer: float = 0.001) -> Vector3:
	if thigh < 0 or calf < 0 or foot < 0:
		return Vector3.ZERO
	var hip_pose: Transform3D = skeleton.get_bone_global_pose(thigh)
	var knee_pose: Transform3D = skeleton.get_bone_global_pose(calf)
	var foot_pose: Transform3D = skeleton.get_bone_global_pose(foot)
	var hip: Vector3 = hip_pose.origin
	var knee: Vector3 = knee_pose.origin
	var ankle: Vector3 = foot_pose.origin
	var upper: float = hip.distance_to(knee)
	var lower: float = knee.distance_to(ankle)
	var target: Vector3 = ankle + offset
	var span: Vector3 = target - hip
	var limit: float = maxf(upper + lower - length_buffer, hip.distance_to(ankle))
	var d: float = clampf(span.length(), 0.01, limit)
	var dir: Vector3 = span.normalized()
	var bend: Vector3 = (knee - hip) - dir * (knee - hip).dot(dir)
	if bend.length_squared() < 1e-8:
		return Vector3.ZERO
	bend = bend.normalized()
	var cos_a: float = clampf((upper * upper + d * d - lower * lower) / (2.0 * upper * d), -1.0, 1.0)
	var new_knee: Vector3 = hip + dir * upper * cos_a + bend * upper * sqrt(1.0 - cos_a * cos_a)
	var new_ankle: Vector3 = hip + dir * d
	var turn_thigh := Basis(Quaternion((knee - hip).normalized(), (new_knee - hip).normalized()))
	_set_global_rotation(skeleton, thigh, turn_thigh * hip_pose.basis)
	var old_shin: Vector3 = turn_thigh * (ankle - knee)
	var turn_shin := Basis(Quaternion(old_shin.normalized(), (new_ankle - new_knee).normalized()))
	_set_global_rotation(skeleton, calf, turn_shin * turn_thigh * knee_pose.basis)
	_set_global_rotation(skeleton, foot, foot_pose.basis)
	return new_ankle - ankle


## Local pose rotation that gives `bone` the skeleton-space basis `global_basis`.
static func _set_global_rotation(skeleton: Skeleton3D, bone: int, global_basis: Basis) -> void:
	var parent: int = skeleton.get_bone_parent(bone)
	var parent_basis: Basis = skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis()
	skeleton.set_bone_pose_rotation(bone, (parent_basis.inverse() * global_basis).get_rotation_quaternion())
