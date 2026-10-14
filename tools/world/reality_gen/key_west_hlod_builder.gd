class_name KeyWestHLODBuilder
extends RefCounted
## Tier 1 HLOD: one proxy mesh per building cluster, merged by material bucket from the same chunk export
## the detail is built from. Deterministic; a cluster rebuilds only when its sources change.

const OUT_DIR: String = "res://scenes/world/key_west/generated/hlod"
const MANIFEST_PATH: String = "res://scenes/world/key_west/generated/hlod/hlod_manifest.json"
const DIGEST_PATH: String = "res://data/world/key_west/reality/editor_export/hlod_digest.json"
const ASSET_MANIFEST_PATH: String = "res://data/world/key_west/reality/authoring/asset_manifest.json"
const GENERATION_CONFIG: String = "res://data/world/key_west/reality/config/generation.json"
const SCHEMA: String = "kw_reality.hlod_manifest.v1"
## Roof snow folded into the proxy: the cap's own colour, without vertex colours.
const SNOW_BUCKET: String = "snow_roof"

var report: Dictionary = {}
var _builder: KeyWestChunkBuilder = KeyWestChunkBuilder.new()
var _docs: Dictionary = {}  # chunk id -> export doc
var _snow_material: Material
var _material_keys: Dictionary = {}  # material instance id -> builder material key
var _max_snow_slope: float = 70.0


func _init() -> void:
	for key: String in _builder._mat.keys():
		_material_keys[(_builder._mat[key] as Material).get_instance_id()] = key
	_snow_material = _builder._material(KeyWestChunkBuilder.STATIC_SNOW_COLOR)
	var generation: Variant = JSON.parse_string(FileAccess.get_file_as_string(GENERATION_CONFIG))
	if generation is Dictionary:
		_max_snow_slope = float((generation as Dictionary).get("static_snow", {}).get("slope_zero_deg", 70.0))


## Cluster id -> {"chunk": id, "features": [...] sorted by feature_id}, plus "excluded" building records.
func sources() -> Dictionary:
	var clusters: Dictionary = {}
	var excluded: Array = []
	for chunk_id: String in KeyWestChunkBuilder.hlod_config().get("chunks", []):
		var doc: Dictionary = _doc(chunk_id)
		if doc.is_empty():
			excluded.append({"chunk": chunk_id, "reason": "chunk export missing"})
			continue
		for feature: Dictionary in doc["features"]:
			var cluster_id: String = KeyWestChunkBuilder.cluster_of_feature(doc, feature)
			if cluster_id == "":
				if String(feature["mesh"].get("kind", "")) == "building":
					excluded.append({"feature_id": feature["feature_id"], "chunk": chunk_id,
						"reason": "regen_action %s: stays Tier 0 in its chunk" % feature["regen_action"]})
				continue
			var entry: Dictionary = clusters.get_or_add(cluster_id, {"chunk": chunk_id, "features": []})
			(entry["features"] as Array).append(feature)
	for entry: Dictionary in clusters.values():
		(entry["features"] as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["feature_id"]) < String(b["feature_id"]))
	return {"clusters": clusters, "excluded": excluded}


## Hash of everything a proxy is made from: build settings and each source feature's full export record.
func source_hash(features: Array) -> String:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var cfg: Dictionary = KeyWestChunkBuilder.hlod_config()
	ctx.update(("%s|%s|%s|%s" % [cfg.get("build_version"), KeyWestChunkBuilder.GENERATOR_VERSION, cfg.get("cluster_m"), _max_snow_slope]).to_utf8_buffer())
	for feature: Dictionary in features:
		ctx.update(JSON.stringify(feature, "", true).to_utf8_buffer())
	return ctx.finish().hex_encode().substr(0, 16)


