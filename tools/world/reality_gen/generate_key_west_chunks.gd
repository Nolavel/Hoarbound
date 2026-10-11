@tool
extends EditorScript
## Editor entry (Script editor > File > Run): regenerates every exported Key West chunk,
## corridor first. Run `key_west_reality.py export-editor` beforehand.


func _run() -> void:
	var generator: KeyWestChunkGenerator = KeyWestChunkGenerator.new()
	var report: Dictionary = generator.generate(PackedStringArray())
	print("Key West chunks: %d, contract violations: %d" % [report["chunks"].size(), report["contract_violations"].size()])
	EditorInterface.get_resource_filesystem().scan()
