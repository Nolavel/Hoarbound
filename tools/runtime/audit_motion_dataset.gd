extends SceneTree

## Headless dataset gate: rebuilds the database and fails on a broken retarget
## audit or missing coverage label. Run before any render capture.

const OUT_PATH := "res://docs/runtime_previews/motion_matching_lab/dataset_audit.json"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var build := MotionMatchingDatabaseBuilder.new().build(30.0, OS.get_environment("MM_ALLOW_UNVERIFIED") == "1", false)
	if not bool(build.get("ok", false)):
		push_error("MotionDatasetAudit: %s" % String(build.get("error", "build failed")))
		quit(2)
		return
	var report: Dictionary = build["report"]
	var database: MotionDatabase = build["database"]
	var failed: Array[String] = []
	for range_report in report.get("ranges", []):
		if not bool(range_report["audit"].get("passed", false)):
			failed.append(String(range_report["clip"]))
	var missing: Array = report.get("selection", {}).get("missing_labels", [])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_PATH.get_base_dir()))
	var file := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"database": database.get_report(), "build": report, "failed_ranges": failed}, "\t"))
	print("[MM_DATASET_AUDIT] samples=%d ranges=%d cache_hit=%s failed_ranges=%s missing=%s" % [
		database.get_sample_count(), database.clip_names.size(), build.get("cache_hit", false),
		JSON.stringify(failed), JSON.stringify(missing),
	])
	quit(0 if failed.is_empty() and missing.is_empty() else 3)
