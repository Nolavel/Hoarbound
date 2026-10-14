@tool
class_name RealityEditorDock
extends VBoxContainer
## Reality editor dock: find buildings by address, name or id, frame them, identify the one under
## the marker or camera, and record edit-layer changes (undoable); generated scenes stay untouched.

const EDITOR_SCENE: String = "res://scenes/world/key_west/key_west_reality_editor.tscn"
const MARKER_NAME: String = "FocusMarker"
## Height of the camera-ray plane used to identify buildings (local metres, NAVD88).
const PICK_PLANE_Y: float = 2.0
## Farthest a camera look ray searches for a building.
const PICK_RAY_M: float = 1500.0

## Set by the plugin; edit-layer changes go through it so Ctrl+Z undoes them.
var undo_redo: EditorUndoRedoManager

var _index: RealityIndex = RealityIndex.new()
var _store: RealityEditStore = RealityEditStore.new()
var _results: Array = []
var _current: Dictionary = {}
var _layer: LineEdit
var _edits: ItemList
var _query: LineEdit
var _list: ItemList
var _record: RichTextLabel
var _status: Label
var _hlod_info: RichTextLabel
var _hlod_sources: ItemList
var _hlod_cluster: String = ""
var _hlod_bounds: bool = false
var _hlod: KeyWestHLODBuilder
var _hlod_state: Dictionary = {}  # cluster id -> "fresh" | "dirty"
var _cluster_of: Dictionary = {}  # feature id -> cluster id, from the HLOD manifest


func _ready() -> void:
	name = "Reality"
	_build_ui()
	var edits: int = _store.load_all()
	if _index.load_index():
		_status.text = "%d buildings indexed, %d edits. Open %s for the view." % [_index.buildings.size(), edits, EDITOR_SCENE.get_file()]
	else:
		_status.text = "No index. Run: python3 tools/world/key_west_reality.py editor-index"


## Runs a search as if typed; returns the number found (used by the capture harness too).
func search_for(text: String) -> int:
	_query.text = text
	_search()
	if not _results.is_empty() and _list.get_selected_items().is_empty():
		_list.select(0)
		_show(0)
	return _results.size()


## "Go to" on the selected result.
func go_to_selected() -> void:
	_go_to()


## "At camera".
func identify_at_camera() -> void:
	_identify_camera()


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
	_record.bbcode_enabled = true
	_record.fit_content = true
	_record.selection_enabled = true
	add_child(_record)
	var layer_row: HBoxContainer = HBoxContainer.new()
	var layer_label: Label = Label.new()
	layer_label.text = "Layer"
	layer_row.add_child(layer_label)
	_layer = LineEdit.new()
	_layer.text = RealityEditStore.LAYERS[0]
	_layer.placeholder_text = "base, winter, loot:<set>, story:<state>"
	_layer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layer_row.add_child(_layer)
	layer_row.add_child(_button("Remove in layer", _remove_in_layer))
	add_child(layer_row)
	_edits = ItemList.new()
	_edits.custom_minimum_size = Vector2(0, 60)
	add_child(_edits)
	var tools: HBoxContainer = HBoxContainer.new()
	tools.add_child(_button("Drop edit", _drop_edit))
	tools.add_child(_button("Copy rebuild", _copy_rebuild))
	tools.add_child(_button("Copy Blender shell", _copy_shell))
	add_child(tools)
	_build_hlod_ui()
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)


## HLOD (docs/technical/REALITY_HLOD.md): the cluster of the picked building, its state and build controls.
func _build_hlod_ui() -> void:
	var title: Label = Label.new()
	title.text = "HLOD cluster"
	add_child(title)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_child(_button("Here", _hlod_pick))
	row.add_child(_button("Bounds", _hlod_toggle_bounds))
	row.add_child(_button("Tier 0/1", _hlod_toggle_tier))
	row.add_child(_button("Sources", _hlod_list_sources))
	add_child(row)
	var build_row: HBoxContainer = HBoxContainer.new()
	build_row.add_child(_button("Build selected", _hlod_build_selected))
	build_row.add_child(_button("Rebuild dirty", _hlod_rebuild_dirty))
	add_child(build_row)
	_hlod_info = RichTextLabel.new()
	_hlod_info.bbcode_enabled = true
	_hlod_info.fit_content = true
	_hlod_info.selection_enabled = true
	add_child(_hlod_info)
	_hlod_sources = ItemList.new()
	_hlod_sources.custom_minimum_size = Vector2(0, 80)
	_hlod_sources.item_activated.connect(func(i: int) -> void: search_for(_hlod_sources.get_item_text(i)))
	add_child(_hlod_sources)


