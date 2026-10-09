class_name InteractComponent
extends Node3D

## Two attentions pick what F acts on: the player's view picks world mechanisms,
## Henry's head picks pickups. World wins F; a pickup acts only when it can be done.

## The world mechanism under the player's view, and whether it is at arm's length.
signal world_target_changed(target: InteractiveArea, in_reach: bool)
## The pickup Henry attends to, and whether F would take it now.
signal pickup_target_changed(target: InteractiveArea, actionable: bool)
## What F acts on right now: the world target, else an actionable pickup.
signal active_target_changed(target: InteractiveArea)
## Emitted after F acted on a target.
signal interaction_performed(target: InteractiveArea)

## Seconds between special-awareness scans; they are rare and cheap.
const AWARENESS_INTERVAL: float = 0.2

@export_group("Intent")
## Flat distance from Henry within which objects can be selected at all.
@export var intent_radius: float = 2.5

@export_group("World")
## The view's aim must pass this close to a mechanism's focus area, degrees.
@export_range(1.0, 45.0, 0.5) var world_aim_cone_deg: float = 10.0
## The current world target stays selected until the aim leaves this wider cone.
@export_range(1.0, 3.0, 0.05) var world_exit_scale: float = 1.5
## Score bonus that keeps the current world target until another clearly wins.
@export var hysteresis_bonus: float = 0.1
## A world target missing for one or two frames is kept this long, seconds.
@export var world_grace_seconds: float = 0.15

@export_group("Pickup attention")
## Half-angle of Henry's pickup awareness field around his attention, degrees.
@export_range(10.0, 90.0, 1.0) var pickup_field_deg: float = 90.0
## Inside this flat distance the field is waived: the item at Henry's feet.
@export var close_override: float = 0.35
## Distance cost per metre, in degrees of attention error; a tie-breaker.
@export var distance_cost_deg_per_m: float = 6.0
## A challenger must beat the dominant pickup by this many degrees.
@export var switch_margin_deg: float = 4.0
## A dominant pickup losing line of sight for a moment is kept this long, seconds.
@export var pickup_grace_seconds: float = 0.15
## Pickups besides the dominant one kept as faint awareness hints.
@export var max_hint_markers: int = 3

@export_group("Approach")
## F acts on the spot inside this flat distance, otherwise Henry walks over.
@export var pickup_distance: float = 0.9
## Inside this distance a world target shows its central F prompt.
@export var prompt_distance: float = 2.0
## Seated, Henry leans: this far, picked by where he looks (stove ring, table).
@export var seated_reach: float = 2.0
## Seated, the view's aim cone is this wide, degrees.
@export var seated_aim_deg: float = 35.0
## Gives up a walk that stops making progress, seconds.
@export var approach_timeout: float = 4.0

var world_target: InteractiveArea = null
var pickup_target: InteractiveArea = null

var _player: CharacterBody3D
var _world_in_reach: bool = false
var _world_in_prompt: bool = false
var _world_missing: float = 0.0
var _pickup_actionable: bool = false
var _pickup_missing: float = 0.0
var _pickup_candidates: Array[InteractiveArea] = []
var _active: InteractiveArea = null
var _pending: InteractiveArea = null
var _approach_elapsed: float = 0.0
var _approach_stopped: bool = false
var _awareness_left: float = 0.0
## Special-awareness objects currently showing their check mark.
var _aware: Dictionary = {}


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	var input_systems: Node = get_node_or_null(^"/root/InputSystems")
	if input_systems != null:
		input_systems.connect(&"interact_pressed", try_interact)
	if _player != null and _player.has_signal(&"movement_stopped"):
		_player.connect(&"movement_stopped", _on_player_movement_stopped)


func _physics_process(delta: float) -> void:
	if _player == null:
		return
	detect_target(delta)
	_update_approach(delta)
	_awareness_left -= delta
	if _awareness_left <= 0.0:
		_awareness_left = AWARENESS_INTERVAL
		_update_awareness()


