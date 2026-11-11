class_name CameraSettingsPanel
extends Control

## Production settings frame. Camera options and the global graphics tier are
## staged locally; Back discards them and Accept persists/applies them together.
signal closed(saved: bool)

const STORE: GDScript = preload("res://scripts/settings/camera_user_settings.gd")
const GRAPHICS: GDScript = preload("res://scripts/settings/graphics_quality.gd")
const BLOT_SHADER: Shader = preload("res://shaders/ui/key_hints_blot.gdshader")
const CAMERA_GROUP: StringName = &"tps_camera_user_settings"

const FRAME_SIZE := Vector2(620.0, 560.0)
const CONTENT_SIZE := Vector2(440.0, 482.0)
const BLOT_SIZE := Vector2(1290.0, 903.0)
const BLOT_VISUAL_CENTER_UV := Vector2(0.625, 0.57)
const BLOT_CANVAS_PADDING: float = 0.22
const BLOT_FINAL_SCALE: float = 1.15
const ACCENT := Color(1.0, 0.823529, 0.0, 1.0)
const ACCENT_HOVER := Color(1.0, 0.88, 0.22, 1.0)
const ACCENT_PRESSED := Color(0.86, 0.66, 0.0, 1.0)
const DISABLED := Color(0.18, 0.18, 0.19, 0.92)
const INK_COLOR := Color(0.025, 0.020, 0.014, 0.965)
## Slider rows: store key, label key, value shown per store unit, step shown, value format.
const SLIDERS: Array = [
	["mouse_sensitivity_multiplier", "SETTINGS_MOUSE_SENSITIVITY", 100.0, 5.0, "%d%%"],
	["stick_sensitivity_multiplier", "SETTINGS_STICK_SENSITIVITY", 100.0, 5.0, "%d%%"],
	["fov_offset_deg", "SETTINGS_FIELD_OF_VIEW", 1.0, 1.0, "%+d°"],
	["distance_scale", "SETTINGS_CAMERA_DISTANCE", 100.0, 5.0, "%d%%"],
]
const CHECKS: Array = [["invert_y", "SETTINGS_INVERT_Y"], ["left_shoulder", "SETTINGS_LEFT_SHOULDER"]]

const INK_APPEAR_DURATION: float = 0.58
const INK_SETTLE_DURATION: float = 0.88
const TITLE_REVEAL_DELAY: float = 0.43
const BODY_REVEAL_DELAY: float = 0.55
const BUTTONS_REVEAL_DELAY: float = 0.70
const TITLE_REVEAL_DURATION: float = 0.16
const BODY_REVEAL_DURATION: float = 0.22
const BUTTONS_REVEAL_DURATION: float = 0.18
const CONTENT_FADE_OUT_DURATION: float = 0.16
const INK_DISSOLVE_DURATION: float = 0.34

var _saved: Dictionary = STORE.defaults()
var _saved_quality: StringName = GRAPHICS.DEFAULT_QUALITY

var _frame_root: Control
var _blot_material: ShaderMaterial
var _title_label: Label
var _settings_body: VBoxContainer
var _buttons_row: HBoxContainer
var _quality_option: OptionButton
## Controls by store key.
var _sliders: Dictionary = {}
var _slider_values: Dictionary = {}
var _checks: Dictionary = {}
var _accept_button: Button
var _transition: Tween
var _closing: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	resized.connect(_layout_frame)
	_layout_frame()
	visible = false


func open() -> void:
	_saved = STORE.load_camera()
	_saved_quality = GRAPHICS.load_quality()
	for row: Array in SLIDERS:
		(_sliders[row[0]] as HSlider).set_value_no_signal(float(_saved[row[0]]) * float(row[2]))
	for row: Array in CHECKS:
		(_checks[row[0]] as CheckBox).set_pressed_no_signal(bool(_saved[row[0]]))
	_quality_option.select(GRAPHICS.index_of(_saved_quality))
	_refresh_value_label()
	_refresh_dirty_state()
	_begin_appear()


func is_open() -> bool:
	return visible


func back() -> void:
	if not visible or _closing:
		return
	_begin_hide(false)


