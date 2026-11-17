# =============================================================================
# player_state.gd — autoload. The single source of truth for what the player
# currently is.
#
# Ported from ADT's core/player_state/player_state.gd, with its modes replaced
# by this game's. The load-bearing part is unchanged and deliberate:
#
#   MENU IS REACHABLE ONLY THROUGH open_menu() / close_menu().
#   set_mode(MENU) push_errors. Pause state and mode must never disagree, so
#   the two are changed together and the previous mode is remembered and
#   restored. Pause is set BEFORE the signal fires, so every listener sees a
#   consistent tree.
#
# Do not create a parallel state enum anywhere. Systems that need to know
# whether the player can act ask here.
# =============================================================================
class_name PlayerStateService
extends Node

## What the player is doing with their body.
enum Mode {
	## Walking the island. The only mode in which movement input is obeyed.
	ON_FOOT,
	## Performing a held action — sealing a breach, feeding a fire. Movement
	## is blocked; releasing the key returns to ON_FOOT.
	WORKING,
	## In the water after falling through the ice. Ends by climbing out.
	SWIMMING,
	## Asleep. The world advances; the player does not act.
	SLEEPING,
	## Any modal UI. Owns get_tree().paused.
	MENU,
}

var mode: Mode = Mode.ON_FOOT
## Mode active before MENU was opened, restored on close.
var _mode_before_menu: Mode = Mode.ON_FOOT

## Emitted on every mode change, including into and out of MENU.
signal mode_changed(old_mode: Mode, new_mode: Mode)


## Changes mode, except into MENU. Refuses while MENU is open so pause can
## never diverge from mode.
func set_mode(new_mode: Mode) -> void:
	if new_mode == Mode.MENU:
		push_error("PlayerState: use open_menu() rather than set_mode(MENU)")
		return
	if mode == Mode.MENU:
		push_error("PlayerState: cannot change mode while MENU is open — use close_menu()")
		return
	if new_mode == mode:
		return
	var old_mode: Mode = mode
	mode = new_mode
	mode_changed.emit(old_mode, new_mode)


## Opens a modal UI and pauses the tree. Pause is set before the signal.
func open_menu() -> void:
	if mode == Mode.MENU:
		return
	_mode_before_menu = mode
	var old_mode: Mode = mode
	mode = Mode.MENU
	if is_inside_tree():
		get_tree().paused = true
	mode_changed.emit(old_mode, Mode.MENU)


## Closes the modal UI, unpauses, and restores the mode that was active
## before it opened — so a menu opened while swimming returns to swimming.
func close_menu() -> void:
	if mode != Mode.MENU:
		return
	if is_inside_tree():
		get_tree().paused = false
	var restored: Mode = _mode_before_menu
	mode = restored
	mode_changed.emit(Mode.MENU, restored)


## True while the player may move under their own power.
func is_on_foot() -> bool:
	return mode == Mode.ON_FOOT


## True while any mode is holding the player still: working, asleep or in a menu.
func is_movement_blocked() -> bool:
	return mode == Mode.WORKING or mode == Mode.SLEEPING or mode == Mode.MENU


## True while gameplay input should be ignored entirely.
func is_paused() -> bool:
	return mode == Mode.MENU
