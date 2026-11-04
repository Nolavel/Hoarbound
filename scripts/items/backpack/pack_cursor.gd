class_name PackCursor
extends Control

## The open pack's cursor (3D inventory): the ring flows into a hovered item's outline, with its readout
## (ItemReadout) below and the drop hint beside; the load bar sits at the top. It draws what PackHandling says.

const RING_RADIUS: float = 11.0
const RING_WIDTH: float = 2.0
const IDLE_COLOUR: Color = Color(0.82, 0.84, 0.86, 0.7)
const HOVER_COLOUR: Color = Color(1.0, 1.0, 1.0, 0.95)
## The ring's points, how far the outline stands off the item (px), and how fast it flows (1/s).
const POINTS: int = 160
const OUTLINE_PAD: float = 6.0
const MORPH_RATE: float = 14.0
## The readout under the item and the load bar: text sizes, underlay, bar size and its top margin (px).
const INFO_SIZE: int = 20
const INFO_SUB_SIZE: int = 17
const INFO_UNDERLAY: Color = Color(0.05, 0.05, 0.06, 0.72)
const LOAD_BAR := Vector2(360.0, 6.0)
const LOAD_TOP: float = 46.0
const LOAD_FILL: Color = Color(0.86, 0.87, 0.88, 0.85)
const LOAD_HEAVY: Color = Color(1.0, 0.72, 0.1, 0.9)
const LOAD_ITEM: Color = Color(1.0, 1.0, 1.0, 1.0)
## The hint's yellow underlay, as the world prompt's.
const HINT_UNDERLAY: Color = Color(1.0, 0.823529, 0.0, 0.42)

var at: Vector2 = Vector2.ZERO
var hovering: bool = false
var shown: bool = true
var hint: String = ""
## A refusal line under the ring (red), and how long it still shows, seconds.
var warning: String = ""
var warning_s: float = 0.0
## The hovered item's silhouette outline on screen (empty: the plain ring), and which item it is.
var outline: PackedVector2Array = PackedVector2Array()
var outline_key: int = 0
## The hovered or carried item's readout (ItemReadout.describe), or {} for none.
var info: Dictionary = {}
## Carried weight and its limit (kg), the share where Henry starts to slow, and the hovered item's kg.
var load_kg: float = 0.0
var load_max_kg: float = 0.0
var load_slows_at: float = 1.0
var load_item_kg: float = 0.0
## 0 the ring, 1 the outline; the outline it flows to or from, resampled to POINTS along its length.
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
		var bottom: float = at.y + RING_RADIUS
		var centre_x: float = 0.0
		for point: Vector2 in line:
			bottom = maxf(bottom, point.y)
			centre_x += point.x
		centre_x /= float(line.size())
		if hovering and not info.is_empty():
			_draw_info(font, Vector2(centre_x, bottom + 14.0))
		if hovering and hint != "":
			var size: int = 20
			var text_at: Vector2 = Vector2(right + 14.0, at.y + 7.0)
			var width: float = font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			draw_rect(Rect2(text_at + Vector2(-8.0, -20.0), Vector2(width + 16.0, 28.0)), HINT_UNDERLAY)
			draw_string(font, text_at, hint, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.08, 0.08, 0.08))
	if not shown and not info.is_empty():
		_draw_info(font, at + Vector2(0.0, 64.0))
	if load_max_kg > 0.0:
		_draw_load(font)
	if warning_s > 0.0 and warning != "":
		var alpha: float = clampf(warning_s / 0.4, 0.0, 1.0)
		var line_at: Vector2 = at + Vector2(-60.0, RING_RADIUS + 34.0)
		var width: float = font.get_string_size(warning, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		draw_rect(Rect2(line_at + Vector2(-8.0, -22.0), Vector2(width + 16.0, 30.0)), Color(0.05, 0.05, 0.06, 0.75 * alpha))
		draw_string(font, line_at, warning, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1.0, 0.32, 0.26, alpha))


