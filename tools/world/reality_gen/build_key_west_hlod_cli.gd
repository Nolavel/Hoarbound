extends SceneTree
## HLOD v1 CLI. godot --headless --script <this> -- [--clean] [--all | --dirty | --cluster <id> ...]
## [--check] [--record-digest] [--verify-digest] [--verify-partial <id> ...]. Exits 1 on any failure.


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var hlod: KeyWestHLODBuilder = KeyWestHLODBuilder.new()
	var failed: bool = false
	var picked: PackedStringArray = PackedStringArray()
	var partial: PackedStringArray = PackedStringArray()
	var target: PackedStringArray = picked
	for a: String in args:
		if a == "--cluster":
			target = picked
		elif a == "--verify-partial":
			target = partial
		elif not a.begins_with("--"):
			target.append(a)
	if args.has("--clean"):
		var dir: DirAccess = DirAccess.open(KeyWestHLODBuilder.OUT_DIR)
		if dir != null:
			for file_name: String in dir.get_files():
				dir.remove(file_name)
		print("hlod: cleaned %s" % KeyWestHLODBuilder.OUT_DIR)
	if args.has("--all") or args.has("--dirty") or not picked.is_empty():
		var t0: int = Time.get_ticks_msec()
		var report: Dictionary = hlod.build(picked, args.has("--dirty"))
		print("hlod: built %d, kept %d, removed %d in %d ms" % [report["built"].size(), report["kept"].size(), report["removed"].size(), Time.get_ticks_msec() - t0])
		for e: String in report["errors"]:
			push_error("hlod: " + e)
			failed = true
	if args.has("--check"):
		var result: Dictionary = hlod.check()
		for e: String in result["errors"]:
			push_error("hlod check: " + e)
		print("hlod check: %d errors, dirty %s" % [result["errors"].size(), result["dirty"]])
		if not result["errors"].is_empty() or not (result["dirty"] as Array).is_empty():
			failed = true
		else:
			print("hlod check: ok")
	if args.has("--record-digest"):
		failed = hlod.record_digest() != OK or failed
		print("hlod digest: recorded %s" % KeyWestHLODBuilder.manifest_digest().substr(0, 16))
	if args.has("--verify-digest"):
		var bad: PackedStringArray = hlod.verify_digest()
		for e: String in bad:
			push_error("hlod digest: " + e)
		if bad.is_empty():
			print("hlod digest: identical")
		failed = failed or not bad.is_empty()
	if not partial.is_empty():
		var mismatched: PackedStringArray = hlod.verify_partial(partial)
		for e: String in mismatched:
			push_error("hlod partial: " + e)
		if mismatched.is_empty():
			print("hlod partial verify: identical")
		failed = failed or not mismatched.is_empty()
	quit(1 if failed else 0)
