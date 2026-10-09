class_name PlayerHubPanel
extends CanvasLayer

## Temporary Hub readout beside Henry: pack contents, Quick Access zones, weight.
## Reads and moves through PlayerHubComponent only; keeps no item state.

const SIZE_KEYS: Array[String] = ["HUB_SIZE_POCKET", "HUB_SIZE_CARRIED", "HUB_SIZE_BULKY"]
const REFUSAL_KEYS: Dictionary = {
	EquipmentComponent.Refusal.TOO_LARGE: "HUB_REFUSED_TOO_LARGE",
	EquipmentComponent.Refusal.SLOT_OCCUPIED: "HUB_REFUSED_OCCUPIED",
}

var hub: PlayerHubComponent

var _pack_list: ItemList
var _zone_list: ItemList
var _weight: Label
var _survival: Label
var _status: Label
var _pack_ids: Array[StringName] = []
## Manual placement: the item being dragged, its ghost and the drop targets.
var _placing: StringName = &""
var _dragging: bool = false
var _ghost: Label
var _targets: Dictionary = {}  # Control -> zone path; empty path means the pack
var _zone_paths: Array[StringName] = []
var _zone_item_ids: Array[StringName] = []
const MANUAL_PACK: StringName = &"@pack"
var _manual_source: StringName = &""
var _manual_item: StringName = &""
var _manual_ghost: Label
var _inspect_button: Button
var _mode: Label


func _ready() -> void:
	layer = 20
	_build()
	hub.contents_changed.connect(_refresh)
	set_inspecting(hub.is_inspecting())
	_refresh()


func _build() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.08
	panel.anchor_bottom = 0.92
	panel.offset_left = -380.0
	panel.offset_right = -24.0
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 8)
	panel.add_child(column)
	column.add_child(_label(tr("HUB_PACK")))
	_pack_list = _list()
	_pack_list.item_selected.connect(_show_item_status)
	column.add_child(_pack_list)
	_weight = _label("")
	column.add_child(_weight)
	_survival = _label("")
	_survival.autowrap_mode = TextServer.AUTOWRAP_WORD
	column.add_child(_survival)
	column.add_child(_label(tr("HUB_QUICK_ACCESS")))
	_zone_list = _list()
	_zone_list.item_selected.connect(_show_zone_status)
	column.add_child(_zone_list)
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	buttons.add_child(_button(tr("HUB_USE"), _on_use))
	buttons.add_child(_button(tr("HUB_TO_POCKET"), _on_to_pocket))
	buttons.add_child(_button(tr("HUB_TO_PACK"), _on_to_pack))
	_inspect_button = _button(tr("HUB_INSPECT"), func() -> void: hub.open_inspection())
	column.add_child(_inspect_button)
	_mode = _label("")
	_mode.visible = false
	column.add_child(_mode)
	_status = _label("")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	column.add_child(_status)
	column.add_child(_label(tr("HUB_CLOSE_HINT")))


## Starts manual placement: pockets that fit light up, the item sits under the
## cursor, LMB drags it and releasing drops it there and closes the Hub.
func begin_placement(item_id: StringName) -> void:
	_placing = item_id
	var item: ItemResource = ItemCatalog.get_item(item_id)
	var strip := VBoxContainer.new()
	strip.anchor_left = 0.03
	strip.anchor_top = 0.2
	strip.offset_right = 300.0
	strip.add_theme_constant_override(&"separation", 6)
	add_child(strip)
	strip.add_child(_label(tr("HUB_PLACE_HINT")))
	strip.add_child(_target(tr("HUB_PACK"), &"", true))
	for zone: Dictionary in hub.get_quick_access_zones():
		var fits: bool = hub.can_place(item_id, zone["path"]) == EquipmentComponent.Refusal.NONE
		strip.add_child(_target(tr(zone["name"]), zone["path"], fits))
	_ghost = _label(tr(item.display_name) if item != null else String(item_id))
	_ghost.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.5))
	var centre: Vector2 = get_viewport().get_visible_rect().size * 0.5
	_ghost.position = centre
	add_child(_ghost)
	Input.warp_mouse(centre)


## Full inspection: the take-off button gives way to the mode title and the pack's
## sections, where sorting, repair and crafting will hang later.
func set_inspecting(on: bool) -> void:
	_inspect_button.visible = not on
	_mode.visible = on
	if not on:
		return
	var sections: PackedStringArray = [tr("HUB_INSPECT_TITLE")]
	for section: String in ["HUB_SECTION_MAIN", "HUB_SECTION_LID", "HUB_SECTION_SIDES"]:
		sections.append("· " + tr(section))
	_mode.text = "\n".join(sections)


func is_placing() -> bool:
	return _placing != &""


## Drops the placed item on a target path ("" = pack); a pocket it does not fit leaves it in the pack.
func drop_on(path: StringName) -> void:
	if _placing == &"":
		return
	if path != &"":
		hub.move_to_zone(_placing, path)
	_placing = &""
	hub.close()