func _accept() -> void:
	if _closing or _accept_button.disabled:
		return

	var staged: Dictionary = _staged()
	var quality: StringName = GRAPHICS.from_index(_quality_option.selected)
	var camera_error: Error = STORE.save_values(staged)
	if camera_error != OK:
		push_warning("CameraSettingsPanel: camera settings save failed (error %d)" % camera_error)
		return
	var graphics_error: Error = GRAPHICS.save_quality(quality)
	if graphics_error != OK:
		push_warning("CameraSettingsPanel: graphics settings save failed (error %d)" % graphics_error)
		return

	_saved = staged
	_saved_quality = quality
	if is_inside_tree():
		get_tree().call_group(CAMERA_GROUP, &"reload_user_settings")
		GRAPHICS.apply(get_tree(), quality)
	_refresh_dirty_state()
	_begin_hide(true)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		back()
		get_viewport().set_input_as_handled()


func _build() -> void:
	var shade := ColorRect.new()
	shade.name = "SettingsShade"
	shade.color = Color(0.0, 0.0, 0.0, 0.48)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	_frame_root = Control.new()
	_frame_root.name = "InkSettingsFrame"
	_frame_root.size = FRAME_SIZE
	_frame_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame_root)
	_layout_frame()

	var blot := ColorRect.new()
	blot.name = "SettingsInkBlot"
	blot.position = FRAME_SIZE * 0.5 - BLOT_SIZE * BLOT_VISUAL_CENTER_UV
	blot.size = BLOT_SIZE
	blot.color = Color.WHITE
	blot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blot_material = ShaderMaterial.new()
	_blot_material.shader = BLOT_SHADER
	_blot_material.set_shader_parameter("progress", 0.0)
	_blot_material.set_shader_parameter("stagger", 0.68)
	_blot_material.set_shader_parameter("entrance_seed", 0.0)
	_blot_material.set_shader_parameter("blob_color", INK_COLOR)
	_blot_material.set_shader_parameter("radius_scale", 0.0)
	_blot_material.set_shader_parameter("edge_ragged", 0.055)
	_blot_material.set_shader_parameter("warp_scale", 4.5)
	_blot_material.set_shader_parameter("rect_size", BLOT_SIZE)
	_blot_material.set_shader_parameter("idle_drift", 0.0)
	_blot_material.set_shader_parameter("canvas_padding", BLOT_CANVAS_PADDING)
	blot.material = _blot_material
	_frame_root.add_child(blot)

	var content := VBoxContainer.new()
	content.name = "SettingsContent"
	content.position = (FRAME_SIZE - CONTENT_SIZE) * 0.5
	content.size = CONTENT_SIZE
	content.add_theme_constant_override("separation", 16)
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	_frame_root.add_child(content)

	_title_label = Label.new()
	_title_label.name = "SettingsTitle"
	_title_label.text = tr("SETTINGS_TITLE")
	_title_label.add_theme_font_size_override("font_size", 32)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.modulate.a = 0.0
	content.add_child(_title_label)

	_settings_body = VBoxContainer.new()
	_settings_body.name = "SettingsBody"
	_settings_body.add_theme_constant_override("separation", 8)
	_settings_body.modulate.a = 0.0
	content.add_child(_settings_body)

	var quality_row := HBoxContainer.new()
	quality_row.name = "GraphicsQualityRow"
	quality_row.add_theme_constant_override("separation", 12)
	_settings_body.add_child(quality_row)
	var quality_label := Label.new()
	quality_label.text = "Graphics quality"
	quality_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quality_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.90, 1.0))
	quality_row.add_child(quality_label)
	_quality_option = OptionButton.new()
	_quality_option.name = "GraphicsQuality"
	_quality_option.custom_minimum_size = Vector2(150.0, 36.0)
	for quality: StringName in GRAPHICS.ORDER:
		_quality_option.add_item(String(quality).to_upper())
	_quality_option.select(GRAPHICS.index_of(GRAPHICS.DEFAULT_QUALITY))
	_quality_option.item_selected.connect(_on_quality_selected)
	quality_row.add_child(_quality_option)

	var quality_hint := Label.new()
	quality_hint.text = "LOW targets integrated GPUs; gameplay and footprint accuracy stay unchanged."
	quality_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quality_hint.add_theme_font_size_override("font_size", 13)
	quality_hint.add_theme_color_override("font_color", Color(0.72, 0.72, 0.70, 0.88))
	_settings_body.add_child(quality_hint)

	var quality_gap := Control.new()
	quality_gap.custom_minimum_size.y = 6.0
	_settings_body.add_child(quality_gap)

	for row: Array in SLIDERS:
		_add_slider_row(row)
	for row: Array in CHECKS:
		var check := CheckBox.new()
		check.name = String(row[0]).to_pascal_case()
		check.text = tr(row[1])
		check.toggled.connect(_on_invert_toggled)
		_settings_body.add_child(check)
		_checks[row[0]] = check

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(spacer)

	_buttons_row = HBoxContainer.new()
	_buttons_row.name = "SettingsButtons"
	_buttons_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons_row.add_theme_constant_override("separation", 14)
	_buttons_row.modulate.a = 0.0
	content.add_child(_buttons_row)

	var back_button := Button.new()
	back_button.name = "BackButton"
	back_button.text = tr("SETTINGS_BACK")
	back_button.custom_minimum_size = Vector2(150.0, 42.0)
	back_button.pressed.connect(back)
	_buttons_row.add_child(back_button)

	_accept_button = Button.new()
	_accept_button.name = "AcceptButton"
	_accept_button.text = tr("SETTINGS_ACCEPT")
	_accept_button.custom_minimum_size = Vector2(150.0, 42.0)
	_accept_button.add_theme_stylebox_override("disabled", _button_style(DISABLED))
	_accept_button.add_theme_stylebox_override("normal", _button_style(ACCENT))
	_accept_button.add_theme_stylebox_override("hover", _button_style(ACCENT_HOVER))
	_accept_button.add_theme_stylebox_override("pressed", _button_style(ACCENT_PRESSED))
	_accept_button.add_theme_color_override("font_color", Color(0.08, 0.07, 0.04))
	_accept_button.add_theme_color_override("font_hover_color", Color(0.05, 0.045, 0.025))
	_accept_button.add_theme_color_override("font_pressed_color", Color(0.05, 0.045, 0.025))
	_accept_button.add_theme_color_override("font_disabled_color", Color(0.58, 0.59, 0.61))
	_accept_button.pressed.connect(_accept)
	_buttons_row.add_child(_accept_button)

	_refresh_value_label()
	_refresh_dirty_state()


