extends SceneTree
## Main-thread cost of attaching every Reality chunk scene and part: the first instantiate() of a freshly loaded
## scene (in debug builds it rebuilds each collision shape once), a repeat instantiate, and add_child. Writes attach_parts.json.
## godot --headless --path . --script tools/runtime/measure_attach_parts.gd -- <out_dir> [chunk_id ...]

const WORLD_DATA: String = "res://scenes/world/key_west/generated/world_data.tres"
const TOP: int = 25
const BUDGET_MS: float = 4.0

var _out: String = "res://docs/runtime_previews/key_west_attach_parts"
var _started: bool = false


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	_run()
	return false


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	var only: PackedStringArray = args.slice(1)
	var stage: Node3D = Node3D.new()
	root.add_child(stage)
	var world: WorldData = load(WORLD_DATA) as WorldData
	var rows: Array = []
	for chunk: ChunkData in world.get_streamable_chunks():
		if not String(chunk.id).begins_with("kw_gen_") or (not only.is_empty() and not only.has(String(chunk.id))):
			continue
		var paths: PackedStringArray = PackedStringArray([chunk.content_scene_path])
		paths.append_array(chunk.part_scene_paths)
		var chunk_root: Node3D = null
		for path: String in paths:
			var cold: PackedScene = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
			var t0: int = Time.get_ticks_usec()
			var cold_node: Node = cold.instantiate()
			var cold_ms: float = (Time.get_ticks_usec() - t0) / 1000.0
			cold_node.free()
			var t1: int = Time.get_ticks_usec()
			var node: Node = cold.instantiate()
			var t2: int = Time.get_ticks_usec()
			if chunk_root == null:
				chunk_root = node as Node3D
				stage.add_child(chunk_root)
			else:
				StreamingSystem.attach_part(chunk_root, node)
			var t3: int = Time.get_ticks_usec()
			var kind: String = "root" if path == chunk.content_scene_path else path.get_file().get_basename().get_slice("__", 1).substr(3)
			rows.append({"chunk": String(chunk.id), "part": kind, "first_ms": snappedf(cold_ms, 0.001),
				"repeat_ms": snappedf((t2 - t1) / 1000.0, 0.001), "add_child_ms": snappedf((t3 - t2) / 1000.0, 0.001)})
		chunk_root.queue_free()
		await process_frame
	var report: Dictionary = {"scenes": rows.size(), "budget_ms": BUDGET_MS,
		"first": _summary(rows, func(r: Dictionary) -> float: return r["first_ms"] + r["add_child_ms"]),
		"repeat": _summary(rows, func(r: Dictionary) -> float: return r["repeat_ms"] + r["add_child_ms"])}
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["first_ms"] > b["first_ms"])
	report["worst_first"] = rows.slice(0, TOP)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["repeat_ms"] + a["add_child_ms"] > b["repeat_ms"] + b["add_child_ms"])
	report["worst_repeat"] = rows.slice(0, TOP)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	var f: FileAccess = FileAccess.open(_out.path_join("attach_parts.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, " ", true))
	print("attach parts: %d scenes; first instantiate %s" % [rows.size(), report["first"]])
	print("attach parts: repeat instantiate %s" % [report["repeat"]])
	for r: Dictionary in rows.slice(0, 8):
		print("attach parts: %-14s %-14s first %6.2f ms  repeat %6.2f + add_child %5.2f ms" % [r["chunk"], r["part"], r["first_ms"], r["repeat_ms"], r["add_child_ms"]])
	quit(0)


func _summary(rows: Array, cost: Callable) -> Dictionary:
	var ms: Array = rows.map(cost)
	ms.sort()
	return {"p50_ms": snappedf(ms[ms.size() / 2], 0.01), "p99_ms": snappedf(ms[int(ms.size() * 0.99)], 0.01),
		"max_ms": snappedf(ms.back(), 0.01), "over_budget": ms.filter(func(v: float) -> bool: return v > BUDGET_MS).size(),
		"over_10ms": ms.filter(func(v: float) -> bool: return v > 10.0).size()}
