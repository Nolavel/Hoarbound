class_name QuickAccessUI
extends Control

## Physical quick access around Henry. Four outer cards are real worn pockets.
## HANDS is live held-state status and is deliberately never selectable.

const QUICK_NEXT: StringName = &"quick_next"
const QUICK_PREV: StringName = &"quick_prev"
const QUICK_USE: StringName = &"quick_use"
const DIRECT_ACTIONS: Array[StringName] = [
	&"select item slot 1", &"select item slot 2", &"select item slot 3", &"select item slot 4"
]

const PATH_COAT_LEFT: StringName = &"torso_outer/coat_left"
const PATH_COAT_RIGHT: StringName = &"torso_outer/coat_right"
const PATH_THIGH_LEFT: StringName = &"legs_outer/thigh_left"
const PATH_PACK_LID: StringName = &"pack/pack_lid"
const POCKET_ORDER: Array[StringName] = [PATH_COAT_LEFT, PATH_COAT_RIGHT, PATH_PACK_LID, PATH_THIGH_LEFT]

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
@export_range(1.0, 40.0, 0.5) var follow_speed := 18.0
## Extra screen-space separation for the four side cards. The sign is derived
## from their projected position, so orbiting Henry keeps the cards moving outwards.
@export_range(0.0, 80.0, 1.0) var side_spread_px := 26.0
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
var _direct_busy := false
var _refresh_left := 0.0
var _reveal_tween: Tween
var _focus_tween: Tween
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
	_prepare_materials()
	_load_icons()
	_configure_layout()
	_set_all_reveal(0.0)
	_set_visible_state(false)
	call_deferred(&"_initial_setup")


func _initial_setup() -> void:
	_snap_all()
	_refresh_content()


func is_open() -> bool:
	return _opened


func show_quick_access() -> void:
	if _opened or _direct_busy or not _can_open():
		return
	_opened = true
	_sync_focus_on_open()
	_refresh_content()
	_set_visible_state(true)
	_snap_all()
	_hold_orbit(0.12)
	_refresh_focus_visuals(false)
	_animate_reveal_in()


func cancel() -> void:
	if not _opened:
		return
	_opened = false
	_animate_reveal_out(false)


func navigate_next() -> void:
	if _opened:
		_move_focus(1)


func navigate_previous() -> void:
	if _opened:
		_move_focus(-1)


func confirm_current() -> void:
	if _opened and _focus_path != &"":
		_confirm_path(_focus_path)


func direct_draw_slot(slot_number: int) -> void:
	if slot_number < 1 or slot_number > POCKET_ORDER.size() or _opened or _direct_busy or not _can_open():
		return
	_direct_draw_path(POCKET_ORDER[slot_number - 1])


func _input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
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
	if not _opened and not _direct_busy:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	_follow(coat_left, coat_left_anchor, coat_left_offset, camera, delta)
	_follow(coat_right, coat_right_anchor, coat_right_offset, camera, delta)
	_follow(thigh_left, thigh_left_anchor, thigh_left_offset, camera, delta)
	_follow(pack_lid, pack_lid_anchor, pack_lid_offset, camera, delta)
	_follow(hands, hands_anchor, hands_offset, camera, delta)
	_sync_fade_directions()
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = 0.12
		_refresh_content()
		if _opened and _focus_path != &"" and _zone_item(_focus_path) == &"":
			_sync_focus_on_open()
			_refresh_focus_visuals(true)


func _resolve_component() -> void:
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


func _prepare_materials() -> void:
	_materials = {
		PATH_COAT_LEFT: _duplicate_material(coat_left_background),
		PATH_COAT_RIGHT: _duplicate_material(coat_right_background),
		PATH_THIGH_LEFT: _duplicate_material(thigh_left_background),
		PATH_PACK_LID: _duplicate_material(pack_lid_background),
		&"hands": _duplicate_material(hands_background),
	}
	# Pockets are graphic bars, not pills. HANDS deliberately keeps its softer
	# prompt-like silhouette and centred fade.
	for path: StringName in POCKET_ORDER:
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
	for path: StringName in POCKET_ORDER:
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
	for path: StringName in POCKET_ORDER:
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
	for path: StringName in POCKET_ORDER:
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
	for zone: Dictionary in quick_access_component.hub.get_quick_access_zones():
		var path := StringName(zone["path"])
		if POCKET_ORDER.has(path) and StringName(zone["item_id"]) != &"":
			result.append(path)
	return result


