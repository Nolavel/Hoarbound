extends Node
## Replays an InputTape in its scene with the real autoloads, then writes report.json (path, end point,
## frame times, shots). --expect=<report.json> turns it into a check: the route must end where it did.
## Run: godot --path . --fixed-fps 60 res://tools/runtime/replay_input_tape.tscn -- --tape=<tape.json> --out=<dir>
##      [--settle=90] [--tail=60] [--shots=120,600] [--expect=<report.json>] [--tolerance=0.25] [--rerecord=<tape.json>]

var _watcher: bool = false
var _args: Dictionary = {}


func _ready() -> void:
	if not _watcher:
		## The scene is replaced by the tape's scene; a copy on the root drives the run.
		var watcher: Node = (get_script() as GDScript).new()
		watcher.set(&"_watcher", true)
		watcher.process_priority = -1000
		watcher.process_physics_priority = -1000
		get_tree().root.add_child.call_deferred(watcher)
		return
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			_args[arg.get_slice("=", 0).trim_prefix("--")] = arg.get_slice("=", 1)
	_run.call_deferred()


func _run() -> void:
	var tape: InputTape = InputTape.load_file(String(_args.get("tape", "")))
	if tape == null:
		_finish(false, "no tape")
		return
	var out: String = String(_args.get("out", "user://replay"))
	DirAccess.make_dir_recursive_absolute(out)
	var shots: Array[int] = []
	for part: String in String(_args.get("shots", "")).split(",", false):
		shots.append(int(part))
	get_tree().change_scene_to_file(tape.scene)
	var player: CharacterBody3D = null
	for _i: int in range(1200):
		await get_tree().physics_frame
		player = get_tree().get_first_node_in_group(&"player") as CharacterBody3D
		if player != null and get_tree().current_scene != null:
			break
	if player == null:
		_finish(false, "no player in %s" % tape.scene)
		return
	for _i: int in range(int(_args.get("settle", "90"))):
		await get_tree().physics_frame
	player.global_transform = tape.start_transform
	player.velocity = Vector3.ZERO
	var camera := get_viewport().get_camera_3d() as TpsCamera
	if camera != null:
		camera.set_look(tape.start_look.x, tape.start_look.y)
		camera.snap_to_target()
	var recorder := get_node_or_null(^"/root/TapeRecorder") as InputTapeRecorder
	var rerecord: String = String(_args.get("rerecord", ""))
	if rerecord != "" and recorder != null:
		recorder.start()
	var end_frame: int = tape.length_frames() + int(_args.get("tail", "60"))
	var next_event: int = 0
	var next_look: int = 0
	var path: Array = []
	var frame_ms: PackedFloat32Array = []
	for frame: int in range(end_frame + 1):
		while next_event < tape.events.size() and int(tape.events[next_event][0]) <= frame:
			var e: Array = tape.events[next_event]
			var action := InputEventAction.new()
			action.action = StringName(e[1])
			action.pressed = bool(e[2])
			action.strength = float(e[3])
			Input.parse_input_event(action)
			next_event += 1
		Input.flush_buffered_events()
		while next_look < tape.looks.size() and int(tape.looks[next_look][0]) <= frame:
			if camera != null:
				camera.set_look(float(tape.looks[next_look][1]), float(tape.looks[next_look][2]))
			next_look += 1
		if frame % 30 == 0:
			var p: Vector3 = player.global_position
			path.append([frame, p.x, p.y, p.z, Vector2(player.velocity.x, player.velocity.z).length(), _speed_factors(player)])
		if shots.has(frame):
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out.path_join("shot_%05d.png" % frame))
		await get_tree().physics_frame
		frame_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	var final_position: Vector3 = player.global_position
	if rerecord != "" and recorder != null:
		var saved: String = recorder.stop()
		DirAccess.copy_absolute(saved, rerecord)
	var report: Dictionary = {"tape": _args.get("tape"), "scene": tape.scene, "frames": end_frame,
		"final": [final_position.x, final_position.y, final_position.z], "path": path, "frame_ms": _stats(frame_ms)}
	var file := FileAccess.open(out.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("REPLAY final=%s frames=%d" % [str(final_position), end_frame])
	var expect: String = String(_args.get("expect", ""))
	if expect == "":
		_finish(true, "")
		return
	var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(expect))
	var want: Array = (expected as Dictionary).get("final", [0, 0, 0]) if expected is Dictionary else [0, 0, 0]
	var drift: float = final_position.distance_to(Vector3(want[0], want[1], want[2]))
	var tolerance: float = float(_args.get("tolerance", "0.25"))
	_finish(drift <= tolerance, "route ended %.3f m from the expected end (tolerance %.2f)" % [drift, tolerance])


## Why Henry moved as fast as he did: snow, carried load and status multipliers.
func _speed_factors(player: Node) -> Array:
	var movement := player.get_node_or_null(^"MovementController") as MovementController
	if movement == null:
		return []
	return [movement.snow_speed_multiplier, movement.get_load_speed_multiplier(), movement.get_status_speed_multiplier()]


func _stats(values: PackedFloat32Array) -> Dictionary:
	if values.is_empty():
		return {}
	var sorted: Array = Array(values)
	sorted.sort()
	var total: float = 0.0
	for v: float in sorted:
		total += v
	return {"avg": total / sorted.size(), "p99": sorted[int(sorted.size() * 0.99) - 1 if sorted.size() > 1 else 0], "max": sorted[-1]}


func _finish(ok: bool, detail: String) -> void:
	print("REPLAY: %s %s" % ["PASS" if ok else "FAIL", detail])
	get_tree().quit(0 if ok else 1)
