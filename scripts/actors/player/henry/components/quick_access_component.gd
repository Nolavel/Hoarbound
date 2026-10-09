class_name QuickAccessComponent
extends Node

## The wheel selects a pocket; wheel-click or 1–4 draws its item into the hand.
## LMB or another wheel-click uses the physically held item.

signal selection_changed(index: int, zone: Dictionary)

const NEXT_ACTION: StringName = &"quick_next"
const PREV_ACTION: StringName = &"quick_prev"
const USE_ACTION: StringName = &"quick_use"
## Existing LMB action. While an item is physically in hand it becomes the
## natural held-item Use trigger; Hub still owns raw LMB for drag/drop.
const HELD_USE_ACTION: StringName = &"fire"
const ROAD_FLARE_ID: StringName = &"road_flare"
const DIRECT_ACTIONS: Array[StringName] = [&"select item slot 1", &"select item slot 2",
	&"select item slot 3", &"select item slot 4"]
## Seconds the pocket readout stays up after the last change.
const READOUT_TIME: float = 2.0

@export var hub: PlayerHubComponent

var _index: int = 0
var _readout: Label
var _readout_left: float = 0.0


func _ready() -> void:
	if hub == null and get_parent() != null:
		hub = get_parent().get_node_or_null(^"PlayerHubComponent") as PlayerHubComponent


func _unhandled_input(event: InputEvent) -> void:
	if hub == null or hub.is_open() or not event.is_pressed() or event.is_echo():
		return
	if _pressed(event, NEXT_ACTION):
		select(_index + 1)
	elif _pressed(event, PREV_ACTION):
		select(_index - 1)
	elif _pressed(event, USE_ACTION):
		use_selected()
	elif _pressed(event, HELD_USE_ACTION):
		if _use_held_only():
			get_viewport().set_input_as_handled()
	else:
		for slot: int in range(DIRECT_ACTIONS.size()):
			if _pressed(event, DIRECT_ACTIONS[slot]):
				select(slot)
				_equip_selected()
				break


func _process(delta: float) -> void:
	if _readout_left > 0.0:
		_readout_left -= delta
		if _readout_left <= 0.0 and is_instance_valid(_readout):
			_readout.visible = false


func get_selected_index() -> int:
	return _index


## Selects a pocket by position, wrapping around; shows which pocket and what is in it.
func select(index: int) -> void:
	if hub == null:
		return
	var zones: Array[Dictionary] = hub.get_quick_access_zones()
	if zones.is_empty():
		return
	var next_index: int = posmod(index, zones.size())
	if next_index != _index:
		_put_away_unlit_held()
		zones = hub.get_quick_access_zones()
		if zones.is_empty():
			return
		next_index = posmod(index, zones.size())
	_index = next_index
	_show_readout(zones[_index])
	selection_changed.emit(_index, zones[_index])


## Held-item Use has priority. Empty hands draw the selected pocket item first.
func use_selected() -> bool:
	if hub == null:
		return false
	if _use_held_only():
		return true
	var zones: Array[Dictionary] = hub.get_quick_access_zones()
	if zones.is_empty():
		return false
	var zone: Dictionary = zones[clampi(_index, 0, zones.size() - 1)]
	var item_id: StringName = zone["item_id"]
	if item_id == &"" or _presented_from(zone["path"]):
		_show_readout(zone)
		return false
	if _equip_selected():
		_hide_readout_if_generic()
		return true
	var drawer := get_parent().get_node_or_null(^"HeldItemComponent") as HeldItemComponent
	if drawer != null and drawer.supports_item(item_id):
		return false
	var used: bool = hub.use_from_zone(zone["path"])
	if used:
		# A flare leaves the pocket and is now burning in hand; do not leave the
		# stale "Use selected item" instruction on screen after the state changed.
		_hide_readout()
	else:
		_show_readout(zone)
	return used


