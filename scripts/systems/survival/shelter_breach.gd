@tool
class_name ShelterBreach
extends Node3D

## A hole in a shelter. Boards are physical placements rather than a binary
## repair: overlap wastes material and only the actually covered aperture stops wind.

signal boarded_changed(is_boarded: bool)
signal coverage_changed(coverage: float)
signal staged_boards_changed(count: int)

## Share of the hole a closed pane still leaks round an old frame.
const GLASS_LEAK: float = 0.12

@export_group("Breach")
@export_range(0.0, 1.0) var severity: float = 0.35:
	set(value):
		severity = clampf(value, 0.0, 1.0)
		_announce()
@export var starts_boarded: bool = false
@export var boardable: bool = true
## Intact glass in the opening (a window). It keeps the heat in until a throw breaks it.
@export var glazed: bool = false
var closure: HingedDoor

@export_group("Repair")
@export var repair_item_id: StringName = &"boards"
@export var name_key: String = "BREACH_GENERIC"
@export_range(0.4, 4.0, 0.05) var opening_width_m: float = 1.8
@export_range(0.4, 3.0, 0.05) var opening_height_m: float = 1.1
@export_range(0.08, 0.5, 0.01) var board_height_m: float = 0.24
@export_range(0.5, 1.0, 0.01) var seal_threshold: float = 0.99

@export_group("Visual")
@export var boarded_visual: Node3D
## The floor relative to the aperture centre; staging stays inside the room.
@export var staging_floor_y: float = -1.35

var _forced_boarded: bool = false
var _placed_board_y: Array[float] = []
var _staged_boards: int = 0
## External closure such as a door leaf can reduce the same aperture without
## pretending it is fully repaired. Thermal and particles read this one value.
var _exposure_multiplier: float = 1.0
var _placed_root: Node3D
var _staged_root: Node3D


func _ready() -> void:
	_forced_boarded = starts_boarded and boardable
	if not Engine.is_editor_hint():
		_ensure_visual_roots()
		_rebuild_dynamic_visuals()
		if get_node_or_null(^"Draft") == null:
			var draft := BreachDraft.new()
			draft.name = "Draft"
			draft.breach = self
			add_child(draft)
	_announce()


func is_boarded() -> bool:
	if not boardable:
		return false
	return _forced_boarded or get_coverage_fraction() >= seal_threshold


func get_open_fraction() -> float:
	var glass: float = GLASS_LEAK if glazed else 1.0
	if not boardable:
		return glass
	return 0.0 if _forced_boarded else clampf(1.0 - get_coverage_fraction(), 0.0, 1.0) * glass


## Breaks or restores the pane: a broken window is a full hole again.
func set_glazed(value: bool) -> void:
	if glazed == value:
		return
	glazed = value
	_announce()


func get_coverage_fraction() -> float:
	if _forced_boarded:
		return 1.0
	if _placed_board_y.is_empty() or opening_height_m <= 0.001:
		return 0.0
	var ys: Array[float] = _placed_board_y.duplicate()
	ys.sort()
	var half: float = opening_height_m * 0.5
	var covered: float = 0.0
	var have_interval: bool = false
	var current_lo: float = 0.0
	var current_hi: float = 0.0
	for center: float in ys:
		var lo: float = maxf(-half, center - board_height_m * 0.5)
		var hi: float = minf(half, center + board_height_m * 0.5)
		if hi <= lo:
			continue
		if not have_interval:
			current_lo = lo
			current_hi = hi
			have_interval = true
		elif lo <= current_hi:
			current_hi = maxf(current_hi, hi)
		else:
			covered += current_hi - current_lo
			current_lo = lo
			current_hi = hi
	if have_interval:
		covered += current_hi - current_lo
	return clampf(covered / opening_height_m, 0.0, 1.0)


func get_gap_fraction() -> float:
	return get_open_fraction()


func set_exposure_multiplier(value: float) -> void:
	var next: float = clampf(value, 0.0, 1.0)
	if is_equal_approx(next, _exposure_multiplier):
		return
	_exposure_multiplier = next
	_announce()


func get_exposure_multiplier() -> float:
	return _exposure_multiplier


func get_board_size() -> Vector3:
	return Vector3(opening_width_m + 0.30, board_height_m, 0.055)


func get_placed_board_positions() -> Array[float]:
	return _placed_board_y.duplicate()


func get_staged_boards() -> int:
	return _staged_boards


func stage_boards(count: int) -> void:
	if not boardable or count <= 0:
		return
	_staged_boards += count
	_refresh_staged_visual()
	staged_boards_changed.emit(_staged_boards)


func take_staged_board() -> bool:
	if _staged_boards <= 0:
		return false
	_staged_boards -= 1
	_refresh_staged_visual()
	staged_boards_changed.emit(_staged_boards)
	return true


func return_staged_board() -> void:
	stage_boards(1)


