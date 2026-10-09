class_name PickupMarkerUI
extends Control

## Ordinary pickups: a three-arc ring over the pickup F would take. Top arc + F =
## tap to store it; lower-left = hold to take it into the hands, growing into a full
## circle, while the same F gains its frame in place. A refusal is one ✕ in the ring
## centre; the right (storage) or left (hands) arc lights to name the cause. Armfuls
## keep the compact [F] keycap. Never the central prompt, never the camera.

const KEY_BASE := Color(0.94, 0.84, 0.65, 1.0)
const KEY_BORDER := Color(0.77, 0.56, 0.27, 1.0)
const KEY_TEXT := Color(0.08, 0.055, 0.035, 1.0)
const DOT_COLOR := Color(1.0, 0.95, 0.82, 1.0)
## The F turns this red while a refusal ✕ shows: the press did not go through.
const REFUSAL_KEY := Color(0.86, 0.22, 0.18, 1.0)
const HAND_ICON: Texture2D = preload("res://assets/ui/hud/pickup_marker/hand_open.svg")
## Arc centres in screen angles (0 = right, clockwise): top, lower-left, lower-right.
const TOP_DEG: float = -90.0
const LEFT_DEG: float = 150.0
const RIGHT_DEG: float = 30.0
const ARC_SPAN_DEG: float = 80.0
## The refusal arc sits almost in the background so three arcs never read as three actions.
## Set to 0 to hide it until a refusal if a playtest still reads it as a command.
const RIGHT_ARC_IDLE_ALPHA: float = 0.12
const TOP_ARC_ALPHA: float = 0.9
const LEFT_ARC_IDLE_ALPHA: float = 0.5
const REFUSAL_SECONDS: float = 0.7
const SUCCESS_FADE_SECONDS: float = 0.25
## Per-second rates the ring's pieces ease at; the collapse after a cancel uses SPAN_RATE.
const ALPHA_RATE: float = 8.0
const SPAN_RATE_DEG: float = 900.0
## Gap between the ring line and the keycap's lower edge; the F glyph never moves.
const KEY_GAP_PX: float = 4.0
const KEY_GLYPH_PX: int = 13
const CROSS_HALF_PX: float = 5.0

@export_group("Ring")
## Ring radius and line width in screen pixels; constant at any distance.
@export var ring_radius_px: float = 15.0
@export var arc_width_px: float = 2.4
## Ring centre above the item's focus point, screen pixels.
@export var lift_px: float = 30.0
## Seconds the ring glides from one pickup to the next.
@export var transfer_seconds: float = 0.12

@export_group("Keycap")
## Keycap edge for armfuls and the hold [F], screen pixels.
@export var key_size: float = 20.0

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
var _mode: StringName = &"none"
var _can_hold: bool = false
var _top_a: float = 0.0
var _left_a: float = 0.0
var _right_a: float = 0.0
var _plain_f_a: float = 0.0
var _key_a: float = 0.0
var _hand_a: float = 0.0
var _span_deg: float = ARC_SPAN_DEG
var _refuse_right: float = 0.0
var _refuse_left: float = 0.0
## A finished pickup fades out where it was, though the item is gone.
var _fade_left: float = 0.0
var _fade_anchor: Vector3 = Vector3.ZERO
var _fade_full: bool = false
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
		_interact.pickup_gesture_finished.connect(_on_gesture_finished)
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


## Follows the gesture or the dominant pickup and eases every piece toward its state.
func refresh(delta: float = 0.0) -> void:
	if _interact == null:
		return
	var gesture: InteractiveArea = _interact.get_gesture_target()
	var committed: InteractiveArea = _interact.get_committed_target()
	var target: InteractiveArea = gesture if gesture != null else committed
	if target == null:
		target = _interact.get_pickup_target()
	_follow(target, delta)
	_mode = _mode_for(target, gesture != null or committed != null)
	_can_hold = target != null and _interact.can_hold_pickup(target)
	var holding: bool = _mode == &"hold"
	var idle: bool = _mode == &"idle"
	_ease(delta, idle, holding)
	_refuse_right = maxf(0.0, _refuse_right - delta)
	_refuse_left = maxf(0.0, _refuse_left - delta)
	_fade_left = maxf(0.0, _fade_left - delta)
	queue_redraw()


## The pickup carrying the ring, or null.
func get_marked_target() -> InteractiveArea:
	return _target


## True while the marker promises F on its pickup: the ring for items, the keycap for armfuls.
func is_key_shown() -> bool:
	return _mode in [&"idle", &"hold", &"carry"]


