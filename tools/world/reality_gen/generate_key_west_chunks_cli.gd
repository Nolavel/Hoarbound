extends SceneTree
## Batch entry (needs a rendering driver for MultiMesh data; under CI use xvfb + lavapipe):
## xvfb-run godot --path . --rendering-driver vulkan --script tools/world/reality_gen/generate_key_west_chunks_cli.gd -- [cx:cz ...]


func _initialize() -> void:
	var ids: PackedStringArray = PackedStringArray()
	var flags: PackedStringArray = PackedStringArray()
	for arg: String in OS.get_cmdline_user_args():
		(flags if arg.begins_with("--") else ids).append(arg)
	var generator: KeyWestChunkGenerator = KeyWestChunkGenerator.new()
	var report: Dictionary = generator.generate(ids)
	var failures: int = 0
	for cid: String in report["chunks"]:
		var entry: Dictionary = report["chunks"][cid]
		print("chunk %s %s" % [cid, JSON.stringify(entry)])
		if entry.get("error", 0) != OK:
			failures += 1
	print("contract violations: %d" % report["contract_violations"].size())
	if flags.has("--record-digest"):
		var err: Error = generator.record_digest()
		print("digest recorded: %s" % ("ok" if err == OK else error_string(err)))
		failures += 0 if err == OK else 1
	if flags.has("--verify-digest"):
		var bad: PackedStringArray = generator.verify_digest()
		print("digest verify: %s" % ("identical" if bad.is_empty() else "%d mismatches, e.g. %s" % [bad.size(), bad.slice(0, 5)]))
		failures += bad.size()
	quit(1 if failures > 0 or not report["contract_violations"].is_empty() else 0)