## `contour` as POINTS points evenly along its length, starting due right of its middle and running the ring's
## way round, each pushed OUTLINE_PAD out from the middle.
func _resample(contour: PackedVector2Array) -> PackedVector2Array:
	var middle := Vector2.ZERO
	for point: Vector2 in contour:
		middle += point
	middle /= float(contour.size())
	var ring_way: float = _signed_area([Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT])
	var path: PackedVector2Array = contour.duplicate()
	if signf(_signed_area(path)) != signf(ring_way):
		path.reverse()
	var begin: int = 0
	var best: float = INF
	for i: int in path.size():
		var off: Vector2 = path[i] - middle
		var score: float = absf(off.angle()) - off.length() * 1e-4
		if off.x > 0.0 and score < best:
			best = score
			begin = i
	var ring := PackedVector2Array()
	var lengths := PackedFloat32Array([0.0])
	for i: int in path.size():
		ring.append(path[(begin + i) % path.size()])
	ring.append(ring[0])
	for i: int in range(1, ring.size()):
		lengths.append(lengths[i - 1] + ring[i].distance_to(ring[i - 1]))
	var total: float = maxf(lengths[lengths.size() - 1], 0.001)
	var out := PackedVector2Array()
	out.resize(POINTS)
	var j: int = 0
	for i: int in POINTS:
		var along: float = total * float(i) / POINTS
		while j < lengths.size() - 2 and lengths[j + 1] < along:
			j += 1
		var span: float = maxf(lengths[j + 1] - lengths[j], 0.0001)
		var point: Vector2 = ring[j].lerp(ring[j + 1], (along - lengths[j]) / span)
		out[i] = point + (point - middle).normalized() * OUTLINE_PAD
	return out


static func _signed_area(points: PackedVector2Array) -> float:
	var area: float = 0.0
	for i: int in points.size():
		area += points[i].cross(points[(i + 1) % points.size()])
	return area


## The item's name, and its weight and key number under it, centred below `top`.
func _draw_info(font: Font, top: Vector2) -> void:
	var name_text: String = info.get("name", "")
	var sub: String = info.get("weight", "")
	if String(info.get("detail", "")) != "":
		sub += "  ·  " + String(info["detail"])
	var width: float = maxf(font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, INFO_SIZE).x,
		font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, INFO_SUB_SIZE).x)
	var box := Rect2(top - Vector2(width * 0.5 + 10.0, 0.0), Vector2(width + 20.0, 52.0))
	draw_rect(box, INFO_UNDERLAY)
	draw_string(font, box.position + Vector2(10.0, 22.0), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, INFO_SIZE, Color(0.95, 0.95, 0.95))
	draw_string(font, box.position + Vector2(10.0, 44.0), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, INFO_SUB_SIZE, Color(0.72, 0.74, 0.76))


## The load bar at the top: what Henry carries of his limit, amber past where he slows, the hovered item's
## share bright at the fill's end, a tick where slowing starts.
func _draw_load(font: Font) -> void:
	var share: float = clampf(load_kg / load_max_kg, 0.0, 1.0)
	var item_share: float = clampf(load_item_kg / load_max_kg, 0.0, share)
	var bar := Rect2(Vector2((get_viewport_rect().size.x - LOAD_BAR.x) * 0.5, LOAD_TOP), LOAD_BAR)
	var label: String = tr(&"INVENTORY_LOAD") % [load_kg, load_max_kg]
	var label_width: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, INFO_SUB_SIZE).x
	draw_rect(Rect2(bar.position - Vector2(10.0, 30.0), Vector2(bar.size.x + 20.0, bar.size.y + 40.0)), INFO_UNDERLAY)
	draw_string(font, Vector2(bar.position.x + (bar.size.x - label_width) * 0.5, bar.position.y - 9.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, INFO_SUB_SIZE, Color(0.86, 0.87, 0.88))
	draw_rect(bar, Color(1.0, 1.0, 1.0, 0.14))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * share, bar.size.y)), LOAD_HEAVY if share > load_slows_at else LOAD_FILL)
	if item_share > 0.0:
		draw_rect(Rect2(bar.position + Vector2(bar.size.x * (share - item_share), -2.0), Vector2(bar.size.x * item_share, bar.size.y + 4.0)), LOAD_ITEM)
	var tick_x: float = bar.position.x + bar.size.x * load_slows_at
	draw_line(Vector2(tick_x, bar.position.y - 4.0), Vector2(tick_x, bar.end.y + 4.0), LOAD_HEAVY, 2.0)
