@tool
class_name KeyWestRealityEditorView
extends Node3D
## Editor view of the generated Reality world: every chunk as its far mesh, full detail for the
## chunks nearest the focus. Preview nodes are internal children and are never saved.

signal detail_changed(loaded: PackedStringArray)

const CHUNK_DIR: String = "res://scenes/world/key_west/generated/chunks"
const FAR_DIR: String = "res://scenes/world/key_west/generated/far"
const CHUNK_M: float = 512.0

## Detailed chunks kept at once; each costs one assembled chunk scene in memory.
@export_range(1, 25) var detail_budget: int = 9
## Chunks whose centre lies farther than this from the focus stay as far meshes.
@export var detail_radius_m: float = 800.0
## Builds the far overview when the scene opens in the editor.
@export var overview_on_ready: bool = true

var _cells: PackedStringArray = PackedStringArray()  # "x_z" of every generated chunk
var _far: Dictionary = {}  # "x_z" -> MeshInstance3D
var _detail: Dictionary = {}  # "x_z" -> Node3D
var _focus: Vector3 = Vector3.INF


func _ready() -> void:
	if Engine.is_editor_hint() and overview_on_ready:
		build_overview()


## Adds every chunk's far mesh; safe to call again (rebuilds).
func build_overview() -> int:
	for node: Node in _far.values():
		node.queue_free()
	_far.clear()
	_cells.clear()
	var dir: DirAccess = DirAccess.open(CHUNK_DIR)
	if dir == null:
		return 0
	for file_name: String in dir.get_files():
		if file_name.begins_with("Chunk_") and file_name.ends_with(".scn"):
			_cells.append(file_name.trim_prefix("Chunk_").trim_suffix(".scn"))
	_cells.sort()
	for cell: String in _cells:
		var mesh: Mesh = load(FAR_DIR.path_join("Far_%s.res" % cell)) as Mesh if ResourceLoader.exists(FAR_DIR.path_join("Far_%s.res" % cell)) else null
		if mesh == null:
			continue
		var instance: MeshInstance3D = MeshInstance3D.new()
		instance.name = "Far_" + cell
		instance.mesh = mesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.position = _cell_centre(cell)
		instance.visible = not _detail.has(cell)
		add_child(instance, false, Node.INTERNAL_MODE_BACK)
		_far[cell] = instance
	return _far.size()


## Moves the detail window; the next step() calls bring the nearest chunks in, one per call.
func set_focus(world_position: Vector3) -> void:
	_focus = world_position


## Frees chunks that left the window and assembles at most one new one; true while work remains.
func step() -> bool:
	if _focus == Vector3.INF:
		return false
	var wanted: PackedStringArray = _wanted()
	for cell: String in _detail.keys():
		if not wanted.has(cell):
			(_detail[cell] as Node).queue_free()
			_detail.erase(cell)
			_set_far_visible(cell, true)
	for cell: String in wanted:
		if _detail.has(cell):
			continue
		var chunk: Node3D = KeyWestChunkGenerator.instantiate_assembled(CHUNK_DIR.path_join("Chunk_%s.scn" % cell))
		var centre: Array = chunk.get_meta("centre_local", [0.0, 0.0])
		chunk.position = Vector3(float(centre[0]), 0.0, float(centre[1]))
		add_child(chunk, false, Node.INTERNAL_MODE_BACK)
		_detail[cell] = chunk
		_set_far_visible(cell, false)
		detail_changed.emit(loaded_cells())
		return wanted.size() > _detail.size()
	return false


func loaded_cells() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray(_detail.keys())
	out.sort()
	return out


func far_count() -> int:
	return _far.size()


## Chunk id "x_z" holding a local position.
static func cell_of(world_position: Vector3) -> String:
	return "%d_%d" % [floori(world_position.x / CHUNK_M), floori(world_position.z / CHUNK_M)]


func _wanted() -> PackedStringArray:
	var ranked: Array = []
	for cell: String in _cells:
		var d: float = Vector2(_focus.x, _focus.z).distance_to(Vector2(_cell_centre(cell).x, _cell_centre(cell).z))
		if d <= detail_radius_m:
			ranked.append([d, cell])
	ranked.sort()
	var out: PackedStringArray = PackedStringArray()
	for pair: Array in ranked.slice(0, detail_budget):
		out.append(pair[1])
	return out


func _cell_centre(cell: String) -> Vector3:
	var xz: PackedStringArray = cell.split("_")
	return Vector3((float(xz[0]) + 0.5) * CHUNK_M, 0.0, (float(xz[1]) + 0.5) * CHUNK_M)


func _set_far_visible(cell: String, on: bool) -> void:
	var far: MeshInstance3D = _far.get(cell) as MeshInstance3D
	if is_instance_valid(far):
		far.visible = on
