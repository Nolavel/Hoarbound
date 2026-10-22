class_name StoveInteractionController
extends Node

## The stove ritual's mode. F walks Henry to StoveInteractionPoint (never a teleport), turns him to
## the door, opens it and crouches him; RMB lays one log, LMB the tinder, a new LMB press works the
## lighter; F closes the door and stands him up. HeatSourceFeed does the acts, HeatSource keeps state.

signal phase_changed(phase: Phase)

enum Phase { OUTSIDE, APPROACHING, OPENING_DOOR, ENTERING_CROUCH, WORKING, EXITING }

const POINT_NAME: StringName = &"StoveInteractionPoint"
## Henry's spot in front of the door, in stove space (+X is the door side): the 0.31 m half
## depth, a crouched body's knees and the reach of the arms into the firebox.
const POINT_OFFSET: Vector3 = Vector3(0.82, 0.0, 0.0)
## Henry counts as on the spot within this flat distance and facing within this angle.
const ARRIVAL_DISTANCE: float = 0.12
const FACING_TOLERANCE_DEG: float = 10.0
## A walk that gains less than STALL_PROGRESS in STALL_SECONDS, or outlasts the timeout, failed.
const APPROACH_TIMEOUT: float = 6.0
const STALL_SECONDS: float = 0.8
const STALL_PROGRESS: float = 0.04
## The door's swing (StoveVisual tweens 0.35 s) and the crouch settling, seconds.
const DOOR_SECONDS: float = 0.4
const CROUCH_SECONDS: float = 0.35
const EXIT_SECONDS: float = 0.45
## Henry turns to the door at this rate while the door opens, radians per second.
const TURN_RATE: float = 8.0
## Work framing in stove space (owner's composition): high over Henry's left shoulder, his head
## and shoulder low left, the stove mid-frame and the open door just right of centre.
const VIEW_FOCUS: Vector3 = Vector3(0.12, 0.32, 0.0)
const VIEW_EYE: Vector3 = Vector3(1.55, 1.85, 0.6)

var feed: HeatSourceFeed

var _phase: Phase = Phase.OUTSIDE
var _player: Player
var _point: Marker3D
var _ring: StoveInteractionRing
var _phase_left: float = 0.0
var _approach_elapsed: float = 0.0
var _approach_best: float = INF
var _approach_stall: float = 0.0
var _lmb_down: bool = false
## Set by the press that laid the tinder: that press never also strikes the lighter.
var _await_lmb_release: bool = false
var _claimed: bool = false
var _set_working_mode: bool = false


func _ready() -> void:
	set_physics_process(false)


func get_phase() -> Phase:
	return _phase


func is_working() -> bool:
	return _phase == Phase.WORKING


func is_active() -> bool:
	return _phase != Phase.OUTSIDE


func get_ring() -> StoveInteractionRing:
	return _ring


## The working spot, made in stove space so it follows the stove wherever it is placed.
func get_interaction_point() -> Marker3D:
	if is_instance_valid(_point):
		return _point
	var source: HeatSource = feed.heat_source if feed != null else null
	if source == null:
		return null
	_point = source.get_node_or_null(NodePath(String(POINT_NAME))) as Marker3D
	if _point == null:
		_point = Marker3D.new()
		_point.name = POINT_NAME
		source.add_child(_point)
		## Facing the door: the marker's -Z looks back into the firebox (-X of the stove).
		_point.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), POINT_OFFSET)
	return _point


## F on the stove: walk to the spot, or start at once if Henry already stands on it.
func request_enter() -> void:
	if _phase != Phase.OUTSIDE or feed == null or feed.heat_source == null or _paused():
		return
	_player = get_tree().get_first_node_in_group(&"player") as Player
	var point: Marker3D = get_interaction_point()
	if _player == null or point == null:
		return
	if not _spot_is_free(point.global_position):
		feed.show_message(tr(&"INTERACT_UNREACHABLE"))
		return
	_claim_interact(true)
	if _flat_distance() <= ARRIVAL_DISTANCE:
		_begin_open()
		return
	_approach_elapsed = 0.0
	_approach_best = INF
	_approach_stall = 0.0
	_set_phase(Phase.APPROACHING)
	_player.move_to_position(_walk_target())
	set_physics_process(true)


