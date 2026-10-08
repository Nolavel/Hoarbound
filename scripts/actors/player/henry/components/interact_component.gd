class_name InteractComponent
extends Node3D

## The objects before Henry form a group; the one nearest his gaze is the target.
## A requested pickup stays selected for arrival even as the walking camera moves.

## What is targeted and whether it is already within arm's reach.
signal interact_target_changed(target: InteractiveArea, in_reach: bool)
## Emitted after F acted on a target.
signal interaction_performed(target: InteractiveArea)

## Line of sight and the gaze ray start at Henry's chest, not at the camera.
const CHEST_HEIGHT: float = 1.3

@export_group("Intent")
## Flat distance to an object's focus point at which it joins the group.
@export var intent_radius: float = 2.5
## Standing, objects further than this angle from Henry's body facing never join.
@export_range(1.0, 180.0, 1.0) var facing_limit_deg: float = 100.0
## Inside this flat distance the facing cone is waived: the item at Henry's feet.
@export var close_override: float = 0.5
## Standing still, Henry's head turns towards the view by at most this angle.
## Keep it equal to HenryUALAnimation.head_look_primary_limit_deg.
@export_range(0.0, 90.0, 1.0) var head_turn_limit_deg: float = 55.0
## Below this flat speed Henry counts as standing and looks with his head, m/s.
@export var still_speed: float = 0.15
## Gaze score falls from 1 on the gaze line to 0 at this angle off it.
@export_range(1.0, 180.0, 1.0) var gaze_cone_deg: float = 60.0
## Score weight of how exactly Henry looks at the object; keep above distance_weight.
@export var gaze_weight: float = 1.0
## Score weight of closeness within the radius; a tie-breaker.
@export var distance_weight: float = 0.25
## Score bonus that keeps the current target until another clearly wins.
@export var hysteresis_bonus: float = 0.05

@export_group("Markers")
## Group members besides the target that show a dim marker at once.
@export var max_hint_markers: int = 3

@export_group("Approach")
## F acts on the spot inside this flat distance, otherwise Henry walks over.
@export var pickup_distance: float = 0.9
## Inside this distance the object shows its F prompt instead of a marker.
@export var prompt_distance: float = 2.0
## Seated, Henry leans: this far, picked by where he looks (stove ring, table).
@export var seated_reach: float = 2.0
## Seated, a target must lie within this angle of Henry's gaze.
@export var seated_aim_deg: float = 35.0
## Gives up a walk that stops making progress, seconds.
@export var approach_timeout: float = 4.0

var current_target: InteractiveArea = null

var _player: CharacterBody3D
var _last_in_reach: bool = false
var _last_in_prompt: bool = false
var _pending: InteractiveArea = null
var _approach_elapsed: float = 0.0
var _approach_stopped: bool = false
## Marker state last sent to each object, so leavers are switched off once.
var _markers: Dictionary = {}


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
	detect_target()
	_update_approach(delta)


## Re-picks the target now; normally run every physics frame.
func detect_target() -> void:
	if not is_instance_valid(current_target):
		if _last_in_reach or _last_in_prompt:
			_clear_current_target(false)
		current_target = null
	elif current_target.is_queued_for_deletion() or not current_target.can_interact():
		_clear_current_target()
	var found: InteractiveArea = _find_best_target()
	var distance: float = _flat_distance_to(found) if found != null else INF
	var in_reach: bool = distance <= _reach()
	var in_prompt: bool = distance <= prompt_distance
	var changed: bool = found != current_target
	if changed:
		if current_target != null:
			current_target.set_target_state(false, false)
		current_target = found
		if found != null:
			found.set_target_state(true, in_prompt)
	elif found != null and in_prompt != _last_in_prompt:
		found.set_target_state(true, in_prompt)
	if changed or in_reach != _last_in_reach or in_prompt != _last_in_prompt:
		interact_target_changed.emit(current_target, in_reach)
	_last_in_reach = in_reach
	_last_in_prompt = in_prompt


func is_target_in_reach() -> bool:
	return is_instance_valid(current_target) and _flat_distance_to(current_target) <= _reach()


## Clears the authoritative focus state, not just its visuals. This is used when
## a target is consumed, disabled, queued for deletion or disappears from the tree.
func _clear_current_target(update_target_state: bool = true) -> void:
	var previous: InteractiveArea = current_target
	if update_target_state and is_instance_valid(previous):
		previous.set_target_state(false, false)
	current_target = null
	_last_in_reach = false
	_last_in_prompt = false
	if _pending == previous:
		_stop_approach()
	interact_target_changed.emit(null, false)


