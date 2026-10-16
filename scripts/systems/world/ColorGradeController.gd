extends Node
class_name ColorGradeController

## Dual-LUT blend: outdoor time corridors + shelter wall-clock crossfade.
## The in-between LUT is pre-baked (LutBlendCache) and stays on the Environment's post-tonemap grade.

signal profile_changed(profile_id: StringName)
signal interior_state_changed(is_inside: bool)
signal blend_finished(profile_id: StringName)

const DAY_PROFILE_ID: StringName = &"HFN_ColdAsh_Day"
const DUSK_PROFILE_ID: StringName = &"HFN_ColdAsh_Dusk"
const NIGHT_PROFILE_ID: StringName = &"HFN_ColdAsh_Night"
const SHELTER_PROFILE_ID: StringName = &"HFN_ColdAsh_Shelter"
const DAY_START_HOUR: float = 7.0
const DUSK_START_HOUR: float = 17.0
const NIGHT_START_HOUR: float = 21.0
const DAWN_START_HOUR: float = 5.0
const TIME_BLEND_HALF_HOURS: float = 0.5

@export var world_environment: WorldEnvironment
@export var day_profile: ColorGradeProfile
@export var dusk_profile: ColorGradeProfile
@export var night_profile: ColorGradeProfile
@export var shelter_profile: ColorGradeProfile
@export var default_profile_id: StringName = DAY_PROFILE_ID
@export_range(0.05, 3.0, 0.05) var shelter_blend_s: float = 0.5
@export_range(0.05, 10.0, 0.05) var time_blend_s: float = 2.5

var _current_profile: ColorGradeProfile
var _outdoor_profile_id: StringName = DAY_PROFILE_ID
var _inside_shelter: bool = false
var _weather_brightness: float = 1.0
var _weather_contrast: float = 1.0
var _weather_saturation: float = 1.0
var _last_game_hour: float = 12.0
var _from_profile: ColorGradeProfile
var _to_profile: ColorGradeProfile
var _blend_weight: float = 1.0
var _blend_speed: float = 0.0
var _timed_blend_active: bool = false
var _from_weather_affects: bool = true
var _to_weather_affects: bool = true
var _lut_cache: LutBlendCache
var _blend_lut: ImageTexture3D
var _blend_lut_from: StringName
var _blend_lut_to: StringName
var _blend_lut_step: int = -1

func _ready() -> void:
	_outdoor_profile_id = default_profile_id if default_profile_id != SHELTER_PROFILE_ID else DAY_PROFILE_ID
	_start_lut_bake()
	if not set_profile(default_profile_id):
		push_warning("ColorGradeController: default profile unavailable; using day.")
		_outdoor_profile_id = DAY_PROFILE_ID
		use_outdoor_profile()
	set_process(true)

func _process(delta: float) -> void:
	if not _timed_blend_active:
		return
	_blend_weight = minf(1.0, _blend_weight + delta * _blend_speed)
	_push_visual_state()
	if _blend_weight >= 1.0 - 0.0001:
		_finish_timed_blend()

func initialize_for_interior(is_inside: bool) -> void:
	if _inside_shelter == is_inside and _current_profile != null and not _timed_blend_active:
		return
	_set_interior_state(is_inside)
	if is_inside:
		_begin_timed_blend(_effective_from_profile(), shelter_profile, false, shelter_blend_s)
	else:
		_begin_timed_blend(_effective_from_profile(), _resolve_profile(_outdoor_profile_id), true, shelter_blend_s)

func update_for_time(game_hour: float) -> void:
	_last_game_hour = game_hour
	_outdoor_profile_id = _profile_id_for_hour(game_hour)
	if _inside_shelter or _timed_blend_active:
		return
	_apply_outdoor_hour_blend(game_hour)

