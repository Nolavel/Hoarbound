extends SceneTree

## Headless audit for the staged CMU pool used by Motion Matching Lab #2.
## Reports measured kinematic roles per source before the expensive UAL bake.

const SOURCE_ROOT := "res://tests/motion_matching/_runtime_cmu/"
const SOURCE_MANIFEST_PATH := SOURCE_ROOT + "source_manifest.tsv"
const DATABASE_CACHE_PATH := "res://tests/motion_matching/_runtime_cache/canonical_motion_database.res"
const STEADY_DIRECTION_ROLES := [
	"walk_f", "walk_fr", "walk_r", "walk_br",
	"walk_b", "walk_bl", "walk_l", "walk_fl",
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not FileAccess.file_exists(SOURCE_MANIFEST_PATH):
		push_error("CMUPoolAudit: source manifest is missing; run tools/ci/prepare_cmu_sample.sh first.")
		quit(2)
		return

	var role_sources: Dictionary = {}
	var segmenter := CMUMotionSegmenter.new()
	var lines := FileAccess.get_file_as_string(SOURCE_MANIFEST_PATH).split("\n", false)
	for line_index in range(1, lines.size()):
		var fields := lines[line_index].split("\t", false)
		if fields.size() < 4:
			continue
		var clip := String(fields[0])
		var subject := String(fields[1])
		var source_path := SOURCE_ROOT + clip + ".bvh"
		var dataset := String(fields[6]) if fields.size() > 6 else "CMU"
		var rest_mode := String(fields[8]) if fields.size() > 8 else "frame_zero_skip"
		var import_options := {
			"dataset": dataset,
			"position_scale": float(fields[7]) if fields.size() > 7 else CMUBVHSource.DEFAULT_POSITION_SCALE,
			"detect_rest_frame": rest_mode == "auto_include",
			"include_first_frame": rest_mode == "auto_include",
			"use_global_pose": String(fields[9]) == "global" if fields.size() > 9 else false,
		}
		var analyzed := segmenter.analyze_file(
			source_path,
			dataset + "_" + clip,
			("CMU Subject %s / %s" % [subject.trim_prefix("0"), clip]) if dataset == "CMU" else (dataset + " / " + clip),
			String(fields[3]),
			import_options
		)
		if not bool(analyzed.get("ok", false)):
			push_error("CMUPoolAudit: %s failed: %s" % [clip, analyzed.get("error", "unknown")])
			quit(3)
			return

		var source_roles: Dictionary = {}
		for candidate in analyzed.get("candidates", []):
			var role := String(candidate.get("role", ""))
			var duration := float(candidate.get("end", 0.0)) - float(candidate.get("start", 0.0))
			source_roles[role] = maxi(int(source_roles.get(role, 0)), int(round(duration * 1000.0)))
			if not role_sources.has(role):
				role_sources[role] = []
			(role_sources[role] as Array).append({
				"source": clip,
				"start": float(candidate.get("start", 0.0)),
				"end": float(candidate.get("end", 0.0)),
				"duration": duration,
				"score": float(candidate.get("score", 0.0)),
			})
		var source_import: Dictionary = analyzed.get("report", {}).get("source_import", {})
		print("[CMU_POOL_SOURCE] %s dataset=%s scale=%.4f rest=%d roles=%s" % [
			clip,
			dataset,
			float(source_import.get("position_scale_to_meters", 0.0)),
			int(source_import.get("rest_frame_index", -1)),
			JSON.stringify(source_roles),
		])

	var missing_steady: Array[String] = []
	for role in CMUMotionSegmenter.ROLE_ORDER:
		var candidates: Array = role_sources.get(role, [])
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("score", 0.0)) > float(b.get("score", 0.0))
		)
		var best: Dictionary = candidates[0] if not candidates.is_empty() else {}
		print("[CMU_POOL_ROLE] %-12s candidates=%d best=%s" % [role, candidates.size(), JSON.stringify(best)])
		if role in STEADY_DIRECTION_ROLES and candidates.is_empty():
			missing_steady.append(role)

	print("[CMU_POOL_STEADY] passed=%s missing=%s" % [missing_steady.is_empty(), JSON.stringify(missing_steady)])
	if FileAccess.file_exists(DATABASE_CACHE_PATH):
		var database := ResourceLoader.load(DATABASE_CACHE_PATH) as MotionDatabase
		if database != null:
			print("[CMU_POOL_DATABASE] %s" % JSON.stringify(database.get_report()))

	if not missing_steady.is_empty():
		quit(4)
		return

	quit(0)
