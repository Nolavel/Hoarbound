@tool
class_name ContainerFramingStage
extends Node3D

## Editor stage for the container framing (owner): move Camera, Pack and Henry, preview through Camera, then
## Save framing. They are kept relative to Front (the cabinet shelves' open face), for the pack on its right.

@export_tool_button("Save framing", "Save") var save_action: Callable = save_framing
@export_tool_button("Load saved framing", "Load") var load_action: Callable = load_framing

@onready var _front: Node3D = $Front
@onready var _camera: Camera3D = $Front/Camera
@onready var _pack: Node3D = $Front/Pack
@onready var _henry: Node3D = $Front/Henry


## Writes the markers to ContainerFraming.PATH; the game frames every container by it.
func save_framing() -> void:
	var framing := ContainerFraming.new()
	framing.camera = _camera.transform
	framing.camera_fov = _camera.fov
	framing.pack = _pack.transform
	framing.henry = _henry.transform
	framing.show_henry = _henry.visible
	var error: Error = ResourceSaver.save(framing, ContainerFraming.PATH)
	print("ContainerFramingStage: saved %s (%s)" % [ContainerFraming.PATH, error_string(error)])


## Puts the markers where the saved framing has them.
func load_framing() -> void:
	var framing: ContainerFraming = ContainerFraming.load_saved()
	if framing == null:
		push_warning("ContainerFramingStage: nothing saved at %s" % ContainerFraming.PATH)
		return
	_camera.transform = framing.camera
	_camera.fov = framing.camera_fov
	_pack.transform = framing.pack
	_henry.transform = framing.henry
	_henry.visible = framing.show_henry