func set_weather_profile(profile: WeatherProfile) -> void:
	var brightness: float = 1.0
	var contrast: float = 1.0
	var saturation: float = 1.0
	if profile != null:
		match profile.id:
			&"calm":
				brightness = 1.03
			&"snowfall":
				brightness = 0.98
				contrast = 0.98
				saturation = 0.94
			&"windy":
				brightness = 0.99
				saturation = 0.96
			&"blizzard":
				brightness = 0.92
				contrast = 0.94
				saturation = 0.86
			_:
				pass
	var changed: bool = (
		not is_equal_approx(_weather_brightness, brightness)
		or not is_equal_approx(_weather_contrast, contrast)
		or not is_equal_approx(_weather_saturation, saturation)
	)
	_weather_brightness = brightness
	_weather_contrast = contrast
	_weather_saturation = saturation
	if changed and not _inside_shelter and not _timed_blend_active:
		_apply_outdoor_hour_blend(_last_game_hour)

func use_outdoor_profile() -> bool:
	_timed_blend_active = false
	_blend_weight = 1.0
	return _snap_to_profile(_resolve_profile(_outdoor_profile_id), true)

func use_shelter_profile() -> bool:
	_timed_blend_active = false
	_blend_weight = 1.0
	return _snap_to_profile(shelter_profile, false)

func set_profile(profile_id: StringName) -> bool:
	if profile_id == SHELTER_PROFILE_ID:
		_set_interior_state(true)
		return use_shelter_profile()
	var profile: ColorGradeProfile = _resolve_profile(profile_id)
	if profile == null:
		push_warning("ColorGradeController: unknown profile '%s'." % profile_id)
		return false
	_set_interior_state(false)
	_outdoor_profile_id = profile_id
	return _snap_to_profile(profile, true)

func blend_outdoor_profiles(from_id: StringName, to_id: StringName, duration_s: float = -1.0) -> bool:
	var from_p: ColorGradeProfile = _resolve_profile(from_id)
	var to_p: ColorGradeProfile = _resolve_profile(to_id)
	if from_p == null or to_p == null:
		return false
	_set_interior_state(false)
	_outdoor_profile_id = to_id
	var dur: float = time_blend_s if duration_s <= 0.0 else duration_s
	_begin_timed_blend(from_p, to_p, true, dur)
	return true

func get_current_profile_id() -> StringName:
	if _inside_shelter:
		return SHELTER_PROFILE_ID
	return _outdoor_profile_id

func get_blend_weight() -> float:
	return _blend_weight

func is_blending() -> bool:
	return _timed_blend_active or (_blend_weight > 0.001 and _blend_weight < 0.999 and _from_profile != _to_profile)

func is_inside_shelter() -> bool:
	return _inside_shelter

func _set_interior_state(is_inside: bool) -> void:
	if _inside_shelter == is_inside:
		return
	_inside_shelter = is_inside
	interior_state_changed.emit(_inside_shelter)

func _profile_id_for_hour(game_hour: float) -> StringName:
	var hour: float = fmod(game_hour + 24.0, 24.0)
	if hour >= DAY_START_HOUR and hour < DUSK_START_HOUR:
		return DAY_PROFILE_ID
	if (hour >= DAWN_START_HOUR and hour < DAY_START_HOUR) or (hour >= DUSK_START_HOUR and hour < NIGHT_START_HOUR):
		return DUSK_PROFILE_ID
	return NIGHT_PROFILE_ID

func _resolve_profile(profile_id: StringName) -> ColorGradeProfile:
	match profile_id:
		DAY_PROFILE_ID:
			return day_profile
		DUSK_PROFILE_ID:
			return dusk_profile
		NIGHT_PROFILE_ID:
			return night_profile
		SHELTER_PROFILE_ID:
			return shelter_profile
		_:
			return null

func _effective_from_profile() -> ColorGradeProfile:
	if _to_profile != null and _blend_weight >= 0.5:
		return _to_profile
	if _from_profile != null:
		return _from_profile
	if _current_profile != null:
		return _current_profile
	return _resolve_profile(_outdoor_profile_id)

