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
var camera_offset := CAMERA_OFFSET
## Height above the visual root the camera looks at, metres.
var camera_focus_height := 0.85
var _camera_focus := Vector3.ZERO


func _ready() -> void:
	skeleton = henry_animation.skeleton
	if henry_animation.animation_tree != null:
		henry_animation.animation_tree.active = false
	if henry_animation.animation_player != null:
		henry_animation.animation_player.stop(true)
	_disable_modifiers(skeleton)
	_camera_focus = body.global_position + Vector3(0.0, camera_focus_height - 1.0, 0.0)
	_place_camera()


func is_ready_for_capture() -> bool:
	return skeleton != null


func follow_camera(dt: float) -> void:
	var weight := 1.0 - exp(-CAMERA_FOLLOW_RATE * dt)
	_camera_focus = _camera_focus.lerp(visual.global_position + Vector3(0.0, camera_focus_height, 0.0), weight)
	_place_camera()


func _place_camera() -> void:
	camera.look_at_from_position(_camera_focus + camera_offset, _camera_focus)


func _disable_modifiers(node: Node) -> void:
	for child in node.get_children():
		if child is SkeletonModifier3D:
			(child as SkeletonModifier3D).active = false
		_disable_modifiers(child)
