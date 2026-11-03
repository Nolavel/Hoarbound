class_name PlayerFeedbackUI
extends CanvasLayer

## The screen owns widgets and timing; player components publish only messages.
const POSITIONS: Dictionary = {
	&"quick": 0.82,
	&"held": 0.84,
	&"wood": 0.73,
	&"rest": 0.88,
	&"water": 0.78,
}

var _labels: Dictionary = {}
var _expiry: Dictionary = {}


func _ready() -> void:
	for kind: StringName in POSITIONS:
		var label := Label.new()
		label.name = "%sMessage" % String(kind).capitalize()
		label.visible = false
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override(&"font_size", 22 if kind == &"water" else 18 if kind == &"quick" else 20)
		label.add_theme_constant_override(&"outline_size", 5 if kind == &"water" else 4)
		add_child(label)
		_labels[kind] = label
		_expiry[kind] = 0.0


func _process(delta: float) -> void:
	var view_size: Vector2 = get_viewport().get_visible_rect().size
	for kind: StringName in _labels:
		var label := _labels[kind] as Label
		if not label.visible:
			continue
		var left := float(_expiry[kind])
		if left > 0.0:
			left -= delta
			_expiry[kind] = left
			if left <= 0.0:
				label.visible = false
				continue
		var width := minf(640.0, maxf(view_size.x - 32.0, 1.0))
		label.size = Vector2(width, label.get_combined_minimum_size().y)
		label.position = Vector2((view_size.x - width) * 0.5, view_size.y * float(POSITIONS[kind]))


func _show(kind: StringName, message: String, duration: float = 0.0) -> void:
	var label := _labels.get(kind) as Label
	if label == null:
		return
	label.text = message
	label.visible = message != ""
	_expiry[kind] = duration if label.visible else 0.0


func show_quick(message: String) -> void:
	_show(&"quick", message)


func show_held(message: String) -> void:
	_show(&"held", message)


func show_wood(message: String) -> void:
	_show(&"wood", message)


func show_rest(message: String, duration: float) -> void:
	_show(&"rest", message, duration)


func show_water(message: String) -> void:
	_show(&"water", message, 4.0)
