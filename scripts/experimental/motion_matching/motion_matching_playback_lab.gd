class_name MotionMatchingPlaybackLab
extends Node3D

## Presentation scene for the lab: real Henry, authored floor, light, camera.
## Henry's production AnimationTree is off; the matched pose is the only source.

const CAMERA_OFFSET := Vector3(1.8, 1.7, 3.2)
const CAMERA_FOLLOW_RATE := 4.0

@onready var henry_animation: HenryUALAnimation = $Henry/HenryUALVisual as HenryUALAnimation
@onready var visual: Node3D = $Henry/HenryUALVisual
@onready var body: CharacterBody3D = $Henry
@onready var camera: Camera3D = $Camera
@onready var debug_view: MotionMatchingDebugView = $DebugView

var skeleton: Skeleton3D
var _camera_focus := Vector3.ZERO


func _ready() -> void:
	skeleton = henry_animation.skeleton
	if henry_animation.animation_tree != null:
		henry_animation.animation_tree.active = false
	if henry_animation.animation_player != null:
		henry_animation.animation_player.stop(true)
	_disable_modifiers(skeleton)
	_camera_focus = body.global_position
	_place_camera()


func is_ready_for_capture() -> bool:
	return skeleton != null


func follow_camera(dt: float) -> void:
	var weight := 1.0 - exp(-CAMERA_FOLLOW_RATE * dt)
	_camera_focus = _camera_focus.lerp(visual.global_position + Vector3(0.0, 1.0, 0.0), weight)
	_place_camera()


func _place_camera() -> void:
	var focus := _camera_focus - Vector3(0.0, 0.15, 0.0)
	camera.look_at_from_position(focus + CAMERA_OFFSET, focus)


func _disable_modifiers(node: Node) -> void:
	for child in node.get_children():
		if child is SkeletonModifier3D:
			(child as SkeletonModifier3D).active = false
		_disable_modifiers(child)