## Re-picks both channels now; normally run every physics frame.
func detect_target(delta: float = 0.0) -> void:
	var seated: bool = _is_seated()
	_set_world(_resolve_world(seated, delta))
	_set_pickup(_resolve_pickup(seated, delta))
	_refresh_active()


func get_world_target() -> InteractiveArea:
	return world_target if _is_available(world_target) else null


func is_world_target_in_reach() -> bool:
	return _is_available(world_target) and _flat_distance_to(world_target) <= _reach()


func get_pickup_target() -> InteractiveArea:
	return pickup_target if _is_available(pickup_target) else null


## True when F would take the dominant pickup: no world target and a way to do it.
func is_pickup_actionable() -> bool:
	return _is_available(pickup_target) and _pickup_actionable and get_world_target() == null


## The faint-hint pickups after the dominant one, best first.
func get_pickup_candidates() -> Array[InteractiveArea]:
	var alive: Array[InteractiveArea] = []
	for area: InteractiveArea in _pickup_candidates:
		if _is_available(area) and area != pickup_target:
			alive.append(area)
	return alive


## What F acts on right now: the world target, else an actionable pickup.
func get_active_target() -> InteractiveArea:
	var world: InteractiveArea = get_world_target()
	if world != null:
		return world
	return pickup_target if is_pickup_actionable() else null


## Whether F acts on the active target on the spot rather than walking over.
func is_active_target_in_reach() -> bool:
	var target: InteractiveArea = get_active_target()
	return target != null and _flat_distance_to(target) <= _reach()


## F states an intent: the world mechanism under the view first, else the pickup Henry attends to.
func try_interact() -> void:
	if _is_blocked():
		return
	detect_target()
	var world: InteractiveArea = get_world_target()
	if world != null:
		if _flat_distance_to(world) <= _reach():
			_stop_approach()
			_perform(world)
		elif not _is_seated():
			_begin_approach(world)
		return
	if not is_pickup_actionable():
		return
	var pickup: InteractiveArea = pickup_target
	if _flat_distance_to(pickup) <= _reach():
		_stop_approach()
		_perform(pickup)
	elif not _is_seated():
		_begin_approach(pickup)


func _perform(target: InteractiveArea) -> void:
	if not is_instance_valid(target):
		return
	## Pickups request their animation only after inventory acceptance.
	if target.get_interaction_channel() != InteractiveArea.InteractionChannel.PICKUP \
		and _player != null and _player.has_method(&"play_action_animation"):
		var action: StringName = target.player_animation_action
		if action == &"":
			action = &"interact"
		_player.call(&"play_action_animation", action)
	target.interact()
	## A consumed target stops being authoritative before observers hear interaction_performed.
	if not _is_available(target):
		if target == world_target:
			_set_world(null)
		if target == pickup_target:
			_set_pickup(null)
		_refresh_active()
	interaction_performed.emit(target)