func place_board(local_y: float) -> bool:
	if not boardable:
		return false
	if opening_height_m <= board_height_m:
		local_y = 0.0
	else:
		var limit: float = opening_height_m * 0.5 - board_height_m * 0.5
		local_y = clampf(local_y, -limit, limit)
	var was_boarded: bool = is_boarded()
	_placed_board_y.append(local_y)
	_spawn_placed_board(local_y)
	coverage_changed.emit(get_coverage_fraction())
	var now_boarded: bool = is_boarded()
	if now_boarded != was_boarded:
		boarded_changed.emit(now_boarded)
	_announce()
	return true


## Legacy seam for old tests/tools. Gameplay places boards individually.
func board_up() -> bool:
	if not boardable or is_boarded():
		return false
	var was_boarded: bool = is_boarded()
	_forced_boarded = true
	if not was_boarded:
		boarded_changed.emit(true)
	coverage_changed.emit(1.0)
	_announce()
	return true


func tear_open() -> bool:
	if not is_boarded() and _placed_board_y.is_empty():
		return false
	var was_boarded: bool = is_boarded()
	_forced_boarded = false
	_placed_board_y.clear()
	_rebuild_dynamic_visuals()
	if was_boarded:
		boarded_changed.emit(false)
	coverage_changed.emit(0.0)
	_announce()
	return true


func get_exposure_against(wind_direction: Vector3) -> float:
	var open_fraction: float = get_open_fraction()
	if open_fraction <= 0.0:
		return 0.0
	if wind_direction.length_squared() < 0.0001:
		return severity * open_fraction * _exposure_multiplier
	return severity * open_fraction * _exposure_multiplier * maxf(0.0, get_facing().dot(-wind_direction.normalized()))


func get_facing() -> Vector3:
	var facing: Vector3 = -global_transform.basis.z
	facing.y = 0.0
	if facing.length_squared() < 0.0001:
		return Vector3.FORWARD
	return facing.normalized()


func get_save_data() -> Dictionary:
	return {
		"forced": _forced_boarded,
		"staged": _staged_boards,
		"boards": _placed_board_y.duplicate(),
	}


func load_save_data(data: Dictionary) -> void:
	if not boardable:
		tear_open()
		_staged_boards = 0
		_refresh_staged_visual()
		return
	var was_boarded: bool = is_boarded()
	_forced_boarded = bool(data.get("forced", data.get("boarded", false)))
	_staged_boards = maxi(0, int(data.get("staged", 0)))
	_placed_board_y.clear()
	for value: Variant in data.get("boards", []):
		_placed_board_y.append(float(value))
	_rebuild_dynamic_visuals()
	_refresh_staged_visual()
	var now_boarded: bool = is_boarded()
	if now_boarded != was_boarded:
		boarded_changed.emit(now_boarded)
	coverage_changed.emit(get_coverage_fraction())
	staged_boards_changed.emit(_staged_boards)
	_announce()


func _ensure_visual_roots() -> void:
	if not is_instance_valid(_placed_root):
		_placed_root = Node3D.new()
		_placed_root.name = "PlacedBoards"
		add_child(_placed_root)
	if not is_instance_valid(_staged_root):
		_staged_root = Node3D.new()
		_staged_root.name = "StagedBoards"
		add_child(_staged_root)


func _rebuild_dynamic_visuals() -> void:
	if Engine.is_editor_hint():
		return
	_ensure_visual_roots()
	for child: Node in _placed_root.get_children():
		child.queue_free()
	for y: float in _placed_board_y:
		_spawn_placed_board(y)
	_refresh_staged_visual()


func _spawn_placed_board(local_y: float) -> void:
	if Engine.is_editor_hint():
		return
	_ensure_visual_roots()
	var plank := MeshInstance3D.new()
	plank.name = "Board_%02d" % _placed_root.get_child_count()
	var mesh := BoxMesh.new()
	mesh.size = get_board_size()
	var material := StylizedEnvironmentMaterial.make(Color(0.42, 0.30, 0.19), 0.95)
	mesh.material = material
	plank.mesh = mesh
	plank.position = Vector3(0.0, local_y, 0.12)
	_placed_root.add_child(plank)


func _refresh_staged_visual() -> void:
	if Engine.is_editor_hint():
		return
	_ensure_visual_roots()
	for child: Node in _staged_root.get_children():
		child.queue_free()
	for i: int in range(_staged_boards):
		var plank := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(minf(opening_width_m + 0.3, 1.35), 0.055, 0.18)
		var material := StylizedEnvironmentMaterial.make(Color(0.34, 0.23, 0.14), 1.0)
		mesh.material = material
		plank.mesh = mesh
		plank.position = Vector3(opening_width_m * 0.5 + 0.25, staging_floor_y + 0.04 + i * 0.065, 0.65)
		_staged_root.add_child(plank)


func _announce() -> void:
	if boarded_visual != null:
		boarded_visual.visible = _forced_boarded
	if not is_inside_tree():
		return
	var zone := get_parent() as ThermalZone
	if zone != null:
		zone.refresh_breaches()
