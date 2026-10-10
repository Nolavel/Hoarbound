class_name KeyWestChunkGenerator
extends RefCounted
## Orchestrates chunk generation: reads the export manifest, builds chunks (corridor first),
## saves one scene per chunk plus a root scene, and checks the metadata contract.

const EXPORT_DIR: String = "res://data/world/key_west/reality/derived/editor_chunks"
const OUT_DIR: String = "res://scenes/world/key_west/generated"
const WORLD_DATA_PATH: String = "res://scenes/world/key_west/generated/world_data.tres"
const STREAM_ID_PREFIX: String = "kw_gen_"
const PACK_MANIFEST: String = "res://data/world/key_west/reality/editor_export/manifest.json"
const DIGEST_PATH: String = "res://data/world/key_west/reality/editor_export/generated_digest.json"
## Stamps that differ between identical rebuilds; everything else must match bit for bit.
const DIGEST_SKIP_META: Array[String] = ["generated_at", "exported_at"]
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
		var digest: String = _digest(root)
		report["contract_violations"].append_array(violations)
		var packed: PackedScene = PackedScene.new()
		var err: Error = packed.pack(root)
		var scene_path: String = OUT_DIR.path_join("chunks/%s.scn" % root.name)
		if err == OK:
			err = ResourceSaver.save(packed, scene_path, ResourceSaver.FLAG_COMPRESS)
		report["chunks"][cid] = {"scene": scene_path, "error": err, "features_in_export": doc["features"].size(),
			"stats": builder.stats.duplicate(), "fidelity": doc["fidelity"], "ms": Time.get_ticks_msec() - t0,
			"contract_violations": violations.size(), "digest": digest}
		root.free()
	if chunk_ids.is_empty():
		_remove_stale_scenes(ids)
	_write_root_scene()
	_write_world_data()
	report["finished"] = Time.get_datetime_string_from_system(true)
	var f: FileAccess = FileAccess.open(OUT_DIR.path_join("generation_report.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, " "))
	return report


## Content hash of a built chunk: tree shape, transforms, metadata, mesh, MultiMesh and collision
## data. Sub-resource ids are random per save, so the .scn bytes cannot serve as the check.
func _digest(root: Node) -> String:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	_digest_node(ctx, root, root)
	return ctx.finish().hex_encode()


func _digest_node(ctx: HashingContext, root: Node, node: Node) -> void:
	var line: String = "%s|%s" % [root.get_path_to(node), node.get_class()]
	if node is Node3D:
		line += "|" + var_to_str((node as Node3D).transform)
	if node.scene_file_path != "":
		line += "|scene=" + node.scene_file_path
	var keys: Array = node.get_meta_list()
	keys.sort()
	for key: StringName in keys:
		if not DIGEST_SKIP_META.has(String(key)):
			line += "|%s=%s" % [key, var_to_str(node.get_meta(key))]
	ctx.update(line.to_utf8_buffer())
	if node is MeshInstance3D and (node as MeshInstance3D).mesh is ArrayMesh:
		var mesh: ArrayMesh = (node as MeshInstance3D).mesh
		for s: int in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(s)
			for kind: int in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_INDEX]:
				if arrays[kind] != null:
					ctx.update(var_to_bytes(arrays[kind]))
			var mat: Material = mesh.surface_get_material(s)
			ctx.update(var_to_str((mat as StandardMaterial3D).albedo_color if mat is StandardMaterial3D else null).to_utf8_buffer())
	elif node is MultiMeshInstance3D:
		ctx.update(var_to_bytes((node as MultiMeshInstance3D).multimesh.buffer))
	elif node is CollisionShape3D:
		var shape: Shape3D = (node as CollisionShape3D).shape
		if shape is ConcavePolygonShape3D:
			ctx.update(var_to_bytes((shape as ConcavePolygonShape3D).get_faces()))
		elif shape is HeightMapShape3D:
			ctx.update(var_to_bytes((shape as HeightMapShape3D).map_data))
	if node.scene_file_path != "" and node != root:
		return  # instanced assets (landmarks) are pinned by sha256 in the asset manifest
	for child: Node in node.get_children():
		_digest_node(ctx, root, child)


## Writes the digest of this build next to the committed interchange archive.
func record_digest() -> Error:
	var pack: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PACK_MANIFEST))
	var doc: Dictionary = {"schema": "kw_reality.generated_digest.v1", "generator_version": KeyWestChunkBuilder.GENERATOR_VERSION,
		"archive_tar_sha256": pack["archive"]["tar_sha256"], "chunks": _digests()}
	var f: FileAccess = FileAccess.open(DIGEST_PATH, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(doc, " ", true))
	return OK


## Compares this build with the recorded digest; returns the mismatching chunk ids.
func verify_digest() -> PackedStringArray:
	var bad: PackedStringArray = PackedStringArray()
	var recorded: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIGEST_PATH))
	var pack: Variant = JSON.parse_string(FileAccess.get_file_as_string(PACK_MANIFEST))
	if not (recorded is Dictionary) or not (pack is Dictionary):
		bad.append("digest or pack manifest missing")
		return bad
	if recorded["archive_tar_sha256"] != pack["archive"]["tar_sha256"]:
		bad.append("digest was recorded for a different interchange archive")
	if recorded["generator_version"] != KeyWestChunkBuilder.GENERATOR_VERSION:
		bad.append("digest was recorded by generator %s" % recorded["generator_version"])
	var now: Dictionary = _digests()
	for cid: String in recorded["chunks"].keys():
		if now.get(cid, "") != recorded["chunks"][cid]:
			bad.append(cid)
	for cid: String in now.keys():
		if not recorded["chunks"].has(cid):
			bad.append(cid)
	return bad


func _digests() -> Dictionary:
	var out: Dictionary = {}
	for cid: String in report["chunks"].keys():
		if report["chunks"][cid].has("digest"):
			out[cid] = report["chunks"][cid]["digest"]
	return out


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
