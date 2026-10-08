# =============================================================================
# input_systems.gd — autoload.
#
# Single responsibility: turn Godot's Input into signals and query methods.
# NO game logic lives here. It does not decide what a press MEANS — that is
# the subscriber's job, based on whatever state the subscriber cares about.
# It emits unconditionally, always.
#
# Two rules taken from the ADT project, both learned the hard way there:
#
#   EDGES COME FROM EVENTS, LEVELS COME FROM POLLS.
#   A discrete press or release is matched on the InputEvent in
#   _unhandled_input(); held state and axes are polled in _physics_process().
#   Do NOT add Input.is_action_just_pressed() anywhere: polling an edge from
#   the physics frame drops presses as soon as the idle and physics rates
#   diverge. A query method that must stay a poll is answered from the edge
#   latch in this file, never from Input.
#
#   ONLY THIS FILE READS Input DIRECTLY.
#   A second reader means two places decide what is pressed, and they will
#   disagree on the frame it matters.
# =============================================================================
class_name InputSystemsService
extends Node

## --- Movement and locomotion ---
signal jump_pressed()
signal sprint_changed(active: bool)

## --- Interaction ---
## Three edges plus a duration. While a claim is held NONE of these fire and
## the key routes to the claimant instead — see the claim block below.
signal interact_pressed()
signal interact_held(duration: float)
signal interact_released(duration: float)
## Steps the target within a cluster of close objects; not affected by the claim.
signal interact_cycle_pressed()

## --- Sleep (hold S, confirm with interact) ---
## The relay reports WHEN and FOR HOW LONG; it never says "that was a hold".
## The threshold belongs to whoever acts on it.
signal sleep_cancel_pressed()
## Debug map visibility edge; subscribers decide whether the feature is enabled.
signal dev_map_toggle_pressed()

const ACTION_MOVE_FORWARD: StringName = &"move_forward"
const ACTION_MOVE_BACKWARD: StringName = &"move_backward"
const ACTION_MOVE_LEFT: StringName = &"move_left"
const ACTION_MOVE_RIGHT: StringName = &"move_right"
const ACTION_SPRINT: StringName = &"sprint"
const ACTION_JUMP: StringName = &"jump"
const ACTION_CROUCH: StringName = &"crouch"
const ACTION_INTERACT: StringName = &"interact"
const ACTION_INTERACT_CYCLE: StringName = &"interact_cycle"
const ACTION_SLEEP_CANCEL: StringName = &"sleep_cancel"
const ACTION_DEV_MAP_TOGGLE: StringName = &"toggle_dev_map"
const ACTION_LEAN_LEFT: StringName = &"lean_left"
const ACTION_LEAN_RIGHT: StringName = &"lean_right"
const ACTION_SWITCH_SHOULDER: StringName = &"switch_shoulder"
## Radians of camera turn per pixel of mouse travel.
const MOUSE_SENSITIVITY: float = 0.003

var _was_sprinting: bool = false
var _interact_claimant: Node = null
var _interact_duration: float = 0.0
var _interact_active: bool = false
var _look_accum: Vector2 = Vector2.ZERO
var _look_capture: bool = false
var _shoulder_latch: bool = false


func _ready() -> void:
	var state: Node = get_node_or_null(^"/root/PlayerState")
	if state != null and state.has_signal(&"mode_changed"):
		state.connect(&"mode_changed", func(_old: int, _new: int) -> void: _apply_mouse_mode())


## Mouse motion is accumulated per event; the camera takes it every rendered frame.
## Screen pixels, not viewport ones, so the stretch mode cannot rescale the look.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _look_capture and not _is_gameplay_blocked():
		_look_accum += (event as InputEventMouseMotion).screen_relative * MOUSE_SENSITIVITY


func _unhandled_input(event: InputEvent) -> void:
	## A paused tree already stops most of this, but the cancel key must still
	## reach the menu that is open, so the gate is per-action rather than a
	## blanket return.
	if _is_gameplay_blocked():
		if _pressed(event, ACTION_SLEEP_CANCEL):
			sleep_cancel_pressed.emit()
		return
	if _pressed(event, ACTION_JUMP):
		jump_pressed.emit()
	if _pressed(event, ACTION_SWITCH_SHOULDER):
		_shoulder_latch = true
	if _pressed(event, ACTION_INTERACT):
		_begin_interact()
	elif _released(event, ACTION_INTERACT):
		_end_interact()
	if _pressed(event, ACTION_INTERACT_CYCLE):
		interact_cycle_pressed.emit()
	if _pressed(event, ACTION_SLEEP_CANCEL):
		sleep_cancel_pressed.emit()
	if _pressed(event, ACTION_DEV_MAP_TOGGLE):
		dev_map_toggle_pressed.emit()


func _physics_process(delta: float) -> void:
	_tick_interact(delta)
	var sprinting: bool = is_sprinting()
	if sprinting != _was_sprinting:
		_was_sprinting = sprinting
		sprint_changed.emit(sprinting)


## ============================================
## INTERACT CLAIM
##
## While a claim is held the interact key belongs entirely to the claimant and
## none of the three interact signals fire. One owner decides what the key
## means, instead of subscribers racing each other for it.
##
## The claimant implements as much of this as it needs, duck-typed:
##   on_interact_claimed()                  key down    (required)
##   on_interact_held(duration: float)       every physics frame while down
##   on_interact_released(duration: float)   key up
## ============================================

## Takes ownership of the interact key. No arbitration: the last caller wins,
## which is why a claimant releases as soon as its reason to hold it ends.
func claim_interact(claimant: Node) -> void:
	_interact_claimant = claimant


