class_name QuickAccessComponent
extends Node

signal readout_changed(text: String)

## The wheel selects a pocket; wheel-click or 1–4 draws its item into the hand.
## LMB or another wheel-click uses the physically held item.

signal selection_changed(index: int, zone: Dictionary)

const NEXT_ACTION: StringName = &"quick_next"
const PREV_ACTION: StringName = &"quick_prev"
const USE_ACTION: StringName = &"quick_use"
## Existing LMB action. While an item is physically in hand it becomes the
## natural held-item Use trigger; Hub still owns raw LMB for drag/drop.
const HELD_USE_ACTION: StringName = &"fire"
## X: everything in Henry's hands goes back where it came from (a burning flare is dropped with G).
const PUT_AWAY_ACTION: StringName = &"put_away_held"
const ROAD_FLARE_ID: StringName = &"road_flare"
const DIRECT_ACTIONS: Array[StringName] = [&"select item slot 1", &"select item slot 2",
	&"select item slot 3", &"select item slot 4"]
## Seconds the pocket readout stays up after the last change.
const READOUT_TIME: float = 2.0

@export var hub: PlayerHubComponent

var _index: int = 0
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
	elif _pressed(event, PUT_AWAY_ACTION):
		if put_away_held():
			get_viewport().set_input_as_handled()
	elif _pressed(event, HELD_USE_ACTION):
		if _use_held_only():
			get_viewport().set_input_as_handled()
	else:
		for slot: int in range(DIRECT_ACTIONS.size()):
			if _pressed(event, DIRECT_ACTIONS[slot]):
				draw(slot)
				break


func _process(delta: float) -> void:
	if _readout_left > 0.0:
		_readout_left -= delta
		if _readout_left <= 0.0:
			readout_changed.emit("")


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


## Empties Henry's hands back into storage; false when nothing was held or a holder cannot let go.
func put_away_held() -> bool:
	var parent: Node = get_parent()
	if parent == null or HeldReleaseCapability.holders(parent).is_empty():
		return false
	var ok: bool = HeldReleaseCapability.release_all(parent)
	_hide_readout()
	return ok


## Draws one pocket into the hand. An item shown from another coat pocket trades places with
## it, so nothing is shown twice; a pack pocket's item just goes back to its own place.
func draw(index: int) -> bool:
	if hub == null:
		return false
	var zones: Array[Dictionary] = hub.get_quick_access_zones()
	if zones.is_empty():
		return false
	var target: StringName = zones[posmod(index, zones.size())]["path"]
	var source: StringName = get_held_source_zone()
	if source == target:
		return true
	_put_away_unlit_held()
	if _held_presenter() != null:
		return false
	## The pack's pockets are fixed places on it: what came from one goes back to it, no trade.
	var swapped: bool = source != &"" and not _on_pack(source) and not _on_pack(target) and _swap_pockets(source, target)
	select(_zone_index(source if swapped else target))
	if use_selected():
		return true
	if swapped:
		_swap_pockets(source, target)
	return false


## The pocket whose item a hand shows right now, or "" (empty hands or a pack item).
func get_held_source_zone() -> StringName:
	var presenter: Node = _held_presenter()
	return HeldDrawCapability.source_zone(presenter) if presenter != null else &""


func _held_presenter() -> Node:
	var holding: Array[Node] = HeldReleaseCapability.holders(get_parent())
	for hand: Node in HeldDrawCapability.hands(get_parent()):
		if holding.has(hand):
			return hand
	return null


func _on_pack(zone: StringName) -> bool:
	return String(zone).begins_with("pack" + EquipmentComponent.POCKET_SEPARATOR)


