class_name FirstExitBearings
extends Node

## First Exit A only: what Henry knows, what he has entered, and the one place the
## compass may point at. Positions come from landmark data. This is not a POI
## registry, and the HUD does not own any of it.

signal bearings_changed

const LANDMARKS_PATH: String = "res://data/world/key_west/reality/overrides/first_exit_landmarks.geojson"
const SHELTER_ROLE: String = "first_exit_primary_shelter"
const THERMAL_SCRIPT: GDScript = preload("res://scripts/systems/survival/thermal_manager.gd")
const SAVE_SCRIPT: GDScript = preload("res://scripts/systems/save/save_manager.gd")
## Visible half-width of the compass tape. One scale, shared with the HUD.
const HALF_ARC_RAD: float = TAU / 360.0 * 50.0
const LABEL_727: String = "727"

var known: Dictionary = {}
var visited: Dictionary = {}
var active_target_id: String = ""
## True once the scenario has spent its single automatic assignment, or this
## boot was never that scenario (shelter spawn, dev street, an older save).
var intro_assigned: bool = false

var _shelter_id: String = ""
var _places: Dictionary = {}
var _labels: Dictionary = {}
var _player: Node3D
var _thermal: ThermalManager
var _save: SaveManager
var _world: World
var _inside_727: bool = false
var _awaiting_load: bool = false
## True from a teleport (load, or the first placement) until the physics step
## has refreshed Area3D overlaps. Signals in that window are not entrances.
var _holding_edges: bool = false
var _settle_token: int = 0


func on_world_ready(context: WorldContext) -> void:
	_player = context.player
	_world = context.world as World
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
	if _world == null or _world.spawn_at_shelter:
		return false
	return _world.dev_spawn().is_empty()


func shelter_id() -> String:
	_ensure_catalog()
	return _shelter_id


func shelter_xz() -> Vector2:
	_ensure_catalog()
	return _places.get(_shelter_id, Vector2.ZERO) as Vector2


func has_active_target() -> bool:
	return active_target_id != "" and _places.has(active_target_id)


func active_label() -> String:
	return String(_labels.get(active_target_id, ""))


func active_xz() -> Vector2:
	return _places.get(active_target_id, Vector2.ZERO) as Vector2


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
	if _shelter_id == "" or not known.has(_shelter_id):
		return
	active_target_id = "" if active_target_id == _shelter_id else _shelter_id
	bearings_changed.emit()


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
	known.clear()
	visited.clear()
	for place_id: Variant in data.get("known", []):
		known[String(place_id)] = true
	for place_id: Variant in data.get("visited", []):
		_mark_visited(String(place_id))
	intro_assigned = bool(data.get("intro_assigned", false)) or not visited.is_empty()
	var active: String = String(data.get("active_target_id", ""))
	active_target_id = active if active != "" and known.has(active) else ""
	bearings_changed.emit()


## Called when a loaded slot has no payload for this key. Continue must not
## grow a fresh mission marker.
func apply_absent_save() -> void:
	_ensure_catalog()
	known.clear()
	visited.clear()
	_grant_shelter()
	active_target_id = ""
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
	active_target_id = _shelter_id
	intro_assigned = true
	bearings_changed.emit()


func _arrive_727() -> void:
	if _shelter_id == "":
		_ensure_catalog()
	if _shelter_id == "":
		return
	_mark_visited(_shelter_id)
	if active_target_id == _shelter_id:
		active_target_id = ""
	intro_assigned = true
	bearings_changed.emit()


func _mark_visited(place_id: String) -> void:
	if place_id == "":
		return
	known[place_id] = true
	visited[place_id] = true


func _grant_shelter() -> void:
	if _shelter_id != "":
		known[_shelter_id] = true


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
	if _shelter_id != "":
		return
	if not FileAccess.file_exists(LANDMARKS_PATH):
		push_error("FirstExitBearings: missing %s" % LANDMARKS_PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LANDMARKS_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("FirstExitBearings: %s is not a FeatureCollection" % LANDMARKS_PATH)
		return
	for feature: Variant in (parsed as Dictionary).get("features", []):
		if not feature is Dictionary:
			continue
		var props: Dictionary = (feature as Dictionary).get("properties", {})
		var params: Dictionary = props.get("params", {})
		if String(params.get("role", "")) != SHELTER_ROLE:
			continue
		_shelter_id = String(props.get("target_feature_id", ""))
		var xz: Array = params.get("bearing_local_xz", params.get("anchor_local_xz", []))
		if xz.size() >= 2:
			_places[_shelter_id] = Vector2(float(xz[0]), float(xz[1]))
		_labels[_shelter_id] = LABEL_727
		return
	push_error("FirstExitBearings: no %s role in %s" % [SHELTER_ROLE, LANDMARKS_PATH])


func _ids(flags: Dictionary) -> Array:
	var out: Array = []
	for place_id: Variant in flags.keys():
		out.append(String(place_id))
	out.sort()
	return out
