extends SceneTree

## Regression for transient Hub visuals and empty optional item IDs.
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var held := HeldItemComponent.new()
	_check(not held.supports_item(&"") and not held.can_use(&""), "empty hand accepted an item")
	held.free()
	_check(ItemReadout.describe(&"").is_empty(), "empty item readout not empty")
	var warmer := StoveWarmer.new()
	_check(not warmer.put(null, &""), "empty stove placement accepted")
	warmer.free()

	var camera := Camera3D.new()
	root.add_child(camera)
	var visual := Node3D.new()
	camera.add_child(visual)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	visual.add_child(mesh)
	var colour := Color(1.0, 0.5, 0.0)
	PackHandling._rim(visual, colour)
	var rim: Material = mesh.material_overlay
	_check(rim != null, "missing rim")
	PackHandling._rim(visual, colour)
	_check(mesh.material_overlay == rim, "unchanged hover replaced material")
	var blur := PackFocusBlur.new()
	camera.add_child(blur)
	blur.setup(visual)
	var mask: Material = mesh.material_overlay
	_check(mask != null and mask != rim and mask.next_pass == rim, "focus mask lost rim")
	PackHandling._rim(visual, Color.RED)
	_check(mesh.material_overlay == mask and mask.next_pass == rim, "colour change rebuilt the mask or rim")
	if rim is ShaderMaterial:
		_check((rim as ShaderMaterial).get_shader_parameter(&"rim_colour") == Color.RED, "rim colour not updated")
	var doomed := MeshInstance3D.new()
	doomed.mesh = BoxMesh.new()
	visual.add_child(doomed)
	await process_frame
	await process_frame
	var doomed_id: int = doomed.get_instance_id()
	_check(blur._masked.has(doomed_id), "new geometry was not tracked")
	doomed.queue_free()
	await process_frame
	await process_frame
	blur._mask_all()
	_check(not blur._masked.has(doomed_id), "freed geometry still tracked")
	# A deferred node-added callback can also outlive its target.
	var fleeting := MeshInstance3D.new()
	fleeting.mesh = BoxMesh.new()
	visual.add_child(fleeting)
	fleeting.free()
	await process_frame
	blur.free()
	_check(mesh.material_overlay == rim, "closing focus did not restore rim")
	camera.free()
	print("test_runtime_visual_lifecycle: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("FAIL: " + message)
