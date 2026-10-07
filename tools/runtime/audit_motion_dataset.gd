extends SceneTree

## Headless dataset gate: rebuilds the database, fails on a broken retarget audit,
## a missing label or a committed database that no longer matches the rebuild.

const OUT_PATH := "res://docs/runtime_previews/motion_matching_lab/dataset_audit.json"
## Baked values may differ by float noise between machines, never more.
const COMMITTED_TOLERANCE := 0.0001


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var allow_unverified := OS.get_environment("MM_ALLOW_UNVERIFIED") == "1"
	var build := MotionMatchingDatabaseBuilder.new().build(30.0, allow_unverified, false)
	if not bool(build.get("ok", false)):
		push_error("MotionDatasetAudit: %s" % String(build.get("error", "build failed")))
		quit(2)
		return
	var report: Dictionary = build["report"]
	var database: MotionDatabase = build["database"]
	var failed: Array[String] = []
	for range_report in report.get("ranges", []):
		if range_report.has("split_for_audit"):
			continue # Re-baked without the failing frames.
		if not bool(range_report["audit"].get("passed", false)):
			failed.append(String(range_report["clip"]))
	var missing: Array = report.get("selection", {}).get("missing_labels", [])
	# MM_WRITE_DATABASE=1 replaces the committed database with a passing rebuild.
	var committed_state := "not compared (unverified profiles allowed)"
	var stale := false
	if not allow_unverified:
		if OS.get_environment("MM_WRITE_DATABASE") == "1" and failed.is_empty() and missing.is_empty():
			var error := MotionMatchingDatabaseBuilder.save_committed(database)
			committed_state = "written" if error == OK else "write failed (%d)" % error
			stale = error != OK
		else:
			var committed := MotionMatchingDatabaseBuilder.load_committed()
			var drift := INF if committed == null else MotionMatchingDatabaseBuilder.difference(committed, database)
			stale = drift > COMMITTED_TOLERANCE
			committed_state = ("missing" if committed == null else "stale (max diff %s)" % str(drift)) if stale else "matches rebuild (max diff %.6f)" % drift
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_PATH.get_base_dir()))
	var file := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"database": database.get_report(), "build": report, "failed_ranges": failed, "committed_database": committed_state}, "\t"))
	print("[MM_DATASET_AUDIT] samples=%d ranges=%d cache_hit=%s failed_ranges=%s missing=%s signature=%s committed=%s" % [
		database.get_sample_count(), database.clip_names.size(), build.get("cache_hit", false),
		JSON.stringify(failed), JSON.stringify(missing), database.build_signature, committed_state,
	])
	if not failed.is_empty() or not missing.is_empty():
		quit(3)
	elif stale:
		push_error("MotionDatasetAudit: committed database %s; rerun with MM_WRITE_DATABASE=1 and commit it." % committed_state)
		quit(4)
	else:
		quit(0)
