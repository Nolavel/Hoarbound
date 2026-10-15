class_name TitleMenu
extends Control

## The first screen: a new game, or back to the last place Henry slept.
## Deliberately bare; how it looks is the author's call, not this file's.

const SETTINGS_PANEL_SCRIPT: GDScript = preload("res://scripts/ui/menu/camera_settings_panel.gd")

@export_group("Scenes")
## The scene New game and Continue both open.
@export_file("*.tscn") var game_scene: String = "res://scenes/world/key_west/key_west_reality.tscn"

var _continue_button: Button
var _status_label: Label
var _menu_column: VBoxContainer
var _settings_panel: CameraSettingsPanel


func _ready() -> void:
	## A pause left over from a game quit mid-menu must not freeze the title.
	get_tree().paused = false
	## A camera freed mid-capture must not leave the title without a pointer.
	InputSystems.set_look_capture(false)
	_build()
	refresh()


## Enables Continue only when there is a sleep to continue from.
func refresh() -> void:
	var can_continue: bool = SaveManager.has_sleep_save()
	_continue_button.disabled = not can_continue
	_status_label.text = "" if can_continue else tr("MENU_NO_SAVE")


func start_new_game() -> void:
	SaveManager.pending_load_slot = -1
	_open_game()


func continue_game() -> void:
	if not SaveManager.has_sleep_save():
		refresh()
		return
	SaveManager.pending_load_slot = SaveManager.SLEEP_SLOT
	_open_game()


func open_settings() -> void:
	if _settings_panel == null:
		return
	_menu_column.visible = false
	_settings_panel.open()


func _on_settings_closed(_saved: bool) -> void:
	_menu_column.visible = true


func quit_game() -> void:
	get_tree().quit()


func _open_game() -> void:
	var error: Error = get_tree().change_scene_to_file(game_scene)
	if error != OK:
		push_error("TitleMenu: cannot open %s (error %d)" % [game_scene, error])
		SaveManager.pending_load_slot = -1


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color(0.04, 0.05, 0.08)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	_menu_column = VBoxContainer.new()
	_menu_column.set_anchors_preset(Control.PRESET_CENTER)
	_menu_column.alignment = BoxContainer.ALIGNMENT_CENTER
	_menu_column.add_theme_constant_override("separation", 14)
	add_child(_menu_column)
	var column: VBoxContainer = _menu_column

	var title := Label.new()
	title.text = tr("MENU_TITLE")
	title.add_theme_font_size_override("font_size", 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	column.add_child(_button("MENU_NEW_GAME", start_new_game))
	_continue_button = _button("MENU_CONTINUE", continue_game)
	column.add_child(_continue_button)
	column.add_child(_button("MENU_SETTINGS", open_settings))
	column.add_child(_button("MENU_QUIT", quit_game))

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.modulate = Color(1.0, 1.0, 1.0, 0.6)
	column.add_child(_status_label)
	column.position -= column.get_combined_minimum_size() * 0.5

	_settings_panel = SETTINGS_PANEL_SCRIPT.new() as CameraSettingsPanel
	_settings_panel.closed.connect(_on_settings_closed)
	add_child(_settings_panel)


func _button(key: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = tr(key)
	button.custom_minimum_size = Vector2(320.0, 44.0)
	button.pressed.connect(action)
	return button