## The world mechanism nearest the view's aim, within reach of Henry and in sight of the camera.
func _resolve_world(seated: bool, delta: float) -> InteractiveArea:
	var previous: InteractiveArea = world_target if _is_available(world_target) else null
	var radius: float = seated_reach if seated else intent_radius
	if previous != null and previous.keeps_focus() and _flat_distance_to_focus(previous) <= radius:
		return previous
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return null
	var from: Vector3 = TpsCamera.aim_origin(camera)
	var aim: Vector3 = TpsCamera.aim_direction(camera)
	var cone: float = deg_to_rad(seated_aim_deg if seated else world_aim_cone_deg)
	var scores: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group(InteractiveArea.INTERACTIVE_GROUP):
		var raw := node as InteractiveArea
		if not _is_world_candidate(raw) or not raw.accepts_focus(from, aim):
			continue
		var area: InteractiveArea = raw.resolve_focus(from, aim)
		if not _is_world_candidate(area) or scores.has(area):
			continue
		if _flat_distance_to_focus(area) > radius:
			continue
		var to_point: Vector3 = area.get_focus_point(_player.global_position) - from
		var distance: float = to_point.length()
		if distance < 0.01:
			continue
		## The focus radius widens acceptance only; ranking stays on the true angle.
		var angle: float = aim.angle_to(to_point)
		var limit: float = cone * (world_exit_scale if area == previous else 1.0) + atan(area.focus_radius / distance)
		if angle > limit:
			continue
		var score: float = 1.0 - angle / limit + area.focus_priority
		if area == previous:
			score += hysteresis_bonus
		scores[area] = score
	var ranked: Array = scores.keys()
	ranked.sort_custom(func(a: InteractiveArea, b: InteractiveArea) -> bool: return float(scores[a]) > float(scores[b]))
	for area: InteractiveArea in ranked:
		if _camera_sees(from, area):
			_world_missing = 0.0
			return area
	## Grace covers a target still under the aim but briefly out of sight, never one the view left.
	if previous != null and scores.has(previous) and _world_missing + delta < world_grace_seconds:
		_world_missing += delta
		return previous
	_world_missing = 0.0
	return null


## The pickup nearest Henry's attention inside his awareness field; distance breaks ties.
func _resolve_pickup(seated: bool, delta: float) -> InteractiveArea:
	_pickup_candidates.clear()
	if _pickup_channel_suspended():
		return null
	var previous: InteractiveArea = pickup_target if _is_available(pickup_target) else null
	var origin: Vector3 = get_attention_origin()
	var attention: Vector3 = get_attention_direction()
	var radius: float = seated_reach if seated else intent_radius
	var field: float = seated_aim_deg if seated else pickup_field_deg
	var costs: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group(InteractiveArea.INTERACTIVE_GROUP):
		var area := node as InteractiveArea
		if not _is_available(area) or area.get_interaction_channel() != InteractiveArea.InteractionChannel.PICKUP:
			continue
		var to_point: Vector3 = area.get_focus_point(origin) - origin
		to_point.y = 0.0
		var distance: float = to_point.length()
		if distance > radius:
			continue
		var error: float = rad_to_deg(attention.angle_to(to_point)) if distance > 0.001 else 0.0
		if error > field and distance > close_override:
			continue
		var cost: float = error + distance_cost_deg_per_m * distance
		if area == previous:
			cost -= switch_margin_deg
		costs[area] = cost
	var ranked: Array = costs.keys()
	ranked.sort_custom(func(a: InteractiveArea, b: InteractiveArea) -> bool: return float(costs[a]) < float(costs[b]))
	for area: InteractiveArea in ranked:
		if _pickup_candidates.size() > max_hint_markers:
			break
		if _head_sees(origin, area):
			_pickup_candidates.append(area)
	var dominant: InteractiveArea = _pickup_candidates[0] if not _pickup_candidates.is_empty() else null
	## A dominant pickup still in the field but briefly out of sight is held, not swapped.
	if previous != null and costs.has(previous) and not _pickup_candidates.has(previous) \
		and _pickup_missing + delta < pickup_grace_seconds:
		_pickup_missing += delta
		return previous
	_pickup_missing = 0.0
	return dominant


## Henry's attention origin, from his rig when he has one.
func get_attention_origin() -> Vector3:
	if _player.has_method(&"get_attention_origin"):
		return _player.call(&"get_attention_origin")
	return _player.global_position + Vector3.UP * Player.EYE_ABOVE_ORIGIN


## Henry's flat attention direction; his facing when the body offers none.
func get_attention_direction() -> Vector3:
	var direction: Vector3 = _player.call(&"get_attention_direction") if _player.has_method(&"get_attention_direction") \
		else -_player.global_transform.basis.z
	direction.y = 0.0
	return direction.normalized() if direction.length() > 0.001 else Vector3.FORWARD