## Merged proxy of one cluster: surfaces in bucket-name order, vertices relative to the cluster centre.
func build_proxy(cluster_id: String, features: Array) -> Dictionary:
	var centre: Vector3 = KeyWestChunkBuilder.cluster_centre(cluster_id)
	var buckets: Dictionary = {}  # bucket -> SurfaceTool
	var triangles: Dictionary = {}
	var detail_triangles: int = 0
	var snow_triangles: int = 0
	for feature: Dictionary in features:
		var instance: MeshInstance3D = _builder._building(feature, feature["mesh"]) as MeshInstance3D
		var offset: Vector3 = instance.position - centre
		var mesh: ArrayMesh = instance.mesh
		for s: int in range(mesh.get_surface_count()):
			var key: String = _material_keys.get(mesh.surface_get_material(s).get_instance_id(), "unknown")
			var arrays: Array = mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			detail_triangles += idx.size() / 3
			var is_roof: bool = mesh.surface_get_name(s) == "roof"
			for t: int in range(0, idx.size(), 3):
				var bucket: String = key
				if is_roof and key != "roof_placeholder":
					var face: Vector3 = (verts[idx[t + 1]] - verts[idx[t]]).cross(verts[idx[t + 2]] - verts[idx[t]]).normalized()
					if rad_to_deg(acos(clampf(absf(face.y), 0.0, 1.0))) < _max_snow_slope:
						bucket = SNOW_BUCKET
						snow_triangles += 1
				var st: SurfaceTool = buckets.get(bucket)
				if st == null:
					st = SurfaceTool.new()
					st.begin(Mesh.PRIMITIVE_TRIANGLES)
					buckets[bucket] = st
				for k: int in range(3):
					st.set_normal(normals[idx[t + k]])
					st.add_vertex(verts[idx[t + k]] + offset)
				triangles[bucket] = int(triangles.get(bucket, 0)) + 1
		instance.free()
	var proxy: ArrayMesh = ArrayMesh.new()
	var names: Array = buckets.keys()
	names.sort()
	for bucket: String in names:
		var st: SurfaceTool = buckets[bucket]
		st.index()
		st.commit(proxy, KeyWestChunkBuilder.MESH_FLAGS)
		var last: int = proxy.get_surface_count() - 1
		proxy.surface_set_name(last, bucket)
		proxy.surface_set_material(last, _snow_material if bucket == SNOW_BUCKET else _builder._mat.get(bucket))
	var total: int = 0
	for n: int in triangles.values():
		total += n
	return {"mesh": proxy, "triangles": total, "detail_triangles": detail_triangles, "snow_roof_triangles": snow_triangles,
		"materials": names, "bucket_triangles": triangles}


## Content hash of a proxy mesh: surface names, vertices, normals, indices.
static func mesh_digest(mesh: ArrayMesh) -> String:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for s: int in range(mesh.get_surface_count()):
		ctx.update(String(mesh.surface_get_name(s)).to_utf8_buffer())
		var arrays: Array = mesh.surface_get_arrays(s)
		for kind: int in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_INDEX]:
			if arrays[kind] != null:
				ctx.update(var_to_bytes(arrays[kind]))
	return ctx.finish().hex_encode().substr(0, 16)


static func proxy_path_of(cluster_id: String) -> String:
	return OUT_DIR.path_join("HLOD_%s.res" % cluster_id)


## Current manifest, or an empty one.
static func load_manifest() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return {}
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	return doc if doc is Dictionary else {}


## Builds clusters: all (filter empty), the listed ones, or only the dirty ones; writes proxies and the manifest.
func build(cluster_filter: PackedStringArray = PackedStringArray(), only_dirty: bool = false) -> Dictionary:
	var src: Dictionary = sources()
	var old: Dictionary = load_manifest()
	var old_entries: Dictionary = {}
	for entry: Dictionary in old.get("clusters", []):
		old_entries[entry["cluster_id"]] = entry
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	report = {"built": [], "kept": [], "removed": [], "errors": []}
	var entries: Array = []
	var ids: Array = (src["clusters"] as Dictionary).keys()
	ids.sort()
	for cluster_id: String in ids:
		var info: Dictionary = src["clusters"][cluster_id]
		var hash: String = source_hash(info["features"])
		var prior: Dictionary = old_entries.get(cluster_id, {})
		var dirty: bool = _is_dirty(prior, hash)
		var wanted: bool = cluster_filter.is_empty() or cluster_filter.has(cluster_id)
		if not wanted or (only_dirty and not dirty):
			if not prior.is_empty():
				entries.append(prior)
				report["kept"].append(cluster_id)
			continue
		var built: Dictionary = build_proxy(cluster_id, info["features"])
		var mesh: ArrayMesh = built["mesh"]
		var err: Error = ResourceSaver.save(mesh, proxy_path_of(cluster_id), ResourceSaver.FLAG_COMPRESS)
		if err != OK:
			report["errors"].append("%s: save failed (%d)" % [cluster_id, err])
			continue
		entries.append(_entry(cluster_id, info, hash, built))
		report["built"].append(cluster_id)
	for cluster_id: String in old_entries.keys():
		if not (src["clusters"] as Dictionary).has(cluster_id):
			report["removed"].append(cluster_id)
	_remove_orphan_files(ids)
	_write_manifest(entries, src["excluded"])
	return report


## Rebuilds only clusters whose sources changed since the manifest was written.
func rebuild_dirty() -> Dictionary:
	return build(PackedStringArray(), true)