func _equip_selected() -> bool:
	if hub == null:
		return false
	var zones: Array[Dictionary] = hub.get_quick_access_zones()
	if zones.is_empty():
		return false
	var zone: Dictionary = zones[clampi(_index, 0, zones.size() - 1)]
	var item_id: StringName = zone["item_id"]
	if item_id == &"":
		return false
	for child: Node in get_parent().get_children():
		if child.has_method(&"equip_from_zone") and bool(child.call(&"equip_from_zone", item_id, zone["path"])):
			if item_id == ROAD_FLARE_ID:
				_show_held_flare_readout(false)
			else:
				_hide_readout_if_generic()
			return true
	return false


## True when a hand already shows the item that pocket keeps; pressing again is a no-op.
func _presented_from(path: StringName) -> bool:
	for child: Node in get_parent().get_children():
		if child.has_method(&"get_source_zone") and child.has_method(&"is_holding") \
			and bool(child.call(&"is_holding")) and StringName(child.call(&"get_source_zone")) == path:
			return true
	return false


func _use_held_only() -> bool:
	var parent := get_parent()
	if parent == null:
		return false
	for child: Node in parent.get_children():
		if not child.has_method(&"use_held") or not bool(child.call(&"use_held")):
			continue
		if child.has_method(&"is_burning") and bool(child.call(&"is_burning")):
			_show_held_flare_readout(true)
		else:
			_hide_readout()
		return true
	return false


func _put_away_unlit_held() -> void:
	var parent := get_parent()
	if parent == null:
		return
	for child: Node in parent.get_children():
		if child.has_method(&"put_away_unlit") and bool(child.call(&"put_away_unlit")):
			return


func _pressed(event: InputEvent, action: StringName) -> bool:
	return InputMap.has_action(action) and event.is_action_pressed(action)


func _show_readout(zone: Dictionary) -> void:
	if not is_inside_tree():
		return
	if not is_instance_valid(_readout):
		var layer := CanvasLayer.new()
		layer.layer = 15
		add_child(layer)
		_readout = Label.new()
		_readout.anchor_left = 0.5
		_readout.anchor_right = 0.5
		_readout.anchor_top = 0.82
		_readout.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		layer.add_child(_readout)
	var held: ItemResource = ItemCatalog.get_item(zone["item_id"]) if zone["item_id"] != &"" else null
	_readout.text = "%s: %s" % [tr(zone["name"]), tr(held.display_name) if held != null else tr("HUB_EMPTY")]
	if zone["item_id"] == ROAD_FLARE_ID and not _flare_is_burning():
		_readout.text += "\n%s  Use selected item — light flare" % _action_label(USE_ACTION)
	_readout.visible = true
	_readout_left = READOUT_TIME


func _show_held_flare_readout(burning: bool) -> void:
	if not is_inside_tree():
		return
	if not is_instance_valid(_readout):
		var layer := CanvasLayer.new()
		layer.layer = 15
		add_child(layer)
		_readout = Label.new()
		_readout.anchor_left = 0.5
		_readout.anchor_right = 0.5
		_readout.anchor_top = 0.82
		_readout.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		layer.add_child(_readout)
	var state := "burning" if burning else "unlit"
	var verb := "drop flare" if burning else "light flare"
	_readout.text = "Road flare — %s\n%s  Use held item — %s" % [
		state, _action_label(HELD_USE_ACTION), verb
	]
	_readout.visible = true
	_readout_left = READOUT_TIME


func _hide_readout() -> void:
	_readout_left = 0.0
	if is_instance_valid(_readout):
		_readout.visible = false


func _hide_readout_if_generic() -> void:
	var held := get_parent().get_node_or_null(^"HeldItemComponent") as HeldItemComponent
	if held != null and held.is_holding():
		_hide_readout()


func _flare_is_burning() -> bool:
	var parent := get_parent()
	var held := parent.get_node_or_null(^"HeldLightComponent") as HeldLightComponent if parent != null else null
	return held != null and held.is_burning()


func _action_label(action: StringName) -> String:
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	return events[0].as_text() if not events.is_empty() else String(action)