## F states an intent: act now at arm's length, or walk over and act on arrival.
func try_interact() -> void:
	if _is_blocked():
		return
	if not is_instance_valid(current_target):
		_clear_current_target(false)
		return
	if current_target.is_queued_for_deletion() or not current_target.can_interact():
		_clear_current_target()
		return
	if _flat_distance_to(current_target) <= _reach():
		_stop_approach()
		_perform(current_target)
		return
	if not _is_seated():
		_begin_approach(current_target)


func _perform(target: InteractiveArea) -> void:
	if not is_instance_valid(target):
		return
	## Pickups request their animation only after inventory acceptance.
	if not (target is ItemPickup) and _player != null and _player.has_method(&"play_action_animation"):
		var action: StringName = target.player_animation_action
		if action == &"":
			action = &"interact"
		_player.call(&"play_action_animation", action)
	target.interact()
	# A consumed/deactivated target stops being authoritative before UI observers
	# receive interaction_performed. This prevents one stale process frame.
	if current_target == target and is_instance_valid(target):
		if target.is_queued_for_deletion() or not target.can_interact():
			_clear_current_target()
	interaction_performed.emit(target)


## Builds the group before Henry, marks it, and returns its dominant member.
func _find_best_target() -> InteractiveArea:
	var seated: bool = _is_seated()
	var radius: float = seated_reach if seated else intent_radius
	var group: Array[InteractiveArea] = _visible_group(seated, radius)
	var best: InteractiveArea = group[0] if not group.is_empty() else null
	if is_instance_valid(current_target) and current_target.keeps_focus() \
		and current_target.can_interact() and _flat_distance_to(current_target) <= radius:
		best = current_target
	_mark_group(group, best, radius)
	return best


## Candidates that pass the gates, best gaze score first, cut to those Henry can see.
func _visible_group(seated: bool, radius: float) -> Array[InteractiveArea]:
	var origin: Vector3 = _player.global_position
	var chest: Vector3 = _chest()
	var facing: Vector3 = get_facing_direction()
	var gaze: Vector3 = get_gaze_direction()
	var facing_limit: float = deg_to_rad(facing_limit_deg)
	var gaze_cone: float = deg_to_rad(gaze_cone_deg)
	var seated_limit: float = deg_to_rad(seated_aim_deg)
	var scores: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group(InteractiveArea.INTERACTIVE_GROUP):
		var raw := node as InteractiveArea
		if not _is_available(raw):
			continue
		var aim: Vector3 = _gaze_ray(chest, gaze, raw.get_focus_point(origin))
		if not raw.accepts_focus(chest, aim):
			continue
		var area: InteractiveArea = raw.resolve_focus(chest, aim)
		if not _is_available(area) or scores.has(area):
			continue
		var to_point: Vector3 = area.get_focus_point(origin) - origin
		to_point.y = 0.0
		var distance: float = to_point.length()
		if distance > radius:
			continue
		var close: bool = distance <= close_override
		if not seated and not close and facing.angle_to(to_point) > facing_limit:
			continue
		var gaze_angle: float = gaze.angle_to(to_point) if distance > 0.001 else 0.0
		if seated and not close and gaze_angle > seated_limit:
			continue
		var score: float = gaze_weight * clampf(1.0 - gaze_angle / gaze_cone, 0.0, 1.0) \
			+ distance_weight * (1.0 - distance / radius) + area.focus_priority
		if area == current_target:
			score += hysteresis_bonus
		scores[area] = score
	var ranked: Array = scores.keys()
	ranked.sort_custom(func(a: InteractiveArea, b: InteractiveArea) -> bool: return float(scores[a]) > float(scores[b]))
	var group: Array[InteractiveArea] = []
	for area: InteractiveArea in ranked:
		if group.size() > max_hint_markers:
			break
		if _has_line_of_sight(area):
			group.append(area)
	return group


