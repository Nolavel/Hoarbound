class_name CMUMultiClipDatabaseBuilder
extends RefCounted

## Issue #202 canonical CMU curation + merged post-retarget database bake.
## Long raw captures are analyzed cheaply first; only clean semantic ranges are
## sent through the expensive UAL retarget baker and runtime search database.

const SOURCE_ROOT := "res://tests/motion_matching/_runtime_cmu/"
const CACHE_DIR := "res://tests/motion_matching/_runtime_cache"
const CACHE_PATH := CACHE_DIR + "/canonical_motion_database.res"
const CACHE_SIGNATURE_PATH := CACHE_DIR + "/canonical_motion_database.signature"
const SOURCE_MANIFEST_PATH := SOURCE_ROOT + "source_manifest.tsv"
const CURATION_VERSION := "cmu-semantic-v5"

# MotionDatabaseBaker historically used the raw BVH root facing, whose forward
# axis is 180 degrees opposite the visual CMU character forward. Retarget pose
# rotations are correct, so fix only the already-baked search basis here.
const FACING_BASIS_FEATURES := [
	0, 1,
	3, 5, 6, 8,
	9, 11, 12, 14,
	15, 17, 18, 20,
	21, 22, 23, 24, 25, 26,
]


func build(lab_scene: PackedScene, parent: Node, sample_rate_hz: float = 30.0) -> Dictionary:
	if lab_scene == null or parent == null:
		return {"ok": false, "error": "invalid scene/parent"}
	var tree := parent.get_tree()
	if tree == null:
		return {"ok": false, "error": "SceneTree unavailable"}
	var source_defs := _load_source_defs()
	if source_defs.is_empty():
		return {"ok": false, "error": "CMU source manifest is missing/empty"}

	var signature := _build_signature()
	var cached := _load_cache(signature)
	if cached != null:
		var cached_lab := await _create_presentation_lab(lab_scene, parent, tree, source_defs)
		if cached_lab == null:
			return {"ok": false, "error": "cached database loaded but presentation lab failed"}
		print("[MM_CACHE_HIT] %d samples / %d clips" % [cached.get_sample_count(), cached.clip_names.size()])
		return {
			"ok": true, "database": cached, "lab": cached_lab,
			"source_reports": [], "proof_source_count": cached.clip_names.size(),
			"cache_hit": true,
			"curation_report": {"signature": signature, "cache_hit": true},
		}

	var segmenter := CMUMotionSegmenter.new()
	var all_candidates: Array[Dictionary] = []
	var source_reports: Array[Dictionary] = []
	for source_def in source_defs:
		var source_path := SOURCE_ROOT + String(source_def["file"])
		if not FileAccess.file_exists(source_path):
			continue
		var analyzed := segmenter.analyze_file(
			source_path,
			String(source_def["clip"]),
			String(source_def["trial"]),
			String(source_def["description"])
		)
		if not bool(analyzed.get("ok", false)):
			return {"ok": false, "error": "segment analysis failed for %s: %s" % [source_def["clip"], analyzed.get("error", "unknown")]}
		all_candidates.append_array(analyzed.get("candidates", []))
		source_reports.append(analyzed.get("report", {}))

	var selection := segmenter.select_canonical(all_candidates)
	var segments: Array[Dictionary] = []
	segments.assign(selection.get("segments", []))
	if segments.size() < 5:
		return {"ok": false, "error": "semantic curation found only %d usable segments" % segments.size()}
	print("[MM_CURATE] candidates=%d selected=%d missing=%s" % [all_candidates.size(), segments.size(), JSON.stringify(selection.get("missing_roles", []))])
	for segment in segments:
		print("[MM_SEGMENT] %-12s %s %.3f..%.3f" % [segment["role"], segment["source"], segment["start"], segment["end"]])

	var master := MotionDatabase.new()
	for segment in segments:
		var lab := lab_scene.instantiate() as CMUUALRetargetLab
		if lab == null:
			return {"ok": false, "error": "CMU lab scene has wrong root type"}
		var provenance := "%s#%.3f-%.3f" % [String(segment["source_path"]), float(segment["start"]), float(segment["end"])]
		if not lab.configure_source(
			String(segment["source_path"]), StringName(segment["clip"]),
			String(segment["trial"]), String(segment["description"]), String(segment["role"])
		):
			lab.free()
			return {"ok": false, "error": "failed to configure %s" % String(segment["clip"])}
		parent.add_child(lab)
		if not await _wait_until_ready(lab, tree):
			var failed_report := lab.get_retarget_report()
			lab.queue_free()
			await tree.process_frame
			return {"ok": false, "error": "retarget setup failed for %s" % String(segment["clip"]), "source_report": failed_report}
		var clip_database: MotionDatabase = await lab.bake_motion_database(
			sample_rate_hz, float(segment["start"]), float(segment["end"]), String(segment["role"]), provenance
		)
		if clip_database == null or not clip_database.is_consistent():
			lab.queue_free()
			await tree.process_frame
			return {"ok": false, "error": "database bake failed for %s" % String(segment["clip"])}
		_flip_facing_basis(clip_database)
		if not master.append_database(clip_database):
			lab.queue_free()
			await tree.process_frame
			return {"ok": false, "error": "database merge failed for %s" % String(segment["clip"])}
		print("[MM_CURATED_BAKE] %s role=%s samples=%d" % [segment["clip"], segment["role"], clip_database.get_sample_count()])
		lab.queue_free()
		await tree.process_frame

	master.rebuild_statistics()
	if not master.is_consistent() or master.clip_names.size() < 2:
		return {"ok": false, "error": "curated merged database invalid"}
	_save_cache(master, signature)

	var presentation_lab := await _create_presentation_lab(lab_scene, parent, tree, source_defs)
	if presentation_lab == null:
		return {"ok": false, "error": "presentation lab failed"}
	return {
		"ok": true, "database": master, "lab": presentation_lab,
		"source_reports": source_reports, "proof_source_count": segments.size(),
		"cache_hit": false,
		"curation_report": {
			"signature": signature,
			"cache_hit": false,
			"candidate_count": all_candidates.size(),
			"selected_segments": segments,
			"missing_roles": selection.get("missing_roles", []),
		},
	}


