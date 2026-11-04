class_name QuickAccessUI
extends Control

## Physical quick access around Henry. The outer cards are real worn pockets: four on his clothes
## and pack lid, plus, while the pack is worn, what sits outside it (side pocket, the two tool
## sleeves, the carabiner). HANDS is live held-state status and is deliberately never selectable.

const QUICK_NEXT: StringName = &"quick_next"
const QUICK_PREV: StringName = &"quick_prev"
const QUICK_USE: StringName = &"quick_use"
const SELECTOR_TIMEOUT_SECONDS := 5.0
const ORBIT_GAP_PX := 24.0
## Fixed cross places of the pockets round HANDS in the tight layout (x right, y down).
const CROSS_PLACES: Dictionary = {
	PATH_COAT_LEFT: Vector2(-1.0, 0.0),
	PATH_COAT_RIGHT: Vector2(1.0, 0.0),
	PATH_PACK_LID: Vector2(0.0, -1.0),
	PATH_THIGH_LEFT: Vector2(0.0, 1.0),
	PATH_PACK_SIDE_LEFT: Vector2(-1.0, -1.0),
	PATH_SLEEVE_FRONT: Vector2(1.0, -1.0),
	PATH_SLEEVE_BACK: Vector2(1.0, 1.0),
	PATH_CARABINER: Vector2(-1.0, 1.0),
}
const DIRECT_ACTIONS: Array[StringName] = [
	&"select item slot 1", &"select item slot 2", &"select item slot 3", &"select item slot 4"
]

const PATH_COAT_LEFT: StringName = &"torso_outer/coat_left"
const PATH_COAT_RIGHT: StringName = &"torso_outer/coat_right"
const PATH_THIGH_LEFT: StringName = &"legs_outer/thigh_left"
const PATH_PACK_LID: StringName = &"pack/pack_lid"
const POCKET_ORDER: Array[StringName] = [PATH_COAT_LEFT, PATH_COAT_RIGHT, PATH_PACK_LID, PATH_THIGH_LEFT]
## Outside a worn pack: cards built at runtime from the coat card, pinned to the pack's own anchors
## (BackpackModel.get_quick_anchor); reached with the wheel, keys 1-4 stay on POCKET_ORDER.
const PATH_PACK_SIDE_LEFT: StringName = &"pack/pack_side_left"
const PATH_SLEEVE_FRONT: StringName = &"pack/pack_side_right_front"
const PATH_SLEEVE_BACK: StringName = &"pack/pack_side_right_back"
const PATH_CARABINER: StringName = &"pack/pack_carabiner"
const PACK_ORDER: Array[StringName] = [PATH_PACK_SIDE_LEFT, PATH_SLEEVE_FRONT, PATH_SLEEVE_BACK, PATH_CARABINER]

const SHADER_REVEAL: StringName = &"reveal"
const SHADER_BASE_COLOR: StringName = &"base_color"
const SHADER_FADE_DIRECTION: StringName = &"fade_direction"
const SHADER_CORNER_RADIUS: StringName = &"corner_radius"

const ICON_HAND := "res://assets/ui/hud/pickup_marker/hand_open.svg"
const ICON_APPAREL := "res://assets/ui/hud/quick_access/icons/apparel.svg"
const ICON_BACKPACK := "res://assets/ui/hud/quick_access/icons/backpack.svg"
const ICON_FIRE := "res://assets/ui/hud/quick_access/icons/local_fire_department.svg"
const ICON_WATER := "res://assets/ui/hud/quick_access/icons/water_bottle.svg"
const ICON_FOOD := "res://assets/ui/hud/quick_access/icons/lunch_dining.svg"
const ICON_GENERIC := "res://assets/ui/hud/quick_access/icons/inventory_2.svg"

@export_group("Henry anchors")
@export var coat_left_anchor: Node3D
@export var coat_right_anchor: Node3D
@export var thigh_left_anchor: Node3D
@export var pack_lid_anchor: Node3D
@export var hands_anchor: Node3D

@export_group("Follow")
@export_range(1.0, 40.0, 0.5) var follow_speed := 24.0
## Extra screen-space separation for the four side cards. The sign is derived
## from their projected position, so orbiting Henry keeps the cards moving outwards.
@export_range(0.0, 80.0, 1.0) var side_spread_px := 26.0
@export_range(0.0, 96.0, 1.0) var viewport_margin_px := 32.0
@export_range(0.0, 160.0, 1.0) var edge_blend_px := 72.0
@export_group("Tight camera")
@export_range(0.5, 3.0, 0.1) var tight_camera_near_distance := 1.25
@export_range(1.0, 6.0, 0.1) var tight_camera_far_distance := 3.5
@export_range(1.0, 20.0, 0.5) var orbit_transition_speed := 8.0
@export_group("Anchor offsets")
@export var coat_left_offset := Vector2.ZERO
@export var coat_right_offset := Vector2.ZERO
@export var thigh_left_offset := Vector2.ZERO
@export var pack_lid_offset := Vector2.ZERO
@export var hands_offset := Vector2.ZERO

@export_group("Animation")
@export_range(0.05, 0.6, 0.01) var reveal_time := 0.22
@export_range(0.0, 0.10, 0.005) var reveal_stagger := 0.025
@export_range(0.05, 0.4, 0.01) var hide_time := 0.14
@export_range(0.0, 0.5, 0.01) var focus_transition_time := 0.10
@export_range(0.0, 0.5, 0.01) var transfer_time := 0.18

@export_group("Colors")
@export var active_color := Color(1.0, 0.72, 0.10, 0.94)
@export var inactive_color := Color(0.36, 0.36, 0.36, 0.72)
@export var empty_color := Color(0.26, 0.26, 0.26, 0.52)
@export var hands_color := Color(0.70, 0.73, 0.76, 0.78)
@export var confirm_color := Color(1.0, 0.86, 0.24, 1.0)

@onready var coat_left: Control = $CoatLeft
@onready var coat_right: Control = $CoatRight
@onready var thigh_left: Control = $ThighLeft
@onready var pack_lid: Control = $PackLid
@onready var hands: Control = $Hands