## F while working: close the door and stand; F during the walk gives the walk up.
func request_exit() -> void:
	match _phase:
		Phase.APPROACHING:
			_abort(&"")
		Phase.OPENING_DOOR, Phase.ENTERING_CROUCH, Phase.WORKING:
			_begin_exit()


## InputSystems hands the interact key here while the ritual runs.
func on_interact_claimed() -> void:
	request_exit()


func on_interact_held(_duration: float) -> void:
	pass


func on_interact_released(_duration: float) -> void:
	pass


func _physics_process(delta: float) -> void:
	if _paused():
		return
	if not is_instance_valid(_player) or feed == null or not is_instance_valid(feed.heat_source):
		_abort(&"")
		return
	match _phase:
		Phase.APPROACHING:
			_update_approach(delta)
		Phase.OPENING_DOOR:
			_turn_to_door(delta)
			_phase_left -= delta
			if _phase_left <= 0.0:
				_player.set_work_crouch(true)
				_phase_left = CROUCH_SECONDS
				_set_phase(Phase.ENTERING_CROUCH)
		Phase.ENTERING_CROUCH:
			_turn_to_door(delta)
			_phase_left -= delta
			if _phase_left <= 0.0 and _player.is_crouching() and is_facing_door():
				_show_ring(true)
				_set_phase(Phase.WORKING)
		Phase.WORKING:
			_keep_lighter_ready()
		Phase.EXITING:
			_phase_left -= delta
			if _phase_left <= 0.0:
				_finish_exit()


func _input(event: InputEvent) -> void:
	if _phase == Phase.OUTSIDE or _paused():
		return
	var mouse := event as InputEventMouseButton
	if mouse == null or mouse.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		return
	## The stove owns both buttons for the whole ritual: Quick Access and tools never see them.
	get_viewport().set_input_as_handled()
	if mouse.button_index == MOUSE_BUTTON_LEFT and not mouse.pressed:
		on_lmb_released()
		return
	if not mouse.pressed or mouse.is_echo() or _phase != Phase.WORKING:
		return
	if mouse.button_index == MOUSE_BUTTON_RIGHT:
		on_rmb_pressed()
	else:
		on_lmb_pressed()


## RMB: exactly one log per press; a held button sends no more presses.
func on_rmb_pressed() -> void:
	if _phase != Phase.WORKING:
		return
	if feed.get_stage() == HeatSourceFeed.Stage.HOLDING:
		feed.report(HeatSourceFeed.Refusal.BUSY)
		return
	feed.report(feed.insert_fuel())


## LMB: tinder first; with tinder laid, a fresh press strikes the existing lighter.
func on_lmb_pressed() -> void:
	_lmb_down = true
	if _phase != Phase.WORKING:
		return
	var source: HeatSource = feed.heat_source
	if source.is_burning():
		feed.report(HeatSourceFeed.Refusal.ALREADY_BURNING)
		return
	if not source.is_tinder_prepared():
		if feed.is_acting():
			feed.report(HeatSourceFeed.Refusal.BUSY)
			return
		var refusal: HeatSourceFeed.Refusal = feed.insert_tinder()
		if refusal == HeatSourceFeed.Refusal.NONE:
			_await_lmb_release = true
		feed.report(refusal)
		return
	if _await_lmb_release:
		return
	match feed.get_stage():
		HeatSourceFeed.Stage.READY:
			feed.attempt_lighter_strike()
		HeatSourceFeed.Stage.IDLE:
			feed.report(feed.prepare_lighter())
		_:
			feed.report(HeatSourceFeed.Refusal.BUSY)


