class_name GraphicsQuality
extends RefCounted

## One production source of truth for renderer quality. Gameplay and simulation
## fidelity are identical across tiers; only presentation cost changes.
const CONFIG_PATH: String = "user://settings.cfg"
const SECTION: String = "graphics"
const KEY_QUALITY: String = "quality"

const LOW: StringName = &"low"
const MEDIUM: StringName = &"medium"
const HIGH: StringName = &"high"
const DEFAULT_QUALITY: StringName = LOW
const ORDER: Array[StringName] = [LOW, MEDIUM, HIGH]

const PROFILES: Dictionary = {
	"low": {
		"render_scale": 0.67,
		"shadow_atlas": 2048,
		"shadow_distance_m": 20.0,
		"snow_packed_res": 640,
		"snow_near_half_m": 1.5,
		"snow_far_spacing_m": 0.8,
		"snow_sim_hz": 4.0,
		"snow_particle_density": 0.50,
	},
	"medium": {
		"render_scale": 0.77,
		"shadow_atlas": 2048,
		"shadow_distance_m": 35.0,
		"snow_packed_res": 768,
		"snow_near_half_m": 2.25,
		"snow_far_spacing_m": 0.6,
		"snow_sim_hz": 8.0,
		"snow_particle_density": 0.75,
	},
	"high": {
		"render_scale": 1.0,
		"shadow_atlas": 4096,
		"shadow_distance_m": 50.0,
		"snow_packed_res": 896,
		"snow_near_half_m": 2.75,
		"snow_far_spacing_m": 0.5,
		"snow_sim_hz": 15.0,
		"snow_particle_density": 1.0,
	},
}


static func normalize(value: Variant) -> StringName:
	var quality := StringName(String(value).to_lower())
	return quality if ORDER.has(quality) else DEFAULT_QUALITY


static func profile_for(value: Variant) -> Dictionary:
	var quality: StringName = normalize(value)
	return (PROFILES[String(quality)] as Dictionary).duplicate(true)


static func load_quality() -> StringName:
	if ProjectSettings.has_setting("hfn/graphics/quality"):
		return normalize(ProjectSettings.get_setting("hfn/graphics/quality"))
	var config := ConfigFile.new()
	var error: Error = config.load(CONFIG_PATH)
	if error == ERR_FILE_NOT_FOUND:
		return DEFAULT_QUALITY
	if error != OK:
		push_warning("GraphicsQuality: cannot read %s (error %d); using LOW" % [CONFIG_PATH, error])
		return DEFAULT_QUALITY
	return normalize(config.get_value(SECTION, KEY_QUALITY, String(DEFAULT_QUALITY)))


static func current_quality() -> StringName:
	return load_quality()


static func current_profile() -> Dictionary:
	return profile_for(current_quality())


static func save_quality(value: Variant) -> Error:
	var config := ConfigFile.new()
	var load_error: Error = config.load(CONFIG_PATH)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		config = ConfigFile.new()
	config.set_value(SECTION, KEY_QUALITY, String(normalize(value)))
	return config.save(CONFIG_PATH)


static func index_of(value: Variant) -> int:
	return ORDER.find(normalize(value))


static func from_index(index: int) -> StringName:
	return ORDER[clampi(index, 0, ORDER.size() - 1)]


static func apply(tree: SceneTree, value: Variant) -> Dictionary:
	var quality: StringName = normalize(value)
	var profile: Dictionary = profile_for(quality)
	ProjectSettings.set_setting("hfn/graphics/quality", String(quality))
	## Keep the old switch as an internal compatibility flag. LOW graphics retains
	## the full deformable snow gameplay; its representation is simply cheaper.
	ProjectSettings.set_setting("hfn/snow/quality", "high")

	if tree != null and tree.root != null:
		tree.root.scaling_3d_scale = float(profile["render_scale"])
		_apply_directional_shadow_distance(tree.root, float(profile["shadow_distance_m"]))
		tree.call_group(&"graphics_quality_consumer", &"apply_graphics_quality", quality, profile)

	var use_16_bits: bool = bool(ProjectSettings.get_setting(
		"rendering/lights_and_shadows/directional_shadow/16_bits", true
	))
	RenderingServer.directional_shadow_atlas_set_size(int(profile["shadow_atlas"]), use_16_bits)
	return profile


static func _apply_directional_shadow_distance(node: Node, distance_m: float) -> void:
	if node is DirectionalLight3D:
		(node as DirectionalLight3D).directional_shadow_max_distance = distance_m
	for child: Node in node.get_children():
		_apply_directional_shadow_distance(child, distance_m)
