class_name FirstExitBearings
extends Node

## First Exit A world adapter. NavigationState owns known/visited/active;
## NavigationCatalog owns the authored target data. This adapter preserves
## the current HUD/save/probe contracts while First Exit remains the only
## production scenario using the navigation service.

signal bearings_changed

const SHELTER_ROLE: String = "first_exit_primary_shelter"
const BUNKER_ROLE: String = "first_exit_start_bunker"
const THERMAL_SCRIPT: GDScript = preload("res://scripts/systems/survival/thermal_manager.gd")
const SAVE_SCRIPT: GDScript = preload("res://scripts/systems/save/save_manager.gd")
## Visible half-width of the compass tape. One scale, shared with the HUD.
const HALF_ARC_RAD: float = TAU / 360.0 * 50.0

## Proximity words are qualitative; thresholds come from the selected
## NavigationTarget. No numerical distance or path exposed to the HUD.
enum Proximity { COLD, WARM, HOT }
enum Trend { STABLE, APPROACHING, MOVING_AWAY }

const PROXIMITY_SAMPLE_SEC: float = 0.25
const TREND_STEP_M: float = 8.0
const TREND_COOLDOWN_SEC: float = 6.0
const TREND_WORD_SEC: float = 2.5
## Radial motion, not camera heading or total walking speed.
const RADIAL_IDLE_SPEED_MPS: float = 0.32
const RADIAL_IDLE_SEC: float = 0.5
const REVERSAL_M: float = 0.75
const BAND_PRIORITY_SEC: float = 1.25
const TELEPORT_STEP_M: float = 30.0

## Renderers can read the current level and event sequence; save data does not.
var proximity_state: Proximity = Proximity.COLD
var trend_state: Trend = Trend.STABLE
var trend_serial: int = 0
var _proximity_initialized: bool = false
var _proximity_target_id: String = ""
var _sample_elapsed: float = 0.0
var _distance_reference: float = 0.0
var _has_distance_reference: bool = false
var _trend_cooldown_left: float = 0.0
var _trend_word_left: float = 0.0
var _last_event_direction: int = 0
var _motion_direction: int = 0 # +1 approach, -1 retreat
var _motion_extreme: float = 0.0
var _previous_distance: float = 0.0
var _radial_idle_elapsed: float = 0.0
var _band_priority_left: float = 0.0
var _last_player_xz: Vector2 = Vector2.ZERO
var _has_last_player_xz: bool = false

var _catalog: NavigationCatalog = NavigationCatalog.new()
var _navigation: NavigationState = NavigationState.new()

## Read-compatible accessors for existing save/tests, not duplicate state.
var known: Dictionary:
	get:
		return _navigation.known

var visited: Dictionary:
	get:
		return _navigation.visited

var active_target_id: String:
	get:
		return _navigation.active_target_id
	set(value):
		if value.is_empty():
			clear_target()
		else:
			select_target(value)

## The First Exit scenario still owns its one-time auto assignment.
var intro_assigned: bool = false
var _shelter_id: String = ""
var _player: Node3D
var _thermal: ThermalManager
var _save: SaveManager
var _world: Node
var _inside_727: bool = false
var _awaiting_load: bool = false
## True from a teleport (load, or the first placement) until the physics step
## has refreshed Area3D overlaps. Signals in that window are not entrances.
var _holding_edges: bool = false
var _settle_token: int = 0


func on_world_ready(context: WorldContext) -> void:
	_player = context.player
	_world = context.world
	_thermal = context.get_system(THERMAL_SCRIPT) as ThermalManager
	_save = context.get_system(SAVE_SCRIPT) as SaveManager
	_bind_input()
	_bind_probe()
	## SaveManager restores participants in a deferred load. A slot written
	## before this system existed has no key, and load_save_data is then never
	## called — so the absent case has to be decided here, not in the loader.
	if _save != null and SaveManager.pending_load_slot >= 0:
		_awaiting_load = true
		if not _save.load_completed.is_connected(_on_load_completed):
			_save.load_completed.connect(_on_load_completed)
			_save.load_failed.connect(_on_load_failed)
		return
	begin_without_save()