## Gives the key back, but only if this claimant still owns it.
func release_interact(claimant: Node) -> void:
	if _interact_claimant == claimant:
		_interact_claimant = null


## Whether anyone owns the key right now. A state read; it interprets nothing.
## Exists so an interaction prompt can stay off screen while a claimant is
## drawing its own.
func is_interact_claimed() -> bool:
	return is_instance_valid(_interact_claimant)


func _begin_interact() -> void:
	_interact_duration = 0.0
	_interact_active = true
	if is_instance_valid(_interact_claimant):
		_interact_claimant.call(&"on_interact_claimed")
	else:
		interact_pressed.emit()


func _end_interact() -> void:
	if not _interact_active:
		return
	if is_instance_valid(_interact_claimant):
		if _interact_claimant.has_method(&"on_interact_released"):
			_interact_claimant.call(&"on_interact_released", _interact_duration)
	else:
		interact_released.emit(_interact_duration)
	_interact_active = false
	_interact_duration = 0.0


## Accumulates the hold. The level poll is a safety net: if the release event
## never arrives — a Control ate it, focus was lost, the claimant was freed —
## the key would otherwise read as held forever.
func _tick_interact(delta: float) -> void:
	if not _interact_active:
		return
	if not (InputMap.has_action(ACTION_INTERACT) and Input.is_action_pressed(ACTION_INTERACT)):
		_end_interact()
		return
	_interact_duration += delta
	if is_instance_valid(_interact_claimant):
		if _interact_claimant.has_method(&"on_interact_held"):
			_interact_claimant.call(&"on_interact_held", _interact_duration)
	else:
		interact_held.emit(_interact_duration)


## Seconds the interact key has been held, from this file's own latch.
func get_interact_duration() -> float:
	return _interact_duration


## Movement intent as a 2D vector, x right and y forward. Zero whenever the
## player's current mode holds them still, so no caller has to check.
func get_move_axis() -> Vector2:
	if not _has_move_actions() or _is_movement_blocked():
		return Vector2.ZERO
	return Input.get_vector(
		ACTION_MOVE_LEFT, ACTION_MOVE_RIGHT, ACTION_MOVE_BACKWARD, ACTION_MOVE_FORWARD
	)


## True while any movement action is held. Used to tell a deliberate hold
## apart from a key that also means "walk".
func is_moving() -> bool:
	for action: StringName in [
		ACTION_MOVE_FORWARD, ACTION_MOVE_BACKWARD, ACTION_MOVE_LEFT,
		ACTION_MOVE_RIGHT, ACTION_JUMP,
	]:
		if InputMap.has_action(action) and Input.is_action_pressed(action):
			return true
	return false


func is_sprinting() -> bool:
	if _is_movement_blocked():
		return false
	return InputMap.has_action(ACTION_SPRINT) and Input.is_action_pressed(ACTION_SPRINT)


func is_crouching() -> bool:
	if _is_movement_blocked():
		return false
	return InputMap.has_action(ACTION_CROUCH) and Input.is_action_pressed(ACTION_CROUCH)


## -1 full left lean, +1 full right; zero while movement is blocked.
func get_lean_axis() -> float:
	if _is_movement_blocked():
		return 0.0
	var axis: float = 0.0
	if InputMap.has_action(ACTION_LEAN_LEFT) and Input.is_action_pressed(ACTION_LEAN_LEFT):
		axis -= 1.0
	if InputMap.has_action(ACTION_LEAN_RIGHT) and Input.is_action_pressed(ACTION_LEAN_RIGHT):
		axis += 1.0
	return axis


## True once per shoulder-swap press; reading it clears the latch.
func consume_switch_shoulder() -> bool:
	var pressed: bool = _shoulder_latch
	_shoulder_latch = false
	return pressed


## Mouse look since the last call, in radians; the look camera is its one reader.
## Zero while paused or not captured.
func consume_look_delta() -> Vector2:
	var delta: Vector2 = Vector2.ZERO if _is_gameplay_blocked() else _look_accum
	_look_accum = Vector2.ZERO
	return delta


## A mouse-look camera asks for the pointer; menus get it back while open.
## Releasing always shows the pointer, so a title menu reached from a game has one.
func set_look_capture(active: bool) -> void:
	_look_capture = active
	_look_accum = Vector2.ZERO
	if not active:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	_apply_mouse_mode()


func _apply_mouse_mode() -> void:
	if not _look_capture:
		return
	var captured: bool = not _is_gameplay_blocked()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE


## PlayerState is an autoload, but this file is also driven directly by tests
## where it may not exist, so both reads are guarded rather than assumed.
func _is_gameplay_blocked() -> bool:
	var state: Node = get_node_or_null(^"/root/PlayerState")
	return state != null and state.call(&"is_paused")


func _is_movement_blocked() -> bool:
	var state: Node = get_node_or_null(^"/root/PlayerState")
	return state != null and state.call(&"is_movement_blocked")


func _pressed(event: InputEvent, action: StringName) -> bool:
	return InputMap.has_action(action) and event.is_action_pressed(action, false, true)


func _released(event: InputEvent, action: StringName) -> bool:
	return InputMap.has_action(action) and event.is_action_released(action, true)


func _has_move_actions() -> bool:
	for action: StringName in [
		ACTION_MOVE_LEFT, ACTION_MOVE_RIGHT, ACTION_MOVE_BACKWARD, ACTION_MOVE_FORWARD
	]:
		if not InputMap.has_action(action):
			return false
	return true
