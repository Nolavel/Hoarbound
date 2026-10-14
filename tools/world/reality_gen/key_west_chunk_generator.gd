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
const PART_DIR: String = "res://scenes/world/key_west/generated/chunks/parts"
## Far-view meshes, one per chunk ("Far_x_z.res"), streamed by KeyWestRealityFar.
const FAR_DIR: String = "res://scenes/world/key_west/generated/far"
## Heavy groups leave the chunk root as part scenes, attached in this order; Terrain and Anchors stay.
const PART_ORDER: Array[String] = ["Buildings", "Roads", "Infrastructure", "Coastal", "Vegetation", "Barriers", "LandUse", "Winter"]
## Buildings per part scene: about 2 ms of instantiate on the densest Old Town chunk.
const BUILDING_BLOCK: int = 120
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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PART_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FAR_DIR))
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
		var far: ArrayMesh = builder.far_mesh(doc)
		var violations: Array = _check_contract(root)
		var digest: String = _digest(root) + ":" + _mesh_digest(far)
		report["contract_violations"].append_array(violations)
		_remove_parts(String(root.name))
		var part_paths: PackedStringArray = _save_parts(root)
		var err: Error = _save(root, OUT_DIR.path_join("chunks/%s.scn" % root.name))
		var far_path: String = far_path_of(String(root.name))
		if far.get_surface_count() > 0:
			var far_err: Error = ResourceSaver.save(far, far_path, ResourceSaver.FLAG_COMPRESS)
			if far_err != OK:
				err = far_err
		elif FileAccess.file_exists(far_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(far_path))
		for path: String in part_paths:
			if FileAccess.file_exists(path) == false:
				err = ERR_FILE_CANT_WRITE
		report["chunks"][cid] = {"scene": OUT_DIR.path_join("chunks/%s.scn" % root.name), "parts": part_paths.size(), "error": err,
			"features_in_export": doc["features"].size(), "stats": builder.stats.duplicate(), "fidelity": doc["fidelity"],
			"ms": Time.get_ticks_msec() - t0, "contract_violations": violations.size(), "digest": digest}
		root.free()
	if chunk_ids.is_empty():
		_remove_stale_scenes(ids)
	_write_root_scene()
	_write_world_data()
	report["finished"] = Time.get_datetime_string_from_system(true)
	var f: FileAccess = FileAccess.open(OUT_DIR.path_join("generation_report.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, " "))
	return report


## Instantiates a saved chunk with all its parts attached, as the streamer leaves it once ACTIVE.
static func instantiate_assembled(scene_path: String) -> Node3D:
	var chunk: Node3D = (load(scene_path) as PackedScene).instantiate() as Node3D
	for path: String in part_paths_of(scene_path.get_file().get_basename()):
		StreamingSystem.attach_part(chunk, (load(path) as PackedScene).instantiate())
	return chunk


## Part scenes of one chunk ("Chunk_x_z"), in attach order.
static func part_paths_of(chunk_name: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(PART_DIR)
	if dir == null:
		return out
	for file_name: String in dir.get_files():
		if file_name.begins_with(chunk_name + "__") and file_name.ends_with(".scn"):
			out.append(PART_DIR.path_join(file_name))
	out.sort()
	return out


## Moves the PART_ORDER groups out of root into numbered part scenes; Buildings split in blocks.
func _save_parts(root: Node3D) -> PackedStringArray:
	var paths: PackedStringArray = PackedStringArray()
	for group_name: String in PART_ORDER:
		var group: Node3D = root.get_node_or_null(NodePath(group_name)) as Node3D
		if group == null:
			continue
		root.remove_child(group)
		_own(group, null)
		var pieces: Array[Node3D] = [group]
		if group_name == "Buildings":
			var kids: Array = group.get_children().filter(func(n: Node) -> bool: return n.name != &"BuildingCollision")
			for start: int in range(BUILDING_BLOCK, kids.size(), BUILDING_BLOCK):
				var block: Node3D = Node3D.new()
				block.name = "Block_%d" % (start / BUILDING_BLOCK)
				block.set_meta("attach_to", "Buildings")
				for n: Node in kids.slice(start, start + BUILDING_BLOCK):
					group.remove_child(n)
					block.add_child(n)
				pieces.append(block)
		for piece: Node3D in pieces:
			if piece.get_child_count() > 0:
				var path: String = PART_DIR.path_join("%s__%02d_%s.scn" % [root.name, paths.size(), piece.name])
				if _save(piece, path) == OK:
					paths.append(path)
			piece.free()
	return paths


## Packs node with every descendant owned by it, except inside instanced scenes.
func _save(node: Node, path: String) -> Error:
	_own(node, node)
	var packed: PackedScene = PackedScene.new()
	var err: Error = packed.pack(node)
	return ResourceSaver.save(packed, path, ResourceSaver.FLAG_COMPRESS) if err == OK else err


## owner_node null clears ownership, so nodes can move between part roots.
func _own(node: Node, owner_node: Node) -> void:
	for child: Node in node.get_children():
		child.owner = owner_node
		if child.scene_file_path == "":
			_own(child, owner_node)


func _remove_parts(chunk_name: String) -> void:
	for path: String in part_paths_of(chunk_name):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Far mesh path of a chunk ("Chunk_x_z" -> far/Far_x_z.res).
static func far_path_of(chunk_name: String) -> String:
	return FAR_DIR.path_join(chunk_name.replace("Chunk_", "Far_") + ".res")


func _mesh_digest(mesh: ArrayMesh) -> String:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update("far".to_utf8_buffer())
	for s: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		for kind: int in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_INDEX]:
			if arrays[kind] != null:
				ctx.update(var_to_bytes(arrays[kind]))
	return ctx.finish().hex_encode().substr(0, 16)


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
	## Sorted as text: StringNames compare by address, so their order would follow the allocator.
	var keys: PackedStringArray = PackedStringArray()
	for key: StringName in node.get_meta_list():
		keys.append(String(key))
	keys.sort()
	for key: String in keys:
		if not DIGEST_SKIP_META.has(key):
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


## Compares only the chunks of this (partial) build with the recorded digest.
func verify_partial() -> PackedStringArray:
	var bad: PackedStringArray = PackedStringArray()
	var recorded: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIGEST_PATH))
	if not (recorded is Dictionary):
		bad.append("digest missing")
		return bad
	var now: Dictionary = _digests()
	for cid: String in now.keys():
		if (recorded["chunks"] as Dictionary).get(cid, "") != now[cid]:
			bad.append(cid)
	return bad


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
	## An auto name ("@Node@12") comes from a process-wide counter: the chunk would differ by build order.
	for node: Node in root.find_children("*", "", true, false):
		if String(node.name).contains("@"):
			bad.append("%s/%s has an engine-assigned name" % [root.name, root.get_path_to(node)])
	for group: Node in root.get_children():
		if group.name in ["Terrain", "Anchors", "Winter"]:
			continue  # Winter is presentation (data layer "winter"), not features
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
	var parts: DirAccess = DirAccess.open(PART_DIR)
	if parts != null:
		for file_name: String in parts.get_files():
			if not keep.has(file_name.get_slice("__", 0) + ".scn"):
				parts.remove(file_name)
	var far: DirAccess = DirAccess.open(FAR_DIR)
	if far != null:
		for file_name: String in far.get_files():
			if not keep.has(file_name.replace("Far_", "Chunk_").replace(".res", ".scn")):
				far.remove(file_name)


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
		chunk.part_scene_paths = part_paths_of(file_name.get_basename())
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
		var chunk: Node3D = instantiate_assembled(OUT_DIR.path_join("chunks").path_join(file_name))
		var centre: Array = chunk.get_meta("centre_local", [0.0, 0.0])
		chunk.position = Vector3(float(centre[0]), 0.0, float(centre[1]))
		root.add_child(chunk)
		chunk.owner = root
		for part: Node in chunk.find_children("*", "", true, false):
			if part.scene_file_path.begins_with(PART_DIR):
				part.owner = root
	var packed: PackedScene = PackedScene.new()
	if packed.pack(root) == OK:
		ResourceSaver.save(packed, OUT_DIR.path_join("KeyWest_generated.tscn"))
	root.free()
