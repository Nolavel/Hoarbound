class_name KeyHintsPanel
extends Control

## Production port of ADT's lower-right KeyHintsPanel.
## Visual constants and transition order intentionally match ADT.
## HFN adapts only the state source: PlayerState + the real Hub/Rest components.

const _KEY_LABEL_SUFFIXES: Array[String] = [" - Physical", " (Physical)"]
const _MOUSE_BUTTON_LABELS: Dictionary = {
	MOUSE_BUTTON_LEFT: "LMB",
	MOUSE_BUTTON_RIGHT: "RMB",
	MOUSE_BUTTON_MIDDLE: "MMB",
	MOUSE_BUTTON_WHEEL_UP: "Wheel Up",
	MOUSE_BUTTON_WHEEL_DOWN: "Wheel Dn",
	MOUSE_BUTTON_WHEEL_LEFT: "Wheel Left",
	MOUSE_BUTTON_WHEEL_RIGHT: "Wheel Right",
	MOUSE_BUTTON_XBUTTON1: "MB4",
	MOUSE_BUTTON_XBUTTON2: "MB5",
}

class _Column:
	var container: VBoxContainer
	var rows_list: VBoxContainer
	var rows: Dictionary = {}

@export var catalog: KeyHintsCatalog

@export_group("Style")
@export var key_color: Color = Color(0.973, 0.910, 0.753, 1.0)
@export var key_box_color: Color = Color(0.118, 0.094, 0.063, 0.85)
@export var key_border_color: Color = Color(0.706, 0.549, 0.275, 0.6)
@export var description_color: Color = Color(0.88, 0.88, 0.88, 1.0)
@export var header_color: Color = Color(0.55, 0.55, 0.55, 0.85)
@export var font_size: int = 14
@export var key_font_size: int = 12
@export var header_font_size: int = 11
@export var group_key_separator: String = " / "
@export var key_description_gap: float = 6.0
@export var row_gap: float = 8.0
@export var category_gap: float = 14.0
@export var content_padding: Vector2 = Vector2(18.0, 14.0)

@export_group("Placement")
@export var panel_scale: float = 0.82
@export var right_margin: float = 24.0
@export var bottom_margin: float = 20.0

@export_group("Blot")
@export var blot_scale: Vector2 = Vector2(1.9, 1.55)
@export var blot_bleed: float = 28.0

@export_group("Animation")
@export var appear_duration: float = 0.8
@export var initial_appear_delay: float = 1.0
@export var content_fade_in_duration: float = 0.4
@export var initial_blot_radius_scale: float = 0.0
@export var assembled_blot_radius_scale: float = 0.8
@export var blot_settle_duration: float = 3.0
@export var text_fade_out_duration: float = 0.22
@export var dissolve_duration: float = 0.35

@onready var _blot_layer: ColorRect = $BlotLayer
@onready var _content: VBoxContainer = $Content
@onready var _title_label: Label = $Content/TitleLabel
@onready var _columns_box: VBoxContainer = $Content/Rows

var _mono_font: Font
var _columns: Dictionary = {}
var _transition: Tween
var _shown_row_keys: Array[StringName] = []
var _player: Node
var _hub: PlayerHubComponent
var _rest: RestComponent
var _context: int = KeyHintEntry.Context.DEFAULT


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blot_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_columns_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_columns_box.add_theme_constant_override("separation", int(category_gap))
	_mono_font = _build_mono_font()
	_style_title()
	_build_columns()
	resized.connect(_reposition)
	get_viewport().size_changed.connect(_reposition)
	var state := _player_state()
	if state != null and state.has_signal(&"mode_changed"):
		state.connect(&"mode_changed", _on_mode_changed)
	visible = false
	_set_blot_progress(0.0)
	_content.modulate.a = 0.0
	_reposition()
	_rebuild(initial_appear_delay)


func on_world_ready(context: WorldContext) -> void:
	_player = context.player if context != null else null
	if _player != null:
		_hub = _player.get_node_or_null(^"PlayerHubComponent") as PlayerHubComponent
		_rest = _player.get_node_or_null(^"RestComponent") as RestComponent
	if _hub != null:
		if not _hub.hub_opened.is_connected(_refresh_context):
			_hub.hub_opened.connect(_refresh_context)
		if not _hub.hub_closed.is_connected(_refresh_context):
			_hub.hub_closed.connect(_refresh_context)
	if _rest != null:
		if not _rest.sat_down.is_connected(_on_sat_down):
			_rest.sat_down.connect(_on_sat_down)
		if not _rest.stood_up.is_connected(_refresh_context):
			_rest.stood_up.connect(_refresh_context)
	_refresh_context()


func _on_sat_down(_spot: Node3D) -> void:
	_refresh_context()


func _refresh_context() -> void:
	var next := KeyHintEntry.Context.DEFAULT
	if _hub != null and _hub.is_open():
		next = KeyHintEntry.Context.HUB
	elif _rest != null and _rest.is_sitting():
		next = KeyHintEntry.Context.SITTING
	if next == _context:
		return
	_context = next
	_rebuild()


