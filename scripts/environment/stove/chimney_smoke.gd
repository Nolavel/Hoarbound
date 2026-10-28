class_name ChimneySmoke
extends GPUParticles3D
## Smoke from a chimney cap while its HeatSource burns; density follows the fire.
## The weather's wind, gust included, drives every puff in the air (chimney_smoke.gdshader).

const SMOKE_SHADER: Shader = preload("res://shaders/environment/stove/chimney_smoke.gdshader")
const WEATHER_GROUP: StringName = &"weather_controller"
## Fewest puffs a just-lit fire shows, as a share of the full plume.
const MIN_DENSITY: float = 0.3
const MAX_WIND_MPS: float = 14.0

@export var source: HeatSource

var _process_material: ShaderMaterial
var _weather: WeatherController
var _search_s: float = 0.0


func _init() -> void:
	name = "ChimneySmoke"
	amount = 72
	lifetime = 7.0
	preprocess = 4.0
	local_coords = false
	fixed_fps = 30
	interpolate = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visibility_aabb = AABB(Vector3(-40.0, -4.0, -40.0), Vector3(80.0, 30.0, 80.0))
	_process_material = ShaderMaterial.new()
	_process_material.shader = SMOKE_SHADER
	process_material = _process_material
	draw_pass_1 = _puff_quad()


func _ready() -> void:
	if source != null:
		source.burning_changed.connect(func(_burning: bool) -> void: _apply_fire())
		source.intensity_changed.connect(func(_value: float) -> void: _apply_fire())
	_apply_fire()


func _process(delta: float) -> void:
	if _weather == null:
		_search_s -= delta
		if _search_s <= 0.0:
			_search_s = 1.0
			_weather = _find_weather()
		return
	var speed: float = clampf(_weather.get_wind_speed_mps(), 0.0, MAX_WIND_MPS)
	_process_material.set_shader_parameter(&"wind", _weather.get_wind_direction() * speed)


## A soft puff with a lumpy, noise-broken edge so overlapping quads never show discs.
static func puff_texture(size: int) -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.09
	noise.fractal_octaves = 3
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var denom: float = maxf(float(size - 1), 1.0)
	for y: int in range(size):
		for x: int in range(size):
			var uv := Vector2(float(x) / denom, float(y) / denom)
			var radial: float = clampf(1.0 - (uv - Vector2(0.5, 0.5)).length() * 2.0, 0.0, 1.0)
			var lump: float = 0.55 + 0.45 * noise.get_noise_2d(float(x), float(y))
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(pow(radial, 0.9) * lump * 1.4, 0.0, 1.0)))
	return ImageTexture.create_from_image(image)


func _apply_fire() -> void:
	var burning: bool = source != null and source.is_burning()
	emitting = burning
	if burning:
		amount_ratio = lerpf(MIN_DENSITY, 1.0, source.get_intensity())


## The one WeatherController with profiles; an empty leftover in an environment scene is skipped.
func _find_weather() -> WeatherController:
	for node: Node in get_tree().get_nodes_in_group(WEATHER_GROUP):
		var weather: WeatherController = node as WeatherController
		if weather != null and not weather.profiles.is_empty():
			return weather
	return null


func _puff_quad() -> QuadMesh:
	var mesh := QuadMesh.new()
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	## The shader grows each puff through its transform; billboards drop that scale otherwise.
	material.billboard_keep_scale = true
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = puff_texture(48)
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = material
	return mesh