func _input(event: InputEvent) -> void:
	if _placing != &"":
		var button := event as InputEventMouseButton
		if button != null and button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_dragging = true
			elif _dragging:
				drop_on(_target_at(button.position))
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseMotion and _dragging:
			_ghost.position = (event as InputEventMouseMotion).position + Vector2(12.0, -8.0)
		return
	_manual_drag_input(event)


## Regular Hub drag/drop delegates to PlayerHubComponent; UI owns no item state.
func _manual_drag_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_begin_manual_drag(button.position)
		elif _manual_source != &"":
			_finish_manual_drag(button.position)
		return
	if event is InputEventMouseMotion and _manual_source != &"" and is_instance_valid(_manual_ghost):
		_manual_ghost.position = (event as InputEventMouseMotion).position + Vector2(12.0, -8.0)


func _begin_manual_drag(point: Vector2) -> void:
	var pack_index: int = _item_at(_pack_list, point)
	if pack_index >= 0 and pack_index < _pack_ids.size():
		_start_manual_ghost(MANUAL_PACK, _pack_ids[pack_index], point)
		return
	var zone_index: int = _item_at(_zone_list, point)
	if zone_index < 0 or zone_index >= _zone_paths.size() or _zone_item_ids[zone_index] == &"":
		return
	_start_manual_ghost(_zone_paths[zone_index], _zone_item_ids[zone_index], point)


func _start_manual_ghost(source: StringName, item_id: StringName, point: Vector2) -> void:
	_clear_manual_drag()
	_manual_source = source
	_manual_item = item_id
	var item: ItemResource = ItemCatalog.get_item(item_id)
	_manual_ghost = _label(tr(item.display_name) if item != null else String(item_id))
	_manual_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_manual_ghost.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.5))
	_manual_ghost.position = point + Vector2(12.0, -8.0)
	add_child(_manual_ghost)


func _finish_manual_drag(point: Vector2) -> void:
	if _manual_source == MANUAL_PACK:
		var zone_index: int = _item_at(_zone_list, point)
		if zone_index >= 0 and zone_index < _zone_paths.size():
			var refusal: EquipmentComponent.Refusal = hub.move_to_zone(_manual_item, _zone_paths[zone_index])
			_status.text = "" if refusal == EquipmentComponent.Refusal.NONE else tr(
				REFUSAL_KEYS.get(refusal, "HUB_REFUSED_NO_ZONE"))
	elif _pack_list.get_global_rect().has_point(point):
		var reason: StringName = hub.move_to_pack(_manual_source)
		_status.text = tr("HUB_REFUSED_OVERWEIGHT") if reason == PlayerHubComponent.OVERWEIGHT else ""
	_clear_manual_drag()


func _clear_manual_drag() -> void:
	if is_instance_valid(_manual_ghost):
		_manual_ghost.queue_free()
	_manual_ghost = null
	_manual_source = &""
	_manual_item = &""


func _item_at(list: ItemList, point: Vector2) -> int:
	var rect: Rect2 = list.get_global_rect()
	if not rect.has_point(point):
		return -1
	return list.get_item_at_position(point - rect.position, true)


func _target_at(point: Vector2) -> StringName:
	for control: Control in _targets:
		if control.get_global_rect().has_point(point):
			return _targets[control]
	return &""


func _target(text: String, path: StringName, fits: bool) -> PanelContainer:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(0.0, 36.0)
	box.modulate = Color(0.6, 1.0, 0.6) if fits else Color(0.5, 0.5, 0.5, 0.6)
	box.add_child(_label(text))
	if fits:
		_targets[box] = path
	return box


func _refresh() -> void:
	_pack_list.clear()
	_pack_ids.clear()
	for item: Dictionary in hub.get_pack_items():
		var count: String = " ×%d" % item["count"] if int(item["count"]) > 1 else ""
		_pack_list.add_item("%s%s  ·  %s  ·  %.1f kg" % [tr(item["name"]), count, tr(SIZE_KEYS[item["size"]]), item["weight"]])
		_pack_ids.append(item["id"])
		var resource: ItemResource = ItemCatalog.get_item(item["id"])
		_pack_list.set_item_tooltip(_pack_list.item_count - 1, resource.get_status_text())
		if resource.water_capacity_ml > 0:
			_pack_list.set_item_text(_pack_list.item_count - 1, "%s · %s" % [tr(resource.display_name), tr("FLASK_SHORT_STATUS") % [resource.water_remaining_ml, resource.water_capacity_ml]])
	_zone_list.clear()
	_zone_paths.clear()
	_zone_item_ids.clear()
	for zone: Dictionary in hub.get_quick_access_zones():
		var held: ItemResource = ItemCatalog.get_item(zone["item_id"]) if zone["item_id"] != &"" else null
		var content: String = tr(held.display_name) if held != null else tr("HUB_EMPTY")
		if held != null and held.water_capacity_ml > 0:
			content += " · " + tr("FLASK_SHORT_STATUS") % [held.water_remaining_ml, held.water_capacity_ml]
		_zone_list.add_item("%s (%s): %s" % [tr(zone["name"]), tr(SIZE_KEYS[zone["max_size"]]), content])
		_zone_paths.append(zone["path"])
		_zone_item_ids.append(zone["item_id"])
	_weight.text = tr("HUB_WEIGHT") % [hub.get_weight(), hub.get_max_weight()]
	_survival.text = _format_survival_readout(hub.get_survival_readout())