@onready var coat_left_background: TextureRect = $CoatLeft/Background
@onready var coat_right_background: TextureRect = $CoatRight/Background
@onready var thigh_left_background: TextureRect = $ThighLeft/Background
@onready var pack_lid_background: TextureRect = $PackLid/Background
@onready var hands_background: TextureRect = $Hands/Background

@onready var coat_left_icon: TextureRect = $CoatLeft/Icon
@onready var coat_right_icon: TextureRect = $CoatRight/Icon
@onready var thigh_left_icon: TextureRect = $ThighLeft/Icon
@onready var pack_lid_icon: TextureRect = $PackLid/Icon
@onready var hands_icon: TextureRect = $Hands/Icon

@onready var coat_left_label: Label = $CoatLeft/Label
@onready var coat_right_label: Label = $CoatRight/Label
@onready var thigh_left_label: Label = $ThighLeft/Label
@onready var pack_lid_label: Label = $PackLid/Label
@onready var hands_label: Label = $Hands/Label

var quick_access_component: QuickAccessComponent
var _materials: Dictionary = {}
var _slots: Dictionary = {}
var _icons: Dictionary = {}
var _labels: Dictionary = {}
var _focus_path: StringName = &""
var _last_confirmed_path: StringName = &""
var _opened := false
var _selection_timeout_left := 0.0
## Pinned up by the open pack (show_pinned): no countdown, no wheel or click selection.
var _pinned := false
var _orbit_blend := 0.0
var _cross_latched := false
var _direct_busy := false
var _refresh_left := 0.0
var _reveal_tween: Tween
var _focus_tween: Tween
var _last_anchor_screen_positions: Dictionary = {}
var _icon_hand: Texture2D
var _icon_apparel: Texture2D
var _icon_backpack: Texture2D
var _icon_fire: Texture2D
var _icon_water: Texture2D
var _icon_food: Texture2D
var _icon_generic: Texture2D


func _ready() -> void:
	_make_mouse_transparent(self)
	_resolve_component()
	_build_maps()
	_build_pack_cards()
	_prepare_materials()
	_load_icons()
	_configure_layout()
	_set_all_reveal(0.0)
	_set_visible_state(false)
	call_deferred(&"_initial_setup")


func _initial_setup() -> void:
	_snap_all()
	_refresh_content()
	## 3D inventory: while Henry holds the pack open, every card stays up on its live anchor.
	var hub: PlayerHubComponent = quick_access_component.hub if quick_access_component != null else null
	if hub != null:
		hub.hub_opened.connect(func() -> void:
			if hub.pack_in_hands and not hub.is_inspecting():
				show_pinned())
		hub.hub_closed.connect(unpin)


## Shows every card on its anchor with no countdown and no selection input (the open pack's view).
func show_pinned() -> void:
	_pinned = true
	_opened = true
	_selection_timeout_left = INF
	_refresh_content()
	_set_visible_state(true)
	_snap_all()
	_refresh_focus_visuals(false)
	_animate_reveal_in()


func is_pinned() -> bool:
	return _pinned


func unpin() -> void:
	if not _pinned:
		return
	_pinned = false
	cancel()


func is_open() -> bool:
	return _opened


func show_quick_access() -> void:
	if _opened or _direct_busy or not _can_open():
		return
	_opened = true
	_cross_latched = false
	_selection_timeout_left = SELECTOR_TIMEOUT_SECONDS
	_sync_focus_on_open()
	_refresh_content()
	_set_visible_state(true)
	_snap_all()
	_refresh_focus_visuals(false)
	_animate_reveal_in()


func cancel() -> void:
	if not _opened:
		return
	_opened = false
	_selection_timeout_left = 0.0
	_animate_reveal_out(false)


func navigate_next() -> void:
	if _opened:
		_selection_timeout_left = SELECTOR_TIMEOUT_SECONDS
		_move_focus(1)


func navigate_previous() -> void:
	if _opened:
		_selection_timeout_left = SELECTOR_TIMEOUT_SECONDS
		_move_focus(-1)


func confirm_current() -> void:
	if _opened and _focus_path != &"":
		_confirm_path(_focus_path)


func direct_draw_slot(slot_number: int) -> void:
	if slot_number < 1 or slot_number > POCKET_ORDER.size() or _opened or _direct_busy or not _can_open():
		return
	_direct_draw_path(POCKET_ORDER[slot_number - 1])


func _input(event: InputEvent) -> void:
	if _pinned or not event.is_pressed() or event.is_echo():
		return

	if _opened:
		if event is InputEventMouseButton:
			var mouse := event as InputEventMouseButton
			match mouse.button_index:
				MOUSE_BUTTON_RIGHT:
					cancel()
				MOUSE_BUTTON_WHEEL_DOWN:
					navigate_next()
				MOUSE_BUTTON_WHEEL_UP:
					navigate_previous()
				MOUSE_BUTTON_LEFT:
					confirm_current()
				MOUSE_BUTTON_MIDDLE:
					pass
				_:
					return
			get_viewport().set_input_as_handled()
			return
		for i: int in range(DIRECT_ACTIONS.size()):
			if event.is_action_pressed(DIRECT_ACTIONS[i]):
				_confirm_path(POCKET_ORDER[i])
				get_viewport().set_input_as_handled()
				return
		return

	if _direct_busy:
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
			_direct_busy = false
			_set_visible_state(false)
			get_viewport().set_input_as_handled()
		return

	## First wheel tick only opens; it never changes a pocket.
	if event.is_action_pressed(QUICK_NEXT) or event.is_action_pressed(QUICK_PREV) or event.is_action_pressed(QUICK_USE):
		show_quick_access()
		get_viewport().set_input_as_handled()
		return

	## Expert path: direct physical pocket draw, no full selector.
	for i: int in range(DIRECT_ACTIONS.size()):
		if event.is_action_pressed(DIRECT_ACTIONS[i]):
			direct_draw_slot(i + 1)
			get_viewport().set_input_as_handled()
			return