## Opt-in check marks: rare objects Henry notices around him, in sight of his head.
func _update_awareness() -> void:
	var origin: Vector3 = get_attention_origin()
	var shown: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group(InteractiveArea.AWARENESS_GROUP):
		var area := node as InteractiveArea
		if not _is_available(area):
			continue
		var offset: Vector3 = area.get_focus_point(origin) - origin
		offset.y = 0.0
		var distance: float = offset.length()
		if distance > area.awareness_radius or not _head_sees(origin, area):
			continue
		area.set_hint_state(InteractiveArea.MarkerState.DOMINANT, 1.0 - clampf(distance / area.awareness_radius, 0.0, 0.6), origin)
		shown[area] = true
	for area: Variant in _aware.keys():
		if not shown.has(area) and is_instance_valid(area):
			(area as InteractiveArea).set_hint_state(InteractiveArea.MarkerState.HIDDEN, 0.0, origin)
	_aware = shown


func _set_world(target: InteractiveArea) -> void:
	var in_reach: bool = target != null and _flat_distance_to(target) <= _reach()
	var in_prompt: bool = target != null and _flat_distance_to(target) <= prompt_distance
	var changed: bool = target != world_target
	if changed:
		if is_instance_valid(world_target):
			world_target.set_target_state(false, false)
		world_target = target
		if target != null:
			target.set_target_state(true, in_prompt)
	elif target != null and in_prompt != _world_in_prompt:
		target.set_target_state(true, in_prompt)
	if changed or in_reach != _world_in_reach:
		_world_in_reach = in_reach
		world_target_changed.emit(target, in_reach)
	_world_in_prompt = in_prompt
	if target == null:
		_world_missing = 0.0


func _set_pickup(target: InteractiveArea) -> void:
	var actionable: bool = target != null and _can_act_on_pickup(target)
	var changed: bool = target != pickup_target
	pickup_target = target
	if changed or actionable != _pickup_actionable:
		_pickup_actionable = actionable
		pickup_target_changed.emit(target, actionable)
	if target == null:
		_pickup_missing = 0.0


func _refresh_active() -> void:
	var active: InteractiveArea = get_active_target()
	if active != _active:
		_active = active
		active_target_changed.emit(active)


## Whether F could take this pickup: within reach, or a walk can bring Henry there.
func _can_act_on_pickup(target: InteractiveArea) -> bool:
	return _flat_distance_to(target) <= _reach() or not _is_seated()


func _is_world_candidate(area: InteractiveArea) -> bool:
	return _is_available(area) and area.get_interaction_channel() == InteractiveArea.InteractionChannel.WORLD


## Board placement and the open Hub own the hands and the view; no pickup is offered.
func _pickup_channel_suspended() -> bool:
	var placement := get_tree().get_first_node_in_group(&"active_board_placement") as BreachBoardUp
	if is_instance_valid(placement) and placement.is_placing_board():
		return true
	var hub := _player.get_node_or_null(^"PlayerHubComponent") as PlayerHubComponent
	return hub != null and hub.is_open()


## Camera to focus point; the object's own bodies never occlude it.
func _camera_sees(from: Vector3, area: InteractiveArea) -> bool:
	return _sees(from, area.get_focus_point(_player.global_position), area)


## Henry's head to the focus point; the object's own bodies never occlude it.
func _head_sees(origin: Vector3, area: InteractiveArea) -> bool:
	return _sees(origin, area.get_focus_point(origin), area)


func _sees(from: Vector3, point: Vector3, area: InteractiveArea) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(from, point)
	ray.collide_with_areas = false
	ray.collide_with_bodies = true
	ray.exclude = [_player.get_rid()]
	var hit: Dictionary = _player.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return true
	return _owns_focus_body(_area_from(hit.get("collider")), area)


func _is_available(area: InteractiveArea) -> bool:
	return is_instance_valid(area) and not area.is_queued_for_deletion() and area.can_interact()


func _is_seated() -> bool:
	var rest := _player.get_node_or_null(^"RestComponent") as RestComponent if _player != null else null
	return rest != null and rest.is_sitting()


