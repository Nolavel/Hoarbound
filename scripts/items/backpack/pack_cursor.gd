class_name PackCursor
extends Control

## The ring cursor of the open pack (3D inventory): over an item the ring flows into the item's outline on
## screen; hidden while an item is held; the hover hint beside it. It only draws what PackHandling says.

const RING_RADIUS: float = 11.0
const RING_WIDTH: float = 2.0
const IDLE_COLOUR: Color = Color(0.82, 0.84, 0.86, 0.7)
const HOVER_COLOUR: Color = Color(1.0, 1.0, 1.0, 0.95)
## The ring's points, how far the outline stands off the item (px), and how fast it flows (1/s).
const POINTS: int = 64
const OUTLINE_PAD: float = 6.0
const MORPH_RATE: float = 14.0
## The hint's yellow underlay, as the world prompt's.
const HINT_UNDERLAY: Color = Color(1.0, 0.823529, 0.0, 0.42)

var at: Vector2 = Vector2.ZERO
var hovering: bool = false
var shown: bool = true
var hint: String = ""
## A refusal line under the ring (red), and how long it still shows, seconds.
var warning: String = ""
var warning_s: float = 0.0
## The hovered item's convex outline on screen (empty: the plain ring), and which item it is.
var outline: PackedVector2Array = PackedVector2Array()
var outline_key: int = 0
## 0 the ring, 1 the outline; the outline it flows to or from, resampled to POINTS around its middle.
var _morph: float = 0.0
var _shape: PackedVector2Array = PackedVector2Array()
var _shape_key: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	warning_s = maxf(warning_s - delta, 0.0)
	if outline.size() >= 3:
		if outline_key != _shape_key:
			_shape_key = outline_key
			_morph = 0.0  # a new item: flow from the ring again
		_shape = _resample(outline)
	var want: float = 1.0 if outline.size() >= 3 and hovering else 0.0
	_morph = lerpf(_morph, want, 1.0 - exp(-MORPH_RATE * delta))
	queue_redraw()


func _draw() -> void:
	var font: Font = get_theme_default_font()
	if shown:
		var line := PackedVector2Array()
		var right: float = at.x + RING_RADIUS
		for i: int in POINTS + 1:
			var ring: Vector2 = at + Vector2.from_angle(TAU * float(i % POINTS) / POINTS) * RING_RADIUS
			var point: Vector2 = ring.lerp(_shape[i % POINTS], _morph) if _shape.size() == POINTS else ring
			line.append(point)
			right = maxf(right, point.x)
		draw_polyline(line, HOVER_COLOUR if hovering else IDLE_COLOUR, RING_WIDTH, true)
		if hovering and hint != "":
			var size: int = 20
			var text_at: Vector2 = Vector2(right + 14.0, at.y + 7.0)
			var width: float = font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			draw_rect(Rect2(text_at + Vector2(-8.0, -20.0), Vector2(width + 16.0, 28.0)), HINT_UNDERLAY)
			draw_string(font, text_at, hint, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.08, 0.08, 0.08))
	if warning_s > 0.0 and warning != "":
		var alpha: float = clampf(warning_s / 0.4, 0.0, 1.0)
		var line_at: Vector2 = at + Vector2(-60.0, RING_RADIUS + 34.0)
		var width: float = font.get_string_size(warning, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		draw_rect(Rect2(line_at + Vector2(-8.0, -22.0), Vector2(width + 16.0, 30.0)), Color(0.05, 0.05, 0.06, 0.75 * alpha))
		draw_string(font, line_at, warning, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1.0, 0.32, 0.26, alpha))


## `hull` (convex) as POINTS points at even angles around its middle, standing OUTLINE_PAD off it.
func _resample(hull: PackedVector2Array) -> PackedVector2Array:
	var middle := Vector2.ZERO
	for point: Vector2 in hull:
		middle += point
	middle /= float(hull.size())
	var out := PackedVector2Array()
	out.resize(POINTS)
	for i: int in POINTS:
		var direction: Vector2 = Vector2.from_angle(TAU * float(i) / POINTS)
		var far: Vector2 = middle + direction * 100000.0
		var hit: Vector2 = middle
		for j: int in hull.size():
			var crossing: Variant = Geometry2D.segment_intersects_segment(middle, far, hull[j], hull[(j + 1) % hull.size()])
			if crossing != null:
				hit = crossing
				break
		out[i] = hit + direction * OUTLINE_PAD
	return out