## Cluster of the current building, else the one under the marker.
func hlod_select(cluster_id: String) -> void:
	_hlod_cluster = cluster_id
	_hlod_sources.clear()
	_hlod_show()


func _hlod_pick() -> void:
	_hlod_refresh_map()
	var cluster_id: String = _cluster_of.get(_current.get("id", ""), "")
	var view: KeyWestRealityEditorView = find_view()
	if cluster_id == "" and view != null and _marker() != null:
		cluster_id = view.cluster_at(_marker().global_position)
	if cluster_id == "":
		_hlod_info.text = "No HLOD cluster here. HLOD v1 covers chunks %s." % ", ".join(PackedStringArray(KeyWestChunkBuilder.hlod_config().get("chunks", [])))
		return
	hlod_select(cluster_id)


func _hlod_show() -> void:
	if _hlod_cluster == "":
		return
	var view: KeyWestRealityEditorView = find_view()
	var entry: Dictionary = view.reload_manifest().get(_hlod_cluster, {}) if view != null else {}
	if _hlod_state.is_empty():
		_hlod_state = _hlod_builder().status()
	var tier: int = view.cluster_tier(_hlod_cluster) if view != null else -1
	var lines: PackedStringArray = PackedStringArray(["[b]%s[/b]  chunk %s" % [_hlod_cluster, entry.get("chunk", "?")],
		"state: %s; editor shows %s" % [_hlod_state.get(_hlod_cluster, "unknown"), ["far mesh (chunk not in detail)", "tier 0 detail", "tier 1 proxy"][tier + 1]],
		"runtime: detail within %.0f m of the cluster centre, proxy beyond while the chunk is loaded" % KeyWestChunkBuilder.detail_band_m()])
	if not entry.is_empty():
		lines.append("sources: %d; triangles proxy %d / detail %d; surfaces %d (%s)" % [entry["source_count"], entry["triangles"], entry["detail_triangles"],
			entry["surfaces"], ", ".join(PackedStringArray(entry["materials"]))])
	else:
		lines.append("no proxy built yet")
	_hlod_info.text = "\n".join(lines)


func _hlod_toggle_bounds() -> void:
	var view: KeyWestRealityEditorView = find_view()
	if view == null or _hlod_cluster == "":
		return
	_hlod_bounds = not _hlod_bounds
	view.show_bounds(_hlod_cluster, _hlod_bounds)


func _hlod_toggle_tier() -> void:
	var view: KeyWestRealityEditorView = find_view()
	if view == null or _hlod_cluster == "":
		return
	if not view.set_cluster_tier(_hlod_cluster, 1 - maxi(view.cluster_tier(_hlod_cluster), 0)):
		_status.text = "Cluster %s is not in detail around the camera, or has no proxy yet." % _hlod_cluster
	_hlod_show()


func _hlod_list_sources() -> void:
	var view: KeyWestRealityEditorView = find_view()
	var entry: Dictionary = view.reload_manifest().get(_hlod_cluster, {}) if view != null else {}
	_hlod_sources.clear()
	for fid: String in entry.get("source_ids", []):
		_hlod_sources.add_item(fid)
	_status.text = "%d source ids; double-click one to find it." % _hlod_sources.item_count


func _hlod_build_selected() -> void:
	if _hlod_cluster == "":
		return
	_hlod_report(_hlod_builder().build(PackedStringArray([_hlod_cluster])))


func _hlod_rebuild_dirty() -> void:
	_hlod_report(_hlod_builder().rebuild_dirty())


func _hlod_report(report: Dictionary) -> void:
	_hlod = null
	_hlod_state.clear()
	_cluster_of.clear()
	var view: KeyWestRealityEditorView = find_view()
	if view != null and view.cluster_tier(_hlod_cluster) == 1:
		view.set_cluster_tier(_hlod_cluster, 1)
	_status.text = "HLOD: built %d, kept %d%s." % [report["built"].size(), report["kept"].size(),
		"" if report["errors"].is_empty() else ", errors: " + ", ".join(PackedStringArray(report["errors"]))]
	_hlod_show()