func _reach() -> float:
	return seated_reach if _is_seated() else pickup_distance


func _area_from(collider: Variant) -> InteractiveArea:
	if not is_instance_valid(collider):
		return null
	var owner_ref: WeakRef = null
	if collider.has_meta(InteractiveArea.FOCUS_OWNER_META):
		owner_ref = collider.get_meta(InteractiveArea.FOCUS_OWNER_META) as WeakRef
	if owner_ref != null:
		var target: InteractiveArea = owner_ref.get_ref() as InteractiveArea
		if is_instance_valid(target) and not target.is_queued_for_deletion() and target.can_interact():
			return target
	var node := collider as Node
	while node != null:
		if node is InteractiveArea:
			var area := node as InteractiveArea
			return area if not area.is_queued_for_deletion() and area.can_interact() else null
		node = node.get_parent()
	return null


func _flat_distance_to(target: Node3D) -> float:
	if not is_instance_valid(target) or not is_instance_valid(_player):
		return INF
	var offset: Vector3 = target.global_position - _player.global_position
	offset.y = 0.0
	return offset.length()


func _flat_distance_to_focus(area: InteractiveArea) -> float:
	var offset: Vector3 = area.get_focus_point(_player.global_position) - _player.global_position
	offset.y = 0.0
	return offset.length()


## Walks to a point on the line from the target toward Henry, inside reach.
func _begin_approach(target: InteractiveArea) -> void:
	if not _player.has_method(&"move_to_position"):
		return
	var from_target: Vector3 = _player.global_position - target.global_position
	from_target.y = 0.0
	if from_target.length() < 0.01:
		return
	var stop_point: Vector3 = target.global_position + from_target.normalized() * pickup_distance * 0.75
	stop_point.y = _player.global_position.y
	_pending = target
	_approach_elapsed = 0.0
	_approach_stopped = false
	_player.call(&"move_to_position", stop_point)


## A committed pickup arrives on the item F chose, never on the attention's new favourite.
## A world mechanism must still be under the view on arrival.
func _update_approach(delta: float) -> void:
	if _pending == null:
		return
	if not _is_available(_pending) or _is_blocked():
		_stop_approach()
		return
	var committed: bool = _pending.get_interaction_channel() == InteractiveArea.InteractionChannel.PICKUP
	## WASD taking over cancels the pickup intent before any arrival is processed.
	if committed and _approach_stopped:
		_stop_approach()
		return
	var distance: float = _flat_distance_to(_pending)
	if committed and distance > intent_radius:
		_stop_approach()
		return
	if (committed or _pending == world_target) and distance <= _reach():
		var target: InteractiveArea = _pending
		_stop_approach()
		_perform(target)
		return
	_approach_elapsed += delta
	if _approach_stopped or _approach_elapsed >= approach_timeout:
		_stop_approach()


func _stop_approach() -> void:
	var was_walking: bool = _pending != null
	_cancel_approach()
	if was_walking and _player.has_method(&"stop_moving"):
		_player.call(&"stop_moving")


func _cancel_approach() -> void:
	_pending = null
	_approach_elapsed = 0.0
	_approach_stopped = false


func _on_player_movement_stopped() -> void:
	if _pending != null:
		_approach_stopped = true


func _is_blocked() -> bool:
	if is_instance_valid(_player) and _player.has_method(&"is_action_locking") \
		and bool(_player.call(&"is_action_locking")):
		return true
	var state: Node = get_node_or_null(^"/root/PlayerState")
	return state != null and bool(state.call(&"is_movement_blocked"))


func _owns_focus_body(owner_area: InteractiveArea, target: InteractiveArea) -> bool:
	if not is_instance_valid(owner_area) or not is_instance_valid(target):
		return false
	return owner_area == target \
		or (target is StoveDoorControl and (target as StoveDoorControl).feed == owner_area) \
		or (owner_area is StoveDoorControl and (owner_area as StoveDoorControl).feed == target)
