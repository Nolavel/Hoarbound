extends SceneTree

## Stills of the game's frosted glass (frosted_glass_727.tres) on panes of different size and proportion, at
## several warmths, one PNG each. The panes carry the same per-vertex data the landmark glass does.
## Run: xvfb-run godot --path . --rendering-driver vulkan --resolution 1920x1080 --script res://tools/runtime/capture_window_frost_shapes.gd -- <out dir>

const GLASS: ShaderMaterial = preload("res://assets/world/key_west/landmarks/frosted_glass_727.tres")
const BACKDROP: Shader = preload("res://tests/demos/window_727_sdf/diagnostic_backdrop.gdshader")
## [width m, height m, centre x m, centre y m]: square light, casement, sash, picture window, transom, door glass.
const PANES: Array = [
	[0.5, 0.5, -2.05, 0.65], [0.6, 1.0, -1.35, 0.40], [1.0, 1.4, -0.40, 0.20],
	[2.0, 1.1, 1.25, 0.35], [1.6, 0.45, 1.05, -0.62], [0.8, 0.45, -1.75, -0.62],
]
const WARMTHS: Array[float] = [0.0, 0.35, 0.6, 0.85, 1.0]
const COLD_COVERAGE: float = 0.7

var _out: String = "user://shots/window_frost_shapes"


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	call_deferred(&"_run")


func _run() -> void:
	var glass := GLASS.duplicate() as ShaderMaterial
	glass.set_shader_parameter(&"growth_seed", 0.28)
	glass.set_shader_parameter(&"melt_seed", 0.73)
	var stage := Node3D.new()
	root.add_child(stage)
	var board := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(7.0, 4.0)
	var checker := ShaderMaterial.new()
	checker.shader = BACKDROP
	quad.material = checker
	board.mesh = quad
	board.position = Vector3(0.0, 0.0, -1.5)
	stage.add_child(board)
	for index: int in PANES.size():
		var pane: Array = PANES[index]
		stage.add_child(_pane(Vector2(pane[0], pane[1]), Vector3(pane[2], pane[3], 0.0), float(index) * 0.137, glass))
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.75
	camera.position = Vector3(-0.2, 0.05, 3.0)
	stage.add_child(camera)
	camera.make_current()
	for warmth: float in WARMTHS:
		glass.set_shader_parameter(&"heated_warmth", warmth)
		for _i: int in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var path: String = "%s/warmth_%03d.png" % [_out, int(round(warmth * 100.0))]
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path) if path.begins_with("user://") else path)
		print("capture window frost shapes: %s" % path)
	quit(0)


## A pane as the landmark glass has it: UV 0..1 with v = 0 at the top, COLOR = (cold coverage, heated, seed).
func _pane(size: Vector2, at: Vector3, seed_value: float, glass: ShaderMaterial) -> MeshInstance3D:
	var half: Vector2 = size * 0.5
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-half.x, half.y, 0.0), Vector3(half.x, half.y, 0.0),
		Vector3(half.x, -half.y, 0.0), Vector3(-half.x, -half.y, 0.0)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)])
	var colour := Color(COLD_COVERAGE, 1.0, seed_value, 1.0)
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([colour, colour, colour, colour])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = glass
	node.position = at
	return node
