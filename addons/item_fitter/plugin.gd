@tool
extends EditorPlugin

const DOCK_SCENE: PackedScene = preload("res://addons/item_fitter/item_fitter_dock.tscn")

var _dock: Control


func _enter_tree() -> void:
	_dock = DOCK_SCENE.instantiate()
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, _dock)


func _exit_tree() -> void:
	if _dock == null:
		return
	if _dock.has_method(&"clear_preview"):
		_dock.call(&"clear_preview")
	remove_control_from_docks(_dock)
	_dock.queue_free()
	_dock = null
