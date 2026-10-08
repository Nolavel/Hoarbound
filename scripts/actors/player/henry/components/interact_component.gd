class_name InteractComponent
extends Node3D

## Scores interactive objects in a cone before Henry; the camera refines the pick.
## A requested pickup stays selected for arrival even as the walking camera moves.

## What is targeted and whether it is already within arm's reach.
signal interact_target_changed(target: InteractiveArea, in_reach: bool)
## Emitted after F acted on a target.
signal interaction_performed(target: InteractiveArea)

## Line of sight starts at Henry's chest, not at the camera.
const CHEST_HEIGHT: float = 1.3
## Only this many best-scored candidates pay for a line-of-sight ray.
const SIGHT_CHECKS: int = 3
## Seconds between passes of the far marker layer.
const HINT_INTERVAL: float = 0.1
## Seated Henry does not turn: the camera decides.
const SEATED_FACING_WEIGHT: float = 0.1
const SEATED_CAMERA_WEIGHT: float = 1.0
## A target picked with interact_cycle holds until Henry moves this far, metres.
const MANUAL_HOLD_DISTANCE: float = 0.5

@export_group("Intent")
## Flat distance to an object's focus point at which it can become current_target.
@export var intent_radius: float = 2.5
## Standing, objects further than this angle from Henry's facing are never picked.
@export_range(1.0, 180.0, 1.0) var facing_limit_deg: float = 100.0
## Inside this flat distance the facing cone is waived: the item at Henry's feet.
@export var close_override: float = 0.5
## Camera aim earns score inside this angle and nothing outside it.
@export_range(1.0, 90.0, 1.0) var camera_cone_deg: float = 30.0
## Score weight of closeness within the radius.
@export var distance_weight: float = 0.5
## Score weight of Henry's body facing towards the object.
@export var facing_weight: float = 0.5
## Score weight of the camera looking at the object; a weight, never a requirement.
@export var camera_weight: float = 0.7
## Score bonus that keeps the current target until another clearly wins.
@export var hysteresis_bonus: float = 0.08
## Candidates this close to the target's focus point form a cluster for interact_cycle.
@export var cluster_radius: float = 0.8

@export_group("Markers")
## Objects whose focus point is this close may show the check-mark marker.
@export var hint_radius: float = 4.5
## Only this many nearest objects in front of Henry show a marker at once.
@export var max_hint_markers: int = 3

@export_group("Approach")
## F acts on the spot inside this flat distance, otherwise Henry walks over.
@export var pickup_distance: float = 0.9
## Inside this distance the object shows its F prompt instead of a marker.
@export var prompt_distance: float = 2.0
## Seated, Henry leans: this far, picked by where the camera looks (stove ring, table).
@export var seated_reach: float = 2.0
## Seated, a target must lie within this angle of the camera aim.
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
var _hint_elapsed: float = 0.0
## Last scoring pass: base score and focus point per eligible candidate.
var _scores: Dictionary = {}
var _points: Dictionary = {}
var _cluster: Array[InteractiveArea] = []
var _manual_target: InteractiveArea = null
var _manual_from: Vector3 = Vector3.ZERO


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	var input_systems: Node = get_node_or_null(^"/root/InputSystems")
	if input_systems != null:
		input_systems.connect(&"interact_pressed", try_interact)
		input_systems.connect(&"interact_cycle_pressed", cycle_target)
	if _player != null and _player.has_signal(&"movement_stopped"):
		_player.connect(&"movement_stopped", _on_player_movement_stopped)


func _physics_process(delta: float) -> void:
	if _player == null:
		return
	detect_target()
	_update_approach(delta)
	_hint_elapsed += delta
	if _hint_elapsed >= HINT_INTERVAL:
		_hint_elapsed = 0.0
		_update_hints()


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


## Picks the best-scored candidate before Henry that he can actually see.
func _find_best_target() -> InteractiveArea:
	var seated: bool = _is_seated()
	var radius: float = seated_reach if seated else intent_radius
	if is_instance_valid(current_target) and current_target.keeps_focus() \
		and current_target.can_interact() and _flat_distance_to(current_target) <= radius:
		_cluster.clear()
		return current_target
	_score_candidates(seated, radius)
	var best: InteractiveArea = _manual_choice()
	if best == null:
		var ranked: Array = _scores.keys()
		ranked.sort_custom(func(a: InteractiveArea, b: InteractiveArea) -> bool: return _ranked_score(a) > _ranked_score(b))
		for index: int in range(mini(ranked.size(), SIGHT_CHECKS)):
			if _has_line_of_sight(ranked[index]):
				best = ranked[index]
				break
	_cluster = _cluster_around(best)
	return best


