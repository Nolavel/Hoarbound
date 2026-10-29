class_name HeldSearchlight
extends Node3D

## Storage owns the switch state; this prop owns optics and bounded presentation inertia.
signal toggled(enabled: bool)

const MODEL: PackedScene = preload("res://assets/items/searchlight/searchlight.glb")
const LENS_SHADER: Shader = preload("res://shaders/props/searchlight_lens.gdshader")
const AURA: Texture2D = preload("res://assets/items/searchlight/textures/lens_aura.png")
const DIVINE: Texture2D = preload("res://assets/items/searchlight/textures/lens_divine.png")

@export_range(0.10, 0.16, 0.01) var response_time_s: float = 0.13
@export_range(4.0, 6.0, 0.1) var maximum_angle_deg: float = 5.0
@export_range(0.02, 0.04, 0.001) var maximum_translation_m: float = 0.03
@export var light_energy: float = 12.0
@export var light_range_m: float = 18.0
@export var spot_angle_deg: float = 27.0
@export var fog_energy: float = 0.12
@export_range(0.0, 0.05, 0.001) var scattering_density: float = 0.012

var lamp: SpotLight3D
var medium: FogVolume
var lens_material: ShaderMaterial
var inertia_offset: Vector3 = Vector3.ZERO
var direction: Vector3 = Vector3.FORWARD
var _enabled: bool = false
var _initialized: bool = false
var _rotation: Quaternion = Quaternion.IDENTITY
var _angular_velocity: Vector3 = Vector3.ZERO
var _offset_velocity: Vector3 = Vector3.ZERO


static func make_model() -> Node3D:
	var model := MODEL.instantiate() as Node3D
	StylizedEnvironmentMaterial.apply_to_tree(model)
	return model


func _ready() -> void:
	var model: Node3D = make_model()
	model.name = "Model"
	add_child(model)
	var grip := model.find_child("GripAnchor", true, false) as Node3D
	if grip == null:
		push_error("Searchlight: model requires GripAnchor")
		return
	model.position -= model.to_local(grip.global_position)
	var optic := model.find_child("OpticalCenter", true, false) as Node3D
	var lens := model.find_child("Searchlight_Lens", true, false) as MeshInstance3D
	if optic == null or lens == null:
		push_error("Searchlight: model requires optical centre and separate lens")
		return
	lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lens_material = ShaderMaterial.new()
	lens_material.shader = LENS_SHADER
	lens_material.set_shader_parameter("aura_mask", AURA)
	lens_material.set_shader_parameter("divine_mask", DIVINE)
	## Keep the protective glass visible when switched off; glow is a separate thin card.
	var glow := MeshInstance3D.new()
	glow.name = "OpticGlow"
	var glow_mesh := QuadMesh.new()
	glow_mesh.size = Vector2(0.158, 0.158)
	glow.mesh = glow_mesh
	glow.material_override = lens_material
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glow)
	glow.position = to_local(optic.global_position) + Vector3(0.0, 0.0, -0.003)
	lamp = SpotLight3D.new()
	lamp.name = "SearchlightBeam"
	lamp.light_color = Color(1.0, 0.88, 0.67)
	lamp.light_energy = light_energy
	lamp.spot_range = light_range_m
	lamp.spot_angle = spot_angle_deg
	lamp.spot_angle_attenuation = 1.8
	lamp.spot_attenuation = 2.0
	lamp.shadow_enabled = true
	lamp.shadow_bias = 0.03
	lamp.shadow_normal_bias = 0.3
	lamp.light_volumetric_fog_energy = fog_energy
	add_child(lamp)
	lamp.position = to_local(optic.global_position)
	medium = FogVolume.new()
	medium.name = "LocalScattering"
	medium.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
	medium.size = Vector3.ONE * 0.7
	var fog := FogMaterial.new()
	fog.density = scattering_density
	fog.edge_fade = 1.0
	fog.albedo = Color(0.8, 0.8, 0.8)
	fog.emission = Color.BLACK
	medium.material = fog
	lamp.add_child(medium)
	apply_enabled(_enabled)


func apply_enabled(enabled: bool) -> void:
	_enabled = enabled
	if lamp != null:
		lamp.visible = enabled
	if medium != null:
		medium.visible = enabled and scattering_density > 0.0
	if lens_material != null:
		lens_material.set_shader_parameter("lit", 1.0 if enabled else 0.0)


func toggle() -> void:
	apply_enabled(not _enabled)
	toggled.emit(_enabled)


func is_enabled() -> bool:
	return _enabled


## Exact critically damped SO(3) error step; the grip and light use the same result.
func advance_inertia(delta: float, forward: Vector3, carrier_velocity: Vector3) -> void:
	if delta <= 0.0 or forward.length_squared() < 0.0001:
		return
	var target: Quaternion = Basis.looking_at(forward.normalized(), Vector3.UP).get_rotation_quaternion()
	if not _initialized:
		_rotation = target
		_initialized = true
	var error: Quaternion = (target.inverse() * _rotation).normalized()
	if error.w < 0.0:
		error = -error
	var angle: float = error.get_angle()
	var displacement: Vector3 = error.get_axis() * angle if angle > 0.0001 else Vector3.ZERO
	var local_speed: Vector3 = Basis(target).inverse() * _angular_velocity
	var omega: float = 2.0 / response_time_s
	var decay: float = exp(-omega * delta)
	var step: Vector3 = local_speed + displacement * omega
	displacement = (displacement + step * delta) * decay
	local_speed = (local_speed - step * omega * delta) * decay
	var limit: float = deg_to_rad(maximum_angle_deg)
	if displacement.length() > limit:
		displacement = displacement.normalized() * limit
		local_speed -= displacement.normalized() * maxf(local_speed.dot(displacement.normalized()), 0.0)
	_angular_velocity = Basis(target) * local_speed
	_rotation = (target * Quaternion(displacement.normalized(), displacement.length())).normalized() if displacement.length() > 0.0001 else target
	direction = -(Basis(_rotation).z)
	var target_offset: Vector3 = -carrier_velocity * 0.012
	target_offset = target_offset.limit_length(maximum_translation_m)
	var error_offset: Vector3 = inertia_offset - target_offset
	step = _offset_velocity + error_offset * omega
	inertia_offset = target_offset + (error_offset + step * delta) * decay
	_offset_velocity = (_offset_velocity - step * omega * delta) * decay
	inertia_offset = inertia_offset.limit_length(maximum_translation_m)


func grip_basis() -> Basis:
	return Basis(_rotation)