## Henry's gaze, flat: moving, his body; standing or seated, his head turned
## towards the view direction as far as his neck allows.
func get_gaze_direction() -> Vector3:
	var facing: Vector3 = get_facing_direction()
	if not _player.has_method(&"get_view_direction"):
		return facing
	var planar_speed: float = Vector2(_player.velocity.x, _player.velocity.z).length()
	if planar_speed >= still_speed and not _is_seated():
		return facing
	var view: Vector3 = _player.call(&"get_view_direction")
	view.y = 0.0
	if view.length() < 0.001:
		return facing
	var limit: float = deg_to_rad(head_turn_limit_deg)
	var yaw: float = clampf(facing.signed_angle_to(view.normalized(), Vector3.UP), -limit, limit)
	return facing.rotated(Vector3.UP, yaw)


## The gaze line pitched to the object's height: Henry looks along his gaze at its level.
func _gaze_ray(chest: Vector3, gaze: Vector3, point: Vector3) -> Vector3:
	var flat: Vector3 = point - chest
	flat.y = 0.0
	var ray: Vector3 = gaze * flat.length() + Vector3.UP * (point.y - chest.y)
	return ray.normalized() if ray.length() > 0.001 else gaze


## Henry's chest to the focus point; the object's own bodies never occlude it.
func _has_line_of_sight(area: InteractiveArea) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(_chest(), area.get_focus_point(_player.global_position))
	ray.collide_with_areas = false
	ray.collide_with_bodies = true
	ray.exclude = [_player.get_rid()]
	var hit: Dictionary = _player.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return true
	return _owns_focus_body(_area_from(hit.get("collider")), area)


## The target gets the bright marker, the rest of the group a dim one, others none.
## Opacity fades out between prompt_distance and the group radius.
func _mark_group(group: Array[InteractiveArea], target: InteractiveArea, radius: float) -> void:
	var origin: Vector3 = _player.global_position
	var fade_span: float = maxf(radius - prompt_distance, 0.001)
	var marked: Dictionary = {}
	var dim_left: int = max_hint_markers
	for area: InteractiveArea in group:
		var state: InteractiveArea.MarkerState = InteractiveArea.MarkerState.DOMINANT
		if area != target:
			if dim_left <= 0:
				continue
			dim_left -= 1
			state = InteractiveArea.MarkerState.DIM
		var distance: float = _flat_distance_to(area)
		area.set_hint_state(state, 1.0 - clampf((distance - prompt_distance) / fade_span, 0.0, 1.0), origin)
		marked[area] = state
	for area: Variant in _markers.keys():
		if not marked.has(area) and is_instance_valid(area):
			(area as InteractiveArea).set_hint_state(InteractiveArea.MarkerState.HIDDEN, 0.0, origin)
	_markers = marked


func _chest() -> Vector3:
	return _player.global_position + Vector3.UP * CHEST_HEIGHT


func _is_available(area: InteractiveArea) -> bool:
	return is_instance_valid(area) and not area.is_queued_for_deletion() and area.can_interact()


func _is_seated() -> bool:
	var rest := _player.get_node_or_null(^"RestComponent") as RestComponent if _player != null else null
	return rest != null and rest.is_sitting()


func _reach() -> float:
	return seated_reach if _is_seated() else pickup_distance


## Henry's flat forward; the body faces -Z.
func get_facing_direction() -> Vector3:
	var forward: Vector3 = -_player.global_transform.basis.z
	forward.y = 0.0
	return forward.normalized() if forward.length() > 0.001 else Vector3.FORWARD


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


## Pickup arrival uses the item requested by F, not the moving camera's focus.
## Other interactions keep their live focus requirement.
func _update_approach(delta: float) -> void:
	if _pending == null:
		return
	if not is_instance_valid(_pending) or _pending.is_queued_for_deletion() \
		or not _pending.can_interact() or _is_blocked():
		_stop_approach()
		return
	var pickup_requested: bool = _pending is ItemPickup
	## WASD taking over cancels the pickup intent before any arrival is processed.
	if pickup_requested and _approach_stopped:
		_stop_approach()
		return
	var distance: float = _flat_distance_to(_pending)
	if pickup_requested and distance > intent_radius:
		_stop_approach()
		return
	if (pickup_requested or _pending == current_target) and distance <= _reach():
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




func is_crosshair_focused() -> bool:
	return is_instance_valid(current_target)


func _owns_focus_body(owner_area: InteractiveArea, target: InteractiveArea) -> bool:
	if not is_instance_valid(owner_area) or not is_instance_valid(target):
		return false
	return owner_area == target \
		or (target is StoveDoorControl and (target as StoveDoorControl).feed == owner_area) \
		or (owner_area is StoveDoorControl and (owner_area as StoveDoorControl).feed == target)
