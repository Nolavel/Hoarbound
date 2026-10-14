@tool
class_name RealityEditorDock
extends VBoxContainer
## Reality editor dock: search buildings by address, name or id, move the focus marker there,
## identify the building under the marker or the editor camera. Reads data; writes nothing.

const EDITOR_SCENE: String = "res://scenes/world/key_west/key_west_reality_editor.tscn"
const MARKER_NAME: String = "FocusMarker"
## Height of the camera-ray plane used to identify buildings (local metres, NAVD88).
const PICK_PLANE_Y: float = 2.0

var _index: RealityIndex = RealityIndex.new()
var _results: Array = []
var _query: LineEdit
var _list: ItemList
var _record: RichTextLabel
var _status: Label


func _ready() -> void:
	name = "Reality"
	_build_ui()
	if _index.load_index():
		_status.text = "%d buildings indexed. Open %s for the view." % [_index.buildings.size(), EDITOR_SCENE.get_file()]
	else:
		_status.text = "No index. Run: python3 tools/world/key_west_reality.py editor-index"


## The view in the edited scene, if the Reality editor scene is open.
func find_view() -> KeyWestRealityEditorView:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null or root is KeyWestRealityEditorView:
		return root as KeyWestRealityEditorView
	for node: Node in root.get_children():
		if node is KeyWestRealityEditorView:
			return node as KeyWestRealityEditorView
	return null


func _build_ui() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	_query = LineEdit.new()
	_query.placeholder_text = "727 fort st, museum, kw:building:..."
	_query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_query.text_submitted.connect(func(_t: String) -> void: _search())
	row.add_child(_query)
	row.add_child(_button("Find", _search))
	add_child(row)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 160)
	_list.item_selected.connect(_show)
	_list.item_activated.connect(func(_i: int) -> void: _go_to())
	add_child(_list)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_child(_button("Go to", _go_to))
	actions.add_child(_button("At marker", _identify_marker))
	actions.add_child(_button("At camera", _identify_camera))
	add_child(actions)
	_record = RichTextLabel.new()
	_record.fit_content = true
	_record.selection_enabled = true
	add_child(_record)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)


func _button(text: String, action: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.pressed.connect(action)
	return b


func _search() -> void:
	_results = _index.search(_query.text)
	_list.clear()
	for b: Dictionary in _results:
		_list.add_item(RealityIndex.label_of(b) + ("" if b["generated"] else "  (not generated)"))
	_status.text = "%d found" % _results.size()
	if _results.size() == 1:
		_list.select(0)
		_show(0)


func _show(i: int) -> void:
	if i < 0 or i >= _results.size():
		return
	_record.text = _describe(_results[i])


func _describe(b: Dictionary) -> String:
	var asset: Dictionary = _index.asset_of(b["id"])
	var lines: PackedStringArray = PackedStringArray([
		"[b]%s[/b]" % RealityIndex.label_of(b),
		"id: %s" % b["id"],
		"address source: %s" % (b["addr_src"] if b["addr_src"] != "" else "none"),
		"use: %s" % b["use"],
		"height: %.1f m, levels: %s, ground: %.2f m" % [b["h"], str(b["levels"]), b["y"]],
		"chunk: %s, centre: %s" % [b["chunk"], str(b["c"])],
		"generated: %s" % ("yes" if b["generated"] else "no (a mapped way runs through it)"),
		"asset: %s" % ("%s (%s)" % [asset.get("godot_scene", ""), asset.get("authoring_state", "")] if not asset.is_empty() else "generic massing"),
	])
	return "\n".join(lines)


func _go_to() -> void:
	var i: int = _list.get_selected_items()[0] if not _list.get_selected_items().is_empty() else -1
	if i < 0:
		return
	var b: Dictionary = _results[i]
	var view: KeyWestRealityEditorView = find_view()
	var marker: Node3D = _marker()
	if view == null or marker == null:
		_status.text = "Open %s first." % EDITOR_SCENE
		return
	var target: Vector3 = Vector3(float(b["c"][0]), float(b["y"]) + float(b["h"]), float(b["c"][1]))
	marker.global_position = target
	view.set_focus(target)
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(marker)
	EditorInterface.edit_node(marker)
	_status.text = "Marker on %s. Press F in the 3D view to frame it." % RealityIndex.label_of(b)


func _identify_marker() -> void:
	var marker: Node3D = _marker()
	if marker == null:
		_status.text = "Open %s first." % EDITOR_SCENE
		return
	_identify(marker.global_position)


func _identify_camera() -> void:
	var camera: Camera3D = EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	if camera == null:
		return
	var ray: Vector3 = -camera.global_basis.z
	var origin: Vector3 = camera.global_position
	if absf(ray.y) < 0.01:
		_status.text = "Tilt the camera towards the ground."
		return
	var t: float = (PICK_PLANE_Y - origin.y) / ray.y
	_identify(origin + ray * maxf(t, 0.0))


func _identify(at: Vector3) -> void:
	var b: Dictionary = _index.pick(at.x, at.z)
	if b.is_empty():
		_record.text = "No building footprint at %.1f, %.1f (chunk %s)." % [at.x, at.z, KeyWestRealityEditorView.cell_of(at)]
		return
	_results = [b]
	_list.clear()
	_list.add_item(RealityIndex.label_of(b))
	_list.select(0)
	_record.text = _describe(b)


func _marker() -> Node3D:
	var root: Node = EditorInterface.get_edited_scene_root()
	return root.find_child(MARKER_NAME, true, false) as Node3D if root != null else null
