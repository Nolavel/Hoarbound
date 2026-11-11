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
## Use Hoarbound's committed font assets, not an arbitrary OS font.
## All project fonts are Latin-only (see cmap); RU uses engine Cyrillic fallback
## until a Cyrillic-capable art font is actually added to the asset library.
const HEADING_FONT: Font = preload("res://assets/fonts/IM Fell English SC/IMFellEnglishSC-Regular.ttf")
const PROXIMITY_FONT: Font = preload("res://assets/fonts/Averia Libre _ Averia Gruesa Libre _ Averia Serif Libre _ Averia Sans Libre/AveriaLibre-Bold.ttf")
const SIGNAL_FONT: Font = preload("res://assets/fonts/Special Elite/SpecialElite-Regular.ttf")
const STREET_FONT: Font = preload("res://assets/fonts/Averia Libre _ Averia Gruesa Libre _ Averia Serif Libre _ Averia Sans Libre/AveriaLibre-Regular.ttf")
## Identity is an independent, quiet loop: open-bottom house, then street.
const IDENTITY_HOUSE_SEC: float = 4.5
const IDENTITY_CYCLE_SEC: float = 6.0
const IDENTITY_FADE_SEC: float = 0.18

## Cooler mineral chalk / mellow honey / restrained copper, not warning-red.
const COLD_COLOR: Color = Color("#B2C1BF")
const WARM_COLOR: Color = Color("#E1B777")
const HOT_COLOR: Color = Color("#F0A177")
const MARKER_SMOOTH_SEC: float = 0.22
const MARKER_MAX_LAG_RAD: float = PI * 8.0 / 180.0
const REAR_LOCK_RAD: float = PI * 8.0 / 180.0
const COLOR_SMOOTH_SEC: float = 0.5
const PULSE_DURATION_SEC: float = 0.95
const RING_EXPAND_SEC: float = 1.25
const RING_EVENT_SEC: float = 0.95
const COLD_RHYTHM_SEC: float = 5.8
const WARM_RHYTHM_SEC: float = 3.8
const HOT_RHYTHM_SEC: float = 2.6

var _camera: Camera3D
var _player: Node3D
var _bearings: FirstExitBearings
var _shown: float = 0.0
var _have_bearing: bool = false
var _ambient_clock: float = 0.0
var _identity_clock: float = 0.0
var _last_proximity: int = -1
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
	_ambient_clock = 0.0
	_identity_clock = 0.0
	_last_proximity = -1


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
		_identity_clock = 0.0
		_last_proximity = -1
		return
	var from := Vector2(_player.global_position.x, _player.global_position.z)
	var target_rel: float = FirstExitBearings.relative_bearing(
		_shown, FirstExitBearings.bearing_of(from, _bearings.active_xz())
	)
	var proximity: int = int(_bearings.proximity_state)
	var desired: Color = _proximity_color(proximity)
	if proximity != _last_proximity:
		_last_proximity = proximity
		_ambient_clock = 0.0
	if not _have_marker or _marker_target_id != _bearings.active_target_id:
		_marker_target_id = _bearings.active_target_id
		_identity_clock = 0.0
		_marker_rel = target_rel
		_marker_color = desired
		_have_marker = true
		_rear_edge = 0
		_pulse_elapsed = PULSE_DURATION_SEC
		_pulse_trend = FirstExitBearings.Trend.STABLE
		_seen_trend_serial = _bearings.trend_serial
	else:
		var blend: float = 1.0 - exp(-delta / MARKER_SMOOTH_SEC)
		_marker_rel = lerp_angle(_marker_rel, target_rel, blend)
		var error: float = wrapf(target_rel - _marker_rel, -PI, PI)
		if absf(error) > MARKER_MAX_LAG_RAD:
			_marker_rel = wrapf(target_rel - signf(error) * MARKER_MAX_LAG_RAD, -PI, PI)
		_marker_color = _marker_color.lerp(desired, 1.0 - exp(-delta / COLOR_SMOOTH_SEC))
		## A target reset / teleport clears pending feedback even when the ID
		## remains unchanged. Never keep the old direction word after reload.
		if _bearings.trend_state == FirstExitBearings.Trend.STABLE:
			_pulse_elapsed = PULSE_DURATION_SEC
			_pulse_trend = FirstExitBearings.Trend.STABLE
		if _seen_trend_serial != _bearings.trend_serial:
			_seen_trend_serial = _bearings.trend_serial
			if _bearings.trend_state != FirstExitBearings.Trend.STABLE:
				_pulse_trend = int(_bearings.trend_state)
				_pulse_elapsed = 0.0
	_pulse_elapsed = minf(PULSE_DURATION_SEC, _pulse_elapsed + delta)
	_ambient_clock += delta
	_identity_clock = fposmod(_identity_clock + delta, IDENTITY_CYCLE_SEC)
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


