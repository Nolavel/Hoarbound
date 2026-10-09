class_name PickupMarkerUI
extends Control

## One segmented ring of three equal arcs with F above it; a hold frames that F in place
## and fills the arcs top-down. A refusal is a red key and a centre ✕.

const KEY_BASE := Color(0.94, 0.84, 0.65, 1.0)
const KEY_BORDER := Color(0.77, 0.56, 0.27, 1.0)
const KEY_TEXT := Color(0.08, 0.055, 0.035, 1.0)
const DOT_COLOR := Color(1.0, 0.95, 0.82, 1.0)
## The F turns this red while a refusal ✕ shows: the press did not go through.
const REFUSAL_KEY := Color(0.86, 0.22, 0.18, 1.0)
const HAND_ICON: Texture2D = preload("res://assets/ui/hud/pickup_marker/hand_open.svg")
## Arc centres in screen angles (0 = right, clockwise): top, lower-right, lower-left.
const TOP_DEG: float = -90.0
const RIGHT_DEG: float = 30.0
const LEFT_DEG: float = 150.0
const ARC_SPAN_DEG: float = 80.0
const ARC_IDLE_ALPHA: float = 0.6
## The unfilled track during a hold; the fill is drawn over it at full strength.
const ARC_TRACK_ALPHA: float = 0.3
const REFUSAL_SECONDS: float = 0.7
## The whole ring swells once at the start of a refusal.
const PULSE_SECONDS: float = 0.3
const SUCCESS_FADE_SECONDS: float = 0.25
const ALPHA_RATE: float = 8.0
## Progress per second the fill drains at after a cancel, so nothing stale remains.
const FILL_DRAIN_RATE: float = 6.0
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
var _ring_a: float = 0.0
var _plain_f_a: float = 0.0
var _key_a: float = 0.0
var _hand_a: float = 0.0
var _fill: float = 0.0
var _refusal_left: float = 0.0
var _refusal_kind: StringName = &""
var _frozen_fill: float = 0.0
## A finished pickup fades out where it was, though the item is gone.
var _fade_left: float = 0.0
var _fade_anchor: Vector3 = Vector3.ZERO
var _fade_hands: bool = false
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
	_ease(delta)
	_refusal_left = maxf(0.0, _refusal_left - delta)
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
	var arc: float = _arc_alpha()
	return {
		"mode": _mode,
		"arc_alphas": [arc, arc, arc],
		"fill_progress": _shown_fill(),
		"fill_segments": fill_segments(_shown_fill()),
		"plain_f_alpha": _plain_f_a,
		"key_framed_alpha": _key_a,
		"hand_alpha": _hand_alpha(),
		"key_glyph_color": _key_glyph_color(),
		"refusal": _refusal_left > 0.0,
		"refusal_kind": _refusal_kind if _refusal_left > 0.0 else &"",
		"fading": _fade_left > 0.0,
		"fade_hands": _fade_left > 0.0 and _fade_hands,
		"layout": _layout(Vector2.ZERO),
	}


## Filled (start_deg, end_deg) pieces for progress 0..1, from the top-arc centre down
## both sides; gaps have no length, so the fill never stalls.
static func fill_segments(progress: float) -> Array[Vector2]:
	var pieces: Array[Vector2] = []
	var half: float = ARC_SPAN_DEG * 0.5
	var side: float = clampf(progress, 0.0, 1.0) * ARC_SPAN_DEG * 1.5
	var top_len: float = minf(side, half)
	var low_len: float = clampf(side - half, 0.0, ARC_SPAN_DEG)
	if top_len > 0.0:
		pieces.append(Vector2(TOP_DEG, TOP_DEG + top_len))
		pieces.append(Vector2(TOP_DEG - top_len, TOP_DEG))
	if low_len > 0.0:
		var right_top: float = RIGHT_DEG - half
		var left_top: float = LEFT_DEG + half
		pieces.append(Vector2(right_top, right_top + low_len))
		pieces.append(Vector2(left_top - low_len, left_top))
	return pieces