func on_lmb_released() -> void:
	_lmb_down = false
	_await_lmb_release = false
	if feed != null and feed.get_stage() == HeatSourceFeed.Stage.HOLDING:
		feed.release_lighter()


## With tinder laid and the button up, the existing lighter comes out ready for a new press.
func _keep_lighter_ready() -> void:
	if _lmb_down or _await_lmb_release or feed.is_acting():
		return
	if feed.get_lighter_refusal() == HeatSourceFeed.Refusal.NONE:
		feed.prepare_lighter()


func _update_approach(delta: float) -> void:
	var remaining: float = _flat_distance()
	if remaining <= ARRIVAL_DISTANCE:
		_player.stop_moving()
		_begin_open()
		return
	if not _player.is_walking_to_target():
		## Braked onto the spot within tolerance, or WASD took the walk back.
		if remaining <= ARRIVAL_DISTANCE * 2.0:
			_begin_open()
		else:
			_abort(&"")
		return
	## A gesture still finishing (a work pose returning) roots Henry; it is not a stall.
	if _player.is_action_locking():
		return
	_approach_elapsed += delta
	if remaining < _approach_best - STALL_PROGRESS:
		_approach_best = remaining
		_approach_stall = 0.0
	else:
		_approach_stall += delta
	if _approach_stall >= STALL_SECONDS or _approach_elapsed >= APPROACH_TIMEOUT:
		_abort(&"INTERACT_UNREACHABLE")


func _begin_open() -> void:
	_claim_interact(true)
	_enter_working_mode()
	feed.session_active = true
	feed.set_door_open(true)
	_frame_camera(true)
	_phase_left = DOOR_SECONDS
	_set_phase(Phase.OPENING_DOOR)
	set_physics_process(true)


func _begin_exit() -> void:
	_lmb_down = false
	_await_lmb_release = false
	## Nothing changes hands half-way: an act that has not committed is cancelled whole.
	feed.cancel_act(&"stove_exit")
	feed.session_active = false
	feed.set_door_open(false)
	_show_ring(false)
	_frame_camera(false)
	_phase_left = EXIT_SECONDS
	_set_phase(Phase.EXITING)


func _finish_exit() -> void:
	if is_instance_valid(_player):
		_player.set_work_crouch(false)
	_restore_mode()
	_claim_interact(false)
	set_physics_process(false)
	_set_phase(Phase.OUTSIDE)


func _abort(message: StringName) -> void:
	if is_instance_valid(_player) and _phase == Phase.APPROACHING:
		_player.stop_moving()
	if feed != null:
		feed.cancel_act(&"stove_abort")
		feed.session_active = false
		if feed.is_door_open():
			feed.set_door_open(false)
		if message != &"":
			feed.show_message(tr(message))
	_show_ring(false)
	_frame_camera(false)
	if is_instance_valid(_player):
		_player.set_work_crouch(false)
	_restore_mode()
	_claim_interact(false)
	_lmb_down = false
	_await_lmb_release = false
	set_physics_process(false)
	_set_phase(Phase.OUTSIDE)


func _exit_tree() -> void:
	if _phase != Phase.OUTSIDE:
		_abort(&"")
	if is_instance_valid(_ring):
		_ring.get_parent().queue_free()
		_ring = null


func _turn_to_door(delta: float) -> void:
	var door: Vector3 = feed.focus_anchor.global_position
	var to_door: Vector3 = door - _player.global_position
	to_door.y = 0.0
	if to_door.length_squared() < 0.0001:
		return
	var goal: float = atan2(-to_door.x, -to_door.z)
	if absf(angle_difference(_player.rotation.y, goal)) <= deg_to_rad(FACING_TOLERANCE_DEG) * 0.25:
		_player.rotation.y = goal
		return
	_player.rotation.y = lerp_angle(_player.rotation.y, goal, minf(1.0, TURN_RATE * delta))