func _trend_text() -> String:
	if _bearings.trend_state == FirstExitBearings.Trend.STABLE:
		return ""
	var ru: bool = TranslationServer.get_locale().begins_with("ru")
	if _bearings.trend_state == FirstExitBearings.Trend.APPROACHING:
		return "ТЕПЛЕЕ" if ru else "WARMER"
	return "ХОЛОДНЕЕ" if ru else "COLDER"


## Only this single word is drawn. Color/rhythm remain absolute proximity.
func _display_word() -> String:
	var movement: String = _trend_text()
	return _proximity_text() if movement.is_empty() else movement


func _rhythm_sec() -> float:
	match _bearings.proximity_state:
		FirstExitBearings.Proximity.WARM:
			return WARM_RHYTHM_SEC
		FirstExitBearings.Proximity.HOT:
			return HOT_RHYTHM_SEC
	return COLD_RHYTHM_SEC


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


func _draw_waves(mid: Vector2, color: Color) -> void:
	## A ring briefly blooms and vanishes, cadence depends on proximity.
	## With no movement, the quiet periodic heartbeat continues; movement
	## adds a stronger one-shot ring whose direction encodes the trend.
	var rhythm: float = _rhythm_sec()
	var ambient_age: float = fposmod(_ambient_clock, rhythm)
	if ambient_age < RING_EXPAND_SEC:
		var t: float = ambient_age / RING_EXPAND_SEC
		var halo_color: Color = color
		halo_color.a = 0.34 * pow(1.0 - t, 1.9)
		draw_arc(mid, lerpf(9.0, 24.0, t), 0.0, TAU, 48, halo_color, 1.3, true)
	if _pulse_elapsed < RING_EVENT_SEC:
		var p: float = _pulse_elapsed / RING_EVENT_SEC
		var moving_away: bool = _pulse_trend == FirstExitBearings.Trend.MOVING_AWAY
		var radius: float = lerpf(21.0, 8.5, p) if moving_away else lerpf(8.5, 27.0, p)
		var event_color: Color = color
		event_color.a = 0.72 * pow(1.0 - p, 1.4)
		draw_arc(mid, radius, 0.0, TAU, 56, event_color, 2.0 - 0.8 * p, true)


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
		## The wider street label needs more breathing room than the old 727.
		if not on_cardinal or absf(x - mark_x) < 44.0:
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
	var x: float = _x_of(x0, width, float(slot["u"])) if on_strip else (
		x0 + 15.0 if int(slot["edge"]) < 0 else x0 + width - 15.0
	)
	var mid := Vector2(x, base_y + 1.0)

	## Three translucent ink layers, not a flat polygon / warning beacon.
	## This halo makes the marker legible on pale snow and in dark interiors.
	var haze: Color = color
	haze.a = 0.055
	draw_circle(mid, 16.0 * scale, haze)
	haze.a = 0.13
	draw_circle(mid, 11.0 * scale, haze)
	draw_circle(mid, 8.0 * scale, Color(0.045, 0.05, 0.055, 0.8))
	_draw_waves(mid, color)
	var line: Color = color
	line.a = 0.90
	draw_arc(mid, 7.5 * scale, 0.0, TAU, 40, line, 1.8, true)
	var center: Color = color
	center.a = 0.94
	draw_circle(mid, 2.5 * scale, center)

	if not on_strip:
		## Keep the existing off-strip direction semantics: short outward
		## chevron next to the ring, not a misleading compass-independent dot.
		var edge: int = int(slot["edge"])
		var tip_x: float = x - 11.0 if edge < 0 else x + 11.0
		var wing: float = 6.5 if edge < 0 else -6.5
		var tip := Vector2(tip_x, mid.y)
		var chevron := PackedVector2Array([
			tip + Vector2(wing, -4.2), tip, tip + Vector2(wing, 4.2),
		])
		draw_polyline(chevron, Color(0.04, 0.04, 0.04, 0.80), 3.5)
		draw_polyline(chevron, color, 1.5, true)

	## Upper identity slot is independent of the single lower search word.
	## Never expose the internal landmark number as a player-facing label.
	_draw_identity(clampf(x, x0 + 12.0, x0 + width - 12.0), base_y, color)
	var style: int = 1 if _bearings.trend_state == FirstExitBearings.Trend.STABLE else 2
	_marker_text(_display_word(), Vector2(x, base_y + 44.0), 16, color, style)


