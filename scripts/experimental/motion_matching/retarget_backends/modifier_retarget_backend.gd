class_name ModifierRetargetBackend
extends RefCounted

## Godot's own RetargetModifier3D as a retarget backend for comparison (#202 Phase 2):
## BVH -> source Skeleton3D -> modifier -> proxy with Henry's rests -> Henry rotations.

var error_message: String = ""
var report: Dictionary = {}

var _clip: BVHClip
var _source: Skeleton3D
var _modifier: RetargetModifier3D
var _proxy: Skeleton3D
## Henry bone index -> source joint, for bones the modifier drives.
var _mapped: Dictionary = {}
var _rest_rotations: Array[Quaternion] = []


## Builds the node chain under `parent` (it must be inside the tree to process).
func setup(clip: BVHClip, profile: SourceRetargetProfile, henry: Skeleton3D, global_pose: bool, parent: Node) -> bool:
	_clip = clip
	_source = Skeleton3D.new()
	_source.name = "ModifierBackendSource"
	for joint in range(clip.get_bone_count()):
		_source.add_bone(clip.bone_names[joint])
	for joint in range(clip.get_bone_count()):
		_source.set_bone_parent(joint, clip.parents[joint])
		_source.set_bone_rest(joint, clip.local_transform(profile.reference_frame, joint))
	_source.reset_bone_poses()
	_proxy = Skeleton3D.new()
	_proxy.name = "ModifierBackendProxy"
	var profile_names: Array[String] = []
	for bone in range(henry.get_bone_count()):
		var henry_name := henry.get_bone_name(bone)
		var source_name := String(profile.bone_map.get(henry_name, ""))
		var joint := clip.find_bone(source_name)
		var proxy_name := henry_name
		if joint >= 0 and not profile_names.has(source_name):
			proxy_name = source_name
			profile_names.append(source_name)
			_mapped[bone] = joint
		_proxy.add_bone(proxy_name)
		_rest_rotations.append(henry.get_bone_rest(bone).basis.get_rotation_quaternion())
	for bone in range(henry.get_bone_count()):
		_proxy.set_bone_parent(bone, henry.get_bone_parent(bone))
		_proxy.set_bone_rest(bone, henry.get_bone_rest(bone))
	_proxy.reset_bone_poses()
	var skeleton_profile := SkeletonProfile.new()
	skeleton_profile.bone_size = profile_names.size()
	for index in range(profile_names.size()):
		skeleton_profile.set_bone_name(index, StringName(profile_names[index]))
	_modifier = RetargetModifier3D.new()
	_modifier.profile = skeleton_profile
	_modifier.use_global_pose = global_pose
	_modifier.set_position_enabled(false)
	_modifier.set_rotation_enabled(true)
	_modifier.set_scale_enabled(false)
	_source.add_child(_modifier)
	_modifier.add_child(_proxy)
	parent.add_child(_source)
	report = {"backend": "RetargetModifier3D", "use_global_pose": global_pose, "mapped_bones": _mapped.size()}
	if _mapped.size() < 20:
		error_message = "too few mapped bones: %d" % _mapped.size()
		return false
	return true


## Henry local rotations for one source frame (unmapped bones at rest); `root_space`
## takes the heading out of the source root as B1 does. Waits for the modifier to run.
func pose_at(frame: int, tree: SceneTree, root_space: Basis = Basis.IDENTITY) -> Array[Quaternion]:
	_proxy.reset_bone_poses()
	for joint in range(_clip.get_bone_count()):
		var local := _clip.local_transform(frame, joint)
		if _clip.parents[joint] < 0:
			local = Transform3D(root_space, Vector3.ZERO) * local
		_source.set_bone_pose_rotation(joint, local.basis.get_rotation_quaternion())
		_source.set_bone_pose_position(joint, local.origin)
	await tree.process_frame
	await tree.process_frame
	var result: Array[Quaternion] = _rest_rotations.duplicate()
	for bone in _mapped.keys():
		result[bone] = _proxy.get_bone_pose_rotation(bone)
	return result


func free_nodes() -> void:
	if _source != null:
		_source.queue_free()