func _format_survival_readout(readout: Dictionary) -> String:
	var load: float = float(readout.get("load_fraction", 0.0))
	var load_key: String = "HUB_LOAD_LIGHT"
	if load >= 0.75:
		load_key = "HUB_LOAD_HEAVY"
	elif load >= 0.40:
		load_key = "HUB_LOAD_LOADED"

	var lines: PackedStringArray = [
		tr("HUB_LOAD_STATUS") % [
			tr(load_key),
			float(readout.get("move_multiplier", 1.0)) * 100.0,
			float(readout.get("energy_multiplier", 1.0)),
		]
	]
	lines.append(
		tr("HUB_ENERGY_DRAIN_LOAD")
		if StringName(readout.get("energy_reason", &"normal")) == &"load"
		else tr("HUB_ENERGY_DRAIN_NORMAL")
	)

	var wetness: float = float(readout.get("wetness", -1.0))
	if wetness >= 0.0:
		var wet_keys: Array[String] = [
			"HUB_CLOTHING_DRY",
			"HUB_CLOTHING_DAMP",
			"HUB_CLOTHING_WET",
			"HUB_CLOTHING_SOAKED",
		]
		var stage: int = clampi(int(readout.get("wetness_stage", 0)), 0, wet_keys.size() - 1)
		var drying_key: String = "HUB_DRYING" if bool(readout.get("drying", false)) else "HUB_NOT_DRYING"
		lines.append(tr("HUB_CLOTHING_STATUS") % [
			tr(wet_keys[stage]),
			wetness * 100.0,
			tr(drying_key),
			float(readout.get("insulation_multiplier", 1.0)) * 100.0,
		])
	return "\n".join(lines)


func _show_item_status(index: int) -> void:
	var item: ItemResource = ItemCatalog.get_item(_pack_ids[index])
	_status.text = item.get_status_text() if item != null else ""


func _show_zone_status(index: int) -> void:
	var item: ItemResource = ItemCatalog.get_item(_zone_item_ids[index]) if _zone_item_ids[index] != &"" else null
	_status.text = item.get_status_text() if item != null else ""


## Selected pack item into the selected zone, or the first free one it fits.
func _on_to_pocket() -> void:
	var picked: PackedInt32Array = _pack_list.get_selected_items()
	if picked.is_empty():
		return
	var item_id: StringName = _pack_ids[picked[0]]
	var zones: PackedInt32Array = _zone_list.get_selected_items()
	var refusal: EquipmentComponent.Refusal = EquipmentComponent.Refusal.NO_SUCH_SLOT
	if not zones.is_empty():
		refusal = hub.move_to_zone(item_id, _zone_paths[zones[0]])
	else:
		for path: StringName in _zone_paths:
			refusal = hub.move_to_zone(item_id, path)
			if refusal == EquipmentComponent.Refusal.NONE:
				break
	_status.text = "" if refusal == EquipmentComponent.Refusal.NONE else tr(REFUSAL_KEYS.get(refusal, "HUB_REFUSED_NO_ZONE"))


func _on_use() -> void:
	var picked: PackedInt32Array = _pack_list.get_selected_items()
	if picked.is_empty():
		return
	if not hub.use_item(_pack_ids[picked[0]]):
		_status.text = tr("HUB_CANNOT_USE")
		var eater := hub.get_parent().get_node_or_null(^"ConsumptionController") as ConsumptionController
		if eater != null:
			var refusal: ConsumptionController.Refusal = eater.can_consume(_pack_ids[picked[0]])
			if refusal == ConsumptionController.Refusal.NO_TOOL or refusal == ConsumptionController.Refusal.EMPTY_FLASK:
				_status.text = tr(ConsumptionController.describe_refusal(refusal))


func _on_to_pack() -> void:
	var zones: PackedInt32Array = _zone_list.get_selected_items()
	if zones.is_empty():
		return
	var reason: StringName = hub.move_to_pack(_zone_paths[zones[0]])
	_status.text = tr("HUB_REFUSED_OVERWEIGHT") if reason == PlayerHubComponent.OVERWEIGHT else ""


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _list() -> ItemList:
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(0.0, 150.0)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return list


func _button(text: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(pressed)
	return button