func _zone(path: StringName) -> Dictionary:
	if quick_access_component == null or quick_access_component.hub == null:
		return {}
	for zone: Dictionary in quick_access_component.hub.get_quick_access_zones():
		if StringName(zone["path"]) == path:
			return zone
	return {}


func _zone_item(path: StringName) -> StringName:
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
	for path: StringName in POCKET_ORDER:
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
	return _icon_backpack if path == PATH_PACK_LID else _icon_apparel


func _icon_for_item(item_id: StringName) -> Texture2D:
	var text := String(item_id)
	if text.begins_with("water_flask"):
		return _icon_water
	if item_id in [&"lighter", &"tinder", &"road_flare"]:
		return _icon_fire
	if item_id in [&"tinned_stew", &"tinned_pineapple", &"opened_pineapple", &"empty_tin"]:
		return _icon_food
	return _icon_generic


func _confirm_path(path: StringName) -> void:
	if not _opened or _zone_item(path) == &"":
		_pulse_denied(path)
		return
	_opened = false
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
	var player := _player()
	if player != null:
		for child: Node in player.get_children():
			if child.has_method(&"put_away_unlit") and bool(child.call(&"put_away_unlit")):
				break
	quick_access_component.select(index)
	return quick_access_component.use_selected()


func _direct_draw_path(path: StringName) -> void:
	if _zone_item(path) == &"":
		return
	_direct_busy = true
	_focus_path = path
	_refresh_content()
	_set_visible_state(false)
	hands.visible = true
	(_slots[path] as Control).visible = true
	_snap_all()
	_hold_orbit(0.10)
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
	for path: StringName in POCKET_ORDER:
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
	for path: StringName in POCKET_ORDER:
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
	coat_left.visible = value
	coat_right.visible = value
	thigh_left.visible = value
	pack_lid.visible = value
	hands.visible = value


func _follow(slot: Control, anchor: Node3D, screen_offset: Vector2, camera: Camera3D, delta: float) -> void:
	if anchor == null or camera.is_position_behind(anchor.global_position):
		slot.visible = false
		return
	if _opened:
		slot.visible = true
	var target := camera.unproject_position(anchor.global_position) - slot.size * 0.5 + screen_offset
	if slot != hands:
		target += _outward_screen_offset(anchor, camera)
	slot.position = slot.position.lerp(target, 1.0 - exp(-follow_speed * delta))


func _snap_all() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	_snap(coat_left, coat_left_anchor, coat_left_offset, camera)
	_snap(coat_right, coat_right_anchor, coat_right_offset, camera)
	_snap(thigh_left, thigh_left_anchor, thigh_left_offset, camera)
	_snap(pack_lid, pack_lid_anchor, pack_lid_offset, camera)
	_snap(hands, hands_anchor, hands_offset, camera)
	_sync_fade_directions()


func _snap(slot: Control, anchor: Node3D, screen_offset: Vector2, camera: Camera3D) -> void:
	if anchor != null and not camera.is_position_behind(anchor.global_position):
		var target := camera.unproject_position(anchor.global_position) - slot.size * 0.5 + screen_offset
		if slot != hands:
			target += _outward_screen_offset(anchor, camera)
		slot.position = target


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


func _hold_orbit(seconds: float) -> void:
	if _anchors() != null and _anchors().has_method(&"hold_for"):
		_anchors().call(&"hold_for", seconds)


func _anchors() -> Node:
	if coat_left_anchor != null:
		return coat_left_anchor.get_parent()
	return null


func _make_mouse_transparent(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children():
		_make_mouse_transparent(child)
