extends SceneTree

## Build with Godot 4.8: --headless --path . --script res://assets/items/bedroll/source/export_godot_scenes.gd
## A packed scene is bundled by game exports even when the editor cannot import a raw GLB.

const BASE := "res://assets/items/bedroll/bedroll_"


func _initialize() -> void:
	for state_name: String in ["open", "packed"]:
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		var source := BASE + state_name + ".glb"
		var result := document.append_from_file(source, state)
		if result != OK:
			push_error("Bedroll GLB read failed: %s (%d)" % [source, result])
			quit(1)
			return
		var scene := document.generate_scene(state)
		if scene == null:
			push_error("Bedroll scene generation failed: %s" % source)
			quit(1)
			return
		var packed := PackedScene.new()
		result = packed.pack(scene)
		if result == OK:
			result = ResourceSaver.save(packed, BASE + state_name + ".scn")
		if result != OK:
			push_error("Bedroll scene save failed: %s (%d)" % [state_name, result])
			quit(1)
			return
		print("BEDROLL_SCENE ", state_name, " meshes=", scene.find_children("*", "MeshInstance3D", true, false).size())
		scene.free()
	quit()
