extends Node3D

var _native_controller: Node

func _ready() -> void:
	if not ClassDB.class_exists(&"HoarboundFrostController"):
		push_error(
			"Hoarbound native artifact is not installed. "
			+ "Run: python tools/native/install_native_artifact.py --branch main"
		)
		return

	_native_controller = ClassDB.instantiate(&"HoarboundFrostController") as Node
	if _native_controller == null:
		push_error("HoarboundFrostController could not be instantiated")
		return

	_native_controller.name = "NativeFrostController"
	_native_controller.call(&"bind_scene", self)
	add_child(_native_controller)
