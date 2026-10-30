class_name JacketSprings
extends SpringBoneSimulator3D

## Swings the jacket's hem and collar on the spring chains the outfit build adds
## (hem_<i>_0..1 from the pelvis, collar_<i>_0..1 from spine_03), kept off the thighs and neck.

const HEM_PREFIX: String = "hem_"
const COLLAR_PREFIX: String = "collar_"
const THIGHS: Array[StringName] = [&"thigh_l", &"thigh_r"]
const CALVES: Array[StringName] = [&"calf_l", &"calf_r"]

@export_group("Hem")
## Pull back to the modelled hang (higher is stiffer cloth) and how fast motion dies out.
@export var hem_stiffness: float = 4.0
@export_range(0.0, 1.0) var hem_drag: float = 0.3
## Downward pull, so the hem settles back after a lift instead of floating.
@export var hem_gravity: float = 0.4
## Distance kept from the colliders: the bones run 1 cm inside the cloth, so cloth thickness included.
@export var hem_radius: float = 0.008
@export_group("Collar")
@export var collar_stiffness: float = 12.0
@export_range(0.0, 1.0) var collar_drag: float = 0.4
@export var collar_gravity: float = 0.0
@export var collar_radius: float = 0.012
@export_group("Colliders")
## Thigh capsule radius at the hip, metres (the jeans' outer surface).
@export var thigh_radius: float = 0.065
@export var neck_radius: float = 0.06


func _ready() -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null:
		return
	var hem: PackedStringArray = _roots(skeleton, HEM_PREFIX)
	var collar: PackedStringArray = _roots(skeleton, COLLAR_PREFIX)
	setting_count = hem.size() + collar.size()
	var i: int = 0
	for root: String in hem:
		_chain(i, root, hem_stiffness, hem_drag, hem_gravity, hem_radius)
		i += 1
	for root: String in collar:
		_chain(i, root, collar_stiffness, collar_drag, collar_gravity, collar_radius)
		i += 1
	for side: int in 2:
		_add_thigh(skeleton, THIGHS[side], CALVES[side])
	_add_capsule(&"neck_01", neck_radius, 0.16, 0.04)


## Root bone names of every two-bone chain whose names start with `prefix`.
func _roots(skeleton: Skeleton3D, prefix: String) -> PackedStringArray:
	var roots := PackedStringArray()
	for bone: int in skeleton.get_bone_count():
		var bone_name: String = skeleton.get_bone_name(bone)
		if bone_name.begins_with(prefix) and bone_name.ends_with("_0"):
			roots.append(bone_name)
	return roots


func _chain(index: int, root: String, stiffness: float, drag: float, gravity: float, radius: float) -> void:
	var end: String = root.trim_suffix("_0") + "_1"
	set_root_bone_name(index, root)
	set_end_bone_name(index, end)
	## The tip bone carries the lowest cloth, so it swings too: extended along itself.
	set_extend_end_bone(index, true)
	set_end_bone_direction(index, BONE_DIRECTION_PLUS_Y)
	set_end_bone_length(index, _length(end))
	set_stiffness(index, stiffness)
	set_drag(index, drag)
	set_gravity(index, gravity)
	set_gravity_direction(index, Vector3.DOWN)
	set_radius(index, radius)
	set_enable_all_child_collisions(index, true)


## A chain's tip bone is as long as its root (the build splits each chain in half).
func _length(bone_name: String) -> float:
	var skeleton: Skeleton3D = get_skeleton()
	return skeleton.get_bone_rest(skeleton.find_bone(bone_name)).origin.length()


func _add_thigh(skeleton: Skeleton3D, thigh: StringName, calf: StringName) -> void:
	var length: float = skeleton.get_bone_rest(skeleton.find_bone(calf)).origin.length()
	_add_capsule(thigh, thigh_radius, length, length * 0.5)


## A capsule along the bone's own axis, centred `along` metres down it.
func _add_capsule(bone_name: StringName, radius: float, mid_height: float, along: float) -> void:
	var capsule := SpringBoneCollisionCapsule3D.new()
	capsule.name = "%s_capsule" % bone_name
	add_child(capsule)
	capsule.bone_name = bone_name
	capsule.position_offset = Vector3(0.0, along, 0.0)
	capsule.radius = radius
	capsule.mid_height = mid_height