func _begin_timed_blend(from_profile: ColorGradeProfile, to_profile: ColorGradeProfile, to_weather_affects: bool, duration_s: float) -> void:
	if from_profile == null or to_profile == null:
		return
	if from_profile == to_profile or duration_s <= 0.05:
		_timed_blend_active = false
		_blend_weight = 1.0
		_snap_to_profile(to_profile, to_weather_affects)
		return
	_from_profile = from_profile
	_to_profile = to_profile
	_from_weather_affects = not _inside_shelter
	_to_weather_affects = to_weather_affects
	_blend_weight = 0.0
	_blend_speed = 1.0 / maxf(0.05, duration_s)
	_timed_blend_active = true
	_current_profile = to_profile
	_push_visual_state()
	profile_changed.emit(to_profile.profile_id)

func _finish_timed_blend() -> void:
	_timed_blend_active = false
	_blend_weight = 1.0
	_snap_to_profile(_to_profile, _to_weather_affects)
	blend_finished.emit(_to_profile.profile_id if _to_profile != null else &"")

func _snap_to_profile(profile: ColorGradeProfile, weather_affects: bool) -> bool:
	if not is_instance_valid(world_environment) or world_environment.environment == null:
		push_warning("ColorGradeController: WorldEnvironment is not ready.")
		return false
	if profile == null or profile.lut == null:
		push_warning("ColorGradeController: requested profile or LUT is missing.")
		return false
	_from_profile = profile
	_to_profile = profile
	_blend_weight = 1.0
	_timed_blend_active = false
	_to_weather_affects = weather_affects
	var environment: Environment = world_environment.environment
	environment.adjustment_enabled = true
	environment.adjustment_color_correction = profile.lut
	var wb: float = _weather_brightness if weather_affects else 1.0
	var wc: float = _weather_contrast if weather_affects else 1.0
	var ws: float = _weather_saturation if weather_affects else 1.0
	environment.adjustment_brightness = profile.brightness * wb
	environment.adjustment_contrast = profile.contrast * wc
	environment.adjustment_saturation = profile.saturation * ws
	var changed: bool = _current_profile != profile
	_current_profile = profile
	if changed:
		profile_changed.emit(profile.profile_id)
	return true

func _apply_outdoor_hour_blend(game_hour: float) -> void:
	var pair: Dictionary = _outdoor_pair_for_hour(game_hour)
	var from_p: ColorGradeProfile = pair["from"]
	var to_p: ColorGradeProfile = pair["to"]
	var weight: float = float(pair["weight"])
	if from_p == null or to_p == null:
		return
	_from_profile = from_p
	_to_profile = to_p
	_from_weather_affects = true
	_to_weather_affects = true
	_blend_weight = weight
	_timed_blend_active = false
	_current_profile = to_p if weight >= 0.5 else from_p
	if is_equal_approx(weight, 0.0) or from_p == to_p:
		_snap_to_profile(from_p, true)
		return
	if is_equal_approx(weight, 1.0):
		_snap_to_profile(to_p, true)
		return
	_push_visual_state()
	profile_changed.emit(_current_profile.profile_id)

func _outdoor_pair_for_hour(game_hour: float) -> Dictionary:
	var hour: float = fmod(game_hour + 24.0, 24.0)
	var half: float = TIME_BLEND_HALF_HOURS
	if hour >= DAWN_START_HOUR - half and hour < DAWN_START_HOUR + half:
		return _pair(night_profile, dusk_profile, _edge_weight(hour, DAWN_START_HOUR, half))
	if hour >= DAY_START_HOUR - half and hour < DAY_START_HOUR + half:
		return _pair(dusk_profile, day_profile, _edge_weight(hour, DAY_START_HOUR, half))
	if hour >= DAY_START_HOUR + half and hour < DUSK_START_HOUR - half:
		return _pair(day_profile, day_profile, 1.0)
	if hour >= DUSK_START_HOUR - half and hour < DUSK_START_HOUR + half:
		return _pair(day_profile, dusk_profile, _edge_weight(hour, DUSK_START_HOUR, half))
	if hour >= DUSK_START_HOUR + half and hour < NIGHT_START_HOUR - half:
		return _pair(dusk_profile, dusk_profile, 1.0)
	if hour >= NIGHT_START_HOUR - half and hour < NIGHT_START_HOUR + half:
		return _pair(dusk_profile, night_profile, _edge_weight(hour, NIGHT_START_HOUR, half))
	return _pair(night_profile, night_profile, 1.0)