func begin_without_save() -> void:
	begin_play(_is_scenario_start())
	_schedule_settled_probe()


## scenario_start arms 727 once. A shelter spawn or dev-street boot passes false
## and only marks the introduction as already spent.
func begin_play(scenario_start: bool) -> void:
	_ensure_catalog()
	_grant_shelter()
	if scenario_start and not intro_assigned:
		_assign_intro()
	elif not intro_assigned:
		intro_assigned = true
		bearings_changed.emit()


## True when this boot is the stranger run from Battery Osceola, not the
## developer shelter spawn and not a debug street start.
func _is_scenario_start() -> bool:
	if _world == null or bool(_world.get(&"spawn_at_shelter")):
		return false
	var spawned: Variant = Callable(_world, &"dev_spawn").call()
	return spawned is Dictionary and (spawned as Dictionary).is_empty()


## The authoritative navigation owner samples movement even when the HUD is hidden.
## Never derive this state from camera yaw, frame rate or the drawn marker.
func _process(delta: float) -> void:
	if _player == null or not has_active_target():
		return
	if active_target_id != _proximity_target_id:
		_reset_proximity_feedback()
	_sample_elapsed += maxf(delta, 0.0)
	## Sample immediately on a new/loaded target; afterwards keep the 4 Hz cadence.
	if _proximity_initialized and _sample_elapsed < PROXIMITY_SAMPLE_SEC:
		return
	var elapsed: float = _sample_elapsed
	_sample_elapsed = 0.0
	var from := Vector2(_player.global_position.x, _player.global_position.z)
	if _has_last_player_xz and from.distance_to(_last_player_xz) > TELEPORT_STEP_M:
		## Teleports / respawns must never look like exceptional approach/retreat.
		_reset_proximity_feedback()
	_last_player_xz = from
	_has_last_player_xz = true
	_sample_distance(from.distance_to(active_xz()), elapsed)


## Called only by the owner; public meters are never sent to the HUD.
## Kept deterministic for headless threshold, cooldown and direction tests.
func _sample_distance(distance_m: float, elapsed: float) -> void:
	if not has_active_target() or is_nan(distance_m) or is_inf(distance_m):
		return
	var d: float = maxf(distance_m, 0.0)
	var target: NavigationTarget = get_active_target()
	var warm_enter_m: float = target.warm_enter_m
	var warm_exit_m: float = target.warm_exit_m
	var hot_enter_m: float = target.hot_enter_m
	var hot_exit_m: float = target.hot_exit_m
	var previous_band: Proximity = proximity_state
	if not _proximity_initialized:
		proximity_state = Proximity.HOT if d <= hot_enter_m else Proximity.WARM if d <= warm_enter_m else Proximity.COLD
		_proximity_initialized = true
	else:
		match proximity_state:
			Proximity.COLD:
				if d <= hot_enter_m:
					proximity_state = Proximity.HOT
				elif d <= warm_enter_m:
					proximity_state = Proximity.WARM
			Proximity.WARM:
				if d <= hot_enter_m:
					proximity_state = Proximity.HOT
				elif d >= warm_exit_m:
					proximity_state = Proximity.COLD
			Proximity.HOT:
				if d >= warm_exit_m:
					proximity_state = Proximity.COLD
				elif d >= hot_exit_m:
					proximity_state = Proximity.WARM

	## One authoritative, expiring movement message. Repeat cooldown applies
	## to the SAME direction only; it must not conceal a genuine reversal.
	var dt: float = maxf(elapsed, 0.0)
	var cooldown_was_active: bool = _trend_cooldown_left > 0.0
	_trend_cooldown_left = maxf(0.0, _trend_cooldown_left - dt)
	_trend_word_left = maxf(0.0, _trend_word_left - dt)
	if _trend_word_left <= 0.0:
		trend_state = Trend.STABLE
	if not _has_distance_reference:
		_reanchor_motion(d)
		_has_distance_reference = true
		return

	var step: float = _previous_distance - d
	_previous_distance = d

	## A new band always wins over a same-sample movement event. Hold it
	## long enough to read, and start fresh after the priority interval.
	if previous_band != proximity_state:
		_cancel_trend()
		_band_priority_left = BAND_PRIORITY_SEC
		_reanchor_motion(d)
		return
	if _band_priority_left > 0.0:
		_band_priority_left = maxf(0.0, _band_priority_left - dt)
		_reanchor_motion(d)
		return

	if absf(step) <= RADIAL_IDLE_SPEED_MPS * dt:
		_radial_idle_elapsed += dt
		if _radial_idle_elapsed >= RADIAL_IDLE_SEC:
			_cancel_trend()
			_reanchor_motion(d)
		return
	_radial_idle_elapsed = 0.0

	var direction: int = 1 if step > 0.0 else -1
	if _motion_direction == 0:
		_motion_direction = direction
		_motion_extreme = _distance_reference
	if direction == _motion_direction:
		_motion_extreme = minf(_motion_extreme, d) if direction > 0 else maxf(_motion_extreme, d)
	else:
		## Ignore tiny radial jitter, but invalidate the old word as soon
		## as a meaningful reversal is observed (even during cooldown).
		if absf(d - _motion_extreme) < REVERSAL_M:
			return
		_cancel_trend()
		_motion_direction = direction
		_distance_reference = _motion_extreme
		_motion_extreme = d

	if direction == _last_event_direction and cooldown_was_active:
		## Drop progress earned during repeat cooldown; do not replay it.
		_distance_reference = d
		return

	var progress: float = (_distance_reference - d) * float(direction)
	if progress >= TREND_STEP_M:
		trend_state = Trend.APPROACHING if direction > 0 else Trend.MOVING_AWAY
		trend_serial += 1
		_last_event_direction = direction
		_trend_cooldown_left = TREND_COOLDOWN_SEC
		_trend_word_left = TREND_WORD_SEC
		_distance_reference = d


