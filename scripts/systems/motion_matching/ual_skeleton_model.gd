class_name UALSkeletonModel
extends RefCounted

## Canonical Henry/UAL rest data and forward kinematics without a scene tree.
## Bone lengths are always Henry's; poses change rotations and pelvis offset.

var bone_names: PackedStringArray = PackedStringArray()
var parents: PackedInt32Array = PackedInt32Array()
var rest_local: Array[Transform3D] = []
var rest_global: Array[Transform3D] = []
var pelvis_index: int = -1
var root_index: int = -1


func load_from_skeleton(skeleton: Skeleton3D) -> bool:
	if skeleton == null:
		return false
	bone_names.clear()
	parents.clear()
	rest_local.clear()
	rest_global.clear()
	for bone_index in range(skeleton.get_bone_count()):
		bone_names.append(skeleton.get_bone_name(bone_index))
		parents.append(skeleton.get_bone_parent(bone_index))
		rest_local.append(skeleton.get_bone_rest(bone_index))
	for bone_index in range(bone_names.size()):
		var parent := parents[bone_index]
		if parent >= bone_index:
			push_error("UALSkeletonModel: bones are not parent-ordered.")
			return false
		rest_global.append(rest_local[bone_index] if parent < 0 else rest_global[parent] * rest_local[bone_index])
	pelvis_index = find_bone("pelvis")
	root_index = find_bone("root")
	return pelvis_index >= 0


func find_bone(bone_name: String) -> int:
	return bone_names.find(bone_name)


func get_bone_count() -> int:
	return bone_names.size()


## Model-space transforms for local rotations plus a pelvis local position.
func forward_kinematics(local_rotations: Array[Quaternion], pelvis_local_position: Vector3) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	result.resize(bone_names.size())
	for bone_index in range(bone_names.size()):
		var origin := rest_local[bone_index].origin
		if bone_index == pelvis_index:
			origin = pelvis_local_position
		var local := Transform3D(Basis(local_rotations[bone_index]), origin)
		var parent := parents[bone_index]
		result[bone_index] = local if parent < 0 else result[parent] * local
	return result


func rest_rotations() -> Array[Quaternion]:
	var result: Array[Quaternion] = []
	for transform in rest_local:
		result.append(transform.basis.get_rotation_quaternion())
	return result


## Henry's hip-to-ankle chain length averaged over both legs, meters.
func leg_length() -> float:
	var total := 0.0
	for side in ["l", "r"]:
		var thigh := find_bone("thigh_" + side)
		var calf := find_bone("calf_" + side)
		var foot := find_bone("foot_" + side)
		total += rest_global[thigh].origin.distance_to(rest_global[calf].origin)
		total += rest_global[calf].origin.distance_to(rest_global[foot].origin)
	return total * 0.5
