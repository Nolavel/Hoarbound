extends SceneTree

## The Hub's hover outlines (#173): a sub-pixel drift shifts the cached outline instead of tracing it again,
## the open Hub traces almost nothing per frame, and every item on the pack is still picked where it is aimed.
## Run: godot --headless --script tests/systems/test_hub_outline_cost.gd

const SCENE: String = "res://tests/scenes/TestScene.tscn"

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_drift_reuses_the_trace()
	await _test_open_hub_traces_little()
	if _failures > 0:
		push_error("hub outline cost: %d check(s) failed" % _failures)
		quit(1)
		return
	print("hub outline cost: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("hub outline cost: " + message)


func _test_drift_reuses_the_trace() -> void:
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.make_current()
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.3, 0.2, 0.1)
	box.mesh = mesh
	root.add_child(box)
	box.global_position = Vector3(0.0, 0.0, -1.5)
	await process_frame
	PackHandling.clear_outline_cache()
	PackHandling.screen_outline(box, camera)
	PackHandling.outline_stats(true)
	var shifted := PackedVector2Array()
	for _i: int in range(30):
		box.global_position += Vector3(0.0003, 0.0002, 0.0)  # about half a pixel a frame, as a held pack drifts
		shifted = PackHandling.screen_outline(box, camera)
	var stats: Dictionary = PackHandling.outline_stats(true)
	_check(int(stats["misses"]) <= 2, "30 sub-pixel drifts traced the outline %d times" % int(stats["misses"]))
	PackHandling.clear_outline_cache()
	var fresh: PackedVector2Array = PackHandling.screen_outline(box, camera)
	var bounds: Rect2 = PackHandling.screen_bounds(box, camera)
	var cell: float = maxf(maxf(bounds.size.x, bounds.size.y) / PackHandling.OUTLINE_GRID, 1.0)
	_check(_centre(shifted).distance_to(_centre(fresh)) <= cell, "the shifted outline is %.2f px off a fresh trace (cell %.2f px)"
		% [_centre(shifted).distance_to(_centre(fresh)), cell])
	box.free()
	camera.free()


func _test_open_hub_traces_little() -> void:
	var scene: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	for _i: int in range(240):
		await process_frame
	var player: Node = scene.find_child("Player", true, false)
	var hub := player.get_node(^"PlayerHubComponent") as PlayerHubComponent
	_check(hub.open(), "the Hub did not open")
	for _i: int in range(90):
		await process_frame
	PackHandling.outline_stats(true)
	for _i: int in range(120):
		await process_frame
	var stats: Dictionary = PackHandling.outline_stats(true)
	_check(float(stats["misses"]) / 120.0 < 0.5, "the open Hub traced %.2f outlines a frame (%.1f ms a frame)"
		% [float(stats["misses"]) / 120.0, float(stats["ms"]) / 120.0])
	var shelf := player.find_child("QuickShelf", true, false) as PackQuickShelf
	var camera: Camera3D = root.get_viewport().get_camera_3d()
	var picked: int = 0
	for k: int in shelf.slots.size():
		var visual: Node3D = shelf.visual_of(k) if shelf.slots[k]["on_pack"] else null
		if visual == null or not visual.is_visible_in_tree():
			continue
		var aim: Vector2 = shelf.aim_point(k)
		var hit: int = shelf.pick(camera.project_ray_origin(aim), camera.project_ray_normal(aim))
		_check(hit == k, "slot %d (%s) aimed at was picked as %d" % [k, visual.name, hit])
		picked += 1
	_check(picked > 0, "no item on the pack to pick")
	hub.close()
	scene.queue_free()


static func _centre(points: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for point: Vector2 in points:
		sum += point
	return sum / maxf(points.size(), 1.0)