func _pair(from_p: ColorGradeProfile, to_p: ColorGradeProfile, weight: float) -> Dictionary:
	return {"from": from_p, "to": to_p, "weight": clampf(weight, 0.0, 1.0)}

func _edge_weight(hour: float, edge: float, half: float) -> float:
	return smoothstep(edge - half, edge + half, hour)

func _bcs(profile: ColorGradeProfile, weather_affects: bool) -> Vector3:
	var wb: float = _weather_brightness if weather_affects else 1.0
	var wc: float = _weather_contrast if weather_affects else 1.0
	var ws: float = _weather_saturation if weather_affects else 1.0
	return Vector3(profile.brightness * wb, profile.contrast * wc, profile.saturation * ws)

func _push_visual_state() -> void:
	if not is_instance_valid(world_environment) or world_environment.environment == null:
		return
	if _from_profile == null or _to_profile == null or _from_profile.lut == null or _to_profile.lut == null:
		return
	var environment: Environment = world_environment.environment
	var from_bcs: Vector3 = _bcs(_from_profile, _from_weather_affects)
	var to_bcs: Vector3 = _bcs(_to_profile, _to_weather_affects)
	environment.adjustment_enabled = true
	environment.adjustment_color_correction = _lut_for_weight()
	environment.adjustment_brightness = lerpf(from_bcs.x, to_bcs.x, _blend_weight)
	environment.adjustment_contrast = lerpf(from_bcs.y, to_bcs.y, _blend_weight)
	environment.adjustment_saturation = lerpf(from_bcs.z, to_bcs.z, _blend_weight)


## Nearest baked in-between LUT, uploaded only when the step changes; the nearer source LUT until baked.
func _lut_for_weight() -> Texture3D:
	var step: int = roundi(_blend_weight * LutBlendCache.STEPS)
	if step >= LutBlendCache.STEPS or _from_profile == _to_profile:
		return _to_profile.lut
	if step <= 0:
		return _from_profile.lut
	var from_id: StringName = _from_profile.profile_id
	var to_id: StringName = _to_profile.profile_id
	if _blend_lut != null and step == _blend_lut_step and from_id == _blend_lut_from and to_id == _blend_lut_to:
		return _blend_lut
	var slices: Array[Image] = []
	if _lut_cache != null:
		slices = _lut_cache.get_slices(from_id, to_id, step)
	if slices.is_empty():
		return _to_profile.lut if step * 2 >= LutBlendCache.STEPS else _from_profile.lut
	if _blend_lut == null:
		_blend_lut = ImageTexture3D.new()
		_blend_lut.create(slices[0].get_format(), slices[0].get_width(), slices[0].get_height(), slices.size(), false, slices)
	else:
		_blend_lut.update(slices)
	_blend_lut_from = from_id
	_blend_lut_to = to_id
	_blend_lut_step = step
	return _blend_lut


func _start_lut_bake() -> void:
	_lut_cache = LutBlendCache.new()
	for profile: ColorGradeProfile in [day_profile, dusk_profile, night_profile, shelter_profile]:
		if profile != null:
			_lut_cache.add_profile(profile.profile_id, profile.lut)
	_lut_cache.start_bake()


## True once every profile pair has its in-between LUTs (never on a renderer without texture readback).
func is_lut_blend_ready() -> bool:
	return _lut_cache != null and _lut_cache.is_baked()
