class_name PauseMenu
extends Control

## Esc pauses and offers Resume or Quit to title. There is no save here on
## purpose: the game saves only when Henry sleeps.

const PAUSE_ACTION: StringName = &"pause"
const PLAYER_STATE_PATH: NodePath = ^"/root/PlayerState"
const SETTINGS_PANEL_SCRIPT: GDScript = preload("res://scripts/ui/menu/camera_settings_panel.gd")

@export_group("Scenes")
@export_file("*.tscn") var title_scene: String = "res://scenes/ui/menu/title_menu.tscn"

var _is_open: bool = false
var _panel: Control
var _settings_panel: CameraSettingsPanel


func _ready() -> void:
	## Must keep hearing Esc while the tree it paused is stopped.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_panel.visible = false


## The sleep dialog also answers Esc and marks it handled first, so this only
## sees Esc when no other modal wanted it.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(PAUSE_ACTION):
		return
	if _is_open and _settings_panel != null and _settings_panel.is_open():
		_settings_panel.back()
	elif _is_open:
		resume()
	elif not _is_other_menu_open():
		open()
	else:
		return
	get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _is_open


func open() -> void:
	if _is_open:
		return
	_is_open = true
	_panel.visible = true
	_player_state_call(&"open_menu")


func resume() -> void:
	if not _is_open:
		return
	_is_open = false
	_panel.visible = false
	_player_state_call(&"close_menu")


func open_settings() -> void:
	if not _is_open or _settings_panel == null:
		return
	_panel.visible = false
	_settings_panel.open()


func _on_settings_closed(_saved: bool) -> void:
	if _is_open:
		_panel.visible = true


func quit_to_title() -> void:
	resume()
	get_tree().paused = false
	get_tree().change_scene_to_file(title_scene)


## True when something else, the sleep dialog say, already holds the menu mode.
func _is_other_menu_open() -> bool:
	var state := get_node_or_null(PLAYER_STATE_PATH) as PlayerStateService
	return state != null and bool(state.is_paused())


## Pause belongs to PlayerState, which couples it to the tree; tests run
## without the autoload, so its absence falls back to pausing directly.
func _player_state_call(method: StringName) -> void:
	var state := get_node_or_null(PLAYER_STATE_PATH) as PlayerStateService
	if state != null:
		state.call(method)
	elif is_inside_tree():
		get_tree().paused = method == &"open_menu"


func _build() -> void:
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)

	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(shade)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.add_theme_constant_override("separation", 12)
	_panel.add_child(column)

	var title := Label.new()
	title.text = tr("PAUSE_TITLE")
	title.add_theme_font_size_override("font_size", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	column.add_child(_button("PAUSE_RESUME", resume))
	column.add_child(_button("MENU_SETTINGS", open_settings))
	column.add_child(_button("PAUSE_TO_TITLE", quit_to_title))

	var hint := Label.new()
	hint.text = tr("PAUSE_UNSAVED_HINT")
	hint.modulate = Color(1.0, 1.0, 1.0, 0.6)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)
	column.position -= column.get_combined_minimum_size() * 0.5

	_settings_panel = SETTINGS_PANEL_SCRIPT.new() as CameraSettingsPanel
	_settings_panel.closed.connect(_on_settings_closed)
	add_child(_settings_panel)


func _button(key: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = tr(key)
	button.custom_minimum_size = Vector2(300.0, 42.0)
	button.pressed.connect(action)
	return button
