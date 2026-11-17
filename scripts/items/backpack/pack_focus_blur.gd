class_name PackFocusBlur
extends MeshInstance3D

## The held pack in focus: all else (Henry too: seen from above he is nearer than its back wall) is blurred by a
## full-screen quad wherever the pack and the camera's children did not write STENCIL_REF (unseen overlays).

const BLUR_SHADER: Shader = preload("res://shaders/items/pack_focus_blur.gdshader")
const CANVAS_SHADER: Shader = preload("res://shaders/items/backpack_canvas.gdshader")
const STENCIL_REF: int = 9
## Masks go on newly shown meshes this often, seconds; the blur fades in and out over FADE_S.
const SCAN_S: float = 0.2
const FADE_S: float = 0.35

var pack: Node3D
## The open container beside the pack, kept sharp too (null when none).
var shelves: Node3D
var _blur: ShaderMaterial
var _scan_s: float = 0.0
var _masked: Dictionary = {}  # instance id -> true; never retain a freed Node
## Kept across Hub visits so each open reuses compiled pipelines (fresh ones recompiled 8 per open on HD 620).
static var _shared_quad: QuadMesh
static var _shared_blur: ShaderMaterial
static var _shared_masks: Dictionary = {}  # instance id of the overlay a mask draws before (0: none) -> mask


## Blurs all but `held_pack`, `beside` (an open container) and the camera's own children; a child of the camera.
func setup(held_pack: Node3D, beside: Node3D = null) -> void:
	pack = held_pack
	shelves = beside
	if _shared_quad == null:
		_shared_quad = QuadMesh.new()
		_shared_quad.size = Vector2(2.0, 2.0)
		_shared_blur = ShaderMaterial.new()
		_shared_blur.shader = BLUR_SHADER
		_shared_blur.render_priority = -127
	mesh = _shared_quad
	extra_cull_margin = 16384.0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blur = _shared_blur
	_blur.set_shader_parameter(&"strength", 0.0)
	material_override = _blur
	create_tween().tween_method(func(value: float) -> void: _blur.set_shader_parameter(&"strength", value), 0.0, 1.0, FADE_S)
	_mask_all()
	## A mesh that appears (an item put in, a card's item) is masked before it is ever drawn blurred.
	get_tree().node_added.connect(_on_node_added)


func _process(delta: float) -> void:
	_scan_s -= delta
	if _scan_s <= 0.0:
		_scan_s = SCAN_S
		_mask_all()


func _on_node_added(node: Node) -> void:
	if node is GeometryInstance3D and _covers(node):
		_mask_deferred.call_deferred(node.get_instance_id())


func _mask_deferred(id: int) -> void:
	if not is_instance_id_valid(id):
		return
	var node := instance_from_id(id) as Node
	if is_instance_valid(node) and node.is_inside_tree() and not node.is_queued_for_deletion() and _covers(node):
		_mask_one(node)


## Whether `node` belongs to the pack or to the camera's other children (what stays sharp).
func _covers(node: Node) -> bool:
	if is_instance_valid(pack) and (pack == node or pack.is_ancestor_of(node)):
		return true
	if is_instance_valid(shelves) and shelves.is_ancestor_of(node):
		return true
	var camera: Node = get_parent()
	return camera != null and camera.is_ancestor_of(node) and not is_ancestor_of(node) and node != self


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	for id: int in _masked.keys():
		if not is_instance_id_valid(id):
			continue
		var geometry := instance_from_id(id) as GeometryInstance3D
		if is_instance_valid(geometry) and geometry.material_overlay != null and geometry.material_overlay.has_meta(&"focus_mask"):
			geometry.material_overlay = geometry.material_overlay.next_pass
	_masked.clear()


## Every mesh of the pack and of the camera's other children writes the stencil (once each).
func _mask_all() -> void:
	for id: int in _masked.keys():
		if not is_instance_id_valid(id):
			_masked.erase(id)
	var roots: Array[Node] = []
	if is_instance_valid(pack):
		roots.append(pack)
	if is_instance_valid(shelves):
		roots.append(shelves)
	for child: Node in get_parent().get_children():
		if child != self:
			roots.append(child)
	for root: Node in roots:
		for node: Node in [root] + root.find_children("*", "GeometryInstance3D", true, false):
			_mask_one(node)


## Puts the stencil mask on one mesh (once); flat cards and the pack's own canvas are left as they are.
func _mask_one(node: Node) -> void:
	var geometry := node as GeometryInstance3D
	## Flat cards and panels (meta flat_card) are see-through and draw after the blur, over a blurred world.
	if geometry == null or not is_instance_valid(geometry) or geometry == self or geometry.has_meta(&"flat_card"):
		return
	if geometry.material_overlay != null and geometry.material_overlay.has_meta(&"focus_mask"):
		return
	## The canvas folds and bulges in its vertex shader, which writes the stencil itself.
	var own: ShaderMaterial = geometry.material_override as ShaderMaterial
	if own != null and own.shader == CANVAS_SHADER:
		return
	geometry.material_overlay = _mask(geometry.material_overlay)
	_masked[geometry.get_instance_id()] = true


## The stencil mask to draw before `after` (null: nothing). Never edit its next_pass: masks are shared.
static func mask_over(after: Material) -> StandardMaterial3D:
	return _mask(after)


## An unseen overlay writing STENCIL_REF where the mesh shows; what was its overlay draws after it.
## Shared by every mesh and visit when `after` is none or a saved resource; a per-item one gets its own.
static func _mask(after: Material) -> StandardMaterial3D:
	var shared: bool = after == null or after.resource_path != ""
	var key: int = after.get_instance_id() if after != null else 0
	if shared and _shared_masks.has(key):
		return _shared_masks[key]
	var mask := StandardMaterial3D.new()
	mask.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mask.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mask.albedo_color = Color(0.0, 0.0, 0.0, 0.0)
	mask.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mask.cull_mode = BaseMaterial3D.CULL_DISABLED  # the dropped panel and the inner walls show their back faces
	mask.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
	mask.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
	mask.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
	mask.stencil_reference = STENCIL_REF
	mask.render_priority = -128
	mask.next_pass = after
	mask.set_meta(&"focus_mask", true)
	if shared:
		_shared_masks[key] = mask
	return mask
