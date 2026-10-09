class_name TpsInteractionFraming
extends Node

## Interaction-aware composition for the production TPS camera.
##
## This never rotates the player's control look and never moves the lens with
## Camera3D.h_offset. It only asks TpsShoulderState for a temporary *physical*
## shoulder position. TpsCamera then runs its normal passage clamp, shoulder
## sweep and boom collision on that position, so geometry always wins.

@export_group("Composition")
## Furthest physical shoulder offset while clearing an interaction target.
@export_range(0.85, 1.40, 0.05) var max_shoulder_offset: float = 1.15
## Horizontal screen band around Henry in which a target is considered at risk
## of being hidden by his silhouette.
@export_range(0.04, 0.25, 0.01) var screen_clearance_fraction: float = 0.11
## Vertical band keeps low/high targets from causing lateral camera motion when
## they are nowhere near Henry's projected body.
@export_range(0.10, 0.60, 0.02) var vertical_window_fraction: float = 0.30
## Opposite-shoulder composition is allowed only for a severe overlap. Smaller
## conflicts merely widen the player's chosen shoulder.
@export_range(0.5, 1.0, 0.02) var swap_threshold: float = 0.74

@export_group("Stability")
## Keep the last valid target briefly when the camera shift itself makes
## InteractComponent drop it. This breaks the focus -> shift -> lost -> return loop.
@export_range(0.0, 0.6, 0.05) var target_hold_seconds: float = 0.25

var _camera: TpsCamera
var _held_target: InteractiveArea
var _hold_left: float = 0.0


func _ready() -> void:
	_camera = get_parent() as TpsCamera
	## Read interaction state before the camera computes this frame's physical rig.
	process_priority = -10


func _exit_tree() -> void:
	if is_instance_valid(_camera):
		_camera._shoulder.clear_interaction_override()


func _process(delta: float) -> void:
	if not is_instance_valid(_camera) or not is_instance_valid(_camera.player):
		return
	if not _camera._has_position:
		_camera._shoulder.clear_interaction_override()
		return

	_update_target(delta)
	if not is_instance_valid(_held_target):
		_camera._shoulder.clear_interaction_override()
		return

	var focus: Vector3 = _held_target.get_focus_point(_camera.player.global_position)
	var body := _camera.get_eye_position()
	if _camera.is_position_behind(focus) or _camera.is_position_behind(body):
		_camera._shoulder.clear_interaction_override()
		return

	var viewport_size := _camera.get_viewport().get_visible_rect().size
	var target_screen := _camera.unproject_position(focus)
	var body_screen := _camera.unproject_position(body)
	var dx := target_screen.x - body_screen.x
	var dy := target_screen.y - body_screen.y
	var clearance_x := maxf(32.0, viewport_size.x * screen_clearance_fraction)
	var clearance_y := maxf(64.0, viewport_size.y * vertical_window_fraction)

	if absf(dx) >= clearance_x or absf(dy) >= clearance_y:
		_camera._shoulder.clear_interaction_override()
		return

	var horizontal := 1.0 - absf(dx) / clearance_x
	var vertical := 1.0 - absf(dy) / clearance_y
	var strength := smoothstep(0.0, 1.0, horizontal * vertical)
	if strength <= 0.001:
		_camera._shoulder.clear_interaction_override()
		return

	## Moving the physical camera toward the target's screen side increases the
	## foreground/background parallax between Henry and that target.
	var desired_sign := signf(dx)
	if absf(dx) < 4.0:
		desired_sign = signf(_camera.global_basis.x.normalized().dot(focus - body))
	var base_sign := 1.0 if _camera._shoulder.is_right() else -1.0
	if is_zero_approx(desired_sign):
		desired_sign = base_sign
	## Do not auto-cross the character for a mild overlap. A real side change is
	## reserved for the case where widening the current shoulder is insufficient.
	if desired_sign != base_sign and strength < swap_threshold:
		desired_sign = base_sign

	_camera._shoulder.set_interaction_override(desired_sign * max_shoulder_offset, strength)


func _update_target(delta: float) -> void:
	var interact := _camera.player.get_node_or_null(^"InteractComponent") as InteractComponent
	var live: InteractiveArea = interact.current_target if interact != null else null
	if is_instance_valid(live):
		_held_target = live
		_hold_left = target_hold_seconds
		return
	if _hold_left > 0.0 and is_instance_valid(_held_target):
		_hold_left = maxf(0.0, _hold_left - delta)
		return
	_held_target = null
	_hold_left = 0.0
