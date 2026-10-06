extends SceneTree

## Issue #203 camera experiment. Six seconds under the real Player + TPS camera:
## approach the production table, acquire nearby ItemPickup focus, sweep between
## items, then look away so the scene-only framing returns to normal.

const SCENE: PackedScene = preload("res://tests/diegetic_inventory/diegetic_inventory_stage.tscn")
const OUT_DIR: String = "res://docs/runtime_previews/diegetic_inventory_stage"
const FRAME_DIR: String = OUT_DIR + "/frames"
const FPS: int = 30
const DURATION_S: float = 6.0
const FRAME_COUNT: int = int(DURATION_S * FPS)

var _stage: DiegeticInventoryStage
var _peak_focus: float = 0.0
var _seen_ids: Array[String] = []


func _initialize() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FRAME_DIR))
	_stage = SCENE.instantiate() as DiegeticInventoryStage
	root.add_child(_stage)
	_run.call_deferred()


func _run() -> void:
	await _frames(90)
	if _stage.table == null or _stage.items.size() < 3:
		push_error("diegetic inventory focus capture: production table/items were not prepared")
		quit(1)
		return

	_stage.prepare_focus_demo()
	await _frames(15)

	for frame: int in range(FRAME_COUNT):
		var t: float = float(frame) / float(FPS)
		_drive_demo(t)
		await process_frame
		_record_probe()
		var image := root.get_texture().get_image()
		image.save_png("%s/%04d.png" % [FRAME_DIR, frame])
		if frame == 24:
			image.save_png("%s/01_approach.png" % OUT_DIR)
		elif frame == 96:
			image.save_png("%s/02_item_focus.png" % OUT_DIR)
		elif frame == 168:
			image.save_png("%s/03_focus_release.png" % OUT_DIR)

	Input.action_release(&"move_forward")
	_write_report()

	if _peak_focus < 0.55 or _seen_ids.is_empty():
		push_error("diegetic inventory focus capture: item focus never became visible enough (peak=%.3f ids=%s)" % [_peak_focus, _seen_ids])
		quit(1)
		return

	print("[diegetic-inventory-focus] complete peak=", _peak_focus, " ids=", _seen_ids)
	quit(0)


func _drive_demo(t: float) -> void:
	## 0.0-1.35 s: normal TPS walk toward the table.
	if t < 1.35:
		Input.action_press(&"move_forward")
		_stage.set_demo_look(0.0, -10.0)
		return
	Input.action_release(&"move_forward")

	## 1.35-2.05 s: lower the player's own look onto the tabletop. No auto-orbit.
	if t < 2.05:
		var a: float = inverse_lerp(1.35, 2.05, t)
		_stage.set_demo_look(lerpf(0.0, -2.0, a), lerpf(-10.0, -22.0, a))
		return

	## 2.05-4.55 s: deliberately sweep the centre ray across several real items.
	if t < 3.05:
		var a: float = inverse_lerp(2.05, 3.05, t)
		_stage.set_demo_look(lerpf(-4.0, 3.0, a), -22.0)
		return
	if t < 4.05:
		var a: float = inverse_lerp(3.05, 4.05, t)
		_stage.set_demo_look(lerpf(3.0, -3.0, a), -22.0)
		return
	if t < 4.55:
		_stage.set_demo_look(-1.0, -22.0)
		return

	## 4.55-6.0 s: player looks away; shoulder/boom should release smoothly.
	var out_a: float = inverse_lerp(4.55, DURATION_S, t)
	_stage.set_demo_look(lerpf(-1.0, 24.0, out_a), lerpf(-22.0, -10.0, out_a))


func _record_probe() -> void:
	_peak_focus = maxf(_peak_focus, _stage.focus_weight)
	var id: StringName = _stage.get_focus_target_id()
	if id != &"" and not _seen_ids.has(String(id)):
		_seen_ids.append(String(id))


func _write_report() -> void:
	var report := {
		"issue": 203,
		"duration_s": DURATION_S,
		"fps": FPS,
		"production_camera_script_changed": false,
		"scene_only_focus_framing": true,
		"focus_peak": _peak_focus,
		"focused_item_ids": _seen_ids,
		"focus_far_distance_m": DiegeticInventoryStage.FOCUS_FAR_DISTANCE,
		"focus_distance_m": DiegeticInventoryStage.FOCUS_DISTANCE_M,
		"aim_mode": false,
		"automatic_orbit": false,
	}
	var file := FileAccess.open("%s/report.json" % OUT_DIR, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()


func _frames(count: int) -> void:
	for i: int in range(count):
		await process_frame
