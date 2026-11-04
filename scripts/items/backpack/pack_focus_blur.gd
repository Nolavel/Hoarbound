class_name PackFocusBlur
extends MeshInstance3D

## The held pack in focus: all else (Henry too: seen from above he is nearer than its back wall) is blurred by a
## full-screen quad wherever the pack and the camera's children did not write STENCIL_REF (unseen overlays).

const BLUR_SHADER: Shader = preload("res://shaders/items/pack_focus_blur.gdshader")
const STENCIL_REF: int = 9
## Masks go on newly shown meshes this often, seconds; the blur fades in and out over FADE_S.
const SCAN_S: float = 0.2
const FADE_S: float = 0.35

var pack: Node3D
var _blur: ShaderMaterial
var _scan_s: float = 0.0
var _masked: Array[GeometryInstance3D] = []


## Blurs all but `held_pack` and the camera's own children (cards, a carried item); a child of the camera.
func setup(held_pack: Node3D) -> void:
	pack = held_pack
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	mesh = quad
	extra_cull_margin = 16384.0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blur = ShaderMaterial.new()
	_blur.shader = BLUR_SHADER
	_blur.render_priority = -127
	_blur.set_shader_parameter(&"strength", 0.0)
	material_override = _blur
	create_tween().tween_method(func(value: float) -> void: _blur.set_shader_parameter(&"strength", value), 0.0, 1.0, FADE_S)
	_mask_all()


func _process(delta: float) -> void:
	_scan_s -= delta
	if _scan_s <= 0.0:
		_scan_s = SCAN_S
		_mask_all()


func _exit_tree() -> void:
	for geometry: GeometryInstance3D in _masked:
		if is_instance_valid(geometry) and geometry.material_overlay != null and geometry.material_overlay.has_meta(&"focus_mask"):
			geometry.material_overlay = geometry.material_overlay.next_pass
	_masked.clear()


## Every mesh of the pack and of the camera's other children writes the stencil (once each).
func _mask_all() -> void:
	var roots: Array[Node] = []
	if is_instance_valid(pack):
		roots.append(pack)
	for child: Node in get_parent().get_children():
		if child != self:
			roots.append(child)
	for root: Node in roots:
		for node: Node in [root] + root.find_children("*", "GeometryInstance3D", true, false):
			var geometry := node as GeometryInstance3D
			## Flat cards and panels (meta flat_card) are see-through and draw after the blur, over a blurred world.
			if geometry == null or geometry == self or geometry.has_meta(&"flat_card"):
				continue
			if geometry.material_overlay != null and geometry.material_overlay.has_meta(&"focus_mask"):
				continue
			geometry.material_overlay = _mask(geometry.material_overlay)
			_masked.append(geometry)


## An unseen overlay writing STENCIL_REF where the mesh shows; what was its overlay draws after it.
static func _mask(after: Material) -> StandardMaterial3D:
	var mask := StandardMaterial3D.new()
	mask.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mask.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mask.albedo_color = Color(0.0, 0.0, 0.0, 0.0)
	mask.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mask.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
	mask.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
	mask.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
	mask.stencil_reference = STENCIL_REF
	mask.render_priority = -128
	mask.next_pass = after
	mask.set_meta(&"focus_mask", true)
	return mask
