class_name MotionRetargetDiagnostic
extends Node3D

## Side-by-side retarget QA: raw source, source normalized to Henry's root and
## scale, final Henry UAL. The first column that disagrees marks the bad stage.

const SOURCE_COLOR := Color(1.0, 0.55, 0.15)
const NORMALIZED_COLOR := Color(0.2, 0.85, 1.0)
const HENRY_JOINT_COLOR := Color(0.25, 1.0, 0.35)
const BONE_HALF_WIDTH := 0.012

@export var raw_slot: Vector3 = Vector3(-1.3, 0.0, 0.0)
@export var normalized_slot: Vector3 = Vector3(0.0, 0.0, 0.0)
@export var henry_slot: Vector3 = Vector3(1.3, 0.0, 0.0)

@onready var henry_animation: HenryUALAnimation = $Henry/HenryUALVisual as HenryUALAnimation
@onready var camera: Camera3D = $Camera
@onready var caption: Label3D = $Caption

var target_skeleton: Skeleton3D
var _source_mesh: MeshInstance3D
var _normalized_mesh: MeshInstance3D
var _henry_overlay_mesh: MeshInstance3D
var _material: StandardMaterial3D


func _ready() -> void:
	target_skeleton = henry_animation.skeleton
	if henry_animation.animation_tree != null:
		henry_animation.animation_tree.active = false
	if henry_animation.animation_player != null:
		henry_animation.animation_player.stop(true)
	_disable_modifiers(target_skeleton)
	$Henry.position = henry_slot + Vector3(0.0, 1.0, 0.0)
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.no_depth_test = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_source_mesh = _make_mesh("RawSource")
	_normalized_mesh = _make_mesh("NormalizedSource")
	_henry_overlay_mesh = _make_mesh("HenryJoints")


func is_ready_for_capture() -> bool:
	return target_skeleton != null


func show_pose(retargeter: MotionRetargeter, seconds: float, label: String) -> Dictionary:
	var pose := retargeter.retarget_at(seconds)
	var rotations: Array[Quaternion] = pose["rotations"]
	for bone_index in range(rotations.size()):
		target_skeleton.set_bone_pose_rotation(bone_index, rotations[bone_index])
		target_skeleton.set_bone_pose_position(bone_index, retargeter.target.rest_local[bone_index].origin)
	target_skeleton.set_bone_pose_position(retargeter.target.pelvis_index, pose["pelvis_position"])
	_draw_source(_source_mesh, retargeter, retargeter.raw_source_positions(seconds), raw_slot, SOURCE_COLOR, true)
	_draw_source(_normalized_mesh, retargeter, retargeter.normalized_source_positions(seconds), normalized_slot, NORMALIZED_COLOR, false)
	_draw_henry_joints(retargeter)
	caption.text = label
	return pose


func _draw_source(instance: MeshInstance3D, retargeter: MotionRetargeter, positions: PackedVector3Array, slot: Vector3, color: Color, recentre: bool) -> void:
	var mesh := instance.mesh as ImmediateMesh
	mesh.clear_surfaces()
	var offset := slot
	if recentre:
		var hips: Vector3 = positions[retargeter.clip.find_bone(String(retargeter.profile.bone_map["pelvis"]))]
		offset -= Vector3(hips.x, 0.0, hips.z)
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
	for joint in range(positions.size()):
		var parent := retargeter.clip.parents[joint]
		if parent >= 0:
			_add_bone(mesh, positions[parent] + offset, positions[joint] + offset, color)
	mesh.surface_end()


func _draw_henry_joints(retargeter: MotionRetargeter) -> void:
	var mesh := _henry_overlay_mesh.mesh as ImmediateMesh
	mesh.clear_surfaces()
	var to_world := target_skeleton.global_transform
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
	for bone_name in retargeter.profile.bone_map.keys():
		var bone_index := target_skeleton.find_bone(String(bone_name))
		var parent := target_skeleton.get_bone_parent(bone_index)
		if parent < 0 or not retargeter.profile.bone_map.has(target_skeleton.get_bone_name(parent)):
			continue
		var a := to_world * target_skeleton.get_bone_global_pose(parent).origin
		var b := to_world * target_skeleton.get_bone_global_pose(bone_index).origin
		_add_bone(mesh, a, b, HENRY_JOINT_COLOR)
	mesh.surface_end()


func _add_bone(mesh: ImmediateMesh, a: Vector3, b: Vector3, color: Color) -> void:
	var view := (camera.global_position - (a + b) * 0.5).normalized()
	var side := (b - a).cross(view)
	if side.length_squared() < 0.0000001:
		return
	side = side.normalized() * BONE_HALF_WIDTH
	for vertex in [a - side, a + side, b + side, a - side, b + side, b - side]:
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(vertex)


func _make_mesh(node_name: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = ImmediateMesh.new()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance


func _disable_modifiers(node: Node) -> void:
	for child in node.get_children():
		if child is SkeletonModifier3D:
			(child as SkeletonModifier3D).active = false
		_disable_modifiers(child)