## Facing the door within FACING_TOLERANCE_DEG (tests and the ring use it).
func is_facing_door() -> bool:
	if not is_instance_valid(_player) or feed == null:
		return false
	var to_door: Vector3 = feed.focus_anchor.global_position - _player.global_position
	to_door.y = 0.0
	var forward: Vector3 = -_player.global_basis.z
	forward.y = 0.0
	return to_door.length() > 0.01 and rad_to_deg(forward.angle_to(to_door)) <= FACING_TOLERANCE_DEG


func _walk_target() -> Vector3:
	var at: Vector3 = get_interaction_point().global_position
	at.y = _player.global_position.y
	return at


func _flat_distance() -> float:
	var offset: Vector3 = get_interaction_point().global_position - _player.global_position
	offset.y = 0.0
	return offset.length()


## Henry's capsule fits on the spot (a cabinet pushed against the stove blocks the ritual).
func _spot_is_free(at: Vector3) -> bool:
	var body := _player.get_node_or_null(^"Main_Collision") as CollisionShape3D
	var capsule := body.shape as CapsuleShape3D if body != null else null
	if capsule == null:
		return true
	var shape := CylinderShape3D.new()
	shape.radius = capsule.radius * 0.9
	shape.height = 0.6
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	var floor_y: float = _player.global_position.y - capsule.height * 0.5
	query.transform = Transform3D(Basis.IDENTITY, Vector3(at.x, floor_y + 0.7, at.z))
	query.exclude = [_player.get_rid()]
	query.collision_mask = _player.collision_mask
	return _player.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


## PlayerState WORKING roots Henry (no WASD, sprint, jump or pickups) for the whole ritual.
func _enter_working_mode() -> void:
	var state: Node = get_node_or_null(^"/root/PlayerState")
	if state == null or int(state.get("mode")) != _mode(&"ON_FOOT"):
		return
	state.call(&"set_mode", _mode(&"WORKING"))
	_set_working_mode = true


func _restore_mode() -> void:
	if not _set_working_mode:
		return
	_set_working_mode = false
	var state: Node = get_node_or_null(^"/root/PlayerState")
	if state != null and int(state.get("mode")) == _mode(&"WORKING"):
		state.call(&"set_mode", _mode(&"ON_FOOT"))


func _mode(mode_name: StringName) -> int:
	var state: Node = get_node_or_null(^"/root/PlayerState")
	return int(state.get_script().get_script_constant_map().get("Mode", {}).get(String(mode_name), -1)) if state != null else -1


func _claim_interact(claim: bool) -> void:
	var input_systems: Node = get_node_or_null(^"/root/InputSystems")
	if input_systems == null or claim == _claimed:
		return
	_claimed = claim
	input_systems.call(&"claim_interact" if claim else &"release_interact", self)


func _show_ring(shown: bool) -> void:
	if shown and not is_instance_valid(_ring):
		var layer := CanvasLayer.new()
		layer.name = "StoveRingLayer"
		layer.layer = 5
		add_child(layer)
		_ring = StoveInteractionRing.new()
		_ring.bind(feed)
		layer.add_child(_ring)
	if is_instance_valid(_ring):
		_ring.set_shown(shown)


## The production TPS camera eases onto the open firebox and Henry's hands; no second camera.
func _frame_camera(framed: bool) -> void:
	var viewport: Viewport = get_viewport()
	var camera := viewport.get_camera_3d() as TpsCamera if viewport != null else null
	if camera == null:
		return
	var source: HeatSource = feed.heat_source if feed != null else null
	if framed and is_instance_valid(source):
		camera.set_work_framing(source.to_global(VIEW_FOCUS), source.to_global(VIEW_EYE))
	else:
		camera.clear_work_framing()


func _set_phase(phase: Phase) -> void:
	if phase == _phase:
		return
	_phase = phase
	phase_changed.emit(phase)


func _paused() -> bool:
	var state: Node = get_node_or_null(^"/root/PlayerState")
	return state != null and bool(state.call(&"is_paused"))