func _cancel_trend() -> void:
	trend_state = Trend.STABLE
	_trend_word_left = 0.0


func _reanchor_motion(d: float) -> void:
	_distance_reference = d
	_previous_distance = d
	_motion_extreme = d
	_motion_direction = 0
	_radial_idle_elapsed = 0.0


func _reset_proximity_feedback() -> void:
	_proximity_target_id = active_target_id
	proximity_state = Proximity.COLD
	trend_state = Trend.STABLE
	_proximity_initialized = false
	_has_distance_reference = false
	_trend_cooldown_left = 0.0
	_trend_word_left = 0.0
	_last_event_direction = 0
	_motion_direction = 0
	_radial_idle_elapsed = 0.0
	_band_priority_left = 0.0
	_sample_elapsed = 0.0
	_has_last_player_xz = false


## Generic target-id interface for later mental-map selection.
## No public path here performs automatic route finding or discovery.
func discover_target(id: String) -> bool:
	_ensure_catalog()
	var was_known: bool = _navigation.known.has(id)
	if not _navigation.discover_target(id):
		return false
	if not was_known:
		bearings_changed.emit()
	return true


func select_target(id: String) -> bool:
	_ensure_catalog()
	var previous: String = _navigation.active_target_id
	if not _navigation.select_target(id):
		return false
	if previous != _navigation.active_target_id:
		_reset_proximity_feedback()
		bearings_changed.emit()
	return true


func clear_target() -> void:
	if _navigation.active_target_id.is_empty():
		return
	_navigation.clear_target()
	_reset_proximity_feedback()
	bearings_changed.emit()


func mark_arrived(id: String) -> bool:
	_ensure_catalog()
	if not _navigation.mark_arrived(id):
		return false
	_reset_proximity_feedback()
	bearings_changed.emit()
	return true


func get_target(id: String) -> NavigationTarget:
	_ensure_catalog()
	return _catalog.get_target(id)


func get_active_target() -> NavigationTarget:
	return get_target(active_target_id) if not active_target_id.is_empty() else null