## Trades the items of two pockets; changes nothing when either would not fit the other.
func _swap_pockets(a: StringName, b: StringName) -> bool:
	var equipment: EquipmentComponent = hub.equipment
	var pa: PackedStringArray = String(a).split(EquipmentComponent.POCKET_SEPARATOR)
	var pb: PackedStringArray = String(b).split(EquipmentComponent.POCKET_SEPARATOR)
	if equipment == null or pa.size() != 2 or pb.size() != 2:
		return false
	if a == b:
		return true
	var payload_a: Dictionary = equipment.take_pocket_instance(StringName(pa[0]), StringName(pa[1]))
	var payload_b: Dictionary = equipment.take_pocket_instance(StringName(pb[0]), StringName(pb[1]))
	var item_a: StringName = StringName(payload_a.get("id", ""))
	var item_b: StringName = StringName(payload_b.get("id", ""))
	var fits: bool = (item_a == &"" or equipment.can_stow(StringName(pb[0]), StringName(pb[1]), item_a) == EquipmentComponent.Refusal.NONE) \
		and (item_b == &"" or equipment.can_stow(StringName(pa[0]), StringName(pa[1]), item_b) == EquipmentComponent.Refusal.NONE)
	var into_a: Dictionary = payload_b if fits else payload_a
	var into_b: Dictionary = payload_a if fits else payload_b
	if not into_a.is_empty():
		if equipment.stow_instance(StringName(pa[0]), StringName(pa[1]), into_a["id"], into_a.get("instance_state", {})) != EquipmentComponent.Refusal.NONE:
			push_error("QuickAccess: failed to restore pocket A")
	if not into_b.is_empty():
		if equipment.stow_instance(StringName(pb[0]), StringName(pb[1]), into_b["id"], into_b.get("instance_state", {})) != EquipmentComponent.Refusal.NONE:
			push_error("QuickAccess: failed to restore pocket B")
	return fits


func _zone_index(path: StringName) -> int:
	var zones: Array[Dictionary] = hub.get_quick_access_zones()
	for i: int in range(zones.size()):
		if zones[i]["path"] == path:
			return i
	return _index


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
	for hand: Node in HeldDrawCapability.hands(get_parent()):
		if HeldDrawCapability.draw(hand, item_id, zone["path"]):
			if item_id == ROAD_FLARE_ID:
				_show_held_flare_readout(false)
			else:
				_hide_readout_if_generic()
			return true
	return false


## True when a hand already shows the item that pocket keeps; pressing again is a no-op.
func _presented_from(path: StringName) -> bool:
	var holding: Array[Node] = HeldReleaseCapability.holders(get_parent())
	for hand: Node in HeldDrawCapability.hands(get_parent()):
		if holding.has(hand) and HeldDrawCapability.source_zone(hand) == path:
			return true
	return false


func _use_held_only() -> bool:
	var parent := get_parent()
	if parent == null:
		return false
	for hand: Node in HeldDrawCapability.hands(parent):
		if not HeldDrawCapability.use(hand):
			continue
		var light := hand as HeldLightComponent
		if light != null and light.is_burning():
			_show_held_flare_readout(true)
		else:
			_hide_readout()
		return true
	return false


func _put_away_unlit_held() -> void:
	var parent := get_parent()
	if parent == null:
		return
	## Only what can go back to storage is hidden; a burning flare stays in hand.
	for holder: Node in HeldReleaseCapability.holders(parent):
		if HeldReleaseCapability.can_release(holder) and HeldReleaseCapability.release(holder):
			return


func _pressed(event: InputEvent, action: StringName) -> bool:
	return InputMap.has_action(action) and event.is_action_pressed(action)


func _show_readout(zone: Dictionary) -> void:
	if not is_inside_tree():
		return
	var held: ItemResource = ItemCatalog.get_item(zone["item_id"]) if zone["item_id"] != &"" else null
	var message := "%s: %s" % [tr(zone["name"]), tr(held.display_name) if held != null else tr("HUB_EMPTY")]
	if zone["item_id"] == ROAD_FLARE_ID and not _flare_is_burning():
		message += "\n%s  %s" % [_action_label(USE_ACTION), tr("FLARE_LIGHT_ACTION")]
	_readout_left = READOUT_TIME
	readout_changed.emit(message)


func _show_held_flare_readout(burning: bool) -> void:
	if not is_inside_tree():
		return
	_readout_left = READOUT_TIME
	readout_changed.emit("%s\n%s  %s" % [tr("FLARE_BURNING" if burning else "FLARE_UNLIT"),
		_action_label(HELD_USE_ACTION), tr("FLARE_DROP_ACTION" if burning else "FLARE_LIGHT_ACTION")])


func _hide_readout() -> void:
	_readout_left = 0.0
	readout_changed.emit("")


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
