extends Node

## Small presentation layer for Quick Access focus. The selector already owns
## world-to-screen following; this node only biases its exported screen offsets
## so the active pocket eases a little toward Henry and the previous pocket
## returns to its authored position.

@export_range(0.0, 40.0, 1.0) var focus_pull_px: float = 14.0
@export_range(1.0, 30.0, 0.5) var focus_motion_speed: float = 13.0

const EMPTY_ICON_PATH := "res://assets/ui/hud/quick_access/icons/empty_circle.svg"
const PATH_COAT_LEFT: StringName = &"torso_outer/coat_left"
const PATH_COAT_RIGHT: StringName = &"torso_outer/coat_right"
const PATH_THIGH_LEFT: StringName = &"legs_outer/thigh_left"
const PATH_PACK_LID: StringName = &"pack/pack_lid"
const POCKET_ORDER: Array[StringName] = [PATH_COAT_LEFT, PATH_COAT_RIGHT, PATH_PACK_LID, PATH_THIGH_LEFT]

var _ui: QuickAccessUI
var _base_offsets: Dictionary = {}
var _empty_circle: Texture2D


func _ready() -> void:
	_ui = get_parent() as QuickAccessUI
	if _ui == null:
		set_process(false)
		return
	_base_offsets = {
		PATH_COAT_LEFT: _ui.coat_left_offset,
		PATH_COAT_RIGHT: _ui.coat_right_offset,
		PATH_THIGH_LEFT: _ui.thigh_left_offset,
		PATH_PACK_LID: _ui.pack_lid_offset,
	}
	_empty_circle = load(EMPTY_ICON_PATH) as Texture2D


func _process(delta: float) -> void:
	if _ui == null:
		return
	var focus := StringName(_ui.get("_focus_path"))
	var selector_active := bool(_ui.get("_opened")) or bool(_ui.get("_direct_busy"))
	var blend := 1.0 - exp(-focus_motion_speed * maxf(delta, 0.0))
	for path: StringName in POCKET_ORDER:
		var base := _base_offsets[path] as Vector2
		var target := base
		if selector_active and path == focus:
			target.x += _toward_henry_sign(path) * focus_pull_px
		_set_offset(path, _get_offset(path).lerp(target, blend))
		_apply_empty_icon(path)


func _toward_henry_sign(path: StringName) -> float:
	var slot := _slot(path)
	var hands := _ui.get_node_or_null(^"Hands") as Control
	if slot == null or hands == null:
		return 0.0
	var slot_center := slot.global_position.x + slot.size.x * 0.5
	var hands_center := hands.global_position.x + hands.size.x * 0.5
	return signf(hands_center - slot_center)


func _apply_empty_icon(path: StringName) -> void:
	if _empty_circle == null:
		return
	var item_id := StringName(_ui.call("_zone_item", path))
	if item_id != &"":
		return
	var icon := _icon(path)
	if icon != null:
		icon.texture = _empty_circle
		icon.modulate = Color(0.72, 0.74, 0.76, 0.72)


func _slot(path: StringName) -> Control:
	match path:
		PATH_COAT_LEFT: return _ui.get_node_or_null(^"CoatLeft") as Control
		PATH_COAT_RIGHT: return _ui.get_node_or_null(^"CoatRight") as Control
		PATH_THIGH_LEFT: return _ui.get_node_or_null(^"ThighLeft") as Control
		PATH_PACK_LID: return _ui.get_node_or_null(^"PackLid") as Control
	return null


func _icon(path: StringName) -> TextureRect:
	var slot := _slot(path)
	return slot.get_node_or_null(^"Icon") as TextureRect if slot != null else null


func _get_offset(path: StringName) -> Vector2:
	match path:
		PATH_COAT_LEFT: return _ui.coat_left_offset
		PATH_COAT_RIGHT: return _ui.coat_right_offset
		PATH_THIGH_LEFT: return _ui.thigh_left_offset
		PATH_PACK_LID: return _ui.pack_lid_offset
	return Vector2.ZERO


func _set_offset(path: StringName, value: Vector2) -> void:
	match path:
		PATH_COAT_LEFT: _ui.coat_left_offset = value
		PATH_COAT_RIGHT: _ui.coat_right_offset = value
		PATH_THIGH_LEFT: _ui.thigh_left_offset = value
		PATH_PACK_LID: _ui.pack_lid_offset = value
