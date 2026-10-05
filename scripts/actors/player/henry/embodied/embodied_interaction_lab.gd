class_name EmbodiedInteractionLabActor
extends CharacterBody3D

## Isolated proof for issue #198. It deliberately bypasses production input and
## only demonstrates the seam: target -> body alignment -> existing action -> release.
## It is not a replacement locomotion/traversal controller.

enum Stage { IDLE, ALIGN, ACTION, RELEASE, DONE }

const IDLE_END: float = 1.2
const ALIGN_END: float = 3.2
const ACTION_END: float = 5.5
const RELEASE_END: float = 7.2
const MAX_PREVIEW_SPEED: float = 1.5

@onready var visual: HenryUALAnimation = $HenryUALVisual
@onready var body_target: EmbodiedTarget3D = get_node("../Targets/BodyTarget") as EmbodiedTarget3D
@onready var hand_target: EmbodiedTarget3D = get_node("../Targets/RightHandTarget") as EmbodiedTarget3D
@onready var stage_label: Label = get_node("../UILayer/Margin/VBox/Stage") as Label
@onready var detail_label: Label = get_node("../UILayer/Margin/VBox/Detail") as Label
@onready var camera: Camera3D = get_node("../Camera3D") as Camera3D

var _elapsed: float = 0.0
var _stage: Stage = Stage.IDLE
var _alignment_start_position: Vector3
var _alignment_start_yaw: float
var _release_start_position: Vector3
var _action_started: bool = false
var _skeleton_missing := PackedStringArray()


func _ready() -> void:
	_alignment_start_position = global_position
	_alignment_start_yaw = rotation.y
	camera.look_at(Vector3(0.0, 1.0, 0.15), Vector3.UP)
	_skeleton_missing = HenrySkeletonContract.validate(visual.skeleton)
	if _skeleton_missing.is_empty():
		print("[EmbodiedLab] Henry skeleton contract OK: %s" % [HenrySkeletonContract.describe(visual.skeleton)])
	else:
		push_warning("[EmbodiedLab] Missing skeleton roles: %s" % [_skeleton_missing])
	_update_labels()


func _process(delta: float) -> void:
	_elapsed += delta
	var previous_position: Vector3 = global_position

	if _elapsed < IDLE_END:
		_set_stage(Stage.IDLE)
	elif _elapsed < ALIGN_END:
		_set_stage(Stage.ALIGN)
		var t: float = clampf((_elapsed - IDLE_END) / (ALIGN_END - IDLE_END), 0.0, 1.0)
		var eased: float = t * t * (3.0 - 2.0 * t)
		global_position = _alignment_start_position.lerp(body_target.global_position, eased)
		var target_yaw: float = body_target.global_rotation.y
		rotation.y = lerp_angle(_alignment_start_yaw, target_yaw, eased)
	elif _elapsed < ACTION_END:
		_set_stage(Stage.ACTION)
		global_position = body_target.global_position
		rotation.y = body_target.global_rotation.y
		if not _action_started:
			_action_started = true
			var played: bool = visual.play_action(&"interact")
			print("[EmbodiedLab] action interact started=%s body_error=%.4f" % [played, global_position.distance_to(body_target.global_position)])
	elif _elapsed < RELEASE_END:
		if _stage != Stage.RELEASE:
			_release_start_position = global_position
		_set_stage(Stage.RELEASE)
		var t: float = clampf((_elapsed - ACTION_END) / (RELEASE_END - ACTION_END), 0.0, 1.0)
		var released_position: Vector3 = body_target.global_position - body_target.global_transform.basis.z.normalized() * 0.38
		global_position = _release_start_position.lerp(released_position, t)
	else:
		_set_stage(Stage.DONE)

	velocity = (global_position - previous_position) / maxf(delta, 0.0001)
	if visual != null:
		visual.update_animation_blend(delta)
	_update_labels()


func _set_stage(next_stage: Stage) -> void:
	if _stage == next_stage:
		return
	_stage = next_stage
	print("[EmbodiedLab] stage=%s" % [_stage_name()])


func _stage_name() -> String:
	match _stage:
		Stage.IDLE:
			return "1 / IDLE — locomotion owns Henry"
		Stage.ALIGN:
			return "2 / ALIGN — BODY TARGET acquired"
		Stage.ACTION:
			return "3 / ACTION — authored interact at target"
		Stage.RELEASE:
			return "4 / RELEASE — ownership returns"
		_:
			return "5 / DONE — normal owner restored"


func _update_labels() -> void:
	if stage_label != null:
		stage_label.text = _stage_name()
	if detail_label != null:
		var body_error: float = global_position.distance_to(body_target.global_position)
		detail_label.text = "green ring = BODY TARGET   amber sphere = RIGHT HAND TARGET\nbody error: %.3f m   target contract is independent from animation" % body_error


## Minimal methods read by the existing HenryUALAnimation component.
func get_locomotion_speed_ratio() -> float:
	return clampf(Vector2(velocity.x, velocity.z).length() / MAX_PREVIEW_SPEED, 0.0, 1.0)


func get_crouch_speed_ratio() -> float:
	return 0.0


func is_crouching() -> bool:
	return false


func get_view_direction() -> Vector3:
	return global_transform.basis.z.normalized()


func get_capture_report() -> Dictionary:
	return {
		"stage": _stage_name(),
		"body_target": [body_target.global_position.x, body_target.global_position.y, body_target.global_position.z],
		"right_hand_target": [hand_target.global_position.x, hand_target.global_position.y, hand_target.global_position.z],
		"skeleton_missing": Array(_skeleton_missing),
		"skeleton_roles": HenrySkeletonContract.describe(visual.skeleton),
		"uses_existing_interact_action": true,
		"production_movement_replaced": false,
	}