## What the marker shows now, for tests and captures.
func get_visual_state() -> Dictionary:
	return {
		"mode": _mode,
		"top_alpha": _top_a,
		"left_alpha": _left_alpha(),
		"right_alpha": _right_alpha(),
		"plain_f_alpha": _plain_f_a,
		"key_framed_alpha": _key_a,
		"hand_alpha": _hand_alpha(),
		"left_span_deg": _span_deg,
		"refusal_right": _refuse_right > 0.0,
		"refusal_left": _refuse_left > 0.0,
		"fading": _fade_left > 0.0,
		"layout": _layout(Vector2.ZERO),
		"key_glyph_color": _key_glyph_color(),
	}


func _mode_for(target: InteractiveArea, owned_by_gesture: bool) -> StringName:
	if target == null:
		return &"none"
	if not owned_by_gesture and not _interact.is_pickup_actionable():
		return &"dot"
	if not _interact.can_hold_pickup(target) and not _uses_ring(target):
		return &"carry"
	return &"hold" if _interact.get_gesture_target() == target and _interact.is_gesture_holding() else &"idle"


func _uses_ring(target: InteractiveArea) -> bool:
	var pickup := target as ItemPickup
	var item: ItemResource = ItemCatalog.get_item(pickup.item_id) if pickup != null else null
	return item != null and not item.carried_in_hands


func _follow(target: InteractiveArea, delta: float) -> void:
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


func _ease(delta: float, idle: bool, holding: bool) -> void:
	var step: float = ALPHA_RATE * delta
	_top_a = move_toward(_top_a, TOP_ARC_ALPHA if idle else 0.0, step)
	_plain_f_a = move_toward(_plain_f_a, 1.0 if idle else 0.0, step)
	_right_a = move_toward(_right_a, RIGHT_ARC_IDLE_ALPHA if idle else 0.0, step)
	var left_goal: float = 1.0 if holding else (LEFT_ARC_IDLE_ALPHA if idle and _can_hold else 0.0)
	_left_a = move_toward(_left_a, left_goal, step)
	_key_a = move_toward(_key_a, 1.0 if holding else 0.0, step)
	_hand_a = move_toward(_hand_a, 1.0 if holding else 0.0, step)
	if holding:
		_span_deg = lerpf(ARC_SPAN_DEG, 360.0, _interact.get_gesture_progress())
	else:
		_span_deg = move_toward(_span_deg, ARC_SPAN_DEG, SPAN_RATE_DEG * delta)


## A storage refusal brightens the background arc and fades back to it.
func _right_alpha() -> float:
	return maxf(_right_a, _refuse_right / REFUSAL_SECONDS)


## A hold refusal lights the hands arc the same way.
func _left_alpha() -> float:
	return maxf(_left_a, _refuse_left / REFUSAL_SECONDS)


func _refusal_strength() -> float:
	return maxf(_refuse_right, _refuse_left) / REFUSAL_SECONDS


## The hand yields the centre to a refusal ✕.
func _hand_alpha() -> float:
	return _hand_a * (1.0 - _refusal_strength())


## Cream bare F, dark on the frame, red while a refusal shows.
func _key_glyph_color() -> Color:
	var refusal: float = _refusal_strength()
	var rgb: Color = DOT_COLOR.lerp(KEY_TEXT, _key_a).lerp(REFUSAL_KEY, refusal)
	return Color(rgb, maxf(maxf(_plain_f_a, _key_a), refusal))


## Where each piece sits around a ring centre; the draw and the tests share it.
func _layout(centre: Vector2) -> Dictionary:
	var key_point: Vector2 = centre + Vector2(0.0, -(ring_radius_px + KEY_GAP_PX + key_size * 0.5))
	var icon: float = ring_radius_px * 1.15
	return {
		"key_point": key_point,
		"key_rect": Rect2(key_point - Vector2(key_size, key_size) * 0.5, Vector2(key_size, key_size)),
		"hand_rect": Rect2(centre - Vector2(icon, icon) * 0.5, Vector2(icon, icon)),
		"cross_point": centre,
	}


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
	if _fade_left > 0.0 and not camera.is_position_behind(_fade_anchor):
		_draw_success_fade(camera.unproject_position(_fade_anchor) - Vector2(0.0, lift_px))
	if _target == null or camera.is_position_behind(_anchor):
		return
	var at: Vector2 = camera.unproject_position(_anchor)
	match _mode:
		&"dot":
			draw_circle(at, hint_radius_px * 1.4, Color(DOT_COLOR, minf(1.0, hint_alpha * 1.8)))
		&"carry":
			var point: Vector2 = at - Vector2(0.0, lift_px)
			_draw_key_frame(Rect2(point - Vector2(key_size, key_size) * 0.5, Vector2(key_size, key_size)), 1.0)
			_draw_key_glyph(point, KEY_TEXT)
		_:
			_draw_ring(at - Vector2(0.0, lift_px))