func _process(delta: float) -> void:
	if _opened:
		_selection_timeout_left -= delta
		if _selection_timeout_left <= 0.0:
			cancel()
			return
	elif not _direct_busy:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	_update_card_positions(camera, delta, false)
	_sync_fade_directions()
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = 0.12
		_refresh_content()
		if _opened and _focus_path != &"" and _zone_item(_focus_path) == &"":
			_sync_focus_on_open()
			_refresh_focus_visuals(true)


func _resolve_component() -> void:
	if quick_access_component != null:
		return
	var node: Node = get_parent()
	while node != null:
		var found := node.get_node_or_null(^"QuickAccessComponent") as QuickAccessComponent
		if found != null:
			quick_access_component = found
			return
		node = node.get_parent()


func _build_maps() -> void:
	_slots = {PATH_COAT_LEFT: coat_left, PATH_COAT_RIGHT: coat_right, PATH_THIGH_LEFT: thigh_left, PATH_PACK_LID: pack_lid}
	_icons = {PATH_COAT_LEFT: coat_left_icon, PATH_COAT_RIGHT: coat_right_icon, PATH_THIGH_LEFT: thigh_left_icon, PATH_PACK_LID: pack_lid_icon}
	_labels = {PATH_COAT_LEFT: coat_left_label, PATH_COAT_RIGHT: coat_right_label, PATH_THIGH_LEFT: thigh_left_label, PATH_PACK_LID: pack_lid_label}


## The cards for what sits outside the pack: copies of the coat card, one per PACK_ORDER path.
func _build_pack_cards() -> void:
	for path: StringName in PACK_ORDER:
		var card := coat_left.duplicate() as Control
		card.name = "Pack_%s" % String(path).get_file()
		add_child(card)
		_slots[path] = card
		_icons[path] = card.get_node(^"Icon")
		_labels[path] = card.get_node(^"Label")


func _prepare_materials() -> void:
	_materials = {&"hands": _duplicate_material(hands_background)}
	for path: StringName in _all_paths():
		_materials[path] = _duplicate_material((_slots[path] as Control).get_node(^"Background") as TextureRect)
	# Pockets are graphic bars, not pills. HANDS deliberately keeps its softer
	# prompt-like silhouette and centred fade.
	for path: StringName in _all_paths():
		var material := _materials.get(path) as ShaderMaterial
		if material != null:
			material.set_shader_parameter(SHADER_CORNER_RADIUS, 0.0)


func _duplicate_material(background: TextureRect) -> ShaderMaterial:
	var source := background.material as ShaderMaterial
	if source == null:
		push_error("QuickAccessUI: %s has no ShaderMaterial." % background.get_path())
		return null
	var copy := source.duplicate() as ShaderMaterial
	background.material = copy
	return copy


func _load_icons() -> void:
	_icon_hand = load(ICON_HAND) as Texture2D
	_icon_apparel = load(ICON_APPAREL) as Texture2D
	_icon_backpack = load(ICON_BACKPACK) as Texture2D
	_icon_fire = load(ICON_FIRE) as Texture2D
	_icon_water = load(ICON_WATER) as Texture2D
	_icon_food = load(ICON_FOOD) as Texture2D
	_icon_generic = load(ICON_GENERIC) as Texture2D


func _configure_layout() -> void:
	for path: StringName in _all_paths():
		_configure_card(_slots[path] as Control, _icons[path] as TextureRect, _labels[path] as Label)
	_configure_card(hands, hands_icon, hands_label)
	hands.size = Vector2(196.0, 62.0)
	hands_background.size = hands.size
	hands_icon.position = Vector2(10.0, 13.0)
	hands_icon.size = Vector2(36.0, 36.0)
	hands_label.position = Vector2(54.0, 8.0)
	hands_label.size = Vector2(134.0, 48.0)


