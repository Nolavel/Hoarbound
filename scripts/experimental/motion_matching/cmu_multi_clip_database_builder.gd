class_name CMUMultiClipDatabaseBuilder
extends RefCounted

## Issue #202 multi-capture bake coordinator.
## It reuses the existing CMU->UAL lab one source at a time, merges the dense
## post-retarget databases, then creates one final presentation lab whose Henry
## is driven only from canonical database poses.

const SOURCE_ROOT := "res://tests/motion_matching/_runtime_cmu/"

# First real multi-clip proof set. The wider staged pool remains available for
# the segmentation pass, but this set stays bounded enough for one CI run.
const PROOF_SOURCES: Array[Dictionary] = [
	{
		"file": "111_28.bvh", "clip": "CMU_111_28", "role": "idle_neutral",
		"trial": "CMU Subject 111 / 111_28", "description": "standing still",
		"start": 0.20, "end": 2.70,
	},
	{
		"file": "69_01.bvh", "clip": "CMU_69_01", "role": "walk_f",
		"trial": "CMU Subject 69 / 69_01", "description": "walk forward",
		"start": 0.20, "end": -1.0,
	},
	{
		"file": "69_50.bvh", "clip": "CMU_69_50", "role": "lateral_back_pool",
		"trial": "CMU Subject 69 / 69_50", "description": "walk sideways and backwards",
		"start": 0.20, "end": -1.0,
	},
	{
		"file": "69_56.bvh", "clip": "CMU_69_56", "role": "lateral_opposite_pool",
		"trial": "CMU Subject 69 / 69_56", "description": "walk sideways and turn opposite direction",
		"start": 0.20, "end": -1.0,
	},
	{
		"file": "16_33.bvh", "clip": "CMU_16_33", "role": "stop_f",
		"trial": "CMU Subject 16 / 16_33", "description": "slow walk, stop",
		"start": 0.20, "end": -1.0,
	},
	{
		"file": "69_16.bvh", "clip": "CMU_69_16", "role": "pivot_pool_a",
		"trial": "CMU Subject 69 / 69_16", "description": "turn in place",
		"start": 0.20, "end": -1.0,
	},
	{
		"file": "69_18.bvh", "clip": "CMU_69_18", "role": "pivot_pool_b",
		"trial": "CMU Subject 69 / 69_18", "description": "opposite turn in place",
		"start": 0.20, "end": -1.0,
	},
	{
		"file": "69_20.bvh", "clip": "CMU_69_20", "role": "turn_90_pool_a",
		"trial": "CMU Subject 69 / 69_20", "description": "walk forward, 90-degree turn",
		"start": 0.20, "end": -1.0,
	},
	{
		"file": "69_24.bvh", "clip": "CMU_69_24", "role": "turn_90_pool_b",
		"trial": "CMU Subject 69 / 69_24", "description": "walk forward, opposite 90-degree turn",
		"start": 0.20, "end": -1.0,
	},
	{
		"file": "41_02.bvh", "clip": "CMU_41_02", "role": "multidirectional_reference",
		"trial": "CMU Subject 41 / 41_02", "description": "forward/backward/sideways/diagonal navigation",
		"start": 0.20, "end": -1.0,
	},
]


func build(
		lab_scene: PackedScene,
		parent: Node,
		sample_rate_hz: float = 30.0
	) -> Dictionary:
	if lab_scene == null or parent == null:
		return {"ok": false, "error": "invalid scene/parent"}

	var tree := parent.get_tree()
	if tree == null:
		return {"ok": false, "error": "SceneTree unavailable"}

	var master := MotionDatabase.new()
	var source_reports: Array[Dictionary] = []

	for source_def in PROOF_SOURCES:
		var lab := lab_scene.instantiate() as CMUUALRetargetLab
		if lab == null:
			return {"ok": false, "error": "CMU lab scene has wrong root type"}
		var source_path := SOURCE_ROOT + String(source_def["file"])
		if not lab.configure_source(
			source_path,
			StringName(source_def["clip"]),
			String(source_def["trial"]),
			String(source_def["description"]),
			String(source_def["role"])
		):
			lab.free()
			return {"ok": false, "error": "failed to configure %s" % String(source_def["clip"])}

		parent.add_child(lab)
		if not await _wait_until_ready(lab, tree):
			var failed_report := lab.get_retarget_report()
			lab.queue_free()
			await tree.process_frame
			return {
				"ok": false,
				"error": "retarget setup failed for %s" % String(source_def["clip"]),
				"source_report": failed_report,
			}

		var clip_database: MotionDatabase = await lab.bake_motion_database(
			sample_rate_hz,
			float(source_def["start"]),
			float(source_def["end"]),
			String(source_def["role"]),
			source_path
		)
		if clip_database == null or not clip_database.is_consistent():
			lab.queue_free()
			await tree.process_frame
			return {"ok": false, "error": "database bake failed for %s" % String(source_def["clip"])}
		if not master.append_database(clip_database):
			lab.queue_free()
			await tree.process_frame
			return {"ok": false, "error": "database merge failed for %s" % String(source_def["clip"])}

		var report := lab.get_retarget_report()
		report["baked_samples"] = clip_database.get_sample_count()
		report["baked_start"] = float(source_def["start"])
		report["baked_end"] = float(source_def["end"])
		source_reports.append(report)
		print("[MM_MULTI_BAKE] %s role=%s samples=%d" % [
			String(source_def["clip"]),
			String(source_def["role"]),
			clip_database.get_sample_count(),
		])

		lab.queue_free()
		await tree.process_frame

	master.rebuild_statistics()
	if not master.is_consistent() or master.clip_names.size() < 2:
		return {"ok": false, "error": "merged database is inconsistent or still single-clip"}

	# Presentation scene uses a real staged source only to create the same Henry,
	# camera and lighting. Its retarget modifier is disabled by database playback.
	var presentation_def: Dictionary = PROOF_SOURCES[0]
	var presentation_lab := lab_scene.instantiate() as CMUUALRetargetLab
	if presentation_lab == null:
		return {"ok": false, "error": "failed to instantiate presentation lab"}
	presentation_lab.configure_source(
		SOURCE_ROOT + String(presentation_def["file"]),
		StringName(presentation_def["clip"]),
		String(presentation_def["trial"]),
		String(presentation_def["description"]),
		String(presentation_def["role"])
	)
	parent.add_child(presentation_lab)
	if not await _wait_until_ready(presentation_lab, tree):
		var presentation_report := presentation_lab.get_retarget_report()
		presentation_lab.queue_free()
		await tree.process_frame
		return {"ok": false, "error": "presentation lab failed", "source_report": presentation_report}

	return {
		"ok": true,
		"database": master,
		"lab": presentation_lab,
		"source_reports": source_reports,
		"proof_source_count": PROOF_SOURCES.size(),
	}


func _wait_until_ready(lab: CMUUALRetargetLab, tree: SceneTree) -> bool:
	for _frame in range(360):
		await tree.process_frame
		if lab.is_ready_for_capture():
			return true
		var report := lab.get_retarget_report()
		if report.has("error"):
			return false
	return false
