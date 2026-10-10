extends SceneTree
## Batch entry (needs a rendering driver for MultiMesh data; under CI use xvfb + lavapipe):
## xvfb-run godot --path . --rendering-driver vulkan --script tools/world/reality_gen/generate_key_west_chunks_cli.gd -- [cx:cz ...]


func _initialize() -> void:
	var ids: PackedStringArray = PackedStringArray(OS.get_cmdline_user_args())
	var generator: KeyWestChunkGenerator = KeyWestChunkGenerator.new()
	var report: Dictionary = generator.generate(ids)
	var failures: int = 0
	for cid: String in report["chunks"]:
		var entry: Dictionary = report["chunks"][cid]
		print("chunk %s %s" % [cid, JSON.stringify(entry)])
		if entry.get("error", 0) != OK:
			failures += 1
	print("contract violations: %d" % report["contract_violations"].size())
	quit(1 if failures > 0 or not report["contract_violations"].is_empty() else 0)
