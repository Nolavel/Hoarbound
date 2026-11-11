class_name CompassStrip
extends Control

## Draws the First Exit tape. It reads the camera and FirstExitBearings and
## stores neither knowledge nor the active target.

const BEARINGS_SCRIPT: GDScript = preload("res://scripts/world/first_exit_bearings.gd")
const STRIP_WIDTH: float = 400.0
const TOP_MARGIN: float = 16.0
const TICK_STEP: float = TAU / 360.0 * 15.0
const SMOOTH_SEC: float = 0.08
const CARDINALS: PackedStringArray = ["N", "E", "S", "W"]
## Contrast tested against white snow and the dim 727 interior: warm, not blue.
const INK: Color = Color(0.95, 0.92, 0.86, 1.0)
const OCHRE: Color = Color(0.87, 0.57, 0.20, 1.0)
const COLD_COLOR: Color = Color(0.537, 0.600, 0.627, 1.0) #8999A0
const WARM_COLOR: Color = Color(0.788, 0.627, 0.373, 1.0) #C9A05F
const HOT_COLOR: Color = Color(0.871, 0.475, 0.314, 1.0) #DE7950
const MARKER_SMOOTH_SEC: float = 0.22
const MARKER_MAX_LAG_RAD: float = PI * 8.0 / 180.0
const REAR_LOCK_RAD: float = PI * 8.0 / 180.0
const COLOR_SMOOTH_SEC: float = 0.5
const PULSE_DURATION_SEC: float = 0.65

var _camera: Camera3D
var _player: Node3D
var _bearings: FirstExitBearings
var _shown: float = 0.0
var _have_bearing: bool = false
var _font: Font
var _marker_rel: float = 0.0
var _have_marker: bool = false
var _marker_target_id: String = ""
var _rear_edge: int = 0
var _seen_trend_serial: int = 0
var _pulse_elapsed: float = PULSE_DURATION_SEC
var _pulse_trend: int = FirstExitBearings.Trend.STABLE
var _marker_color: Color = COLD_COLOR


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
	_have_marker = false
	_marker_target_id = ""
	_rear_edge = 0


func _process(delta: float) -> void:
	var want: float = FirstExitBearings.camera_bearing(_camera)
	if not _have_bearing:
		_shown = want
		_have_bearing = true
	else:
		var blend: float = 1.0 - exp(-delta / SMOOTH_SEC)
		_shown = lerp_angle(_shown, want, blend)
	_tick_marker(delta)
	queue_redraw()


## Keep the strip quick and the marker slightly weighted, with an 8-degree
## maximum lag; directional accuracy still wins over animation.
func _tick_marker(delta: float) -> void:
	if _bearings == null or _player == null or not _bearings.has_active_target():
		_have_marker = false
		_marker_target_id = ""
		_rear_edge = 0
		_pulse_elapsed = PULSE_DURATION_SEC
		return
	var from := Vector2(_player.global_position.x, _player.global_position.z)
	var target_rel: float = FirstExitBearings.relative_bearing(
		_shown, FirstExitBearings.bearing_of(from, _bearings.active_xz())
	)
	var desired: Color = _proximity_color(int(_bearings.proximity_state))
	if not _have_marker or _marker_target_id != _bearings.active_target_id:
		_marker_target_id = _bearings.active_target_id
		_marker_rel = target_rel
		_marker_color = desired
		_have_marker = true
		_rear_edge = 0
		_pulse_elapsed = PULSE_DURATION_SEC
		_seen_trend_serial = _bearings.trend_serial
	else:
		var blend: float = 1.0 - exp(-delta / MARKER_SMOOTH_SEC)
		_marker_rel = lerp_angle(_marker_rel, target_rel, blend)
		var error: float = wrapf(target_rel - _marker_rel, -PI, PI)
		if absf(error) > MARKER_MAX_LAG_RAD:
			_marker_rel = wrapf(target_rel - signf(error) * MARKER_MAX_LAG_RAD, -PI, PI)
		_marker_color = _marker_color.lerp(desired, 1.0 - exp(-delta / COLOR_SMOOTH_SEC))
		if _seen_trend_serial != _bearings.trend_serial:
			_seen_trend_serial = _bearings.trend_serial
			_pulse_trend = int(_bearings.trend_state)
			_pulse_elapsed = 0.0
	_pulse_elapsed = minf(PULSE_DURATION_SEC, _pulse_elapsed + delta)
	## Keep an off-strip side stable at +/-180 degrees (target exactly behind).
	if absf(_marker_rel) < PI - REAR_LOCK_RAD:
		_rear_edge = -1 if _marker_rel < 0.0 else 1
	elif _rear_edge == 0:
		_rear_edge = -1 if _marker_rel < 0.0 else 1


func _proximity_color(level: int) -> Color:
	match level:
		FirstExitBearings.Proximity.WARM:
			return WARM_COLOR
		FirstExitBearings.Proximity.HOT:
			return HOT_COLOR
	return COLD_COLOR


func _proximity_text() -> String:
	## Keep the compact copy intelligible in the existing English HUD and RU.
	var ru: bool = TranslationServer.get_locale().begins_with("ru")
	match _bearings.proximity_state:
		FirstExitBearings.Proximity.WARM:
			return "ТЕПЛО" if ru else "WARM"
		FirstExitBearings.Proximity.HOT:
			return "ГОРЯЧО" if ru else "HOT"
	return "ХОЛОДНО" if ru else "COLD"