## Fills _scores and _points with every candidate that passes the gates.
func _score_candidates(seated: bool, radius: float) -> void:
	_scores.clear()
	_points.clear()
	var viewport := get_viewport()
	var camera: Camera3D = viewport.get_camera_3d() if viewport != null else null
	var view_from: Vector3 = TpsCamera.aim_origin(camera) if camera != null else _chest()
	var view_direction: Vector3 = TpsCamera.aim_direction(camera) if camera != null else _flat_view_direction()
	var facing: Vector3 = get_facing_direction()
	var facing_limit: float = deg_to_rad(facing_limit_deg)
	var camera_cone: float = deg_to_rad(camera_cone_deg)
	var seated_limit: float = deg_to_rad(seated_aim_deg)
	var facing_w: float = SEATED_FACING_WEIGHT if seated else facing_weight
	var camera_w: float = SEATED_CAMERA_WEIGHT if seated else camera_weight
	for node: Node in get_tree().get_nodes_in_group(InteractiveArea.INTERACTIVE_GROUP):
		var raw := node as InteractiveArea
		if not _is_available(raw) or not raw.accepts_focus(view_from, view_direction):
			continue
		var area: InteractiveArea = raw.resolve_focus(view_from, view_direction)
		if not _is_available(area) or _scores.has(area):
			continue
		var point: Vector3 = area.get_focus_point(_player.global_position)
		var to_point: Vector3 = point - _player.global_position
		to_point.y = 0.0
		var distance: float = to_point.length()
		if distance > radius:
			continue
		var face_angle: float = facing.angle_to(to_point) if distance > 0.001 else 0.0
		if not seated and distance > close_override and face_angle > facing_limit:
			continue
		var from_view: Vector3 = point - view_from
		if camera == null:
			from_view.y = 0.0  # the fallback view is flat
		var view_angle: float = view_direction.angle_to(from_view) if from_view.length() > 0.001 else 0.0
		if seated and view_angle > seated_limit:
			continue
		var face_score: float = clampf(1.0 - face_angle / facing_limit, 0.0, 1.0)
		var camera_score: float = clampf(1.0 - view_angle / camera_cone, 0.0, 1.0)
		_scores[area] = distance_weight * (1.0 - distance / radius) + facing_w * face_score \
			+ camera_w * camera_score + area.focus_priority
		_points[area] = point


func _ranked_score(area: InteractiveArea) -> float:
	return float(_scores[area]) + (hysteresis_bonus if area == current_target else 0.0)


## The interact_cycle pick while it is still eligible, visible and Henry stays put.
func _manual_choice() -> InteractiveArea:
	if _manual_target == null:
		return null
	var moved: Vector3 = _player.global_position - _manual_from
	moved.y = 0.0
	if not is_instance_valid(_manual_target) or not _scores.has(_manual_target) \
		or moved.length() > MANUAL_HOLD_DISTANCE or not _has_line_of_sight(_manual_target):
		_manual_target = null
		return null
	return _manual_target


## Candidates whose focus points lie within cluster_radius of the target, best first.
func _cluster_around(target: InteractiveArea) -> Array[InteractiveArea]:
	var cluster: Array[InteractiveArea] = []
	if target == null or not _points.has(target):
		return cluster
	var centre: Vector3 = _points[target]
	for area: InteractiveArea in _scores.keys():
		if (_points[area] as Vector3).distance_to(centre) <= cluster_radius:
			cluster.append(area)
	cluster.sort_custom(func(a: InteractiveArea, b: InteractiveArea) -> bool: return float(_scores[a]) > float(_scores[b]))
	return cluster


## interact_cycle: steps to the next visible member of the cluster, by score order.
func cycle_target() -> void:
	if _player == null or _is_blocked() or _cluster.size() < 2:
		return
	var start: int = maxi(_cluster.find(current_target), 0)
	for step: int in range(1, _cluster.size()):
		var next: InteractiveArea = _cluster[(start + step) % _cluster.size()]
		if _is_available(next) and _has_line_of_sight(next):
			_manual_target = next
			_manual_from = _player.global_position
			detect_target()
			return


## 1-based place of current_target in its cluster and the cluster size; zero when alone.
func get_cluster_position() -> Vector2i:
	var index: int = _cluster.find(current_target)
	if _cluster.size() < 2 or index < 0:
		return Vector2i.ZERO
	return Vector2i(index + 1, _cluster.size())


## Without a camera (headless tests), Henry's own flat view stands in for the aim.
func _flat_view_direction() -> Vector3:
	var view: Vector3 = _player.call(&"get_view_direction") if _player.has_method(&"get_view_direction") else get_facing_direction()
	view.y = 0.0
	return view.normalized() if view.length() > 0.001 else get_facing_direction()


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


## Far marker layer: the nearest few objects before Henry, in sight, fade in by distance.
func _update_hints() -> void:
	var origin: Vector3 = _player.global_position
	var facing: Vector3 = get_facing_direction()
	var facing_limit: float = deg_to_rad(facing_limit_deg)
	var areas: Array[Node] = get_tree().get_nodes_in_group(InteractiveArea.INTERACTIVE_GROUP)
	var nearby: Array = []
	for node: Node in areas:
		var area := node as InteractiveArea
		if not _is_available(area):
			continue
		var to_point: Vector3 = area.get_focus_point(origin) - origin
		to_point.y = 0.0
		var distance: float = to_point.length()
		if distance > hint_radius:
			continue
		if distance > close_override and facing.angle_to(to_point) > facing_limit:
			continue
		nearby.append([distance, area])
	nearby.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var shown: Dictionary = {}
	for index: int in range(mini(nearby.size(), max_hint_markers)):
		var candidate: InteractiveArea = nearby[index][1]
		if _has_line_of_sight(candidate):
			shown[candidate] = float(nearby[index][0])
	var fade_span: float = maxf(hint_radius - intent_radius, 0.001)
	for node: Node in areas:
		var area := node as InteractiveArea
		if area == null or area.is_queued_for_deletion():
			continue
		if shown.has(area):
			var opacity: float = 1.0 - clampf((float(shown[area]) - intent_radius) / fade_span, 0.0, 1.0)
			area.set_hint_state(true, opacity, origin)
		else:
			area.set_hint_state(false, 0.0, origin)


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