func known_targets() -> Array[NavigationTarget]:
	_ensure_catalog()
	return _navigation.known_targets()


func target_id_for_role(role: String) -> String:
	_ensure_catalog()
	return _catalog.id_for_role(role)


## Kept for the existing First Exit adapter, scenes and tests.
func shelter_id() -> String:
	_ensure_catalog()
	return _shelter_id


func shelter_xz() -> Vector2:
	var target: NavigationTarget = get_target(shelter_id())
	return target.bearing_xz if target != null else Vector2.ZERO


func has_active_target() -> bool:
	return not active_target_id.is_empty() and get_active_target() != null


func active_label() -> String:
	var target: NavigationTarget = get_active_target()
	return target.internal_label if target != null else ""


## Legacy view-facing method name; now returns the authored compass title
## of ANY target. No changes are required in CompassStrip for switching.
func active_street_label() -> String:
	var target: NavigationTarget = get_active_target()
	return target.compass_title if target != null else ""


func active_xz() -> Vector2:
	var target: NavigationTarget = get_active_target()
	return target.bearing_xz if target != null else Vector2.ZERO


func is_known(place_id: String) -> bool:
	return known.has(place_id)


func is_visited(place_id: String) -> bool:
	return visited.has(place_id)


## Local frame: x east, z south. 0 is north (-Z), matching the dev compass.
static func bearing_of(from_xz: Vector2, to_xz: Vector2) -> float:
	var offset: Vector2 = to_xz - from_xz
	return atan2(offset.x, -offset.y)


## Horizontal direction the camera is showing, not Henry's body yaw.
static func camera_bearing(camera: Camera3D) -> float:
	if camera == null:
		return 0.0
	var forward: Vector3 = -camera.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.000001:
		return 0.0
	return atan2(forward.x, -forward.z)


static func relative_bearing(camera_bearing_rad: float, target_bearing_rad: float) -> float:
	return wrapf(target_bearing_rad - camera_bearing_rad, -PI, PI)


## u is -1..1 across the tape. edge is -1 or 1 when the mark is pinned to a side.
static func marker_slot(relative_rad: float) -> Dictionary:
	if absf(relative_rad) <= HALF_ARC_RAD:
		return {"on_strip": true, "u": relative_rad / HALF_ARC_RAD, "edge": 0}
	var edge: int = -1 if relative_rad < 0.0 else 1
	return {"on_strip": false, "u": float(edge), "edge": edge}


func recall() -> void:
	_ensure_catalog()
	if _shelter_id.is_empty() or not is_known(_shelter_id):
		return
	if active_target_id == _shelter_id:
		clear_target()
	else:
		select_target(_shelter_id)


## Zones the thermal probe currently overlaps. fresh_edge is false for the
## first sample after a load, so standing inside does not count as a new entry.
func note_zones(zones: Array, fresh_edge: bool = true) -> void:
	var inside: bool = false
	for zone: Variant in zones:
		if zone is Area3D and _zone_is_727(zone as Area3D):
			inside = true
			break
	if fresh_edge and inside and not _inside_727:
		_arrive_727()
	_inside_727 = inside


func get_save_key() -> StringName:
	return &"first_exit_bearings"


func get_save_data() -> Dictionary:
	return {
		"known": _ids(known),
		"visited": _ids(visited),
		"active_target_id": active_target_id,
		"intro_assigned": intro_assigned,
	}


func load_save_data(data: Dictionary) -> void:
	_ensure_catalog()
	_navigation.restore(data)
	intro_assigned = bool(data.get("intro_assigned", false)) or not visited.is_empty()
	_reset_proximity_feedback()
	bearings_changed.emit()


## Called when a loaded slot has no payload for this key. Continue must not
## grow a fresh mission marker.
func apply_absent_save() -> void:
	_ensure_catalog()
	_navigation.reset()
	_grant_shelter()
	_reset_proximity_feedback()
	intro_assigned = true
	_inside_727 = false
	bearings_changed.emit()