func _pulse_scale() -> float:
	if _pulse_elapsed >= PULSE_DURATION_SEC:
		return 1.0
	var phase: float = sin(PI * _pulse_elapsed / PULSE_DURATION_SEC)
	if _pulse_trend == FirstExitBearings.Trend.APPROACHING:
		return 1.0 + 0.08 * phase
	if _pulse_trend == FirstExitBearings.Trend.MOVING_AWAY:
		return 1.0 - 0.08 * phase
	return 1.0


func _draw() -> void:
	var view: Vector2 = get_viewport_rect().size
	if view.x < 32.0:
		return
	var width: float = minf(STRIP_WIDTH, view.x * 0.62)
	var origin := Vector2((view.x - width) * 0.5, TOP_MARGIN)
	var base_y: float = origin.y + 36.0
	var slot: Dictionary = {}
	if _have_marker and _bearings != null and _bearings.has_active_target():
		slot = FirstExitBearings.marker_slot(_marker_rel)
		if not bool(slot["on_strip"]) and absf(_marker_rel) >= PI - REAR_LOCK_RAD and _rear_edge != 0:
			slot["edge"] = _rear_edge
	_draw_wash(origin.x, width, origin.y - 2.0, base_y - origin.y + 6.0)
	_draw_tape(origin.x, width, base_y, slot)
	_draw_index(origin.x + width * 0.5, base_y)
	if not slot.is_empty():
		_draw_marker(origin.x, width, base_y, slot)


func _draw_wash(x: float, width: float, top: float, height: float) -> void:
	var mid: float = x + width * 0.5
	var edge := Color(0.02, 0.02, 0.018, 0.0)
	var center := Color(0.02, 0.02, 0.018, 0.42)
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
		var length: float = 18.0 if on_cardinal else 10.0 if on_major else 5.0
		var ink := INK
		ink.a = 1.0 if on_cardinal else 0.84 if on_major else 0.62
		var top := Vector2(x, base_y - length)
		var bottom := Vector2(x, base_y)
		draw_line(top, bottom, Color(0.04, 0.035, 0.03, 0.8), 3.0)
		draw_line(top, bottom, ink, 1.5)
		if not on_cardinal or absf(x - mark_x) < 22.0:
			continue
		var letter: String = CARDINALS[cardinal]
		var at := Vector2(x - _text_width(letter, 26) * 0.5, base_y - 22.0)
		_text(letter, at, 26, INK)


func _draw_index(x: float, base_y: float) -> void:
	draw_line(Vector2(x, base_y - 26.0), Vector2(x, base_y + 4.0), Color(0.04, 0.035, 0.03, 0.85), 3.0)
	draw_line(Vector2(x, base_y - 26.0), Vector2(x, base_y + 4.0), Color(INK.r, INK.g, INK.b, 0.95), 1.5)


func _draw_marker(x0: float, width: float, base_y: float, slot: Dictionary) -> void:
	var on_strip: bool = bool(slot["on_strip"])
	var color: Color = _marker_color
	var scale: float = _pulse_scale()
	var x: float
	if on_strip:
		x = _x_of(x0, width, float(slot["u"]))
		var mid := Vector2(x, base_y - 8.0)
		var size: float = 4.0 * scale
		var dark := PackedVector2Array([
			mid + Vector2(0.0, -size - 1.5), mid + Vector2(size + 1.5, 0.0),
			mid + Vector2(0.0, size + 1.5), mid + Vector2(-size - 1.5, 0.0),
		])
		var pigment := PackedVector2Array([
			mid + Vector2(0.0, -size), mid + Vector2(size, 0.0),
			mid + Vector2(0.0, size), mid + Vector2(-size, 0.0),
		])
		draw_colored_polygon(dark, Color(0.04, 0.03, 0.02, 0.85))
		draw_colored_polygon(pigment, color)
	else:
		var edge: int = int(slot["edge"])
		x = x0 + 6.0 if edge < 0 else x0 + width - 6.0
		var wing: float = (10.0 if edge < 0 else -10.0) * scale
		var tip := Vector2(x, base_y - 8.0)
		var chevron := PackedVector2Array([
			tip + Vector2(wing, -6.0 * scale), tip,
			tip + Vector2(wing, 6.0 * scale),
		])
		draw_polyline(chevron, Color(0.04, 0.03, 0.02, 0.85), 4.0)
		draw_polyline(chevron, color, 2.0)
	var label: String = _bearings.active_label()
	var size_label: int = 18
	var label_width: float = _text_width(label, size_label)
	var label_x: float = clampf(x - label_width * 0.5, x0 + 4.0, x0 + width - label_width - 4.0)
	_text(label, Vector2(label_x, base_y - 22.0), size_label, color)
	var proximity_text: String = _proximity_text()
	var size_text: int = 14
	var text_width: float = _text_width(proximity_text, size_text)
	var text_x: float = clampf(x - text_width * 0.5, x0 + 4.0, x0 + width - text_width - 4.0)
	_text(proximity_text, Vector2(text_x, base_y + 24.0), size_text, color)


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
	## An actual two-pixel outline is legible on blizzard-white frames; a 1px
	## offset shadow disappears at the 960x540 preview scale.
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 2, Color(0.045, 0.038, 0.032, 0.90))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _text_width(text: String, size: int) -> float:
	var font: Font = _ui_font()
	if font == null:
		return 0.0
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