func _configure_card(slot: Control, icon: TextureRect, label: Label) -> void:
	slot.size = Vector2(184.0, 58.0)
	slot.pivot_offset = slot.size * 0.5
	var background := slot.get_node(^"Background") as TextureRect
	background.position = Vector2.ZERO
	background.size = slot.size
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = Vector2(10.0, 11.0)
	icon.size = Vector2(36.0, 36.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = Vector2(54.0, 6.0)
	label.size = Vector2(122.0, 48.0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.add_theme_font_size_override(&"font_size", 14)
	label.add_theme_constant_override(&"outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _can_open() -> bool:
	if quick_access_component == null or quick_access_component.hub == null or quick_access_component.hub.is_open():
		return false
	var player := _player()
	if player == null:
		return false
	var carry := player.get_node_or_null(^"CarryComponent") as CarryComponent
	if carry != null and carry.is_carrying():
		return false
	var light := player.get_node_or_null(^"HeldLightComponent") as HeldLightComponent
	if light != null and light.is_burning():
		return false
	var visual := player.get_node_or_null(^"HenryUALVisual") as HenryUALAnimation
	return visual == null or not visual.is_action_locking()


func _player() -> Node:
	if quick_access_component != null:
		return quick_access_component.get_parent()
	var node: Node = get_parent()
	while node != null:
		if node.get_node_or_null(^"EquipmentComponent") != null:
			return node
		node = node.get_parent()
	return null


func _sync_focus_on_open() -> void:
	var filled := _filled_paths()
	if filled.is_empty():
		_focus_path = &""
		return
	if _last_confirmed_path != &"" and filled.has(_last_confirmed_path):
		_focus_path = _last_confirmed_path
		return
	if quick_access_component != null and quick_access_component.hub != null:
		var zones := quick_access_component.hub.get_quick_access_zones()
		var selected := quick_access_component.get_selected_index()
		if selected >= 0 and selected < zones.size():
			var selected_path := StringName(zones[selected]["path"])
			if filled.has(selected_path):
				_focus_path = selected_path
				return
	for path: StringName in _all_paths():
		if filled.has(path):
			_focus_path = path
			return


func _move_focus(direction: int) -> void:
	var filled := _filled_paths()
	if filled.is_empty():
		_focus_path = &""
		_refresh_focus_visuals(true)
		return
	var ordered: Array[StringName] = []
	for path: StringName in _all_paths():
		if filled.has(path):
			ordered.append(path)
	var index := ordered.find(_focus_path)
	index = 0 if index < 0 else posmod(index + direction, ordered.size())
	_focus_path = ordered[index]
	_refresh_focus_visuals(true)


func _filled_paths() -> Array[StringName]:
	var result: Array[StringName] = []
	if quick_access_component == null or quick_access_component.hub == null:
		return result
	for path: StringName in _all_paths():
		if _is_shown(path) and _zone_item(path) != &"":
			result.append(path)
	return result


## Every pocket card, the clothes' first then the pack's outside.
func _all_paths() -> Array[StringName]:
	var paths: Array[StringName] = POCKET_ORDER.duplicate()
	paths.append_array(PACK_ORDER)
	return paths


## A card shows while its pocket exists: the outside-pack ones only while the pack is worn.
func _is_shown(path: StringName) -> bool:
	if quick_access_component == null or quick_access_component.hub == null:
		return POCKET_ORDER.has(path)
	return not _zone(path).is_empty()


## The pack's own anchor for an outside-pack card (null if the pack is not worn).
func _pack_anchor(path: StringName) -> Node3D:
	var player := _player()
	var visual := player.get_node_or_null(^"HenryUALVisual") as HenryUALAnimation if player != null else null
	var rig: PackRig = visual.get_pack_rig() if visual != null else null
	var canvas: BackpackModel = rig.get_canvas() if rig != null else null
	return canvas.get_quick_anchor(StringName(String(path).get_file())) if canvas != null else null


func _zone(path: StringName) -> Dictionary:
	if quick_access_component == null or quick_access_component.hub == null:
		return {}
	for zone: Dictionary in quick_access_component.hub.get_quick_access_zones():
		if StringName(zone["path"]) == path:
			return zone
	return {}


## What a pocket card shows: the pocket whose item is in hand reads empty, HANDS owns it.
func _zone_item(path: StringName) -> StringName:
	if quick_access_component != null and path == quick_access_component.get_held_source_zone():
		return &""
	return StringName(_zone(path).get("item_id", &""))


func _zone_index(path: StringName) -> int:
	if quick_access_component == null or quick_access_component.hub == null:
		return -1
	var zones := quick_access_component.hub.get_quick_access_zones()
	for i: int in range(zones.size()):
		if StringName(zones[i]["path"]) == path:
			return i
	return -1


func _refresh_content() -> void:
	for path: StringName in _all_paths():
		var item_id := _zone_item(path)
		var label := _labels[path] as Label
		var icon := _icons[path] as TextureRect
		label.text = "%s\n%s" % [_location_label(path), _item_label(item_id)]
		icon.texture = _pocket_icon(path) if item_id == &"" else _icon_for_item(item_id)
		icon.modulate = Color(0.90, 0.91, 0.92, 0.92) if item_id != &"" else Color(0.62, 0.64, 0.66, 0.60)
	var held := _held_status()
	var held_id := StringName(held.get("item_id", &""))
	var state := String(held.get("state", ""))
	hands_label.text = "HANDS\n%s" % (_item_label(held_id) if state == "" else "%s · %s" % [_item_label(held_id), state])
	hands_icon.texture = _icon_hand if held_id == &"" else _icon_for_item(held_id)
	hands_icon.modulate = Color(0.92, 0.93, 0.94, 0.95)


func _location_label(path: StringName) -> String:
	match path:
		PATH_COAT_LEFT: return "COAT L"
		PATH_COAT_RIGHT: return "COAT R"
		PATH_THIGH_LEFT: return "THIGH"
		PATH_PACK_LID: return "PACK LID"
		PATH_PACK_SIDE_LEFT: return tr(&"QA_PACK_SIDE")
		PATH_SLEEVE_FRONT: return tr(&"QA_SLEEVE_FRONT")
		PATH_SLEEVE_BACK: return tr(&"QA_SLEEVE_BACK")
		PATH_CARABINER: return tr(&"QA_CARABINER")
	return "POCKET"


func _item_label(item_id: StringName) -> String:
	if item_id == &"":
		return "EMPTY"
	var item: ItemResource = ItemCatalog.get_item(item_id)
	return String(item_id).to_upper() if item == null else tr(item.display_name).to_upper()


func _held_status() -> Dictionary:
	var player := _player()
	if player == null:
		return {"item_id": &"", "state": ""}
	var light := player.get_node_or_null(^"HeldLightComponent") as HeldLightComponent
	if light != null and light.is_holding():
		var state := "BURNING" if light.is_burning() else ("UNLIT" if light.is_holding_unlit() else "SPENT")
		return {"item_id": light.flare_item_id, "state": state}
	var hammer := player.get_node_or_null(^"HammerComponent") as HammerComponent
	if hammer != null and hammer.is_holding():
		return {"item_id": hammer.hammer_item_id, "state": ""}
	var held := player.get_node_or_null(^"HeldItemComponent") as HeldItemComponent
	if held != null and held.is_holding():
		var item_id := held.get_item_id()
		var item: ItemResource = ItemCatalog.get_item(item_id)
		var state := ""
		if item != null and item.water_capacity_ml > 0:
			state = item.get_status_text().to_upper()
		return {"item_id": item_id, "state": state}
	return {"item_id": &"", "state": ""}


func _pocket_icon(path: StringName) -> Texture2D:
	return _icon_backpack if path == PATH_PACK_LID or PACK_ORDER.has(path) else _icon_apparel


func _icon_for_item(item_id: StringName) -> Texture2D:
	var text := String(item_id)
	if text.begins_with("water_flask"):
		return _icon_water
	if item_id in [&"lighter", &"tinder", &"road_flare"]:
		return _icon_fire
	if item_id in [&"tinned_stew", &"tinned_pineapple", &"tinned_pineapple_open", &"spov_can", &"spov_can_open", &"empty_tin"]:
		return _icon_food
	return _icon_generic


func _confirm_path(path: StringName) -> void:
	if not _opened or _zone_item(path) == &"":
		_pulse_denied(path)
		return
	_opened = false
	_selection_timeout_left = 0.0
	_last_confirmed_path = path
	_animate_confirm(path)


func _animate_confirm(path: StringName) -> void:
	var material := _materials.get(path) as ShaderMaterial
	var slot := _slots.get(path) as Control
	if material != null:
		_set_shader_color(material, confirm_color)
	if slot != null:
		var pulse := slot.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		pulse.tween_property(slot, ^"scale", Vector2.ONE * 1.08, 0.08)
		pulse.tween_property(slot, ^"scale", Vector2.ONE * 1.04, 0.07)
	_transfer_icon(path)


func _transfer_icon(path: StringName) -> void:
	var source := _icons.get(path) as TextureRect
	if source == null or source.texture == null:
		_perform_draw(path)
		_animate_reveal_out(true)
		return
	var ghost := TextureRect.new()
	ghost.texture = source.texture
	ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.size = source.size
	ghost.global_position = source.global_position
	ghost.modulate = active_color
	add_child(ghost)
	var move := ghost.create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	move.tween_property(ghost, ^"global_position", hands_icon.global_position, transfer_time)
	move.tween_property(ghost, ^"scale", Vector2.ONE * 0.92, transfer_time)
	await move.finished
	ghost.queue_free()
	_perform_draw(path)
	_refresh_content()
	_pulse_hands()
	await get_tree().create_timer(0.12).timeout
	_animate_reveal_out(true)


func _perform_draw(path: StringName) -> bool:
	if quick_access_component == null:
		return false
	var index := _zone_index(path)
	if index < 0:
		return false
	return quick_access_component.draw(index)


func _direct_draw_path(path: StringName) -> void:
	if _zone_item(path) == &"":
		return
	_direct_busy = true
	_cross_latched = false
	_focus_path = path
	_refresh_content()
	_set_visible_state(false)
	hands.visible = true
	(_slots[path] as Control).visible = true
	_snap_all()
	_set_shader_reveal(_materials[&"hands"] as ShaderMaterial, 0.0)
	_set_shader_reveal(_materials[path] as ShaderMaterial, 0.0)
	_set_shader_color(_materials[&"hands"] as ShaderMaterial, hands_color)
	_set_shader_color(_materials[path] as ShaderMaterial, active_color)
	var reveal := create_tween().set_parallel(true)
	reveal.tween_method(_tween_shader_reveal.bind(_materials[&"hands"] as ShaderMaterial), 0.0, 1.0, 0.12)
	reveal.tween_method(_tween_shader_reveal.bind(_materials[path] as ShaderMaterial), 0.0, 1.0, 0.12)
	await reveal.finished
	_last_confirmed_path = path
	await _direct_transfer(path)
	_direct_busy = false


func _direct_transfer(path: StringName) -> void:
	var source := _icons[path] as TextureRect
	var ghost := TextureRect.new()
	ghost.texture = source.texture
	ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.size = source.size
	ghost.global_position = source.global_position
	ghost.modulate = active_color
	add_child(ghost)
	var move := ghost.create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	move.tween_property(ghost, ^"global_position", hands_icon.global_position, 0.16)
	move.tween_property(ghost, ^"scale", Vector2.ONE * 0.9, 0.16)
	await move.finished
	ghost.queue_free()
	_perform_draw(path)
	_refresh_content()
	_pulse_hands()
	await get_tree().create_timer(0.20).timeout
	await _hide_direct(path)


func _hide_direct(path: StringName) -> void:
	var hide := create_tween().set_parallel(true)
	hide.tween_method(_tween_shader_reveal.bind(_materials[&"hands"] as ShaderMaterial), _get_shader_reveal(_materials[&"hands"] as ShaderMaterial), 0.0, 0.12)
	hide.tween_method(_tween_shader_reveal.bind(_materials[path] as ShaderMaterial), _get_shader_reveal(_materials[path] as ShaderMaterial), 0.0, 0.12)
	await hide.finished
	_set_visible_state(false)


func _pulse_denied(path: StringName) -> void:
	var slot := _slots.get(path) as Control
	if slot == null:
		return
	var pulse := slot.create_tween().set_trans(Tween.TRANS_SINE)
	pulse.tween_property(slot, ^"scale", Vector2.ONE * 0.96, 0.05)
	pulse.tween_property(slot, ^"scale", Vector2.ONE, 0.07)


func _pulse_hands() -> void:
	var material := _materials.get(&"hands") as ShaderMaterial
	if material == null:
		return
	var pulse := create_tween()
	pulse.tween_method(_tween_shader_color.bind(material), _get_shader_color(material), confirm_color, 0.06)
	pulse.tween_method(_tween_shader_color.bind(material), confirm_color, hands_color, 0.12)


func _animate_reveal_in() -> void:
	_kill_reveal_tween()
	var order: Array[StringName] = [&"hands", PATH_COAT_LEFT, PATH_COAT_RIGHT, PATH_THIGH_LEFT, PATH_PACK_LID]
	order.append_array(PACK_ORDER)
	for key: StringName in order:
		_set_shader_reveal(_materials.get(key) as ShaderMaterial, 0.0)
	_reveal_tween = create_tween().set_parallel(true)
	for i: int in range(order.size()):
		var key := order[i]
		_reveal_tween.tween_method(
			_tween_shader_reveal.bind(_materials.get(key) as ShaderMaterial),
			0.0, 1.0 if key == &"hands" or key == _focus_path else 0.90, reveal_time
		).set_delay(float(i) * reveal_stagger)


func _animate_reveal_out(keep_hands_moment: bool) -> void:
	_kill_reveal_tween()
	_reveal_tween = create_tween().set_parallel(true)
	for key: Variant in _materials.keys():
		var material := _materials[key] as ShaderMaterial
		var delay := 0.05 if keep_hands_moment and StringName(key) == &"hands" else 0.0
		_reveal_tween.tween_method(_tween_shader_reveal.bind(material), _get_shader_reveal(material), 0.0, hide_time).set_delay(delay)
	_reveal_tween.finished.connect(_finish_hide)


func _finish_hide() -> void:
	if not _opened and not _direct_busy:
		_set_visible_state(false)


func _refresh_focus_visuals(animate: bool) -> void:
	if _focus_tween != null and _focus_tween.is_valid():
		_focus_tween.kill()
	_focus_tween = create_tween().set_parallel(true) if animate else null
	for path: StringName in _all_paths():
		var material := _materials.get(path) as ShaderMaterial
		var slot := _slots.get(path) as Control
		var item_id := _zone_item(path)
		var active := path == _focus_path and item_id != &""
		var color := active_color if active else (empty_color if item_id == &"" else inactive_color)
		var target_scale := Vector2.ONE * (1.045 if active else 1.0)
		var target_reveal := 1.0 if active else 0.90
		if animate:
			_focus_tween.tween_method(_tween_shader_color.bind(material), _get_shader_color(material), color, focus_transition_time)
			_focus_tween.tween_method(_tween_shader_reveal.bind(material), _get_shader_reveal(material), target_reveal, focus_transition_time)
			_focus_tween.tween_property(slot, ^"scale", target_scale, focus_transition_time)
		else:
			_set_shader_color(material, color)
			_set_shader_reveal(material, target_reveal if _opened else 0.0)
			slot.scale = target_scale
	_set_shader_color(_materials.get(&"hands") as ShaderMaterial, hands_color)


func _sync_fade_directions() -> void:
	var hands_center := hands.global_position.x + hands.size.x * 0.5
	for path: StringName in _all_paths():
		var slot := _slots[path] as Control
		var material := _materials[path] as ShaderMaterial
		var icon := _icons[path] as TextureRect
		var label := _labels[path] as Label
		if slot == null or material == null or icon == null or label == null:
			continue
		var center := slot.global_position.x + slot.size.x * 0.5
		var left_of_hands := center < hands_center
		# Dense edge always faces Henry/HANDS. The icon sits on that dense patch;
		# the label extends away from Henry through the translucent tail.
		material.set_shader_parameter(SHADER_FADE_DIRECTION, 1 if left_of_hands else 0)
		_apply_pocket_side_layout(slot, icon, label, left_of_hands)


func _apply_pocket_side_layout(slot: Control, icon: TextureRect, label: Label, left_of_hands: bool) -> void:
	if left_of_hands:
		icon.position = Vector2(slot.size.x - 46.0, 11.0)
		label.position = Vector2(8.0, 6.0)
		label.size = Vector2(slot.size.x - 62.0, 48.0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	else:
		icon.position = Vector2(10.0, 11.0)
		label.position = Vector2(54.0, 6.0)
		label.size = Vector2(slot.size.x - 62.0, 48.0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT


## Tween's interpolated value is argument 1; bound material follows it.
func _tween_shader_reveal(value: float, material: ShaderMaterial) -> void:
	_set_shader_reveal(material, value)


func _tween_shader_color(value: Color, material: ShaderMaterial) -> void:
	_set_shader_color(material, value)


func _set_shader_reveal(material: ShaderMaterial, value: float) -> void:
	if material != null:
		material.set_shader_parameter(SHADER_REVEAL, value)


func _get_shader_reveal(material: ShaderMaterial) -> float:
	if material == null:
		return 0.0
	var value: Variant = material.get_shader_parameter(SHADER_REVEAL)
	return float(value) if value != null else 0.0


func _set_shader_color(material: ShaderMaterial, value: Color) -> void:
	if material != null:
		material.set_shader_parameter(SHADER_BASE_COLOR, value)


func _get_shader_color(material: ShaderMaterial) -> Color:
	if material == null:
		return inactive_color
	var value: Variant = material.get_shader_parameter(SHADER_BASE_COLOR)
	return value if value is Color else inactive_color


func _set_all_reveal(value: float) -> void:
	for material: Variant in _materials.values():
		_set_shader_reveal(material as ShaderMaterial, value)


func _kill_reveal_tween() -> void:
	if _reveal_tween != null and _reveal_tween.is_valid():
		_reveal_tween.kill()


func _set_visible_state(value: bool) -> void:
	for path: StringName in _all_paths():
		(_slots[path] as Control).visible = value and _is_shown(path)
	hands.visible = value


func _snap_all() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	_update_card_positions(camera, 0.0, true)
	_sync_fade_directions()


func _update_card_positions(camera: Camera3D, delta: float, snap: bool) -> void:
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var margin := minf(viewport_margin_px, maxf(0.0, minf(viewport_size.x, viewport_size.y) * 0.08))
	var specs := _card_specs()
	var raw_targets: Dictionary = {}
	var visible_specs: Array[Dictionary] = []

	for spec: Dictionary in specs:
		var path := StringName(spec["path"])
		var slot := spec["slot"] as Control
		var anchor := spec["anchor"] as Node3D
		if slot == null or (not _opened and not slot.visible):
			continue
		if anchor == null:
			slot.visible = false
			continue

		var projected_target: Vector2
		if camera.is_position_behind(anchor.global_position):
			if not _last_anchor_screen_positions.has(path):
				slot.visible = false
				continue
			projected_target = _last_anchor_screen_positions[path]
		else:
			var screen_offset: Vector2 = spec["offset"]
			projected_target = camera.unproject_position(anchor.global_position) - slot.size * 0.5 + screen_offset
			if path != &"hands":
				projected_target += _outward_screen_offset(anchor, camera)
			_last_anchor_screen_positions[path] = projected_target

		if _opened:
			slot.visible = true
		raw_targets[path] = projected_target
		visible_specs.append(spec)

	_stack_pack_cards(raw_targets, viewport_size, margin)
	var target_orbit_blend := 0.0
	if (_opened or _direct_busy) and raw_targets.has(&"hands"):
		var bounded_targets: Dictionary = {}
		for spec: Dictionary in visible_specs:
			var path := StringName(spec["path"])
			var slot := spec["slot"] as Control
			var projected: Vector2 = raw_targets[path]
			projected = _soft_bound_slot_position(slot, projected, viewport_size, margin, edge_blend_px)
			bounded_targets[path] = _clamp_slot_position(slot, projected, viewport_size, margin)
		## Pinned by the open pack, each card stays on its own pocket: no cross, whatever the framing.
		_cross_latched = not _pinned and _wants_cross(camera, visible_specs, bounded_targets)
		target_orbit_blend = 1.0 if _cross_latched else 0.0
	if snap:
		_orbit_blend = target_orbit_blend
	else:
		var orbit_follow := 1.0 - exp(-orbit_transition_speed * delta)
		_orbit_blend = lerpf(_orbit_blend, target_orbit_blend, orbit_follow)

	var orbit_targets: Dictionary = {}
	if _orbit_blend > 0.001 and raw_targets.has(&"hands"):
		orbit_targets = _build_orbit_targets(visible_specs, raw_targets, viewport_size, margin, camera)
	var follow_blend := 1.0 if snap else 1.0 - exp(-follow_speed * delta)
	for spec: Dictionary in visible_specs:
		var path := StringName(spec["path"])
		var slot := spec["slot"] as Control
		var target: Vector2 = raw_targets[path]
		target = _soft_bound_slot_position(slot, target, viewport_size, margin, edge_blend_px)
		## The cross is already bounded as a whole; per-card edge pushes would close it up.
		if orbit_targets.has(path):
			var orbit_target: Vector2 = orbit_targets[path]
			target = target.lerp(orbit_target, _orbit_blend)
		var next_position := target if snap else slot.position.lerp(target, follow_blend)
		slot.position = _clamp_slot_position(slot, next_position, viewport_size, margin)


## The outside-pack cards pin to anchors only centimetres apart, so in the spread they stand as one
## column (in PACK_ORDER, which never swaps mid-glide, a card plus twice ORBIT_GAP_PX apart) beside the body
## cards, on the side of the screen the pack's anchors are on, or the other side if it fits only there.
func _stack_pack_cards(targets: Dictionary, viewport_size: Vector2, margin: float) -> void:
	var stacked: Array[StringName] = []
	for path: StringName in PACK_ORDER:
		if targets.has(path):
			stacked.append(path)
	if stacked.is_empty() or not targets.has(&"hands"):
		return
	var card: Vector2 = (_slots[stacked[0]] as Control).size
	var centre := Vector2.ZERO
	for path: StringName in stacked:
		centre += (targets[path] as Vector2) + card * 0.5
	centre /= stacked.size()
	var hands_centre: Vector2 = (targets[&"hands"] as Vector2) + hands.size * 0.5
	var preferred: float = 1.0 if centre.x >= hands_centre.x else -1.0
	var step: float = card.y + ORBIT_GAP_PX * 2.0 + 2.0
	var top: float = centre.y - card.y * 0.5 - (stacked.size() - 1) * 0.5 * step
	var column := Vector2(card.x, (stacked.size() - 1) * step + card.y)
	var body: Array[Rect2] = [Rect2(targets[&"hands"] as Vector2, hands.size).grow(ORBIT_GAP_PX)]
	var outer_edge := {1.0: hands_centre.x + hands.size.x * 0.5, -1.0: hands_centre.x - hands.size.x * 0.5}
	for path: StringName in targets:
		if PACK_ORDER.has(path) or path == &"hands":
			continue
		var rect := Rect2(targets[path] as Vector2, (_slots[path] as Control).size)
		body.append(rect.grow(ORBIT_GAP_PX))
		outer_edge[1.0] = maxf(outer_edge[1.0], rect.end.x)
		outer_edge[-1.0] = minf(outer_edge[-1.0], rect.position.x)
	## Outside the body cards (pack side first), else between HANDS and them; twice the gap, the
	## clearance the cross needs before it lets go (_wants_cross).
	var clear: float = ORBIT_GAP_PX * 2.0 + 2.0
	var candidates: Array[float] = []
	for side: float in [preferred, -preferred]:
		candidates.append(outer_edge[side] + clear if side > 0.0 else outer_edge[side] - clear - card.x)
	for side: float in [preferred, -preferred]:
		candidates.append(hands_centre.x + hands.size.x * 0.5 + clear if side > 0.0 else hands_centre.x - hands.size.x * 0.5 - clear - card.x)
	var column_x: float = NAN
	for x: float in candidates:
		var rect := Rect2(Vector2(x, top), column)
		if x < margin or rect.end.x > viewport_size.x - margin:
			continue
		if body.all(func(other: Rect2) -> bool: return not rect.intersects(other)):
			column_x = x
			break
	if is_nan(column_x):
		return  # no room: they stay by their anchors, and crowding picks the cross
	for i: int in range(stacked.size()):
		targets[stacked[i]] = Vector2(column_x, top + i * step)


func _card_specs() -> Array[Dictionary]:
	var specs: Array[Dictionary] = [
		{"path": PATH_COAT_LEFT, "slot": coat_left, "anchor": coat_left_anchor, "offset": coat_left_offset},
		{"path": PATH_COAT_RIGHT, "slot": coat_right, "anchor": coat_right_anchor, "offset": coat_right_offset},
		{"path": PATH_THIGH_LEFT, "slot": thigh_left, "anchor": thigh_left_anchor, "offset": thigh_left_offset},
		{"path": PATH_PACK_LID, "slot": pack_lid, "anchor": pack_lid_anchor, "offset": pack_lid_offset},
		{"path": &"hands", "slot": hands, "anchor": hands_anchor, "offset": hands_offset},
	]
	for path: StringName in PACK_ORDER:
		if _is_shown(path):
			specs.append({"path": path, "slot": _slots[path], "anchor": _pack_anchor(path), "offset": Vector2.ZERO})
	return specs


## Spread or cross, never a mix: a partial blend of two layouts is what let cards overlap.
## Leaving the cross needs twice the clearance and a lower framing share, so it cannot flicker.
func _wants_cross(camera: Camera3D, specs: Array[Dictionary], positions: Dictionary) -> bool:
	var tight := _screen_centre_share(camera) if camera is TpsCamera else _tight_camera_factor(camera)
	var gap := ORBIT_GAP_PX * (2.0 if _cross_latched else 1.0)
	return tight > (0.35 if _cross_latched else 0.5) or _cards_crowded(specs, positions, gap)


func _cards_crowded(specs: Array[Dictionary], positions: Dictionary, gap: float) -> bool:
	for i: int in range(specs.size()):
		var path_a := StringName(specs[i]["path"])
		if not positions.has(path_a):
			continue
		var rect_a := _slot_rect(specs[i]["slot"] as Control, positions[path_a]).grow(gap * 0.5)
		for j: int in range(i + 1, specs.size()):
			var path_b := StringName(specs[j]["path"])
			if positions.has(path_b) and rect_a.intersects(_slot_rect(specs[j]["slot"] as Control, positions[path_b]).grow(gap * 0.5)):
				return true
	return false


## Tight layout: a cross round HANDS with fixed places (coats left and right, pack lid
## above, thigh below), spaced from the real card sizes so no two cards can touch.
## Its centre glides from Henry's hands to the screen centre with the camera composition.
func _build_orbit_targets(
	specs: Array[Dictionary],
	positions: Dictionary,
	viewport_size: Vector2,
	margin: float,
	camera: Camera3D
) -> Dictionary:
	var result: Dictionary = {}
	if not positions.has(&"hands"):
		return result
	var card_half := Vector2.ZERO
	for spec: Dictionary in specs:
		if StringName(spec["path"]) != &"hands":
			var slot := spec["slot"] as Control
			card_half = card_half.max(slot.size * slot.scale * 0.5)
	var hands_half := hands.size * hands.scale * 0.5
	var step_x := hands_half.x + card_half.x + ORBIT_GAP_PX
	var step_y := maxf(hands_half.y, card_half.y) + card_half.y + ORBIT_GAP_PX
	var extent := Vector2(step_x + card_half.x, step_y + card_half.y)
	var orbit_center := _slot_center(hands, positions[&"hands"]).lerp(viewport_size * 0.5, _screen_centre_share(camera))
	orbit_center.x = _clamp_center(orbit_center.x, margin + extent.x, viewport_size.x - margin - extent.x)
	orbit_center.y = _clamp_center(orbit_center.y, margin + extent.y, viewport_size.y - margin - extent.y)
	result[&"hands"] = _slot_position_for_center(hands, orbit_center)
	for spec: Dictionary in specs:
		var path := StringName(spec["path"])
		if path == &"hands" or not positions.has(path):
			continue
		var place: Vector2 = CROSS_PLACES.get(path, Vector2.ZERO)
		result[path] = _slot_position_for_center(spec["slot"] as Control, orbit_center + place * Vector2(step_x, step_y))
	return result


## 1 when the camera frames Henry in a tight space: the cards then gather at the screen centre.
func _screen_centre_share(camera: Camera3D) -> float:
	var tps := camera as TpsCamera
	return tps.get_composition() if tps != null else 0.0


func _slot_rect(slot: Control, position: Vector2) -> Rect2:
	var scaled_offset := slot.pivot_offset - slot.pivot_offset * slot.scale
	return Rect2(position + scaled_offset, slot.size * slot.scale)


func _slot_center(slot: Control, position: Vector2) -> Vector2:
	return _slot_rect(slot, position).get_center()


func _slot_position_for_center(slot: Control, center: Vector2) -> Vector2:
	var scaled_offset := slot.pivot_offset - slot.pivot_offset * slot.scale
	return center - scaled_offset - slot.size * slot.scale * 0.5


func _clamp_center(value: float, minimum: float, maximum: float) -> float:
	if maximum < minimum:
		return (minimum + maximum) * 0.5
	return clampf(value, minimum, maximum)


func _soft_bound_slot_position(
	slot: Control,
	position: Vector2,
	viewport_size: Vector2,
	margin: float,
	blend_distance: float
) -> Vector2:
	var scaled_offset := slot.pivot_offset - slot.pivot_offset * slot.scale
	var scaled_size := slot.size * slot.scale
	var minimum := Vector2(margin, margin) - scaled_offset
	var maximum := viewport_size - Vector2(margin, margin) - scaled_offset - scaled_size
	return Vector2(
		_soft_bound_axis(position.x, minimum.x, maximum.x, blend_distance),
		_soft_bound_axis(position.y, minimum.y, maximum.y, blend_distance)
	)


func _soft_bound_axis(value: float, minimum: float, maximum: float, blend_distance: float) -> float:
	if maximum <= minimum:
		return (minimum + maximum) * 0.5
	var blend := minf(blend_distance, (maximum - minimum) * 0.5)
	if blend <= 0.0:
		return clampf(value, minimum, maximum)
	var inner_min := minimum + blend
	var inner_max := maximum - blend
	var target := clampf(value, inner_min, inner_max)
	var weight := 0.0
	if value < inner_min:
		weight = 1.0 - smoothstep(minimum, inner_min, value)
	elif value > inner_max:
		weight = smoothstep(inner_max, maximum, value)
	return lerpf(value, target, weight)


func _tight_camera_factor(camera: Camera3D) -> float:
	if hands_anchor == null:
		return 0.0
	var near_distance := maxf(0.0, tight_camera_near_distance)
	var far_distance := maxf(tight_camera_far_distance, near_distance + 0.01)
	var distance := camera.global_position.distance_to(hands_anchor.global_position)
	return 1.0 - smoothstep(near_distance, far_distance, distance)


func _clamp_slot_position(slot: Control, position: Vector2, viewport_size: Vector2, margin: float) -> Vector2:
	var scaled_offset := slot.pivot_offset - slot.pivot_offset * slot.scale
	var scaled_size := slot.size * slot.scale
	var min_x := margin - scaled_offset.x
	var min_y := margin - scaled_offset.y
	var max_x := viewport_size.x - margin - scaled_offset.x - scaled_size.x
	var max_y := viewport_size.y - margin - scaled_offset.y - scaled_size.y
	return Vector2(
		_clamp_center(position.x, min_x, max_x),
		_clamp_center(position.y, min_y, max_y)
	)


func _outward_screen_offset(anchor: Node3D, camera: Camera3D) -> Vector2:
	if anchor == null or hands_anchor == null or side_spread_px <= 0.0:
		return Vector2.ZERO
	if camera.is_position_behind(hands_anchor.global_position):
		return Vector2.ZERO
	var anchor_x := camera.unproject_position(anchor.global_position).x
	var hands_x := camera.unproject_position(hands_anchor.global_position).x
	var side := signf(anchor_x - hands_x)
	if is_zero_approx(side):
		return Vector2.ZERO
	return Vector2(side * side_spread_px, 0.0)


func _make_mouse_transparent(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children():
		_make_mouse_transparent(child)