## Dirty and fresh state of every cluster without writing anything.
func status() -> Dictionary:
	var src: Dictionary = sources()
	var old: Dictionary = {}
	for entry: Dictionary in load_manifest().get("clusters", []):
		old[entry["cluster_id"]] = entry
	var out: Dictionary = {}
	for cluster_id: String in (src["clusters"] as Dictionary).keys():
		out[cluster_id] = "dirty" if _is_dirty(old.get(cluster_id, {}), source_hash(src["clusters"][cluster_id]["features"])) else "fresh"
	return out


## Validation for CI and the editor: missing or duplicate sources, orphans either way, stale proxies.
func check() -> Dictionary:
	var errors: PackedStringArray = PackedStringArray()
	var src: Dictionary = sources()
	var manifest: Dictionary = load_manifest()
	if manifest.is_empty():
		errors.append("manifest missing")
		return {"errors": errors, "dirty": []}
	var seen: Dictionary = {}
	var listed: Dictionary = {}
	for entry: Dictionary in manifest["clusters"]:
		listed[entry["cluster_id"]] = entry
		for fid: String in entry["source_ids"]:
			if seen.has(fid):
				errors.append("duplicate source %s in %s and %s" % [fid, seen[fid], entry["cluster_id"]])
			seen[fid] = entry["cluster_id"]
		if not FileAccess.file_exists(proxy_path_of(entry["cluster_id"])):
			errors.append("missing proxy %s" % entry["cluster_id"])
		elif mesh_digest(load(proxy_path_of(entry["cluster_id"])) as ArrayMesh) != entry["proxy_digest"]:
			errors.append("proxy %s differs from its manifest digest" % entry["cluster_id"])
		if not FileAccess.file_exists(KeyWestChunkGenerator.cluster_path_of(entry["cluster_id"])):
			errors.append("orphan proxy %s: no detail cluster scene" % entry["cluster_id"])
	var dirty: PackedStringArray = PackedStringArray()
	for cluster_id: String in (src["clusters"] as Dictionary).keys():
		for feature: Dictionary in src["clusters"][cluster_id]["features"]:
			if not seen.has(feature["feature_id"]):
				errors.append("missing source %s (cluster %s)" % [feature["feature_id"], cluster_id])
		if not listed.has(cluster_id):
			errors.append("cluster %s has sources but no manifest entry" % cluster_id)
		elif _is_dirty(listed[cluster_id], source_hash(src["clusters"][cluster_id]["features"])):
			dirty.append(cluster_id)
	for cluster_id: String in KeyWestChunkGenerator.cluster_ids():
		if not listed.has(cluster_id):
			errors.append("detail cluster %s has no proxy" % cluster_id)
	var dir: DirAccess = DirAccess.open(OUT_DIR)
	if dir != null:
		for file_name: String in dir.get_files():
			if file_name.begins_with("HLOD_") and file_name.ends_with(".res") and not listed.has(file_name.trim_prefix("HLOD_").trim_suffix(".res")):
				errors.append("orphan proxy file %s" % file_name)
	return {"errors": errors, "dirty": dirty}


## Builds the given clusters in memory and compares them with the manifest; returns mismatches.
func verify_partial(ids: PackedStringArray) -> PackedStringArray:
	var bad: PackedStringArray = PackedStringArray()
	var src: Dictionary = sources()
	var listed: Dictionary = {}
	for entry: Dictionary in load_manifest().get("clusters", []):
		listed[entry["cluster_id"]] = entry
	for cluster_id: String in ids:
		if not (src["clusters"] as Dictionary).has(cluster_id) or not listed.has(cluster_id):
			bad.append("%s unknown" % cluster_id)
			continue
		var built: Dictionary = build_proxy(cluster_id, src["clusters"][cluster_id]["features"])
		if mesh_digest(built["mesh"]) != listed[cluster_id]["proxy_digest"]:
			bad.append(cluster_id)
	return bad


## Digest of the whole HLOD build: the manifest text (it holds every proxy digest and no timestamps).
static func manifest_digest() -> String:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return ""
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(FileAccess.get_file_as_bytes(MANIFEST_PATH))
	return ctx.finish().hex_encode()


func record_digest() -> Error:
	var f: FileAccess = FileAccess.open(DIGEST_PATH, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify({"schema": "kw_reality.hlod_digest.v1", "build_version": KeyWestChunkBuilder.hlod_config().get("build_version"),
		"manifest_sha256": manifest_digest()}, " ", true))
	return OK


func verify_digest() -> PackedStringArray:
	var recorded: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIGEST_PATH)) if FileAccess.file_exists(DIGEST_PATH) else null
	if not (recorded is Dictionary):
		return PackedStringArray(["hlod digest missing"])
	if recorded["manifest_sha256"] != manifest_digest():
		return PackedStringArray(["hlod manifest %s differs from the recorded %s" % [manifest_digest().substr(0, 16), String(recorded["manifest_sha256"]).substr(0, 16)]])
	return PackedStringArray()