## PlayerState outlives the HUD: a world torn down (quit to title) still restores modes after
## the panel has left the tree, and a detached panel has nothing to lay out.
func _on_mode_changed(_old_mode: int, _new_mode: int) -> void:
	if is_inside_tree():
		_rebuild()


func _style_title() -> void:
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_label.add_theme_font_size_override("font_size", header_font_size)
	_title_label.add_theme_color_override("font_color", header_color)
	_title_label.add_theme_constant_override("spacing", 3)


func _build_columns() -> void:
	for category in KeyHintEntry.Category.values():
		var column := _Column.new()
		column.container = VBoxContainer.new()
		column.container.name = "Column_%s" % KeyHintEntry.Category.keys()[category]
		column.container.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var header := Label.new()
		header.text = KeyHintEntry.Category.keys()[category].capitalize()
		header.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header.add_theme_font_size_override("font_size", header_font_size)
		header.add_theme_color_override("font_color", header_color)
		column.container.add_child(header)

		column.rows_list = VBoxContainer.new()
		column.rows_list.name = "Rows"
		column.rows_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.rows_list.add_theme_constant_override("separation", int(row_gap))
		column.container.add_child(column.rows_list)

		_columns_box.add_child(column.container)
		_columns[category] = column


func _rebuild(delay: float = 0.0) -> void:
	if catalog == null:
		push_warning("[KeyHintsPanel] no catalog assigned")
		return
	var state := _player_state()
	var mode: int = int(state.get("mode")) if state != null else 0
	var active := catalog.get_active_entries(mode, int(_context))
	var wanted := _collect_row_keys(active)

	if wanted.is_empty():
		_shown_row_keys = wanted
		_apply_rebuild(active)
		if visible:
			_begin_hide()
		return

	if wanted == _shown_row_keys:
		if not visible:
			visible = true
			_begin_appear(delay)
		return

	if not visible or _blot_progress() <= 0.01:
		_apply_rebuild(active)
		_shown_row_keys = wanted
		visible = true
		_begin_appear(delay)
		return

	_kill_transition()
	_transition = create_tween()
	_transition.tween_property(_content, "modulate:a", 0.0, text_fade_out_duration)
	_transition.tween_method(_set_blot_progress, _blot_progress(), 0.0, dissolve_duration)
	_transition.tween_callback(func() -> void:
		_apply_rebuild(active)
		_shown_row_keys = wanted
		_begin_appear()
	)


func _collect_row_keys(active: Array[KeyHintEntry]) -> Array[StringName]:
	var keys: Array[StringName] = []
	for entry: KeyHintEntry in active:
		keys.append(entry.get_row_key())
	return keys


func _apply_rebuild(active: Array[KeyHintEntry]) -> void:
	var active_by_category: Dictionary = {}
	for entry: KeyHintEntry in active:
		if not active_by_category.has(entry.category):
			active_by_category[entry.category] = []
		(active_by_category[entry.category] as Array).append(entry)
	for category in _columns.keys():
		var column: _Column = _columns[category]
		_rebuild_column(column, active_by_category.get(category, []))
	_reposition()


func _rebuild_column(column: _Column, active_entries: Array) -> void:
	var wanted: Array[StringName] = []
	for entry: KeyHintEntry in active_entries:
		wanted.append(entry.get_row_key())
	for row_key in column.rows.keys():
		if not wanted.has(row_key):
			var stale: Control = column.rows[row_key]
			stale.queue_free()
			column.rows.erase(row_key)
	for i in active_entries.size():
		var entry: KeyHintEntry = active_entries[i]
		var row_key := entry.get_row_key()
		var row: Control = column.rows.get(row_key) as Control
		if row == null:
			row = _make_row(entry)
			column.rows_list.add_child(row)
			column.rows[row_key] = row
		column.rows_list.move_child(row, i)
	column.container.visible = not active_entries.is_empty()


func _make_row(entry: KeyHintEntry) -> Control:
	var row := HBoxContainer.new()
	row.name = "Row_%s" % entry.get_row_key()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", int(key_description_gap))

	var labels := _resolve_entry_key_labels(entry)
	for i in labels.size():
		if i > 0:
			var joiner := Label.new()
			joiner.text = group_key_separator.strip_edges()
			joiner.mouse_filter = Control.MOUSE_FILTER_IGNORE
			joiner.add_theme_font_size_override("font_size", font_size)
			joiner.add_theme_color_override("font_color", description_color)
			row.add_child(joiner)
		row.add_child(_make_key_box(labels[i]))

	var desc := Label.new()
	desc.text = entry.description
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc.add_theme_font_size_override("font_size", font_size)
	desc.add_theme_color_override("font_color", description_color)
	row.add_child(desc)
	return row


func _make_key_box(label_text: String) -> Control:
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style := StyleBoxFlat.new()
	style.bg_color = key_box_color
	style.border_color = key_border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 1.0
	style.content_margin_bottom = 1.0
	box.add_theme_stylebox_override("panel", style)

	var key_label := Label.new()
	key_label.text = label_text
	key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_label.add_theme_font_override("font", _mono_font)
	key_label.add_theme_font_size_override("font_size", key_font_size)
	key_label.add_theme_color_override("font_color", key_color)
	box.add_child(key_label)
	return box


