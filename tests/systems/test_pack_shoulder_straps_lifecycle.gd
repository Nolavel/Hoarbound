extends SceneTree

## When Henry or his skeleton leaves the world, the skinning redraw must not
## read an out-of-tree global_transform, and the update signal must reconnect
## if the same rig re-enters the tree.
var _failures: int = 0


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var skeleton := Skeleton3D.new()
	root.add_child(skeleton)
	var straps := PackShoulderStraps.new()
	straps.set(&"_skeleton", skeleton)
	skeleton.add_child(straps)

	_check(straps._can_skin(), "attached straps can read skeleton transform")
	_check(skeleton.skeleton_updated.is_connected(straps._redraw), "attached straps listen for skeleton updates")

	skeleton.remove_child(straps)
	_check(not straps._can_skin(), "detached straps cannot skin")
	_check(not skeleton.skeleton_updated.is_connected(straps._redraw), "detached straps release skeleton update signal")
	straps._redraw()  # Must be a no-op, not a Node3D.get_global_transform error.

	skeleton.add_child(straps)
	_check(straps._can_skin(), "reattached straps can skin")
	_check(skeleton.skeleton_updated.is_connected(straps._redraw), "reattached straps resubscribe")
	straps._redraw()
	straps.queue_free()
	skeleton.queue_free()
	print("test_pack_shoulder_straps_lifecycle: %s" % ("all checks passed" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	print("%s %s" % ["ok " if condition else "FAIL", label])
	if not condition:
		_failures += 1