## The three arcs as (start_deg, end_deg), in the same order as arc_alphas.
static func arc_ranges() -> Array[Vector2]:
	var half: float = ARC_SPAN_DEG * 0.5
	return [Vector2(TOP_DEG - half, TOP_DEG + half), Vector2(RIGHT_DEG - half, RIGHT_DEG + half),
		Vector2(LEFT_DEG - half, LEFT_DEG + half)]


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
		## A new pickup never inherits the last one's hold; a success fade draws its own copy.
		_key_a = 0.0
		_hand_a = 0.0
		_fill = 0.0
		if target != null:
			_from = _anchor if glide else _focus(target)
			_transfer_left = transfer_seconds if glide else 0.0
	if _target != null:
		_transfer_left = maxf(0.0, _transfer_left - delta)
		var t: float = 1.0 - (_transfer_left / transfer_seconds if transfer_seconds > 0.0 else 0.0)
		_anchor = _from.lerp(_focus(_target), smoothstep(0.0, 1.0, t))


func _ease(delta: float) -> void:
	var step: float = ALPHA_RATE * delta
	var holding: bool = _mode == &"hold"
	var ring: bool = holding or _mode == &"idle"
	var hold_refused: bool = _refusal_left > 0.0 and _refusal_kind == &"hold"
	_ring_a = move_toward(_ring_a, (ARC_TRACK_ALPHA if holding else ARC_IDLE_ALPHA) if ring else 0.0, step)
	_plain_f_a = move_toward(_plain_f_a, 1.0 if _mode == &"idle" else 0.0, step)
	_key_a = 1.0 if hold_refused else move_toward(_key_a, 1.0 if holding else 0.0, step)
	_hand_a = move_toward(_hand_a, 1.0 if holding else 0.0, step)
	if holding:
		_fill = _interact.get_gesture_progress()
	else:
		_fill = move_toward(_fill, 0.0, FILL_DRAIN_RATE * delta)


## The fill a hold refusal froze stays until its ✕ fades; otherwise the live fill.
func _shown_fill() -> float:
	if _refusal_left > 0.0 and _refusal_kind == &"hold":
		return _frozen_fill
	return _fill


## One alpha for all three arcs, swelling briefly at the start of a refusal.
func _arc_alpha() -> float:
	var since: float = REFUSAL_SECONDS - _refusal_left
	if _refusal_left <= 0.0 or since >= PULSE_SECONDS:
		return _ring_a
	return lerpf(_ring_a, 1.0, sin(PI * since / PULSE_SECONDS))


func _refusal_strength() -> float:
	return _refusal_left / REFUSAL_SECONDS


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


## Three equal arcs, the top-down fill over them, then the one F at its fixed spot.
func _draw_ring(centre: Vector2) -> void:
	var layout: Dictionary = _layout(centre)
	var arc: float = _arc_alpha()
	for span: Vector2 in arc_ranges():
		_arc(centre, span, arc)
	for piece: Vector2 in fill_segments(_shown_fill()):
		_arc(centre, piece, 1.0)
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
	for span: Vector2 in arc_ranges():
		_arc(centre, span, a if _fade_hands else a * ARC_IDLE_ALPHA)
	if _fade_hands:
		draw_texture_rect(HAND_ICON, _layout(centre)["hand_rect"], false, Color(DOT_COLOR, a))


func _arc(centre: Vector2, span: Vector2, alpha: float) -> void:
	if alpha <= 0.005 or span.y - span.x <= 0.1:
		return
	draw_arc(centre, ring_radius_px, deg_to_rad(span.x), deg_to_rad(span.y), 24, Color(DOT_COLOR, alpha), arc_width_px, true)


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
			_fade_hands = result == &"hands"
			_fade_anchor = _anchor if target == _target or not is_instance_valid(target) else _focus(target)
			_fill = 0.0
		&"refused_storage":
			_refuse(&"tap")
		&"refused_hands":
			_refuse(&"hold")
	refresh()


func _refuse(kind: StringName) -> void:
	_refusal_kind = kind
	_refusal_left = REFUSAL_SECONDS
	_frozen_fill = _fill
	if kind == &"hold":
		_key_a = 1.0