## One builder per state read: it caches the chunk exports it parsed.
func _hlod_builder() -> KeyWestHLODBuilder:
	if _hlod == null:
		_hlod = KeyWestHLODBuilder.new()
	return _hlod


func _hlod_refresh_map() -> void:
	if not _cluster_of.is_empty():
		return
	for entry: Dictionary in KeyWestHLODBuilder.load_manifest().get("clusters", []):
		for fid: String in entry["source_ids"]:
			_cluster_of[fid] = entry["cluster_id"]


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
	_select(_results[i])


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
	var hit: Dictionary = _index.pick_ray(origin, ray, PICK_RAY_M)
	if not hit.is_empty():
		_show_record(hit)
		return
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
	_show_record(b)


func _show_record(b: Dictionary) -> void:
	_results = [b]
	_list.clear()
	_list.add_item(RealityIndex.label_of(b))
	_list.select(0)
	_select(b)


func _marker() -> Node3D:
	var root: Node = EditorInterface.get_edited_scene_root()
	return root.find_child(MARKER_NAME, true, false) as Node3D if root != null else null


func _select(b: Dictionary) -> void:
	_current = b
	_record.text = _describe(b)
	_edits.clear()
	for e: Dictionary in _store.edits_for(b["id"]):
		_edits.add_item("%s  %s  [%s]" % [e["edit_id"], e["op"], e["layer"]])
		_edits.set_item_metadata(_edits.item_count - 1, e["edit_id"])
	_hlod_refresh_map()
	if _cluster_of.has(b["id"]):
		hlod_select(_cluster_of[b["id"]])


func _remove_in_layer() -> void:
	var layer: String = _layer.text.strip_edges()
	if _current.is_empty() or not _store.is_valid_layer(layer):
		_status.text = "Pick a building and a layer (base, winter, loot:<set>, story:<state>)."
		return
	var edit: Dictionary = RealityEditStore.new_edit("remove", layer, _current["id"], _current["chunk"], _current.get("gh", ""))
	undo_redo.create_action("Reality: remove %s in %s" % [RealityIndex.label_of(_current), layer])
	undo_redo.add_do_method(_store, &"add_edit", edit)
	undo_redo.add_undo_method(_store, &"remove_edit", edit["edit_id"])
	undo_redo.add_do_method(self, &"_select", _current)
	undo_redo.add_undo_method(self, &"_select", _current)
	undo_redo.commit_action()
	_status.text = "Recorded. Rebuild chunk %s to see it (Copy rebuild)." % _current["chunk"]


func _drop_edit() -> void:
	var picked: PackedInt32Array = _edits.get_selected_items()
	if picked.is_empty() or _current.is_empty():
		return
	var edit_id: String = String(_edits.get_item_metadata(picked[0]))
	var edit: Dictionary = {}
	for e: Dictionary in _store.edits_for(_current["id"]):
		if e["edit_id"] == edit_id:
			edit = e
	undo_redo.create_action("Reality: drop edit %s" % edit_id)
	undo_redo.add_do_method(_store, &"remove_edit", edit_id)
	undo_redo.add_undo_method(_store, &"add_edit", edit)
	undo_redo.add_do_method(self, &"_select", _current)
	undo_redo.add_undo_method(self, &"_select", _current)
	undo_redo.commit_action()


## Puts the two rebuild commands for the current chunk on the clipboard.
func _copy_rebuild() -> void:
	if _current.is_empty():
		return
	var chunk: String = _current["chunk"]
	DisplayServer.clipboard_set("python3 tools/world/key_west_reality.py export-editor --chunk=%s\n" % chunk
		+ "godot --path . --script tools/world/reality_gen/generate_key_west_chunks_cli.gd -- %s" % chunk)
	_status.text = "Rebuild commands for chunk %s copied; run them from the project folder." % chunk


## Puts the shell export command on the clipboard; the model comes back as assets/.../<stem>.glb.
func _copy_shell() -> void:
	if _current.is_empty():
		return
	DisplayServer.clipboard_set("python3 tools/world/key_west_reality.py blender-shell --feature-id %s" % _current["id"])
	_status.text = "Shell command copied. It writes the shell and its sizes for Blender; see its output for the return path."
