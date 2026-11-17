extends SceneTree

## SeeThroughWarmup (#173): under the startup card it draws one see-through copy per distinct (material, vertex
## format) of the thin meshes near the camera, so the first occluder fade compiles nothing; it skips wide, far
## and Henry's meshes, leaves the originals untouched, frees its copies and then lets the card go.
## Run: godot --headless --script tests/systems/test_see_through_warmup.gd

const PLAYER: String = "res://scenes/actors/player/player.tscn"
const CAMERA: String = "res://scenes/game/systems/camera/tps_camera.tscn"

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var player := (load(PLAYER) as PackedScene).instantiate() as Player
	root.add_child(player)
	var camera := (load(CAMERA) as PackedScene).instantiate() as TpsCamera
	camera.player = player
	root.add_child(camera)
	camera.make_current()
	var paint_a := StandardMaterial3D.new()
	var paint_b := StandardMaterial3D.new()
	paint_b.albedo_color = Color.RED
	var thin: Array[MeshInstance3D] = [
		_mesh(Vector3(1.0, 0.0, -3.0), Vector3(0.1, 1.0, 0.1), paint_a),
		_mesh(Vector3(-1.0, 0.0, -3.0), Vector3(0.1, 1.0, 0.1), paint_a),  # same material and format: no second copy
		_mesh(Vector3(0.0, 0.0, -4.0), Vector3(0.2, 0.8, 0.2), paint_b),
	]
	var wide: MeshInstance3D = _mesh(Vector3(0.0, 0.0, -6.0), Vector3(4.0, 3.0, 0.2), StandardMaterial3D.new())
	var far: MeshInstance3D = _mesh(Vector3(0.0, 0.0, -90.0), Vector3(0.1, 1.0, 0.1), StandardMaterial3D.new())
	var warmup := SeeThroughWarmup.new()
	warmup.name = "SeeThroughWarmup"
	warmup.camera = camera
	root.add_child(warmup)
	_check(warmup.is_pending() and BootLoadCapability.pending_names(self).has("SeeThroughWarmup"),
		"the warm-up does not hold the startup card while it works")
	var copies: Array = []  # [transparency, mesh] of each copy while it is drawn
	for _i: int in 60:
		await process_frame
		if copies.is_empty():
			for node: Node in warmup.get_children():
				copies.append([(node as MeshInstance3D).transparency, (node as MeshInstance3D).mesh])
		if not warmup.is_pending():
			break
	_check(not warmup.is_pending(), "the warm-up never finished")
	_check(warmup.get_warmed_count() == 2, "it drew %d copies, not one per distinct (material, format) = 2" % warmup.get_warmed_count())
	var meshes: Array = []
	_check(copies.size() == 2, "%d copies were drawn at once, not 2" % copies.size())
	for copy: Array in copies:
		_check(is_equal_approx(float(copy[0]), camera.occluder_transparency), "a copy was not see-through as the fader makes it")
		meshes.append(copy[1])
	for skipped: MeshInstance3D in [wide, far]:
		_check(not meshes.has(skipped.mesh), "%s was warmed though the fader never fades it" % skipped.name)
	for original: MeshInstance3D in thin + [wide, far]:
		_check(original.transparency == 0.0, "%s itself was made see-through" % original.name)
	await process_frame
	_check(warmup.get_child_count() == 0, "the copies were not freed")
	print("see-through warm-up: %d copies drawn and freed" % warmup.get_warmed_count())
	if _failures > 0:
		push_error("see-through warm-up: %d check(s) failed" % _failures)
		quit(1)
		return
	print("see-through warm-up: all checks passed")
	quit(0)


func _mesh(at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.material_override = material
	root.add_child(mesh)
	mesh.global_position = at
	return mesh


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("see-through warm-up: " + message)
