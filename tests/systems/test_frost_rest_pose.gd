extends SceneTree

## Rime rides the cloth (#42 record 02, item 10): skinning runs before vertex(), so rime sampled at a skinned
## VERTEX slid over the clothes as Henry moved. Every skinned mesh he wears now carries its rest pose in CUSTOM0
## and samples its rime there (the face's brow rime too); materials, surface count and blend shapes are kept.
## Run: godot --headless --script tests/systems/test_frost_rest_pose.gd

const PLAYER: String = "res://scenes/actors/player/player.tscn"

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var player := (load(PLAYER) as PackedScene).instantiate() as Player
	var before: Dictionary = {}
	root.add_child(player)
	for node: Node in player.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.skin != null and mesh.mesh != null:
			before[mesh] = mesh.mesh
	var frost := player.get_node(^"ClothingFrostComponent") as ClothingFrostComponent
	frost.set_frost(0.85)
	for _i: int in 5:
		await process_frame
	var tied: int = 0
	for mesh: MeshInstance3D in before:
		var original: Mesh = before[mesh]
		if mesh.mesh == original:
			continue  # skipped as bare skin or helper (Mannequin, Skin_*)
		tied += 1
		_check(float(mesh.get_instance_shader_parameter(&"garment_frost_rest")) == 1.0, "%s does not sample rime in its rest pose" % mesh.name)
		_check(mesh.mesh.get_surface_count() == original.get_surface_count(), "%s lost surfaces" % mesh.name)
		_check(mesh.mesh.get_blend_shape_count() == original.get_blend_shape_count(), "%s lost blend shapes" % mesh.name)
		for surface: int in original.get_surface_count():
			_check(mesh.mesh.surface_get_material(surface) == original.surface_get_material(surface), "%s surface %d lost its material" % [mesh.name, surface])
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var rest: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0] if arrays[Mesh.ARRAY_CUSTOM0] != null else PackedFloat32Array()
			_check(rest.size() == points.size() * 3, "%s surface %d has no rest positions in CUSTOM0" % [mesh.name, surface])
			if rest.size() == points.size() * 3 and not points.is_empty():
				var k: int = points.size() / 2
				_check(Vector3(rest[k * 3], rest[k * 3 + 1], rest[k * 3 + 2]).is_equal_approx(points[k]), "%s CUSTOM0 is not the rest pose" % mesh.name)
	_check(tied >= 3, "only %d skinned meshes were tied to the cloth" % tied)
	var head := player.find_child("Henry_Head", true, false) as MeshInstance3D
	_check(head != null and float(head.get_instance_shader_parameter(&"garment_frost_rest")) == 1.0,
		"the brow rime on the face still samples the pose")
	print("frost rest pose: %d skinned meshes tied to the cloth" % tied)
	if _failures > 0:
		push_error("frost rest pose: %d check(s) failed" % _failures)
		quit(1)
		return
	print("frost rest pose: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("frost rest pose: " + message)
