class_name BlobMaskDemo
extends Control

## Three simultaneously animated uses of one reusable Godot shader/controller.

const PANEL_WIDTH: float = 284.0
const PANEL_HEIGHT: float = 288.0
const PANEL_TOP: float = 124.0

var _stage: Control
var _masks: Array[UniversalBlobMask] = []
var _external_clock: bool = false
var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage = Control.new()
	_stage.size = Vector2(960.0, 540.0)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	_build_scene()
	resized.connect(_update_stage_layout)
	_update_stage_layout()
	_update_blobs(0.0)


func _update_stage_layout() -> void:
	var available: Vector2 = size
	var factor: float = minf(available.x / 960.0, available.y / 540.0)
	_stage.scale = Vector2.ONE * factor
	_stage.position = (available - _stage.size * factor) * 0.5


func _process(delta: float) -> void:
	if not _external_clock:
		_time += delta
		_update_blobs(_time)


## CI supplies the timeline explicitly: exactly six seconds at 30 FPS.
func set_demo_time(seconds: float) -> void:
	_external_clock = true
	_time = seconds
	_update_blobs(_time)


func _build_scene() -> void:
	var backdrop: ColorRect = _rect(_stage, Vector2.ZERO, Vector2(960.0, 540.0), Color("#10141c"))
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label("HOARBOUND / SDF MASK LAB", Vector2(32.0, 20.0), 31, Color("#f3f1e9"))
	_label("ONE SHADER  /  16 SDF CIRCLES  /  LIVE SMOOTH UNION", Vector2(34.0, 68.0), 15, Color("#8e9eaf"))

	for index: int in range(3):
		var left: float = 32.0 + float(index) * 304.0
		var panel: ColorRect = _rect(
			_stage, Vector2(left, PANEL_TOP),
			Vector2(PANEL_WIDTH, PANEL_HEIGHT), Color("#202832")
		)
		_rect(panel, Vector2(10.0, 12.0), Vector2(264.0, 264.0), Color("#131a23"))
		if index == 2:
			_add_checker(panel)

		var mask: UniversalBlobMask = UniversalBlobMask.new()
		mask.position = Vector2(9.0, 12.0)
		mask.size = Vector2(266.0, 264.0)
		mask.merge_width = 0.105
		mask.stroke_width = 0.008
		mask.edge_softness = 1.1
		mask.fill_color = Color("#f7f6f1")
		mask.outline_color = Color("#f7f6f1")
		if index == 0:
			mask.display_mode = UniversalBlobMask.DisplayMode.OUTLINE
		elif index == 1:
			mask.display_mode = UniversalBlobMask.DisplayMode.FILL
		else:
			mask.display_mode = UniversalBlobMask.DisplayMode.MASK
			mask.use_content_texture = true
			var gradient: Gradient = Gradient.new()
			gradient.set_color(0, Color("#68d5db"))
			gradient.set_color(1, Color("#f3b45b"))
			var gradient_texture: GradientTexture2D = GradientTexture2D.new()
			gradient_texture.gradient = gradient
			gradient_texture.width = 256
			gradient_texture.height = 256
			gradient_texture.fill_from = Vector2(0.1, 0.0)
			gradient_texture.fill_to = Vector2(0.9, 1.0)
			mask.content_texture = gradient_texture
		panel.add_child(mask)
		_masks.append(mask)

		var label_text: String = ["01  /  OUTLINE", "02  /  FILL", "03  /  ALPHA REVEAL"][index]
		_label(label_text, Vector2(left + 12.0, 425.0), 20, Color("#d6dfe7"))

	_label("CPU VULKAN CAPTURE   •   960 × 540   •   30 FPS   •   6 SECONDS", Vector2(32.0, 491.0), 15, Color("#8e9eaf"))


func _update_blobs(t: float) -> void:
	var circles: Array[Vector3] = [
		Vector3(0.31 + 0.20 * sin(t * 1.35), 0.47 + 0.07 * cos(t * 0.70), 0.094),
		Vector3(0.69 - 0.20 * sin(t * 1.35), 0.48 - 0.09 * cos(t * 0.87), 0.086),
		Vector3(0.43 + 0.14 * sin(t * 1.90 + 1.80), 0.30 + 0.10 * cos(t * 0.90 + 0.80), 0.061),
		Vector3(0.56 - 0.12 * sin(t * 1.10 + 0.70), 0.69 - 0.09 * cos(t * 1.13), 0.068),
		Vector3(0.50 + 0.22 * sin(t * 0.90 + 2.80), 0.49 + 0.15 * sin(t * 0.78 + 1.30), 0.045),
	]
	for mask: UniversalBlobMask in _masks:
		mask.set_blobs(circles)


func _add_checker(panel: ColorRect) -> void:
	for row: int in range(8):
		for column: int in range(8):
			var shade: Color = Color("#263846") if (row + column) % 2 == 0 else Color("#17242f")
			_rect(panel, Vector2(10.0 + float(column) * 33.0, 12.0 + float(row) * 33.0), Vector2(33.0, 33.0), shade)


func _rect(parent: Control, at: Vector2, dimensions: Vector2, tint: Color) -> ColorRect:
	var item: ColorRect = ColorRect.new()
	item.position = at
	item.size = dimensions
	item.color = tint
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent._stage.add_child(item)
	return item


func _label(value: String, at: Vector2, font_size: int, tint: Color) -> void:
	var item: Label = Label.new()
	item.text = value
	item.position = at
	item.add_theme_font_size_override("font_size", font_size)
	item.add_theme_color_override("font_color", tint)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(item)
