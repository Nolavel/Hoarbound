class_name PackCursor
extends Control

## The ring cursor of the open pack (3D inventory): a ring that brightens over an item, hidden while an item
## is held, with the hover hint beside it (G or the pad's Y to drop). It only draws what PackHandling says.

const RING_RADIUS: float = 11.0
const RING_WIDTH: float = 2.0
const IDLE_COLOUR: Color = Color(0.82, 0.84, 0.86, 0.7)
const HOVER_COLOUR: Color = Color(1.0, 1.0, 1.0, 0.95)
## The hint's yellow underlay, as the world prompt's.
const HINT_UNDERLAY: Color = Color(1.0, 0.823529, 0.0, 0.42)

var at: Vector2 = Vector2.ZERO
var hovering: bool = false
var shown: bool = true
var hint: String = ""
## A refusal line under the ring (red), and how long it still shows, seconds.
var warning: String = ""
var warning_s: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	warning_s = maxf(warning_s - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	var font: Font = get_theme_default_font()
	if shown:
		draw_arc(at, RING_RADIUS, 0.0, TAU, 40, HOVER_COLOUR if hovering else IDLE_COLOUR, RING_WIDTH, true)
		if hovering and hint != "":
			var size: int = 20
			var text_at: Vector2 = at + Vector2(RING_RADIUS + 14.0, 7.0)
			var width: float = font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			draw_rect(Rect2(text_at + Vector2(-8.0, -20.0), Vector2(width + 16.0, 28.0)), HINT_UNDERLAY)
			draw_string(font, text_at, hint, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.08, 0.08, 0.08))
	if warning_s > 0.0 and warning != "":
		var alpha: float = clampf(warning_s / 0.4, 0.0, 1.0)
		var line_at: Vector2 = at + Vector2(-60.0, RING_RADIUS + 34.0)
		var width: float = font.get_string_size(warning, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		draw_rect(Rect2(line_at + Vector2(-8.0, -22.0), Vector2(width + 16.0, 30.0)), Color(0.05, 0.05, 0.06, 0.75 * alpha))
		draw_string(font, line_at, warning, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1.0, 0.32, 0.26, alpha))
