extends SceneTree

## Covers the player state machine and the interact claim: the pause coupling
## that must never diverge, and one owner of the interact key at a time.
## Run: godot --headless --script tests/systems/test_player_state.gd

var _failures: int = 0


func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	_test_menu_is_only_reachable_through_open_menu()
	_test_menu_restores_the_previous_mode()
	_test_pause_is_set_before_the_signal()
	_test_movement_is_blocked_by_mode()
	_test_a_claimant_takes_the_interact_key()
	_test_releasing_a_claim_returns_the_key()
	_test_a_freed_claimant_does_not_hold_the_key()
	_test_only_a_claimant_takes_the_key()
	if _failures > 0:
		push_error("state: %d check(s) failed" % _failures)
		quit(1)
		return
	print("state: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("state: %s" % message)


func _dispose(node: Node) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()


func _state() -> Node:
	return root.get_node_or_null(^"PlayerState")


## Pause and mode must never disagree, which is the whole reason MENU is
## walled off behind its own pair of functions.
func _test_menu_is_only_reachable_through_open_menu() -> void:
	var state: Node = _state()
	_check(state != null, "PlayerState autoload is missing")
	if state == null:
		return

	state.set_mode(state.Mode.ON_FOOT)
	state.set_mode(state.Mode.MENU)
	_check(state.mode != state.Mode.MENU, "set_mode(MENU) was allowed")

	state.open_menu()
	_check(state.mode == state.Mode.MENU, "open_menu did not enter MENU")
	state.set_mode(state.Mode.ON_FOOT)
	_check(state.mode == state.Mode.MENU, "set_mode escaped MENU without close_menu")
	state.close_menu()


func _test_menu_restores_the_previous_mode() -> void:
	var state: Node = _state()
	state.set_mode(state.Mode.SWIMMING)
	state.open_menu()
	state.close_menu()
	_check(
		state.mode == state.Mode.SWIMMING,
		"a menu opened while swimming did not return to swimming"
	)
	state.set_mode(state.Mode.ON_FOOT)


## Every listener must see a tree already in its final pause state.
func _test_pause_is_set_before_the_signal() -> void:
	var state: Node = _state()
	var seen: Array[bool] = []
	var probe := func(_old: int, _new: int) -> void: seen.append(paused)

	state.mode_changed.connect(probe)
	state.open_menu()
	_check(seen.size() == 1 and seen[0], "the tree was not paused when mode_changed fired")
	seen.clear()
	state.close_menu()
	_check(seen.size() == 1 and not seen[0], "the tree was still paused when mode_changed fired")
	state.mode_changed.disconnect(probe)
	_check(not paused, "close_menu left the tree paused")


func _test_movement_is_blocked_by_mode() -> void:
	var state: Node = _state()
	var input: Node = root.get_node_or_null(^"InputSystems")
	_check(input != null, "InputSystems autoload is missing")
	if input == null:
		return

	state.set_mode(state.Mode.ON_FOOT)
	_check(state.is_on_foot(), "ON_FOOT did not report as on foot")
	_check(not state.is_movement_blocked(), "ON_FOOT blocked movement")

	for blocked: int in [state.Mode.WORKING, state.Mode.SLEEPING]:
		state.set_mode(blocked)
		_check(
			state.is_movement_blocked(),
			"mode %d did not block movement" % blocked
		)
		_check(
			input.get_move_axis() == Vector2.ZERO,
			"movement input survived mode %d" % blocked
		)
		_check(not input.is_sprinting(), "sprint survived mode %d" % blocked)

	state.set_mode(state.Mode.ON_FOOT)


## While a claim is held the key belongs to the claimant and the plain
## signals must stay silent, or two subscribers act on one press.
func _test_a_claimant_takes_the_interact_key() -> void:
	var input: Node = root.get_node_or_null(^"InputSystems")
	var claimant := _make_claimant()
	var plain: Array[String] = []
	var relay := func() -> void: plain.append("pressed")

	input.interact_pressed.connect(relay)
	input.claim_interact(claimant)
	_check(input.is_interact_claimed(), "the claim was not registered")

	## The key is pressed for real: _tick_interact level-polls Input as a safety
	## net, so a simulated press is the only way to exercise the hold path.
	Input.action_press(&"interact")
	input._begin_interact()
	_check(claimant.claimed == 1, "the claimant was not told the key went down")
	_check(plain.is_empty(), "interact_pressed fired while the key was claimed")

	input._tick_interact(0.5)
	_check(claimant.held > 0, "the claimant received no hold ticks")

	Input.action_release(&"interact")
	input._tick_interact(0.1)
	_check(
		claimant.released == 1,
		"releasing the key did not end the hold through the safety net"
	)
	input._end_interact()
	_check(claimant.released == 1, "the release was reported more than once")
	_check(
		is_equal_approx(claimant.last_duration, 0.5),
		"the claimant got the wrong duration: %.2f" % claimant.last_duration
	)

	input.interact_pressed.disconnect(relay)
	input.release_interact(claimant)
	_dispose(claimant)


func _test_releasing_a_claim_returns_the_key() -> void:
	var input: Node = root.get_node_or_null(^"InputSystems")
	var claimant := _make_claimant()
	var plain: Array[String] = []
	var relay := func() -> void: plain.append("pressed")

	input.claim_interact(claimant)
	input.release_interact(claimant)
	_check(not input.is_interact_claimed(), "the claim was not released")

	input.interact_pressed.connect(relay)
	input._begin_interact()
	_check(plain.size() == 1, "interact_pressed did not fire once the claim was gone")
	_check(claimant.claimed == 0, "a released claimant still received the key")
	input._end_interact()

	input.interact_pressed.disconnect(relay)
	_dispose(claimant)


## A claimant freed mid-hold must not wedge the key.
func _test_a_freed_claimant_does_not_hold_the_key() -> void:
	var input: Node = root.get_node_or_null(^"InputSystems")
	var claimant := _make_claimant()
	input.claim_interact(claimant)
	_dispose(claimant)
	_check(
		not input.is_interact_claimed(),
		"a freed claimant still reported as holding the interact key"
	)
	input.release_interact(null)


## A node that cannot take the key is refused and the owner kept (it used to take the key and crash on the
## next press); a claimant with only claimed() sits through a hold and a release.
func _test_only_a_claimant_takes_the_key() -> void:
	var input: Node = root.get_node_or_null(^"InputSystems")
	var owner := _make_claimant()
	var stranger := Node.new()
	root.add_child(stranger)
	input.claim_interact(owner)
	input.claim_interact(stranger)
	Input.action_press(&"interact")
	input._begin_interact()
	_check(owner.claimed == 1, "a node with no claimed() took the key from its owner")
	input.release_interact(owner)
	var bare := _make_bare_claimant()
	input.claim_interact(bare)
	input._begin_interact()
	input._tick_interact(0.2)
	Input.action_release(&"interact")
	input._end_interact()
	_check(bare.claimed == 1 and input.is_interact_claimed(), "a claimant with only claimed() was not served")
	input.release_interact(bare)
	for node: Node in [owner, stranger, bare]:
		_dispose(node)


func _make_bare_claimant() -> Node:
	var script := GDScript.new()
	script.source_code = """
extends Node

var claimed: int = 0


func own_press() -> void:
	claimed += 1


func _init() -> void:
	InteractClaimantCapability.publish(self, &"own_press")
"""
	script.reload()
	var node := Node.new()
	node.set_script(script)
	root.add_child(node)
	return node


func _make_claimant() -> Node:
	var script := GDScript.new()
	script.source_code = """
extends Node

var claimed: int = 0
var held: int = 0
var released: int = 0
var last_duration: float = 0.0


func on_interact_claimed() -> void:
	claimed += 1


func on_interact_held(duration: float) -> void:
	held += 1
	last_duration = duration


func on_interact_released(duration: float) -> void:
	released += 1
	last_duration = duration
"""
	script.reload()
	var node := Node.new()
	node.set_script(script)
	root.add_child(node)
	return node
