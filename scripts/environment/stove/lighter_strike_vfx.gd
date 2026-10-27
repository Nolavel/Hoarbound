class_name LighterStrikeVFX
extends Node3D

## The authored lighter with momentary sparks and a hold-controlled flame.
## Origin is the grip on the nozzle axis; the flame stands on the nozzle and always burns world-up.
const FLAME_SHADER := preload("res://shaders/environment/stove/lighter_flame.gdshader")
## Nozzle above the grip origin, along the lighter's local +Y.
const NOZZLE := Vector3(0.0, 0.038, 0.0)
const FLAME_HEIGHT: float = 0.032
const FLAME_WIDTH: float = 0.026
## Rest of a strike: one thumb roll of the flint wheel.
const WHEEL_ROLL: float = -TAU * 0.3

var _model: Node3D
var _wheel: Node3D
var _flame: MeshInstance3D
var _flame_light: OmniLight3D
var _spark_light: OmniLight3D
var _flash_tween: Tween
var _strike_tween: Tween
var _rest_rotation: Vector3
var _flame_on: bool = false
var _time: float = 0.0


func _ready() -> void:
	_model = SurvivalItemVisual.make(&"lighter")
	_model.position = NOZZLE - SurvivalItemVisual.LIGHTER_NOZZLE
	add_child(_model)
	_wheel = _model.find_child("Lighter_v2_Wheel", true, false) as Node3D
	_flame = MeshInstance3D.new()
	_flame.mesh = _flame_geometry()
	var material := ShaderMaterial.new()
	material.shader = FLAME_SHADER
	_flame.material_override = material
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flame)
	_flame_light = _light(1.4)
	_spark_light = _light(0.8)
	_spark_light.light_energy = 0.0
	set_flame(_flame_on)
	_place_flame(1.0)


func strike(success: bool) -> void:
	if _strike_tween != null:
		_strike_tween.kill()
	else:
		_rest_rotation = rotation
	rotation = _rest_rotation
	_strike_tween = create_tween()
	_strike_tween.tween_property(self, ^"rotation", _rest_rotation + Vector3(-0.16, 0.0, 0.10), 0.07)
	_strike_tween.tween_property(self, ^"rotation", _rest_rotation, 0.13)
	if _wheel != null:
		create_tween().tween_property(_wheel, ^"rotation:z", _wheel.rotation.z + WHEEL_ROLL, 0.12)
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
		spark.position = NOZZLE
		add_child(spark)
		var angle: float = TAU * float(index) / 9.0
		var target := NOZZLE + Vector3(cos(angle) * 0.06, 0.03 + 0.012 * (index % 3), sin(angle) * 0.06)
		var tween := create_tween().set_parallel(true)
		tween.tween_property(spark, ^"position", target, 0.24)
		tween.tween_property(spark, ^"scale", Vector3.ZERO, 0.24)
		tween.chain().tween_callback(spark.queue_free)
	set_flame(success)


func set_flame(active: bool) -> void:
	_flame_on = active
	if _flame != null:
		_flame.visible = active
	if _flame_light != null:
		_flame_light.visible = active


func is_flame_visible() -> bool:
	return _flame_on and _flame != null and _flame.visible


## World point of the nozzle, where the flame stands.
func get_flame_tip() -> Vector3:
	return to_global(NOZZLE)


func _process(delta: float) -> void:
	if not _flame_on:
		return
	_time += delta
	var flicker: float = 0.93 + 0.07 * sin(_time * 17.0)
	_flame_light.light_energy = 2.7 * flicker
	_place_flame(flicker)


## The flame pivots on the nozzle and keeps world-up whatever the hand's tilt.
func _place_flame(flicker: float) -> void:
	if not is_inside_tree():
		return
	var nozzle: Vector3 = get_flame_tip()
	var size := Vector3(FLAME_WIDTH, FLAME_HEIGHT * flicker, FLAME_WIDTH)
	_flame.global_transform = Transform3D(Basis.from_scale(size), nozzle)
	_flame_light.global_position = nozzle + Vector3.UP * FLAME_HEIGHT * 0.5
	_spark_light.global_position = nozzle


## Unit tongue, base at the origin: narrow root, belly low, pointed tip.
func _flame_geometry() -> ArrayMesh:
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


func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


func _light(radius: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = NOZZLE
	light.light_color = Color(1.0, 0.63, 0.28)
	light.omni_range = radius
	light.shadow_enabled = false
	add_child(light)
	return light


func _spark_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.58, 0.15)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = material.albedo_color
	material.emission_energy_multiplier = 2.5
	return material