## One F glyph at one spot: idle shows it bare, hold fades its frame in around it.
func _draw_ring(centre: Vector2) -> void:
	var layout: Dictionary = _layout(centre)
	_arc(centre, TOP_DEG, ARC_SPAN_DEG, _top_a)
	_arc(centre, RIGHT_DEG, ARC_SPAN_DEG, _right_alpha())
	_arc(centre, LEFT_DEG, _span_deg, _left_alpha())
	if _key_a > 0.01:
		_draw_key_frame(layout["key_rect"], _key_a)
	var glyph: Color = _key_glyph_color()
	if glyph.a > 0.01:
		_draw_key_glyph(layout["key_point"], glyph)
	var hand_a: float = _hand_alpha()
	if hand_a > 0.01:
		draw_texture_rect(HAND_ICON, layout["hand_rect"], false, Color(DOT_COLOR, hand_a))
	var refusal: float = _refusal_strength()
	if refusal > 0.0:
		_draw_cross(layout["cross_point"], refusal)


func _draw_success_fade(centre: Vector2) -> void:
	var a: float = _fade_left / SUCCESS_FADE_SECONDS
	if _fade_full:
		_arc(centre, LEFT_DEG, 360.0, a)
		draw_texture_rect(HAND_ICON, _layout(centre)["hand_rect"], false, Color(DOT_COLOR, a))
	else:
		_arc(centre, TOP_DEG, ARC_SPAN_DEG, a * TOP_ARC_ALPHA)


func _arc(centre: Vector2, mid_deg: float, span_deg: float, alpha: float) -> void:
	if alpha <= 0.005 or span_deg <= 0.5:
		return
	var half: float = deg_to_rad(minf(span_deg, 360.0) * 0.5)
	var mid: float = deg_to_rad(mid_deg)
	draw_arc(centre, ring_radius_px, mid - half, mid + half, 40, Color(DOT_COLOR, alpha), arc_width_px, true)


func _draw_key_frame(rect: Rect2, alpha: float) -> void:
	draw_rect(Rect2(rect.position + Vector2(0.0, 2.0), rect.size), Color(0.16, 0.10, 0.055, 0.7 * alpha), true)
	_key_style.bg_color = Color(KEY_BASE, alpha)
	_key_style.border_color = Color(KEY_BORDER, alpha)
	draw_style_box(_key_style, rect)


## The key label centred on point, one size for the bare F and the framed [F].
func _draw_key_glyph(point: Vector2, colour: Color) -> void:
	var key: String = InteractiveArea._interact_key_label()
	var width: float = _font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, KEY_GLYPH_PX).x
	var baseline: float = point.y + (_font.get_ascent(KEY_GLYPH_PX) - _font.get_descent(KEY_GLYPH_PX)) * 0.5
	draw_string(_font, Vector2(point.x - width * 0.5, baseline), key, HORIZONTAL_ALIGNMENT_LEFT, -1, KEY_GLYPH_PX, colour)


func _draw_cross(at: Vector2, alpha: float) -> void:
	var r: float = CROSS_HALF_PX
	var colour := Color(DOT_COLOR, clampf(alpha * 1.2, 0.0, 1.0))
	draw_line(at + Vector2(-r, -r), at + Vector2(r, r), colour, 2.2, true)
	draw_line(at + Vector2(-r, r), at + Vector2(r, -r), colour, 2.2, true)


## A consumed pickup loses its live ring in the same frame.
func _on_interaction_performed(_target_area: InteractiveArea) -> void:
	refresh()


func _on_gesture_finished(target: InteractiveArea, result: StringName) -> void:
	match result:
		&"stored", &"hands":
			_fade_left = SUCCESS_FADE_SECONDS
			_fade_full = result == &"hands"
			_fade_anchor = _anchor if target == _target or not is_instance_valid(target) else _focus(target)
		&"refused_storage":
			_refuse_right = REFUSAL_SECONDS
		&"refused_hands":
			_refuse_left = REFUSAL_SECONDS
	refresh()
