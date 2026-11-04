class_name UniversalBlobMask
extends ColorRect

## Reusable 2D SDF union: positions in [0, 1], radii relative to rect height.
## Each instance owns its material, so independently animated masks never alias.

enum DisplayMode { FILL, OUTLINE, FILL_OUTLINE, MASK }

const MAX_BLOBS: int = 16
const MASK_SHADER: Shader = preload("res://shaders/ui/universal_blob_mask.gdshader")

@export var display_mode: DisplayMode = DisplayMode.OUTLINE:
	set(value):
		display_mode = value
		_push_style()
@export_range(0.001, 0.3, 0.001) var merge_width: float = 0.1:
	set(value):
		merge_width = maxf(value, 0.001)
		_push_style()
@export_range(0.001, 0.05, 0.001) var stroke_width: float = 0.008:
	set(value):
		stroke_width = maxf(value, 0.001)
		_push_style()
@export_range(0.1, 3.0, 0.1) var edge_softness: float = 1.0:
	set(value):
		edge_softness = maxf(value, 0.1)
		_push_style()
@export var fill_color: Color = Color.WHITE:
	set(value):
		fill_color = value
		_push_style()
@export var outline_color: Color = Color.WHITE:
	set(value):
		outline_color = value
		_push_style()
@export var background_color: Color = Color(0.0, 0.0, 0.0, 0.0):
	set(value):
		background_color = value
		_push_style()
@export var invert_mask: bool = false:
	set(value):
		invert_mask = value
		_push_style()
@export var use_content_texture: bool = false:
	set(value):
		use_content_texture = value
		_push_style()
@export var content_texture: Texture2D:
	set(value):
		content_texture = value
		_push_style()

var _blobs: Array[Vector3] = []
var _shader_material: ShaderMaterial


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = MASK_SHADER
	material = _shader_material
	resized.connect(_push_aspect)
	_push_aspect()
	_push_style()
	_push_blobs()


## Replace all circles atomically. Vector3 stores normalized X, Y and radius.
func set_blobs(circles: Array[Vector3]) -> void:
	_blobs.clear()
	for circle: Vector3 in circles:
		if _blobs.size() >= MAX_BLOBS:
			break
		_blobs.append(Vector3(circle.x, circle.y, maxf(circle.z, 0.0)))
	_push_blobs()


func set_blob(index: int, position_uv: Vector2, radius: float) -> void:
	if index < 0 or index >= MAX_BLOBS:
		push_warning("UniversalBlobMask: index must be 0..15")
		return
	while _blobs.size() <= index:
		_blobs.append(Vector3(0.5, 0.5, 0.0))
	_blobs[index] = Vector3(position_uv.x, position_uv.y, maxf(radius, 0.0))
	_push_blobs()


func set_blob_position(index: int, position_uv: Vector2) -> void:
	if index < 0 or index >= _blobs.size():
		return
	var entry: Vector3 = _blobs[index]
	set_blob(index, position_uv, entry.z)


func set_blob_radius(index: int, radius: float) -> void:
	if index < 0 or index >= _blobs.size():
		return
	var entry: Vector3 = _blobs[index]
	set_blob(index, Vector2(entry.x, entry.y), radius)


func remove_blob(index: int) -> void:
	if index < 0 or index >= _blobs.size():
		return
	_blobs.remove_at(index)
	_push_blobs()


func clear_blobs() -> void:
	_blobs.clear()
	_push_blobs()


func get_blob_count() -> int:
	return _blobs.size()


func set_mode(value: DisplayMode) -> void:
	display_mode = value


func _push_aspect() -> void:
	if _shader_material == null:
		return
	_shader_material.set_shader_parameter("aspect_ratio", size.x / maxf(size.y, 1.0))


func _push_style() -> void:
	if _shader_material == null:
		return
	_shader_material.set_shader_parameter("display_mode", int(display_mode))
	_shader_material.set_shader_parameter("merge_width", merge_width)
	_shader_material.set_shader_parameter("stroke_width", stroke_width)
	_shader_material.set_shader_parameter("edge_softness", edge_softness)
	_shader_material.set_shader_parameter("fill_color", fill_color)
	_shader_material.set_shader_parameter("outline_color", outline_color)
	_shader_material.set_shader_parameter("background_color", background_color)
	_shader_material.set_shader_parameter("invert_mask", invert_mask)
	_shader_material.set_shader_parameter("use_content_texture", use_content_texture)
	if content_texture != null:
		_shader_material.set_shader_parameter("content_texture", content_texture)


func _push_blobs() -> void:
	if _shader_material == null:
		return
	var packed: Array[Vector4] = []
	for index: int in range(MAX_BLOBS):
		if index < _blobs.size():
			var b: Vector3 = _blobs[index]
			packed.append(Vector4(b.x, b.y, b.z, 0.0))
		else:
			packed.append(Vector4.ZERO)
	_shader_material.set_shader_parameter("blob_data", packed)
	_shader_material.set_shader_parameter("blob_count", _blobs.size())
