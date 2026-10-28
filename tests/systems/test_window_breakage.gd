extends SceneTree

## Breaking glass (#257 stage 3): a facade pane is found from the hit point, snow cracks it and a
## second snowball breaks it, a stone breaks one at once, bare wall is left alone, a 727 pane
## opens its breach when broken, and damage survives a save.
## Run: godot --headless --script tests/systems/test_window_breakage.gd

var _failures: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var breakage := WindowBreakage.new()
	root.add_child(breakage)
	var buildings := Node3D.new()
	buildings.name = "Buildings"
	root.add_child(buildings)
	var body := StaticBody3D.new()
	buildings.add_child(body)
	## Two panes on a wall facing +Z: 1.0 x 1.4 m at x = -2 and x = 2, sill at 0.9 m.
	var facade := MeshInstance3D.new()
	facade.mesh = _facade([Vector2(-2.0, 0.0), Vector2(2.0, 0.0)])
	buildings.add_child(facade)

	var left := Vector3(-2.0, 1.6, 0.04)
	_check(breakage.take_hit(&"snow_handful", left, Vector3.BACK, 2.6, body), "the snowball missed the left pane")
	var key: StringName = breakage.find_pane(left, body)["key"]
	_check(breakage.get_pane_state(key) == WindowBreakage.PaneState.CRACKED, "one snowball did not crack the pane")
	breakage.take_hit(&"snow_handful", left + Vector3(0.2, 0.1, 0.0), Vector3.BACK, 2.6, body)
	_check(breakage.get_pane_state(key) == WindowBreakage.PaneState.BROKEN, "a second snowball did not break the cracked pane")
	var right := Vector3(2.0, 1.3, 0.04)
	breakage.take_hit(&"stone", right, Vector3.BACK, 0.35 * 15.0, body)
	_check(breakage.get_pane_state(breakage.find_pane(right, body)["key"]) == WindowBreakage.PaneState.BROKEN, "a stone did not break a pane at once")
	_check(not breakage.take_hit(&"stone", Vector3(0.0, 1.6, 0.0), Vector3.BACK, 5.0, body), "bare wall between the panes took a hit")

	var breach := ShelterBreach.new()
	breach.glazed = true
	breach.opening_width_m = 2.0
	breach.opening_height_m = 1.1
	breach.position = Vector3(10.0, 2.0, 0.0)
	root.add_child(breach)
	breach.add_to_group(WindowBreakage.BREACH_GROUP)
	var sealed_open: float = breach.get_open_fraction()
	breakage.take_hit(&"stone", Vector3(10.4, 2.2, 0.0), Vector3.BACK, 5.25, null)
	_check(not breach.glazed and breach.get_open_fraction() > sealed_open * 5.0,
		"the broken 727 pane did not open its breach (%.2f -> %.2f)" % [sealed_open, breach.get_open_fraction()])

	var saved: Dictionary = breakage.get_save_data()
	var restored := WindowBreakage.new()
	root.add_child(restored)
	breach.set_glazed(true)
	restored.load_save_data(saved)
	_check(restored.get_pane_state(key) == WindowBreakage.PaneState.BROKEN, "pane damage did not survive the save")
	_check(not breach.glazed, "a saved broken 727 pane came back glazed")
	_check(restored.get_child_count() >= 3, "restored panes show no damage overlays")
	print("test_window_breakage: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


## A windows surface with one pane quad per centre (x, z) on a wall facing +Z, as the chunk builder lays them.
func _facade(centres: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for c: Vector2 in centres:
		var q: Array[Vector3] = [Vector3(c.x - 0.5, 0.9, 0.04), Vector3(c.x + 0.5, 0.9, 0.04), Vector3(c.x + 0.5, 2.3, 0.04), Vector3(c.x - 0.5, 2.3, 0.04)]
		for k: int in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.BACK)
			st.add_vertex(q[k])
	st.index()
	var mesh: ArrayMesh = st.commit()
	mesh.surface_set_name(0, "windows")
	return mesh


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
