class_name MotionMatchingDatabaseBuilder
extends RefCounted

## Builds the lab database: profile -> root-space retarget -> curated ranges ->
## bake. Pure data, no scene frames, so bakes are deterministic and cached.

const SOURCE_ROOT := "res://tests/motion_matching/_runtime_cmu/"
const SOURCE_MANIFEST_PATH := SOURCE_ROOT + "source_manifest.tsv"
const CACHE_DIR := "res://tests/motion_matching/_runtime_cache"
const CACHE_PATH := CACHE_DIR + "/canonical_motion_database.res"
const CACHE_SIGNATURE_PATH := CACHE_DIR + "/canonical_motion_database.signature"
const HENRY_MODEL_PATH := "res://assets/characters/henry/henry_outfit.glb"
const BUILD_VERSION := "root-space-v2"


func build(sample_rate_hz: float = 30.0, allow_unverified_profiles: bool = false, use_cache: bool = true) -> Dictionary:
	var sources := _load_manifest()
	if sources.is_empty():
		return {"ok": false, "error": "source manifest missing or empty: %s" % SOURCE_MANIFEST_PATH}
	var target := load_henry_model()
	if target == null:
		return {"ok": false, "error": "Henry UAL skeleton unavailable"}

	var signature := "%s:%d:%s" % [BUILD_VERSION, FileAccess.get_file_as_string(SOURCE_MANIFEST_PATH).hash(), allow_unverified_profiles]
	var cached := _load_cache(signature) if use_cache else null
	if cached != null:
		print("[MM_CACHE_HIT] %d samples / %d ranges" % [cached.get_sample_count(), cached.clip_names.size()])
		return {"ok": true, "database": cached, "target": target, "cache_hit": true, "report": {"signature": signature}}

	var curator := MotionDatasetCurator.new()
	var retargeters: Dictionary = {}
	var windows: Array[Dictionary] = []
	var source_reports: Array[Dictionary] = []
	var skipped: Array[Dictionary] = []
	for source in sources:
		var profile := SourceRetargetProfile.for_dataset(String(source["dataset"]))
		var source_id := "%s_%s" % [source["dataset"], source["clip"]]
		if profile == null or (not profile.verified and not allow_unverified_profiles):
			skipped.append({"source": source_id, "reason": "no verified retarget profile for %s" % source["dataset"]})
			continue
		var path := SOURCE_ROOT + String(source["clip"]) + ".bvh"
		if not FileAccess.file_exists(path):
			skipped.append({"source": source_id, "reason": "not staged"})
			continue
		var clip := BVHClip.new()
		var retargeter := MotionRetargeter.new()
		if not clip.load_file(path, profile.units_to_meters) or not retargeter.setup(clip, profile, target, sample_rate_hz):
			skipped.append({"source": source_id, "reason": "retarget setup failed: %s" % retargeter.error_message})
			continue
		retargeters[source_id] = {"retargeter": retargeter, "source": source}
		var analysis := curator.analyze(retargeter, source_id)
		windows.append_array(analysis["windows"])
		var report: Dictionary = analysis["report"]
		report["retarget"] = retargeter.report
		source_reports.append(report)

	var selection := curator.select(windows)
	var master := MotionDatabase.new()
	var baker := MotionDatabaseBaker.new()
	var range_reports: Array[Dictionary] = []
	for range_entry in selection["ranges"]:
		var source_id := String(range_entry["source"])
		var entry: Dictionary = retargeters[source_id]
		var source: Dictionary = entry["source"]
		var clip_name := "%s@%.2f-%.2f" % [source_id, float(range_entry["start"]), float(range_entry["end"])]
		var provenance := "%s|sha256=%s|%s" % [source.get("url", ""), source.get("sha256", ""), source.get("description", "")]
		var database := baker.bake_range(entry["retargeter"], StringName(clip_name), float(range_entry["start"]), float(range_entry["end"]), String(range_entry["role"]), provenance, sample_rate_hz)
		if database == null or not master.append_database(database):
			return {"ok": false, "error": "bake failed for %s" % clip_name}
		range_reports.append({
			"clip": clip_name, "role_metadata": range_entry["role"], "samples": database.get_sample_count(),
			"label_seconds": range_entry["label_seconds"], "audit": baker.last_quality,
		})
		print("[MM_BAKE] %-34s role(meta)=%-8s samples=%d audit=%s" % [clip_name, range_entry["role"], database.get_sample_count(), baker.last_quality.get("passed", false)])
	master.rebuild_statistics()
	if not master.is_consistent() or master.get_sample_count() == 0:
		return {"ok": false, "error": "merged database invalid"}
	_save_cache(master, signature)
	return {
		"ok": true,
		"database": master,
		"target": target,
		"cache_hit": false,
		"report": {
			"signature": signature,
			"sources": source_reports,
			"skipped_sources": skipped,
			"selection": {
				"covered_seconds": selection["covered_seconds"],
				"available_seconds": selection["available_seconds"],
				"missing_labels": selection["missing_labels"],
				"total_seconds": selection["total_seconds"],
			},
			"ranges": range_reports,
		},
	}


static func load_henry_model() -> UALSkeletonModel:
	var packed := load(HENRY_MODEL_PATH) as PackedScene
	if packed == null:
		return null
	var instance := packed.instantiate()
	var skeletons := instance.find_children("*", "Skeleton3D", true, false)
	var model := UALSkeletonModel.new()
	var ok := not skeletons.is_empty() and model.load_from_skeleton(skeletons[0] as Skeleton3D)
	instance.free()
	return model if ok else null


func _load_manifest() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not FileAccess.file_exists(SOURCE_MANIFEST_PATH):
		return result
	var lines := FileAccess.get_file_as_string(SOURCE_MANIFEST_PATH).split("\n", false)
	var header := lines[0].split("\t")
	for line_index in range(1, lines.size()):
		var fields := lines[line_index].split("\t")
		if fields.size() < header.size():
			continue
		var entry: Dictionary = {}
		for column in range(header.size()):
			entry[header[column]] = fields[column]
		result.append(entry)
	return result


func _load_cache(signature: String) -> MotionDatabase:
	if not FileAccess.file_exists(CACHE_PATH) or not FileAccess.file_exists(CACHE_SIGNATURE_PATH):
		return null
	if FileAccess.get_file_as_string(CACHE_SIGNATURE_PATH).strip_edges() != signature:
		return null
	var database := ResourceLoader.load(CACHE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as MotionDatabase
	return database if database != null and database.is_consistent() else null


func _save_cache(database: MotionDatabase, signature: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIR))
	if ResourceSaver.save(database, CACHE_PATH) != OK:
		push_warning("MotionMatchingDatabaseBuilder: cache save failed.")
		return
	var file := FileAccess.open(CACHE_SIGNATURE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(signature + "\n")
