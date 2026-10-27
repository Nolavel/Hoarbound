class_name LighterFlame
extends Node3D

## Lighter flame placed at the burner nozzle: pivots on it and always burns world-up.
## Shared by the stove act (LighterStrikeVFX) and the lighter held in Henry's hand.
const SHADER := preload("res://shaders/environment/stove/lighter_flame.gdshader")
const HEIGHT: float = 0.032
const WIDTH: float = 0.026
const LIGHT_ENERGY: float = 2.7
## One thumb roll of the flint wheel per strike.
const WHEEL_ROLL: float = -TAU * 0.3

## The model's flint wheel, rolled on each strike when set.
var wheel: Node3D

var _mesh: MeshInstance3D
var _light: OmniLight3D
var _spark_light: OmniLight3D
var _flash_tween: Tween
var _lit: bool = false
var _time: float = 0.0


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _geometry()
	var material := ShaderMaterial.new()
	material.shader = SHADER
	_mesh.material_override = material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.63, 0.28)
	_light.omni_range = 1.4
	_light.shadow_enabled = false
	add_child(_light)
	_spark_light = _light.duplicate() as OmniLight3D
	_spark_light.omni_range = 0.8
	_spark_light.light_energy = 0.0
	_spark_light.visible = true
	add_child(_spark_light)
	set_lit(_lit)
	_place(1.0)


## Flint wheel roll, a spark burst and a flash; the flame itself follows set_lit.
func strike() -> void:
	if wheel != null:
		create_tween().tween_property(wheel, ^"rotation:z", wheel.rotation.z + WHEEL_ROLL, 0.12)
	if _flash_tween != null:
		_flash_tween.kill()
	_spark_light.light_energy = 3.0
	_flash_tween = create_tween()
	_flash_tween.tween_property(_spark_light, ^"light_energy", 0.0, 0.20)
	var mesh := SphereMesh.new()
	mesh.radius = 0.004
	mesh.height = 0.008
	mesh.material = _spark_material()
	for index: int in range(9):
		var spark := MeshInstance3D.new()
		spark.mesh = mesh
		spark.top_level = true
		add_child(spark)
		spark.global_position = global_position
		var angle: float = TAU * float(index) / 9.0
		var target := global_position + Vector3(cos(angle) * 0.06, 0.03 + 0.012 * (index % 3), sin(angle) * 0.06)
		var tween := create_tween().set_parallel(true)
		tween.tween_property(spark, ^"global_position", target, 0.24)
		tween.tween_property(spark, ^"scale", Vector3.ZERO, 0.24)
		tween.chain().tween_callback(spark.queue_free)


func set_lit(lit: bool) -> void:
	_lit = lit
	if _mesh != null:
		_mesh.visible = lit
		_light.visible = lit
	set_process(lit)


func is_lit() -> bool:
	return _lit and _mesh != null and _mesh.is_visible_in_tree()


func _process(delta: float) -> void:
	_time += delta
	_place(0.93 + 0.07 * sin(_time * 17.0))


func _place(flicker: float) -> void:
	if _mesh == null or not is_inside_tree():
		return
	global_basis = Basis.IDENTITY
	_mesh.scale = Vector3(WIDTH, HEIGHT * flicker, WIDTH)
	_light.position = Vector3.UP * HEIGHT * 0.5
	_light.light_energy = LIGHT_ENERGY * flicker


## Unit tongue, base at the origin: narrow root, belly low, pointed tip.
func _geometry() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var widths: Array[float] = [0.10, 0.34, 0.46, 0.44, 0.36, 0.24, 0.12, 0.01]
	var rings: Array[PackedVector3Array] = []
	for i: int in range(widths.size()):
		var y: float = float(i) / float(widths.size() - 1)
		var ring := PackedVector3Array()
		for side: int in range(12):
			var a: float = TAU * float(side) / 12.0
			ring.append(Vector3(cos(a) * widths[i] * 0.5, y, sin(a) * widths[i] * 0.5))
		rings.append(ring)
	for i: int in range(rings.size() - 1):
		for side: int in range(12):
			var j: int = (side + 1) % 12
			_triangle(st, rings[i][side], rings[i + 1][side], rings[i][j])
			_triangle(st, rings[i][j], rings[i + 1][side], rings[i + 1][j])
	for side: int in range(12):
		var j: int = (side + 1) % 12
		_triangle(st, Vector3.ZERO, rings[0][side], rings[0][j])
		_triangle(st, Vector3.UP, rings[-1][j], rings[-1][side])
	st.generate_normals()
	return st.commit()


func _spark_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.58, 0.15)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = material.albedo_color
	material.emission_energy_multiplier = 2.5
	return material


func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