func _identity_is_street() -> bool:
	return _identity_clock >= IDENTITY_HOUSE_SEC


func _identity_opacity() -> float:
	var start: float = IDENTITY_HOUSE_SEC if _identity_is_street() else 0.0
	var finish: float = IDENTITY_CYCLE_SEC if _identity_is_street() else IDENTITY_HOUSE_SEC
	## Fade out fully before switching, then fade in the new symbol.
	## A house and a word never occupy the slot simultaneously.
	return clampf(minf(_identity_clock - start, finish - _identity_clock) / IDENTITY_FADE_SEC, 0.0, 1.0)


func _draw_identity(x: float, base_y: float, color: Color) -> void:
	var ink: Color = color
	ink.a *= _identity_opacity()
	if ink.a <= 0.0:
		return
	var street: String = _bearings.active_street_label()
	if _identity_is_street() and not street.is_empty():
		_marker_text(street, Vector2(x, base_y - 30.0), 17, ink, 3)
		return
	## Open-bottom house silhouette: two walls joined by a pitched roof.
	## Draw it in the same ink as the marker, with a dark outline for snow.
	var mid := Vector2(x, base_y - 35.0)
	var shape := PackedVector2Array([
		mid + Vector2(-9.0, 8.0), mid + Vector2(-9.0, -1.0),
		mid + Vector2(0.0, -9.0),
		mid + Vector2(9.0, -1.0), mid + Vector2(9.0, 8.0),
	])
	draw_polyline(shape, Color(0.035, 0.04, 0.044, ink.a * 0.93), 4.0, true)
	draw_polyline(shape, ink, 2.0, true)


func _marker_text(value: String, mid: Vector2, font_px: int, color: Color, style: int) -> void:
	var font: Font = _font_for(value, style)
	var text_w: float = font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x
	var x0: float = (get_viewport_rect().size.x - minf(STRIP_WIDTH, get_viewport_rect().size.x * 0.62)) * 0.5
	var width: float = minf(STRIP_WIDTH, get_viewport_rect().size.x * 0.62)
	var left: float = clampf(mid.x - text_w * 0.5, x0 + 7.0, x0 + width - text_w - 7.0)
	var at := Vector2(left, mid.y)
	draw_string_outline(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px,
		3, Color(0.035, 0.040, 0.044, color.a * 0.93))
	draw_string(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, color)


func _font_for(value: String, style: int) -> Font:
	if style == 0:
		return HEADING_FONT
	if style == 3:
		return STREET_FONT
	## All of the project's authored font files are Latin-only. Do not render
	## missing Cyrillic glyphs as squares. Native fallback is temporary.
	if TranslationServer.get_locale().begins_with("ru"):
		return ThemeDB.fallback_font
	if style == 2:
		return SIGNAL_FONT
	return PROXIMITY_FONT


func _x_of(x0: float, width: float, u: float) -> float:
	return x0 + width * 0.5 + u * width * 0.5


func _ui_font() -> Font:
	return HEADING_FONT


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
