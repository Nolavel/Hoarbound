extends SceneTree

## Retarget diagnostics: per clip audit, front/side keyframes and a short video
## (args: dataset:clip ...; MM_DIAG_VIDEO=0 skips the video).

const SCENE_PATH := "res://tests/motion_matching/motion_retarget_diagnostic.tscn"
const SOURCE_ROOT := "res://tests/motion_matching/_runtime_cmu/"
const OUT_DIR := "res://docs/runtime_previews/motion_retarget_diagnostics"
const CAPTURE_SIZE := Vector2i(1280, 720)
const VIDEO_FPS := 30.0
const VIDEO_SECONDS := 5.0
const DEFAULT_CLIPS := ["CMU:09_12", "CMU:113_17", "CMU:41_02", "CMU:111_28", "CMU:69_18", "CMU:40_04"]
const FRONT_CAMERA := [Vector3(0.0, 1.75, 4.6), Vector3(0.0, 0.85, 0.0)]
const SIDE_CAMERA := [Vector3(5.2, 1.45, 0.9), Vector3(0.0, 0.85, 0.0)]

var _scene: MotionRetargetDiagnostic
var _model := UALSkeletonModel.new()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	FileAccess.open(OUT_DIR + "/.gdignore", FileAccess.WRITE)
	root.size = CAPTURE_SIZE
	_scene = (load(SCENE_PATH) as PackedScene).instantiate() as MotionRetargetDiagnostic
	root.add_child(_scene)
	for _frame in range(8):
		await process_frame
	if not _scene.is_ready_for_capture() or not _model.load_from_skeleton(_scene.target_skeleton):
		push_error("RetargetDiagnostics: Henry skeleton unavailable.")
		quit(2)
		return

	var requested: Array = Array(OS.get_cmdline_user_args())
	if requested.is_empty():
		requested = DEFAULT_CLIPS
	var report := {"clips": [], "henry_leg_length_m": _model.leg_length()}
	var all_passed := true
	for entry in requested:
		var parts := String(entry).split(":")
		var clip_report := await _capture_clip(parts[0], parts[1])
		report["clips"].append(clip_report)
		_print_clip(clip_report)
		all_passed = all_passed and bool(clip_report.get("audit", {}).get("passed", false))
	report["all_passed"] = all_passed
	var file := FileAccess.open(OUT_DIR + "/report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("[RETARGET_DIAGNOSTICS] clips=%d all_passed=%s -> %s" % [requested.size(), all_passed, ProjectSettings.globalize_path(OUT_DIR)])
	# Reports only: raw clips keep glitches; audit_motion_dataset.gd gates baked data.
	quit(0)


func _capture_clip(dataset: String, clip_name: String) -> Dictionary:
	var profile := SourceRetargetProfile.for_dataset(dataset)
	var clip := BVHClip.new()
	if profile == null or not clip.load_file(SOURCE_ROOT + clip_name + ".bvh", profile.units_to_meters):
		return {"dataset": dataset, "clip": clip_name, "error": "cannot load"}
	var retargeter := MotionRetargeter.new()
	if not retargeter.setup(clip, profile, _model):
		return {"dataset": dataset, "clip": clip_name, "error": retargeter.error_message}
	var baker := MotionDatabaseBaker.new()
	var database := baker.bake_range(retargeter, StringName(clip_name), 0.0, retargeter.get_duration())
	var duration := retargeter.get_duration()
	var extreme := _most_extreme_time(database)
	var keyframes := {
		"start": 0.15, "quarter": duration * 0.25, "middle": duration * 0.5,
		"extreme": extreme, "end": maxf(0.0, duration - 0.2),
	}
	var prefix := "%s_%s" % [dataset, clip_name]
	for key in keyframes.keys():
		var time: float = keyframes[key]
		var label := "%s %s  %s @ %.2fs" % [dataset, clip_name, key, time]
		_scene.show_pose(retargeter, time, label)
		for view in [["front", FRONT_CAMERA], ["side", SIDE_CAMERA]]:
			var camera_pose: Array = view[1]
			_scene.camera.look_at_from_position(camera_pose[0], camera_pose[1])
			_scene.show_pose(retargeter, time, label)
			await _save_frame("%s/%s_%s_%s.png" % [OUT_DIR, prefix, key, view[0]])
	_scene.camera.look_at_from_position(FRONT_CAMERA[0], FRONT_CAMERA[1])
	var frame_dir := "%s/video_%s" % [OUT_DIR, prefix]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(frame_dir))
	var video_frames := 0 if OS.get_environment("MM_DIAG_VIDEO") == "0" else int(minf(VIDEO_SECONDS, duration) * VIDEO_FPS)
	var video_start := clampf(extreme - VIDEO_SECONDS * 0.5, 0.0, maxf(0.0, duration - VIDEO_SECONDS))
	for frame in range(video_frames):
		var time := video_start + float(frame) / VIDEO_FPS
		_scene.show_pose(retargeter, time, "%s %s  t=%.2fs" % [dataset, clip_name, time])
		await _save_frame("%s/%04d.png" % [frame_dir, frame])
	return {
		"dataset": dataset,
		"clip": clip_name,
		"retarget": retargeter.report,
		"audit": baker.last_quality,
		"keyframes": keyframes,
		"video_start": video_start,
		"video_frames": video_frames,
	}


## One log line per clip so CI logs carry the verdict without the artifact.
func _print_clip(clip_report: Dictionary) -> void:
	if clip_report.has("error"):
		print("[RETARGET_CLIP] %s %s ERROR %s" % [clip_report.get("dataset", "?"), clip_report.get("clip", "?"), clip_report["error"]])
		return
	var retarget: Dictionary = clip_report["retarget"]
	var audit: Dictionary = clip_report["audit"]
	print("[RETARGET_CLIP] %s %s passed=%s failures=%s ground=%s forward_agreement=%.3f scale=%.3f segment_deg=%s feet=%s" % [
		clip_report["dataset"], clip_report["clip"], audit["passed"],
		JSON.stringify(audit["failures"]), JSON.stringify(audit["ground_error_m"]),
		float(retarget.get("reference_forward_agreement", 0.0)),
		float(retarget.get("motion_scale_henry_over_source_leg", 0.0)),
		JSON.stringify(retarget.get("segment_alignment_degrees", {})),
		JSON.stringify(retarget.get("foot_calibration", {})),
	])


func _most_extreme_time(database: MotionDatabase) -> float:
	var best_time := 0.0
	var best_score := -1.0
	for sample in range(database.get_sample_count()):
		var row := database.get_feature_row(sample)
		var lateral := absf(row[0])
		var turn := absf(row[2]) * 0.4
		var knee := maxf(0.0, 0.9 - row[4]) * 3.0
		var score := lateral + turn + knee
		if score > best_score:
			best_score = score
			best_time = database.get_sample_time(sample)
	return best_time


func _save_frame(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("RetargetDiagnostics: empty frame for %s" % path)
		return
	image.save_png(ProjectSettings.globalize_path(path))
