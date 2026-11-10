class_name CompassStrip
extends Control

## Draws the First Exit tape. It reads the camera and FirstExitBearings and
## stores neither knowledge nor the active target.

const BEARINGS_SCRIPT: GDScript = preload("res://scripts/world/first_exit_bearings.gd")
const STRIP_WIDTH: float = 400.0
## Under DebugTime, which owns the top 100px. That clock is not this compass.
const TOP_MARGIN: float = 108.0
const TICK_STEP: float = TAU / 360.0 * 15.0
const SMOOTH_SEC: float = 0.08
const CARDINALS: PackedStringArray = ["N", "E", "S", "W"]
const INK: Color = Color(0.90, 0.87, 0.80, 1.0)
const OCHRE: Color = Color(0.86, 0.62, 0.28, 1.0)

var _camera: Camera3D
var _player: Node3D
var _bearings: FirstExitBearings
var _shown: float = 0.0
var _have_bearing: bool = false
var _font: Font


func on_world_ready(context: WorldContext) -> void:
	_camera = context.camera
	_player = context.player
	_bearings = context.get_system(BEARINGS_SCRIPT) as FirstExitBearings
	if _bearings == null:
		hide()
		set_process(false)
		return
	if not _bearings.bearings_changed.is_connected(queue_redraw):
		_bearings.bearings_changed.connect(queue_redraw)
	_have_bearing = false


func _process(delta: float) -> void:
	var want: float = FirstExitBearings.camera_bearing(_camera)
	if not _have_bearing:
		_shown = want
		_have_bearing = true
	else:
		var blend: float = 1.0 - exp(-delta / SMOOTH_SEC)
		_shown = lerp_angle(_shown, want, blend)
	queue_redraw()


func _draw() -> void:
	var view: Vector2 = get_viewport_rect().size
	if view.x < 32.0:
		return
	var width: float = minf(STRIP_WIDTH, view.x * 0.62)
	var origin := Vector2((view.x - width) * 0.5, TOP_MARGIN)
	var base_y: float = origin.y + 36.0
	var slot: Dictionary = {}
	if _bearings != null and _bearings.has_active_target() and _player != null:
		var from := Vector2(_player.global_position.x, _player.global_position.z)
		var rel: float = FirstExitBearings.relative_bearing(_shown, FirstExitBearings.bearing_of(from, _bearings.active_xz()))
		slot = FirstExitBearings.marker_slot(rel)
	_draw_wash(origin.x, width, origin.y - 2.0, base_y - origin.y + 6.0)
	_draw_tape(origin.x, width, base_y, slot)
	_draw_index(origin.x + width * 0.5, base_y)
	if not slot.is_empty():
		_draw_marker(origin.x, width, base_y, slot)


func _draw_wash(x: float, width: float, top: float, height: float) -> void:
	var mid: float = x + width * 0.5
	var edge := Color(0.02, 0.02, 0.018, 0.0)
	var center := Color(0.02, 0.02, 0.018, 0.28)
	var bottom: float = top + height
	draw_polygon(PackedVector2Array([
		Vector2(x, top), Vector2(mid, top), Vector2(mid, bottom), Vector2(x, bottom),
	]), PackedColorArray([edge, center, center, edge]))
	draw_polygon(PackedVector2Array([
		Vector2(mid, top), Vector2(x + width, top), Vector2(x + width, bottom), Vector2(mid, bottom),
	]), PackedColorArray([center, edge, edge, center]))


func _draw_tape(x0: float, width: float, base_y: float, slot: Dictionary) -> void:
	var half: float = FirstExitBearings.HALF_ARC_RAD
	var first: int = int(ceil((_shown - half) / TICK_STEP))
	var last: int = int(floor((_shown + half) / TICK_STEP))
	var mark_x: float = INF
	if bool(slot.get("on_strip", false)):
		mark_x = _x_of(x0, width, float(slot["u"]))
	for step: int in range(first, last + 1):
		var world: float = float(step) * TICK_STEP
		var x: float = _x_of(x0, width, (world - _shown) / half)
		var degrees: float = fposmod(rad_to_deg(world), 360.0)
		var cardinal: int = int(round(degrees / 90.0)) % 4
		var on_cardinal: bool = absf(degrees - float(cardinal) * 90.0) < 0.6 or (cardinal == 0 and degrees > 359.4)
		var on_major: bool = int(round(degrees)) % 45 == 0
		var length: float = 15.0 if on_cardinal else 8.0 if on_major else 4.0
		var ink := INK
		ink.a = 0.92 if on_cardinal else 0.50 if on_major else 0.28
		draw_line(Vector2(x, base_y - length), Vector2(x, base_y), ink, 1.0)
		if not on_cardinal or absf(x - mark_x) < 16.0:
			continue
		var letter: String = CARDINALS[cardinal]
		var at := Vector2(x - _text_width(letter, 18) * 0.5, base_y - 18.0)
		_text(letter, at, 18, INK)


func _draw_index(x: float, base_y: float) -> void:
	draw_line(Vector2(x, base_y - 22.0), Vector2(x, base_y + 3.0), Color(INK.r, INK.g, INK.b, 0.95), 1.0)


func _draw_marker(x0: float, width: float, base_y: float, slot: Dictionary) -> void:
	if bool(slot["on_strip"]):
		var x: float = _x_of(x0, width, float(slot["u"]))
		draw_circle(Vector2(x, base_y - 7.0), 2.6, OCHRE)
		var label: String = _bearings.active_label()
		_text(label, Vector2(x - _text_width(label, 14) * 0.5, base_y - 18.0), 14, OCHRE)
		return
	var edge: int = int(slot["edge"])
	var tip_x: float = x0 + 4.0 if edge < 0 else x0 + width - 4.0
	var wing: float = 7.0 if edge < 0 else -7.0
	var tip := Vector2(tip_x, base_y - 7.0)
	draw_polyline(PackedVector2Array([
		tip + Vector2(wing, -4.5), tip, tip + Vector2(wing, 4.5),
	]), OCHRE, 1.5)


func _x_of(x0: float, width: float, u: float) -> float:
	return x0 + width * 0.5 + u * width * 0.5


func _ui_font() -> Font:
	if _font == null:
		var system := SystemFont.new()
		system.font_names = PackedStringArray(["DejaVu Sans", "Liberation Sans", "sans-serif"])
		_font = system
	return _font


func _text(text: String, at: Vector2, size: int, color: Color) -> void:
	var font: Font = _ui_font()
	if font == null:
		return
	draw_string(font, at + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.45))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _text_width(text: String, size: int) -> float:
	var font: Font = _ui_font()
	if font == null:
		return 0.0
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