func _resolve_entry_key_labels(entry: KeyHintEntry) -> Array[String]:
	var labels: Array[String] = []
	for action_name: StringName in entry.get_action_names():
		labels.append(_resolve_key_label(action_name))
	return labels


func _resolve_key_label(action_name: StringName) -> String:
	if action_name == &"" or not InputMap.has_action(action_name):
		return "?"
	var events := InputMap.action_get_events(action_name)
	if events.is_empty():
		return "?"
	return _format_event_label(_pick_display_event(events))


func _pick_display_event(events: Array) -> InputEvent:
	for event: InputEvent in events:
		if event is InputEventKey:
			return event
	return events[0] as InputEvent


func _format_event_label(event: InputEvent) -> String:
	if event is InputEventKey:
		return _format_key_label(event as InputEventKey)
	if event is InputEventMouseButton:
		return _format_mouse_button_label(event as InputEventMouseButton)
	return event.as_text().strip_edges()


func _format_key_label(event: InputEventKey) -> String:
	var text := event.as_text()
	for suffix: String in _KEY_LABEL_SUFFIXES:
		var index := text.rfind(suffix)
		if index != -1:
			text = text.substr(0, index)
			break
	var paren_index := text.find(" (")
	if paren_index != -1:
		text = text.substr(0, paren_index)
	return text.strip_edges()


func _format_mouse_button_label(event: InputEventMouseButton) -> String:
	if _MOUSE_BUTTON_LABELS.has(event.button_index):
		return _MOUSE_BUTTON_LABELS[event.button_index]
	return "MB%d" % event.button_index


func _reposition() -> void:
	if not is_instance_valid(_content) or not is_instance_valid(_blot_layer):
		return
	var content_min := _content.get_combined_minimum_size()
	_content.position = content_padding
	_content.size = content_min
	size = content_min + content_padding * 2.0
	scale = Vector2.ONE * panel_scale
	var viewport_size := get_viewport_rect().size
	global_position = Vector2(
		viewport_size.x - size.x * panel_scale - right_margin,
		viewport_size.y - size.y * panel_scale - bottom_margin
	)
	var blot_size := Vector2(size.x * blot_scale.x, size.y * blot_scale.y)
	_blot_layer.size = blot_size
	_blot_layer.position = size - blot_size + Vector2.ONE * blot_bleed
	var mat := _blot_layer.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("rect_size", blot_size)


func _blot_progress() -> float:
	var mat := _blot_layer.material as ShaderMaterial
	return float(mat.get_shader_parameter("progress")) if mat != null else 0.0


func _set_blot_progress(value: float) -> void:
	var mat := _blot_layer.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("progress", clampf(value, 0.0, 1.0))


func _blot_radius_scale() -> float:
	var mat := _blot_layer.material as ShaderMaterial
	return float(mat.get_shader_parameter("radius_scale")) if mat != null else initial_blot_radius_scale


func _set_blot_radius_scale(value: float) -> void:
	var mat := _blot_layer.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("radius_scale", clampf(value, 0.0, 2.0))


func _set_blot_entrance_seed(value: float) -> void:
	var mat := _blot_layer.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("entrance_seed", value)


func _begin_appear(delay: float = 0.0) -> void:
	_kill_transition()
	visible = true
	_content.modulate.a = 0.0
	_set_blot_entrance_seed(randf())
	_set_blot_radius_scale(initial_blot_radius_scale)
	_transition = create_tween()
	if delay > 0.0:
		_transition.tween_interval(delay)
	_transition.tween_method(_set_blot_progress, _blot_progress(), 1.0, appear_duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_transition.parallel().tween_method(
		_set_blot_radius_scale, _blot_radius_scale(), assembled_blot_radius_scale, appear_duration
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_transition.tween_property(_content, "modulate:a", 1.0, content_fade_in_duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_transition.tween_method(
		_set_blot_radius_scale, assembled_blot_radius_scale, 1.0, blot_settle_duration
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)


func _begin_hide() -> void:
	_kill_transition()
	_transition = create_tween()
	_transition.tween_property(_content, "modulate:a", 0.0, text_fade_out_duration)
	_transition.tween_method(_set_blot_progress, _blot_progress(), 0.0, dissolve_duration)
	_transition.tween_callback(func() -> void: visible = false)


func _kill_transition() -> void:
	if _transition != null and _transition.is_valid():
		_transition.kill()
	_transition = null


func _build_mono_font() -> Font:
	var system_font := SystemFont.new()
	system_font.font_names = ["Consolas", "Courier New", "DejaVu Sans Mono", "monospace"]
	return system_font


## Tests may instantiate World without project autoload globals. Resolve the
## singleton by path so this UI stays loadable in those isolated script runs.
func _player_state() -> Node:
	return get_node_or_null(^"/root/PlayerState")
