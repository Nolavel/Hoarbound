class_name CompassStrip
extends Control

## Draws the First Exit tape. It reads the camera and FirstExitBearings and
## stores neither knowledge nor the active target.

const BEARINGS_SCRIPT: GDScript = preload("res://scripts/world/first_exit_bearings.gd")
const STRIP_WIDTH: float = 480.0
const STRIP_HEIGHT: float = 32.0
const TOP_MARGIN: float = 16.0
const TICK_STEP: float = TAU / 360.0 * 15.0
const SMOOTH_SEC: float = 0.08
const CARDINALS: PackedStringArray = ["N", "E", "S", "W"]
const BONE: Color = Color(0.93, 0.90, 0.82, 0.95)
const OCHRE: Color = Color(0.86, 0.62, 0.28, 1.0)
const SHADOW: Color = Color(0.0, 0.0, 0.0, 0.88)

var _camera: Camera3D
var _player: Node3D
var _bearings: FirstExitBearings
var _shown: float = 0.0
var _have_bearing: bool = false


func on_world_ready(context: WorldContext) -> void:
	_camera = context.camera
	_player = context.player
	_bearings = context.get_system(BEARINGS_SCRIPT) as FirstExitBearings
	if _bearings != null and not _bearings.bearings_changed.is_connected(queue_redraw):
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
	var width: float = minf(STRIP_WIDTH, view.x * 0.70)
	var bar := Rect2(Vector2((view.x - width) * 0.5, TOP_MARGIN), Vector2(width, STRIP_HEIGHT))
	draw_rect(bar, Color(0.02, 0.025, 0.03, 0.46))
	draw_rect(bar, Color(BONE.r, BONE.g, BONE.b, 0.45), false, 1.0)
	var slot: Dictionary = {}
	if _bearings != null and _bearings.has_active_target() and _player != null:
		var from := Vector2(_player.global_position.x, _player.global_position.z)
		var rel: float = FirstExitBearings.relative_bearing(_shown, FirstExitBearings.bearing_of(from, _bearings.active_xz()))
		slot = FirstExitBearings.marker_slot(rel)
	_draw_tape(bar, slot)
	_draw_notch(bar)
	if not slot.is_empty():
		_draw_marker(bar, slot)


func _draw_tape(bar: Rect2, slot: Dictionary) -> void:
	var half: float = FirstExitBearings.HALF_ARC_RAD
	var first: int = int(ceil((_shown - half) / TICK_STEP))
	var last: int = int(floor((_shown + half) / TICK_STEP))
	var badge: Rect2 = _badge_rect(bar, int(slot.get("edge", 0)))
	for step: int in range(first, last + 1):
		var world: float = float(step) * TICK_STEP
		var rel: float = world - _shown
		var x: float = _x_of(bar, rel / half)
		var degrees: float = fposmod(rad_to_deg(world), 360.0)
		var cardinal: int = int(round(degrees / 90.0)) % 4
		var on_cardinal: bool = absf(degrees - float(cardinal) * 90.0) < 0.6 or (cardinal == 0 and degrees > 359.4)
		var height: float = 14.0 if on_cardinal else 9.0 if int(round(degrees)) % 45 == 0 else 5.0
		var top: float = bar.position.y + (bar.size.y - height) * 0.5
		draw_line(Vector2(x, top), Vector2(x, top + height), BONE, 1.0)
		if not on_cardinal:
			continue
		var letter: String = CARDINALS[cardinal]
		var at: Vector2 = Vector2(x, bar.position.y + 13.0)
		at.x -= _text_width(letter, 13) * 0.5
		if badge.size.x > 0.0 and badge.has_point(Vector2(x, bar.position.y + bar.size.y * 0.5)):
			continue
		_text(letter, at, 13, BONE)


func _draw_notch(bar: Rect2) -> void:
	var x: float = bar.position.x + bar.size.x * 0.5
	var y: float = bar.position.y + bar.size.y - 5.0
	var notch: PackedVector2Array = PackedVector2Array([
		Vector2(x - 4.0, y + 5.0), Vector2(x, y - 2.0), Vector2(x + 4.0, y + 5.0),
	])
	draw_colored_polygon(notch, SHADOW)
	draw_colored_polygon(PackedVector2Array([notch[0] + Vector2(0, -1), notch[1] + Vector2(0, -1), notch[2] + Vector2(0, -1)]), BONE)


func _draw_marker(bar: Rect2, slot: Dictionary) -> void:
	var label: String = _bearings.active_label()
	if bool(slot["on_strip"]):
		var x: float = _x_of(bar, float(slot["u"]))
		draw_circle(Vector2(x + 0.6, bar.position.y + 22.0), 3.2, SHADOW)
		draw_circle(Vector2(x, bar.position.y + 21.4), 3.0, OCHRE)
		var at := Vector2(x - _text_width(label, 13) * 0.5, bar.position.y - 2.0)
		_text(label, at, 13, OCHRE)
		return
	var badge: Rect2 = _badge_rect(bar, int(slot["edge"]))
	draw_rect(badge, Color(0.03, 0.025, 0.02, 0.94))
	draw_rect(badge, Color(OCHRE.r, OCHRE.g, OCHRE.b, 0.85), false, 1.0)
	var inward: float = -float(slot["edge"])
	var tip := Vector2(badge.position.x + (6.0 if inward > 0.0 else badge.size.x - 6.0), badge.position.y + badge.size.y * 0.5)
	var chevron := PackedVector2Array([
		tip + Vector2(inward * 6.0, -4.0), tip, tip + Vector2(inward * 6.0, 4.0),
	])
	draw_polyline(chevron, OCHRE, 1.5)
	var text_x: float = badge.position.x + (14.0 if int(slot["edge"]) < 0 else 8.0)
	_text(label, Vector2(text_x, badge.position.y + 21.0), 13, OCHRE)


func _badge_rect(bar: Rect2, edge: int) -> Rect2:
	if edge == 0:
		return Rect2()
	var width: float = 58.0
	var x: float = bar.position.x if edge < 0 else bar.position.x + bar.size.x - width
	return Rect2(x, bar.position.y, width, bar.size.y)


func _x_of(bar: Rect2, u: float) -> float:
	return bar.position.x + bar.size.x * 0.5 + u * bar.size.x * 0.5


func _text(text: String, at: Vector2, size: int, color: Color) -> void:
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	for offset: Vector2 in [Vector2(1, 1), Vector2(-1, 0), Vector2(0, 1)]:
		draw_string(font, at + offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, SHADOW)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _text_width(text: String, size: int) -> float:
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return 0.0
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
