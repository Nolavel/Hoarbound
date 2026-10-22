class_name LighterStrikeVFX
extends Node3D

## A physical lighter with separate momentary sparks and a hold-controlled flame.
var _flame: MeshInstance3D
var _flame_light: OmniLight3D
var _spark_light: OmniLight3D
var _flash_tween: Tween
var _strike_tween: Tween
var _rest_rotation: Vector3
var _flame_on: bool = false
var _time: float = 0.0


func _ready() -> void:
	var body := BoxMesh.new()
	body.size = Vector3(0.022, 0.055, 0.014)
	body.material = _material(Color(0.52, 0.18, 0.11), false)
	var shell := MeshInstance3D.new()
	shell.mesh = body
	add_child(shell)
	var head := BoxMesh.new()
	head.size = Vector3(0.024, 0.014, 0.016)
	head.material = _material(Color(0.55, 0.53, 0.47), false)
	var cap := MeshInstance3D.new()
	cap.mesh = head
	cap.position.y = 0.031
	add_child(cap)
	_flame = MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.012
	mesh.height = 0.045
	mesh.material = _material(Color(1.0, 0.55, 0.12), true)
	_flame.mesh = mesh
	_flame.position.y = 0.061
	_flame.visible = false
	add_child(_flame)
	_flame_light = _light(1.4)
	_flame_light.visible = false
	_spark_light = _light(0.8)
	_spark_light.light_energy = 0.0


func strike(success: bool) -> void:
	if _strike_tween != null:
		_strike_tween.kill()
	else:
		_rest_rotation = rotation
	rotation = _rest_rotation
	_strike_tween = create_tween()
	_strike_tween.tween_property(self, ^"rotation", _rest_rotation + Vector3(-0.16, 0.0, 0.10), 0.07)
	_strike_tween.tween_property(self, ^"rotation", _rest_rotation, 0.13)
	if _flash_tween != null:
		_flash_tween.kill()
	_spark_light.light_energy = 3.0
	_flash_tween = create_tween()
	_flash_tween.tween_property(_spark_light, ^"light_energy", 0.0, 0.20)
	var mesh := SphereMesh.new()
	mesh.radius = 0.008
	mesh.height = 0.016
	mesh.material = _material(Color(1.0, 0.58, 0.15), true)
	for index: int in range(9):
		var spark := MeshInstance3D.new()
		spark.mesh = mesh
		spark.position.y = 0.045
		add_child(spark)
		var angle: float = TAU * float(index) / 9.0
		var target := Vector3(cos(angle) * 0.085, 0.09 + 0.018 * (index % 3), sin(angle) * 0.085)
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


func _process(delta: float) -> void:
	if not _flame_on:
		return
	_time += delta
	var flicker: float = 0.93 + 0.07 * sin(_time * 17.0)
	_flame_light.light_energy = 2.7 * flicker
	_flame.scale = Vector3(0.8, flicker, 0.8)


func _light(radius: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position.y = 0.05
	light.light_color = Color(1.0, 0.63, 0.28)
	light.omni_range = radius
	light.shadow_enabled = false
	add_child(light)
	return light


func _material(color: Color, glowing: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.75
	if glowing:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 2.5
	return material


func get_flame_tip() -> Vector3:
	return to_global(Vector3(0,0.061,0))
