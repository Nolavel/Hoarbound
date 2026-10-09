class_name PickupMarkerUI
extends Control

## Ordinary pickups: one compact [F] keycap over the pickup F would take, faint dots
## over the others Henry notices. Never the central prompt, never the camera.

const KEY_BASE := Color(0.94, 0.84, 0.65, 1.0)
const KEY_BORDER := Color(0.77, 0.56, 0.27, 1.0)
const KEY_TEXT := Color(0.08, 0.055, 0.035, 1.0)
const DOT_COLOR := Color(1.0, 0.95, 0.82, 1.0)

@export_group("Keycap")
## Keycap edge in screen pixels; constant at any distance.
@export var key_size: float = 24.0
## Keycap centre above the item's focus point, screen pixels.
@export var lift_px: float = 26.0
## Seconds the keycap glides from one pickup to the next.
@export var transfer_seconds: float = 0.12

@export_group("Hints")
## Radius of the faint dot over noticed pickups, screen pixels.
@export var hint_radius_px: float = 3.0
## Opacity of the faint dots.
@export var hint_alpha: float = 0.35

var _interact: InteractComponent
var _target: InteractiveArea = null
var _anchor: Vector3 = Vector3.ZERO
var _from: Vector3 = Vector3.ZERO
var _transfer_left: float = 0.0
var _key_shown: bool = false
var _font: Font
var _key_style: StyleBoxFlat


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var player: Node = get_parent()
	if player != null:
		_interact = player.get_node_or_null(^"InteractComponent") as InteractComponent
	if _interact != null:
		_interact.interaction_performed.connect(_on_interaction_performed)
	_key_style = StyleBoxFlat.new()
	_key_style.bg_color = KEY_BASE
	_key_style.border_color = KEY_BORDER
	_key_style.set_border_width_all(2)
	_key_style.set_corner_radius_all(5)
	var font := SystemFont.new()
	font.font_names = ["Consolas", "Courier New", "DejaVu Sans Mono", "monospace"]
	_font = font


func _process(delta: float) -> void:
	var state: Node = get_node_or_null(^"/root/PlayerState")
	visible = state == null or not bool(state.call(&"is_paused"))
	refresh(delta)


## Follows the dominant pickup; the keycap glides between neighbours, never jumps.
func refresh(delta: float = 0.0) -> void:
	## A committed F keeps the keycap on the item Henry is walking to.
	var committed: InteractiveArea = _interact.get_committed_target() if _interact != null else null
	var target: InteractiveArea = committed if committed != null else (_interact.get_pickup_target() if _interact != null else null)
	if target != _target:
		var glide: bool = _target != null and target != null and is_instance_valid(_target)
		_target = target
		if target != null:
			_from = _anchor if glide else _focus(target)
			_transfer_left = transfer_seconds if glide else 0.0
	if _target != null:
		_transfer_left = maxf(0.0, _transfer_left - delta)
		var t: float = 1.0 - (_transfer_left / transfer_seconds if transfer_seconds > 0.0 else 0.0)
		_anchor = _from.lerp(_focus(_target), smoothstep(0.0, 1.0, t))
	_key_shown = _target != null and (committed != null or _interact.is_pickup_actionable())
	queue_redraw()


## The pickup carrying the keycap, or null.
func get_marked_target() -> InteractiveArea:
	return _target


## True while the [F] keycap promises a pickup.
func is_key_shown() -> bool:
	return _key_shown


func _focus(area: InteractiveArea) -> Vector3:
	return area.get_focus_point(_interact.get_attention_origin())


func _draw() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or _interact == null:
		return
	for area: InteractiveArea in _interact.get_pickup_candidates():
		var point: Vector3 = _focus(area)
		if not camera.is_position_behind(point):
			draw_circle(camera.unproject_position(point), hint_radius_px, Color(DOT_COLOR, hint_alpha))
	if _target == null or camera.is_position_behind(_anchor):
		return
	var at: Vector2 = camera.unproject_position(_anchor)
	if not _key_shown:
		draw_circle(at, hint_radius_px * 1.4, Color(DOT_COLOR, minf(1.0, hint_alpha * 1.8)))
		return
	var rect := Rect2(at - Vector2(key_size * 0.5, key_size * 0.5 + lift_px), Vector2(key_size, key_size))
	draw_rect(Rect2(rect.position + Vector2(0.0, 2.0), rect.size), Color(0.16, 0.10, 0.055, 0.7), true)
	draw_style_box(_key_style, rect)
	var key: String = InteractiveArea._interact_key_label()
	var font_size: int = int(key_size * 0.62)
	var width: float = _font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(_font, Vector2(rect.position.x + (key_size - width) * 0.5, rect.position.y + key_size * 0.72),
		key, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, KEY_TEXT)


## A consumed pickup loses its keycap in the same frame.
func _on_interaction_performed(_target_area: InteractiveArea) -> void:
	refresh()
