class_name KeyWestRealityFar
extends Node3D
## Far view: each chunk's generated far mesh streams through the shared StreamingSystem in a wide band,
## like the legacy far city, and hides while its detailed chunk is in. No collision.

const STREAMING: GDScript = preload("res://core/world/streaming_system.gd")
const FAR_DIR: String = "res://scenes/world/key_west/generated/far"
const NEAR_PREFIX: String = "kw_gen_"
const FAR_PREFIX: String = "kw_far_"
const CHUNK_M: float = 512.0

## Far meshes stream within this distance of Henry.
@export var far_radius_m: float = 2500.0

var _streaming: StreamingSystem
var _nodes: Dictionary = {}  # far id -> MeshInstance3D
var _near_in: Dictionary = {}  # cell suffix "x_z" -> true while its detailed chunk is in the tree


func on_world_ready(context: WorldContext) -> void:
	_streaming = context.get_system(STREAMING) as StreamingSystem
	if _streaming == null:
		push_warning("KeyWestRealityFar: no StreamingSystem; far view is off")
		return
	_streaming.cell_state_changed.connect(_on_cell_state_changed)
	sync_with(_streaming)
	_streaming.register_runtime_source(self)


## Picks up detailed chunks the streamer made live before this node connected (boot prewarm).
func sync_with(streaming: StreamingSystem) -> void:
	for descriptor: Dictionary in get_stream_chunks():
		var cell: String = String(descriptor["id"]).trim_prefix(FAR_PREFIX)
		_on_cell_state_changed(StringName(NEAR_PREFIX + cell), streaming.get_state(StringName(NEAR_PREFIX + cell)))


## Runtime source contract (StreamingSystem.register_runtime_source).
func get_stream_chunks() -> Array:
	var out: Array = []
	var dir: DirAccess = DirAccess.open(FAR_DIR)
	if dir == null:
		return out
	for file_name: String in dir.get_files():
		var cell: String = file_name.trim_suffix(".remap").trim_suffix(".res").trim_prefix("Far_")
		if cell == file_name or not file_name.contains(".res"):
			continue
		var xz: PackedStringArray = cell.split("_")
		out.append({"id": StringName(FAR_PREFIX + cell), "radius": far_radius_m,
			"position": Vector3((float(xz[0]) + 0.5) * CHUNK_M, 0.0, (float(xz[1]) + 0.5) * CHUNK_M)})
	return out


func activate_stream_chunk(id: StringName, _container: Node3D) -> Node3D:
	var cell: String = String(id).trim_prefix(FAR_PREFIX)
	var mesh: Mesh = ResourceLoader.load(FAR_DIR.path_join("Far_%s.res" % cell)) as Mesh
	if mesh == null:
		return null
	var xz: PackedStringArray = cell.split("_")
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = "Far_" + cell
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = Vector3((float(xz[0]) + 0.5) * CHUNK_M, 0.0, (float(xz[1]) + 0.5) * CHUNK_M)
	instance.visible = not _near_in.has(cell)
	add_child(instance)
	_nodes[id] = instance
	return instance


func deactivate_stream_chunk(id: StringName) -> void:
	var instance: Node = _nodes.get(id) as Node
	_nodes.erase(id)
	if is_instance_valid(instance):
		instance.queue_free()


## A detailed chunk entering (its terrain is in from the first assembly frame) hides its far mesh.
func _on_cell_state_changed(id: StringName, state: StreamingSystem.CellState) -> void:
	if not String(id).begins_with(NEAR_PREFIX):
		return
	var cell: String = String(id).trim_prefix(NEAR_PREFIX)
	var near_in: bool = state == StreamingSystem.CellState.ACTIVE or state == StreamingSystem.CellState.ASSEMBLING
	if near_in:
		_near_in[cell] = true
	else:
		_near_in.erase(cell)
	var far: MeshInstance3D = _nodes.get(StringName(FAR_PREFIX + cell)) as MeshInstance3D
	if is_instance_valid(far):
		far.visible = not near_in