func on_loaded_payload(payload: Dictionary) -> void:
	if not payload.has(String(get_save_key())):
		apply_absent_save()
	_schedule_settled_probe()


func _on_load_completed(slot: int) -> void:
	_awaiting_load = false
	var document: Dictionary = _save.read_slot(slot) if _save != null else {}
	on_loaded_payload(document.get("payload", {}))


func _on_load_failed(_slot: int, _reason: String) -> void:
	_awaiting_load = false
	begin_without_save()


func _assign_intro() -> void:
	if _shelter_id == "" or not known.has(_shelter_id):
		return
	if select_target(_shelter_id):
		intro_assigned = true


## Physical 727 zone is only an arrival *source*, never the navigation owner.
## Other places may confirm by interaction or their own trusted zone event.
func _arrive_727() -> void:
	if _shelter_id.is_empty():
		_ensure_catalog()
	if _shelter_id.is_empty():
		return
	mark_arrived(_shelter_id)
	intro_assigned = true


func _grant_shelter() -> void:
	if not _shelter_id.is_empty():
		discover_target(_shelter_id)


func _bind_input() -> void:
	var input_systems: Node = get_node_or_null(^"/root/InputSystems")
	if input_systems != null and input_systems.has_signal(&"recall_bearing_pressed"):
		if not input_systems.is_connected(&"recall_bearing_pressed", recall):
			input_systems.connect(&"recall_bearing_pressed", recall)


func _bind_probe() -> void:
	if _thermal == null or _thermal.zone_probe == null:
		return
	var probe: Area3D = _thermal.zone_probe
	if not probe.area_entered.is_connected(_on_probe_area):
		probe.area_entered.connect(_on_probe_area)
		probe.area_exited.connect(_on_probe_area)


func _on_probe_area(_area: Area3D) -> void:
	if _holding_edges:
		return
	_sample_probe(true)


## The overlap list is stale until the next physics step. Call this, ignore
## edges, then accept_settled_overlap with whatever the probe reports after.
func hold_probe_edges() -> void:
	_holding_edges = true


## A probe signal. Dropped while a settle is in progress.
func notify_probe_edge(zones: Array) -> void:
	if _holding_edges:
		return
	note_zones(zones, true)


## The first overlap list that belongs to the loaded position. Not an entrance.
func accept_settled_overlap(zones: Array) -> void:
	_holding_edges = false
	note_zones(zones, false)


func _schedule_settled_probe() -> void:
	_settle_token += 1
	var token: int = _settle_token
	hold_probe_edges()
	if is_inside_tree():
		_wait_for_settled_probe(token)


func _wait_for_settled_probe(token: int) -> void:
	## Two steps: the first moves the physics state, the second is the one
	## get_overlapping_areas() is documented to have refreshed.
	await get_tree().physics_frame
	await get_tree().physics_frame
	if token != _settle_token or not is_inside_tree():
		return
	var zones: Array = []
	if _thermal != null and _thermal.zone_probe != null:
		zones = _thermal.zone_probe.get_overlapping_areas()
	if token != _settle_token:
		return
	accept_settled_overlap(zones)


func _sample_probe(fresh_edge: bool) -> void:
	if _thermal == null or _thermal.zone_probe == null:
		return
	note_zones(_thermal.zone_probe.get_overlapping_areas(), fresh_edge)


func _zone_is_727(area: Area3D) -> bool:
	var node: Node = area
	while node != null:
		if node is KeyWest727Shelter:
			return true
		node = node.get_parent()
	return false


func _ensure_catalog() -> void:
	if not _shelter_id.is_empty():
		return
	if not _catalog.ensure_loaded():
		return
	_navigation.catalog = _catalog
	_shelter_id = _catalog.id_for_role(SHELTER_ROLE)
	if _shelter_id.is_empty():
		push_error("FirstExitBearings: no primary shelter target in NavigationCatalog")


func _ids(flags: Dictionary) -> Array:
	var out: Array = []
	for place_id: Variant in flags.keys():
		out.append(String(place_id))
	out.sort()
	return out