func _flip_facing_basis(database: MotionDatabase) -> void:
	for sample_index in range(database.get_sample_count()):
		var base := sample_index * database.feature_count
		for feature_index in FACING_BASIS_FEATURES:
			database.features[base + feature_index] = -database.features[base + feature_index]
	for value_index in range(database.sample_root_facings.size()):
		database.sample_root_facings[value_index] = -database.sample_root_facings[value_index]
	database.rebuild_statistics()


func _load_source_defs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not FileAccess.file_exists(SOURCE_MANIFEST_PATH):
		return result
	var lines := FileAccess.get_file_as_string(SOURCE_MANIFEST_PATH).split("\n", false)
	for line_index in range(1, lines.size()):
		var line := lines[line_index].strip_edges()
		if line.is_empty():
			continue
		var fields := line.split("\t", false)
		if fields.size() < 4:
			continue
		var clip := String(fields[0])
		var subject := String(fields[1])
		result.append({
			"file": clip + ".bvh",
			"clip": "CMU_" + clip,
			"trial": "CMU Subject %s / %s" % [subject.trim_prefix("0"), clip],
			"description": String(fields[3]),
		})
	return result


func _create_presentation_lab(lab_scene: PackedScene, parent: Node, tree: SceneTree, source_defs: Array[Dictionary]) -> CMUUALRetargetLab:
	var definition: Dictionary = source_defs[0]
	for candidate in source_defs:
		if String(candidate["file"]) == "111_28.bvh":
			definition = candidate
			break
	var lab := lab_scene.instantiate() as CMUUALRetargetLab
	if lab == null:
		return null
	if not lab.configure_source(
		SOURCE_ROOT + String(definition["file"]), StringName(definition["clip"]),
		String(definition["trial"]), String(definition["description"]), "idle_neutral"
	):
		lab.free()
		return null
	parent.add_child(lab)
	if not await _wait_until_ready(lab, tree):
		lab.queue_free()
		await tree.process_frame
		return null
	return lab


func _build_signature() -> String:
	var manifest := FileAccess.get_file_as_string(SOURCE_MANIFEST_PATH) if FileAccess.file_exists(SOURCE_MANIFEST_PATH) else ""
	return "%s:%d" % [CURATION_VERSION, manifest.hash()]


func _load_cache(signature: String) -> MotionDatabase:
	if not FileAccess.file_exists(CACHE_PATH) or not FileAccess.file_exists(CACHE_SIGNATURE_PATH):
		return null
	if FileAccess.get_file_as_string(CACHE_SIGNATURE_PATH).strip_edges() != signature:
		return null
	var resource := ResourceLoader.load(CACHE_PATH)
	var database := resource as MotionDatabase
	return database if database != null and database.is_consistent() else null


func _save_cache(database: MotionDatabase, signature: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIR))
	var error := ResourceSaver.save(database, CACHE_PATH)
	if error != OK:
		push_warning("CMUMultiClipDatabaseBuilder: cache save failed (%d)." % error)
		return
	var file := FileAccess.open(CACHE_SIGNATURE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(signature + "\n")
	print("[MM_CACHE_SAVE] %s" % ProjectSettings.globalize_path(CACHE_PATH))


func _wait_until_ready(lab: CMUUALRetargetLab, tree: SceneTree) -> bool:
	for _frame in range(360):
		await tree.process_frame
		if lab.is_ready_for_capture():
			return true
		var report := lab.get_retarget_report()
		if report.has("error"):
			return false
	return false