func _is_dirty(prior: Dictionary, hash: String) -> bool:
	return prior.is_empty() or prior.get("source_hash") != hash or prior.get("build_version") != KeyWestChunkBuilder.hlod_config().get("build_version") \
		or not FileAccess.file_exists(proxy_path_of(String(prior.get("cluster_id", ""))))


func _entry(cluster_id: String, info: Dictionary, hash: String, built: Dictionary) -> Dictionary:
	var mesh: ArrayMesh = built["mesh"]
	var centre: Vector3 = KeyWestChunkBuilder.cluster_centre(cluster_id)
	var box: AABB = mesh.get_aabb()
	var ids: PackedStringArray = PackedStringArray()
	for feature: Dictionary in info["features"]:
		ids.append(String(feature["feature_id"]))
	var p: PackedStringArray = cluster_id.split("_")
	return {
		"cluster_id": cluster_id, "chunk": info["chunk"], "grid": [int(p[1]), int(p[2])],
		"detail_cell": KeyWestChunkGenerator.CLUSTER_ID_PREFIX + cluster_id, "detail_scene": KeyWestChunkGenerator.cluster_path_of(cluster_id),
		"centre_local": [centre.x, centre.z],
		"bounds": {"min": _round3(box.position + centre), "max": _round3(box.end + centre)},
		"source_ids": ids, "source_count": ids.size(), "source_hash": hash,
		"build_version": KeyWestChunkBuilder.hlod_config().get("build_version"), "builder_version": KeyWestChunkBuilder.GENERATOR_VERSION,
		"proxy_path": proxy_path_of(cluster_id), "proxy_digest": mesh_digest(mesh),
		"triangles": built["triangles"], "detail_triangles": built["detail_triangles"], "snow_roof_triangles": built["snow_roof_triangles"],
		"surfaces": mesh.get_surface_count(), "materials": built["materials"], "bucket_triangles": built["bucket_triangles"],
	}


func _write_manifest(entries: Array, excluded: Array) -> void:
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["cluster_id"]) < String(b["cluster_id"]))
	var cfg: Dictionary = KeyWestChunkBuilder.hlod_config()
	var totals: Dictionary = {"clusters": entries.size(), "sources": 0, "triangles": 0, "detail_triangles": 0, "surfaces": 0}
	for entry: Dictionary in entries:
		for key: String in ["triangles", "detail_triangles", "surfaces"]:
			totals[key] += int(entry[key])
		totals["sources"] += int(entry["source_count"])
	var doc: Dictionary = {"schema": SCHEMA, "build_version": cfg.get("build_version"), "builder_version": KeyWestChunkBuilder.GENERATOR_VERSION,
		"cluster_m": cfg.get("cluster_m"), "chunks": cfg.get("chunks"), "detail_band_m": snappedf(KeyWestChunkBuilder.detail_band_m(), 0.01),
		"policy": cfg.get("policy"), "winter": cfg.get("winter"), "excluded": excluded, "authored": _authored(), "totals": totals, "clusters": entries}
	var f: FileAccess = FileAccess.open(MANIFEST_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(doc, " ", true))
	f.close()


## Authored assets island-wide with their explicit HLOD policy (Tier 0 only in v1).
func _authored() -> Array:
	var out: Array = []
	if not FileAccess.file_exists(ASSET_MANIFEST_PATH):
		return out
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(ASSET_MANIFEST_PATH))
	var assets: Variant = (doc as Dictionary).get("assets", []) if doc is Dictionary else []
	for asset: Variant in (assets as Array if assets is Array else (assets as Dictionary).values()):
		if asset is Dictionary:
			out.append({"feature_id": asset.get("feature_id", ""), "asset_id": asset.get("asset_id", ""),
				"policy": "excluded from HLOD v1: Tier 0 authored scene in its chunk; manual proxy is phase 2"})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["feature_id"]) < String(b["feature_id"]))
	return out


func _remove_orphan_files(ids: Array) -> void:
	var dir: DirAccess = DirAccess.open(OUT_DIR)
	if dir == null:
		return
	for file_name: String in dir.get_files():
		if file_name.begins_with("HLOD_") and file_name.ends_with(".res") and not ids.has(file_name.trim_prefix("HLOD_").trim_suffix(".res")):
			dir.remove(file_name)
			report["removed"].append(file_name)


func _doc(chunk_id: String) -> Dictionary:
	if not _docs.has(chunk_id):
		var p: PackedStringArray = chunk_id.split(":")
		var path: String = KeyWestChunkGenerator.EXPORT_DIR.path_join("chunk_%s_%s.json" % [p[0], p[1]])
		_docs[chunk_id] = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}
	return _docs[chunk_id]


static func _round3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]