## One line: label, slider, value. The slider works in shown units (percent, degrees).
func _add_slider_row(row: Array) -> void:
	var key: String = row[0]
	var scale: float = row[2]
	var line := HBoxContainer.new()
	line.name = key.to_pascal_case() + "Row"
	line.add_theme_constant_override("separation", 10)
	_settings_body.add_child(line)
	var label := Label.new()
	label.text = tr(row[1])
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.90, 1.0))
	line.add_child(label)
	var slider := HSlider.new()
	slider.name = key.to_pascal_case() + "Slider"
	slider.min_value = float(STORE.RANGES[key][1]) * scale
	slider.max_value = float(STORE.RANGES[key][2]) * scale
	slider.step = float(row[3])
	slider.value = float(STORE.RANGES[key][0]) * scale
	slider.custom_minimum_size = Vector2(170.0, 30.0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(_on_value_changed)
	line.add_child(slider)
	var value := Label.new()
	value.name = key.to_pascal_case() + "Value"
	value.custom_minimum_size.x = 56.0
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_color_override("font_color", Color(1.0, 0.86, 0.42, 0.95))
	line.add_child(value)
	_sliders[key] = slider
	_slider_values[key] = value


## What the controls hold now, in store units.
func _staged() -> Dictionary:
	var values: Dictionary = {}
	for row: Array in SLIDERS:
		values[row[0]] = (_sliders[row[0]] as HSlider).value / float(row[2])
	for row: Array in CHECKS:
		values[row[0]] = (_checks[row[0]] as CheckBox).button_pressed
	return values


func _layout_frame() -> void:
	if _frame_root == null:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	_frame_root.position = (viewport_size - FRAME_SIZE) * 0.5
	_frame_root.size = FRAME_SIZE


func _begin_appear() -> void:
	_kill_transition()
	_closing = false
	visible = true
	_title_label.modulate.a = 0.0
	_settings_body.modulate.a = 0.0
	_buttons_row.modulate.a = 0.0
	_set_blot_progress(0.0)
	_set_blot_radius_scale(0.0)
	_blot_material.set_shader_parameter("entrance_seed", randf() * 100.0)
	_transition = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	_transition.tween_method(_set_blot_progress, 0.0, 1.0, INK_APPEAR_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_transition.tween_method(_set_blot_radius_scale, 0.0, BLOT_FINAL_SCALE, INK_SETTLE_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_transition.tween_property(_title_label, "modulate:a", 1.0, TITLE_REVEAL_DURATION).set_delay(TITLE_REVEAL_DELAY).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_transition.tween_property(_settings_body, "modulate:a", 1.0, BODY_REVEAL_DURATION).set_delay(BODY_REVEAL_DELAY).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_transition.tween_property(_buttons_row, "modulate:a", 1.0, BUTTONS_REVEAL_DURATION).set_delay(BUTTONS_REVEAL_DELAY).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func _begin_hide(saved: bool) -> void:
	_kill_transition()
	_closing = true
	_transition = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_transition.tween_property(_buttons_row, "modulate:a", 0.0, CONTENT_FADE_OUT_DURATION)
	_transition.parallel().tween_property(_settings_body, "modulate:a", 0.0, CONTENT_FADE_OUT_DURATION)
	_transition.parallel().tween_property(_title_label, "modulate:a", 0.0, CONTENT_FADE_OUT_DURATION)
	_transition.tween_method(_set_blot_progress, _blot_progress(), 0.0, INK_DISSOLVE_DURATION).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_transition.parallel().tween_method(_set_blot_radius_scale, _blot_radius_scale(), 0.0, INK_DISSOLVE_DURATION).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	_transition.tween_callback(_finish_hide.bind(saved))


func _finish_hide(saved: bool) -> void:
	visible = false
	_closing = false
	_transition = null
	closed.emit(saved)


func _on_value_changed(_value: float) -> void:
	_refresh_value_label()
	_refresh_dirty_state()


func _on_invert_toggled(_pressed: bool) -> void:
	_refresh_dirty_state()


func _on_quality_selected(_index: int) -> void:
	_refresh_dirty_state()


func _refresh_value_label() -> void:
	for row: Array in SLIDERS:
		if _slider_values.has(row[0]):
			(_slider_values[row[0]] as Label).text = String(row[4]) % int(round((_sliders[row[0]] as HSlider).value))


func _refresh_dirty_state() -> void:
	if _accept_button == null or _quality_option == null or _sliders.size() < SLIDERS.size() or _checks.size() < CHECKS.size():
		return
	var staged: Dictionary = _staged()
	var dirty: bool = GRAPHICS.from_index(_quality_option.selected) != _saved_quality
	for key: String in staged:
		if staged[key] is bool:
			dirty = dirty or staged[key] != bool(_saved[key])
		else:
			dirty = dirty or not is_equal_approx(float(staged[key]), float(_saved[key]))
	_accept_button.disabled = not dirty


func _blot_progress() -> float:
	return float(_blot_material.get_shader_parameter("progress")) if _blot_material != null else 0.0


func _set_blot_progress(value: float) -> void:
	if _blot_material != null:
		_blot_material.set_shader_parameter("progress", clampf(value, 0.0, 1.0))


func _blot_radius_scale() -> float:
	return float(_blot_material.get_shader_parameter("radius_scale")) if _blot_material != null else 0.0


func _set_blot_radius_scale(value: float) -> void:
	if _blot_material != null:
		_blot_material.set_shader_parameter("radius_scale", clampf(value, 0.0, 2.0))


func _kill_transition() -> void:
	if _transition != null and _transition.is_valid():
		_transition.kill()
	_transition = null


func _button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style
