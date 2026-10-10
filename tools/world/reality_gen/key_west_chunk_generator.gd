class_name KeyWestChunkGenerator
extends RefCounted
## Orchestrates chunk generation: reads the export manifest, builds chunks (corridor first),
## saves one scene per chunk plus a root scene, and checks the metadata contract.

const EXPORT_DIR: String = "res://data/world/key_west/reality/derived/editor_chunks"
const OUT_DIR: String = "res://scenes/world/key_west/generated"
const WORLD_DATA_PATH: String = "res://scenes/world/key_west/generated/world_data.tres"
const STREAM_ID_PREFIX: String = "kw_gen_"
const CONTRACT_KEYS: Array[String] = ["feature_id", "feature_class", "source_geometry_hash", "source_dataset", "source_epoch",
	"reconstruction_class", "confidence", "override_state", "authoring_state", "generator_version", "generated_at", "regen_action"]

var report: Dictionary = {}


## Generates the given chunk ids ("cx:cz"); empty means every exported chunk, corridor chunks first.
func generate(chunk_ids: PackedStringArray) -> Dictionary:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(EXPORT_DIR.path_join("manifest.json")))
	var ids: PackedStringArray = chunk_ids
	if ids.is_empty():
		ids = PackedStringArray(manifest["route_chunks"])
		for cid: String in manifest["chunks"]:
			if not ids.has(cid):
				ids.append(cid)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR.path_join("chunks")))
	var builder: KeyWestChunkBuilder = KeyWestChunkBuilder.new()
	report = {"chunks": {}, "contract_violations": [], "started": Time.get_datetime_string_from_system(true)}
	for cid: String in ids:
		var parts: PackedStringArray = cid.split(":")
		var json_path: String = EXPORT_DIR.path_join("chunk_%s_%s.json" % [parts[0], parts[1]])
		if not FileAccess.file_exists(json_path):
			report["chunks"][cid] = {"error": "no export"}
			continue
		var t0: int = Time.get_ticks_msec()
		var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(json_path))
		var root: Node3D = builder.build(doc, EXPORT_DIR)
		var violations: Array = _check_contract(root)
		report["contract_violations"].append_array(violations)
		var packed: PackedScene = PackedScene.new()
		var err: Error = packed.pack(root)
		var scene_path: String = OUT_DIR.path_join("chunks/%s.scn" % root.name)
		if err == OK:
			err = ResourceSaver.save(packed, scene_path, ResourceSaver.FLAG_COMPRESS)
		report["chunks"][cid] = {"scene": scene_path, "error": err, "features_in_export": doc["features"].size(),
			"stats": builder.stats.duplicate(), "fidelity": doc["fidelity"], "ms": Time.get_ticks_msec() - t0,
			"contract_violations": violations.size()}
		root.free()
	if chunk_ids.is_empty():
		_remove_stale_scenes(ids)
	_write_root_scene()
	_write_world_data()
	report["finished"] = Time.get_datetime_string_from_system(true)
	var f: FileAccess = FileAccess.open(OUT_DIR.path_join("generation_report.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, " "))
	return report


## Every feature node under the feature groups must carry the contract keys.
func _check_contract(root: Node3D) -> Array:
	var bad: Array = []
	for group: Node in root.get_children():
		if group.name in ["Terrain", "Anchors"]:
			continue
		for node: Node in group.get_children():
			if String(node.name).begins_with("KW_WIRE_") or node.name == &"BuildingCollision":
				continue
			if node is MultiMeshInstance3D:
				bad.append_array(_check_instances(root, node as MultiMeshInstance3D))
				continue
			for key: String in CONTRACT_KEYS:
				if not node.has_meta(key):
					bad.append("%s/%s missing %s" % [root.name, node.name, key])
					break
	return bad


## Batched point features carry the contract per instance, in arrays as long as the MultiMesh.
func _check_instances(root: Node3D, node: MultiMeshInstance3D) -> Array:
	var count: int = node.multimesh.instance_count
	if count > 0 and node.multimesh.buffer.is_empty():
		return ["%s/%s MultiMesh buffer is empty: generate with a rendering driver, not --headless" % [root.name, node.name]]
	if node.has_meta("instances_of"):
		return []
	for key: String in KeyWestChunkBuilder.CONTRACT_KEYS:
		var values: Variant = node.get_meta("instance_" + key, null)
		if not (values is PackedStringArray) or (values as PackedStringArray).size() != count:
			return ["%s/%s instance_%s missing or not %d long" % [root.name, node.name, key, count]]
	return []


func _remove_stale_scenes(ids: PackedStringArray) -> void:
	var keep: Dictionary = {}
	for cid: String in ids:
		var parts: PackedStringArray = cid.split(":")
		keep["Chunk_%s_%s.scn" % [parts[0], parts[1]]] = true
	var dir: DirAccess = DirAccess.open(OUT_DIR.path_join("chunks"))
	if dir == null:
		return
	for file_name: String in dir.get_files():
		if file_name.ends_with(".scn") and not keep.has(file_name):
			dir.remove(file_name)


## WorldData for the production StreamingSystem: one ChunkData per saved chunk, centred.
func _write_world_data() -> void:
	var data: WorldData = WorldData.new()
	data.source_scene_path = OUT_DIR.path_join("KeyWest_generated.tscn")
	var dir: DirAccess = DirAccess.open(OUT_DIR.path_join("chunks"))
	if dir == null:
		return
	var names: PackedStringArray = dir.get_files()
	names.sort()
	for file_name: String in names:
		if not file_name.ends_with(".scn"):
			continue
		var parts: PackedStringArray = file_name.trim_prefix("Chunk_").trim_suffix(".scn").split("_")
		var cx: int = int(parts[0])
		var cz: int = int(parts[1])
		var chunk: ChunkData = ChunkData.new()
		chunk.id = StringName("%s%d_%d" % [STREAM_ID_PREFIX, cx, cz])
		chunk.display_name = "Key West %d:%d" % [cx, cz]
		chunk.location = "key_west"
		chunk.position = Vector3((cx + 0.5) * 512.0, 0.0, (cz + 0.5) * 512.0)
		chunk.radius = 512.0 * sqrt(2.0) * 0.5
		chunk.content_scene_path = OUT_DIR.path_join("chunks").path_join(file_name)
		data.chunks.append(chunk)
	ResourceSaver.save(data, WORLD_DATA_PATH)
	report["world_data"] = {"path": WORLD_DATA_PATH, "chunks": data.chunks.size()}


## KeyWest root that instances every saved chunk scene.
func _write_root_scene() -> void:
	var root: Node3D = Node3D.new()
	root.name = "KeyWest"
	root.set_meta("generator", "KeyWestChunkGenerator")
	var dir: DirAccess = DirAccess.open(OUT_DIR.path_join("chunks"))
	if dir == null:
		return
	var names: PackedStringArray = dir.get_files()
	names.sort()
	for file_name: String in names:
		if not file_name.ends_with(".scn"):
			continue
		var chunk: Node3D = (load(OUT_DIR.path_join("chunks").path_join(file_name)) as PackedScene).instantiate() as Node3D
		var centre: Array = chunk.get_meta("centre_local", [0.0, 0.0])
		chunk.position = Vector3(float(centre[0]), 0.0, float(centre[1]))
		root.add_child(chunk)
		chunk.owner = root
	var packed: PackedScene = PackedScene.new()
	if packed.pack(root) == OK:
		ResourceSaver.save(packed, OUT_DIR.path_join("KeyWest_generated.tscn"))
	root.free()
