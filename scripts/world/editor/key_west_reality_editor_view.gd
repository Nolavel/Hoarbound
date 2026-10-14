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
var _clusters: Dictionary = {}  # cluster id -> {"detail": Node3D, "proxy": MeshInstance3D or null, "chunk": "x_z"}
var _bounds: Dictionary = {}  # cluster id -> MeshInstance3D wire box
var _manifest: Dictionary = {}  # cluster id -> HLOD manifest entry


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
			_drop_clusters(cell)
			_set_far_visible(cell, true)
	for cell: String in wanted:
		if _detail.has(cell):
			continue
		var chunk: Node3D = KeyWestChunkGenerator.instantiate_assembled(CHUNK_DIR.path_join("Chunk_%s.scn" % cell))
		var centre: Array = chunk.get_meta("centre_local", [0.0, 0.0])
		chunk.position = Vector3(float(centre[0]), 0.0, float(centre[1]))
		add_child(chunk, false, Node.INTERNAL_MODE_BACK)
		_detail[cell] = chunk
		_add_clusters(cell, chunk)
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


## HLOD manifest entries by cluster id (re-read on demand after a build).
func reload_manifest() -> Dictionary:
	_manifest.clear()
	for entry: Dictionary in KeyWestHLODBuilder.load_manifest().get("clusters", []):
		_manifest[entry["cluster_id"]] = entry
	return _manifest


## Cluster id whose cell holds a local position, or "" when no cluster was built there.
func cluster_at(world_position: Vector3) -> String:
	if _manifest.is_empty():
		reload_manifest()
	var size: float = float(KeyWestChunkBuilder.hlod_config().get("cluster_m", 128))
	var cluster_id: String = KeyWestChunkBuilder.cluster_id_of(Vector2i(floori(world_position.x / size), floori(world_position.z / size)))
	return cluster_id if _manifest.has(cluster_id) else ""


## Previews a loaded cluster as its detail (tier 0) or its proxy (tier 1); false when it is not loaded.
func set_cluster_tier(cluster_id: String, tier: int) -> bool:
	var c: Dictionary = _clusters.get(cluster_id, {})
	if c.is_empty():
		return false
	if c["proxy"] != null:
		(c["proxy"] as Node).queue_free()
		c["proxy"] = null
	(c["detail"] as Node3D).visible = tier == 0
	if tier == 1:
		var path: String = KeyWestHLODBuilder.proxy_path_of(cluster_id)
		var mesh: Mesh = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as Mesh if ResourceLoader.exists(path) else null
		if mesh == null:
			(c["detail"] as Node3D).visible = true
			return false
		var proxy: MeshInstance3D = MeshInstance3D.new()
		proxy.name = "HLOD_" + cluster_id
		proxy.mesh = mesh
		proxy.position = KeyWestChunkBuilder.cluster_centre(cluster_id)
		add_child(proxy, false, Node.INTERNAL_MODE_BACK)
		c["proxy"] = proxy
	return true


## 0 or 1 while the cluster's chunk is in detail, -1 otherwise.
func cluster_tier(cluster_id: String) -> int:
	var c: Dictionary = _clusters.get(cluster_id, {})
	if c.is_empty():
		return -1
	return 1 if c["proxy"] != null else 0


## Draws or removes the cluster's world bounds (from the manifest) as a wire box.
func show_bounds(cluster_id: String, on: bool) -> void:
	if _bounds.has(cluster_id):
		(_bounds[cluster_id] as Node).queue_free()
		_bounds.erase(cluster_id)
	if not on:
		return
	var entry: Dictionary = reload_manifest().get(cluster_id, {})
	if entry.is_empty():
		return
	var lo: Array = entry["bounds"]["min"]
	var hi: Array = entry["bounds"]["max"]
	var a: Vector3 = Vector3(float(lo[0]), float(lo[1]), float(lo[2]))
	var b: Vector3 = Vector3(float(hi[0]), float(hi[1]), float(hi[2]))
	var lines: ImmediateMesh = ImmediateMesh.new()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.55, 0.1)
	material.no_depth_test = true
	lines.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for edge: Array in _box_edges(a, b):
		lines.surface_add_vertex(edge[0])
		lines.surface_add_vertex(edge[1])
	lines.surface_end()
	var box: MeshInstance3D = MeshInstance3D.new()
	box.name = "Bounds_" + cluster_id
	box.mesh = lines
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(box, false, Node.INTERNAL_MODE_BACK)
	_bounds[cluster_id] = box


func loaded_clusters() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray(_clusters.keys())
	out.sort()
	return out


func _add_clusters(cell: String, chunk: Node3D) -> void:
	for cluster_id: String in KeyWestChunkGenerator.cluster_ids(cell.replace("_", ":")):
		var detail: Node3D = (load(KeyWestChunkGenerator.cluster_path_of(cluster_id)) as PackedScene).instantiate() as Node3D
		detail.position = KeyWestChunkBuilder.cluster_centre(cluster_id) - chunk.position
		chunk.add_child(detail)
		_clusters[cluster_id] = {"detail": detail, "proxy": null, "chunk": cell}


func _drop_clusters(cell: String) -> void:
	for cluster_id: String in _clusters.keys():
		if _clusters[cluster_id]["chunk"] == cell:
			if _clusters[cluster_id]["proxy"] != null:
				(_clusters[cluster_id]["proxy"] as Node).queue_free()
			_clusters.erase(cluster_id)


static func _box_edges(a: Vector3, b: Vector3) -> Array:
	var c: Array[Vector3] = []
	for i: int in range(8):
		c.append(Vector3(b.x if i & 1 else a.x, b.y if i & 2 else a.y, b.z if i & 4 else a.z))
	var out: Array = []
	for i: int in range(8):
		for bit: int in [1, 2, 4]:
			if not (i & bit):
				out.append([c[i], c[i | bit]])
	return out
