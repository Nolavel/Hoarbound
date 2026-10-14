extends SceneTree

## Reality editor: index search and picking find 727 Fort Street; the view shows every chunk as a
## far mesh, swaps the nearest ones for detail around the focus, and never adds saved children.

const EDITOR_SCENE: String = "res://scenes/world/key_west/key_west_reality_editor.tscn"
const ID_727: String = "kw:building:osm:w339414849"
const MAX_STEPS: int = 40

var _failures: int = 0


func _initialize() -> void:
	_check_index()
	_check_view()
	if _failures > 0:
		push_error("reality editor: %d check(s) failed" % _failures)
		quit(1)
	else:
		print("reality editor: all checks passed")
		quit(0)


func _check_index() -> void:
	var index: RealityIndex = RealityIndex.new()
	_check(index.load_index(), "index did not load")
	_check(index.buildings.size() > 10000, "index holds %d buildings" % index.buildings.size())
	var found: Array = index.search("727 fort")
	_check(not found.is_empty() and found[0]["id"] == ID_727, "727 fort -> %s" % [found.slice(0, 1)])
	_check(index.search("").is_empty(), "an empty query returns results")
	_check(not index.search("museum").is_empty(), "no museum found by name")
	var b: Dictionary = found[0] if not found.is_empty() else {}
	if not b.is_empty():
		_check(index.pick(float(b["c"][0]), float(b["c"][1])).get("id", "") == ID_727, "pick at the 727 centre missed it")
		_check(not index.asset_of(ID_727).is_empty(), "727 has no authored asset in the manifest")
	_check(index.pick(-20000.0, -20000.0).is_empty(), "pick far out at sea found a building")


func _check_view() -> void:
	var scene: Node3D = (load(EDITOR_SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	var view: KeyWestRealityEditorView = scene.get_node(^"RealityView") as KeyWestRealityEditorView
	_check(view != null and scene.get_node_or_null(^"FocusMarker") is Marker3D, "editor scene lacks the view or the marker")
	if view == null:
		return
	var far: int = view.build_overview()
	_check(far > 400, "overview has %d far meshes" % far)
	var at: Vector3 = (scene.get_node(^"FocusMarker") as Node3D).position  # the scene root sits at the origin
	view.set_focus(at)
	var steps: int = 0
	while view.step() and steps < MAX_STEPS:
		steps += 1
	var loaded: PackedStringArray = view.loaded_cells()
	_check(loaded.has(KeyWestRealityEditorView.cell_of(at)), "the focus chunk is not in detail: %s" % loaded)
	_check(loaded.size() <= view.detail_budget, "%d detail chunks over the budget" % loaded.size())
	_check(view.get_child_count(false) == 0, "the view gained saved (non-internal) children")
	var far_727: Node = view.find_child("Far_" + KeyWestRealityEditorView.cell_of(at), false, false)
	_check(far_727 is MeshInstance3D and not (far_727 as MeshInstance3D).visible, "the far mesh under a detail chunk stays visible")
	view.set_focus(Vector3(4000.0, 0.0, -4000.0))
	steps = 0
	while view.step() and steps < MAX_STEPS:
		steps += 1
	view.step()
	_check(not view.loaded_cells().has(KeyWestRealityEditorView.cell_of(at)), "detail stayed after the focus moved away")
	_check(far_727 is MeshInstance3D and (far_727 as MeshInstance3D).visible, "the far mesh did not come back")


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("reality editor: %s" % message)
