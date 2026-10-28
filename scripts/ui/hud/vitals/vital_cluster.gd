class_name VitalCluster
extends Control

## Survival vitals as gradient columns with trends, temperature readouts and a frosting
## silhouette over the warmth column; layout and rules in docs/technical/VITALS_HUD.md.
const THERMAL_SCRIPT: GDScript = preload("res://scripts/systems/survival/thermal_manager.gd")
const THIRST_TEXTURE: Texture2D = preload("res://assets/textures/ui/game/biomonitor/thirst_icon.png")
const HUNGER_TEXTURE: Texture2D = preload("res://assets/textures/ui/game/biomonitor/hunger_icon.png")
const SLEEP_TEXTURE: Texture2D = preload("res://assets/textures/ui/game/biomonitor/sleep.png")
const WARMTH_TEXTURE: Texture2D = preload("res://assets/textures/ui/game/biomonitor/temperature_icon.png")
const COLUMN_SHADER: Shader = preload("res://shaders/ui/vital_column.gdshader")
const ICON_SHADER: Shader = preload("res://shaders/ui/vital_icon.gdshader")
const FROST_SHADER: Shader = preload("res://shaders/ui/vital_frost.gdshader")
const READOUT_FONT: Font = preload("res://assets/fonts/IM Fell English SC/IMFellEnglishSC-Regular.ttf")
## Silhouette base; part masks come from BodyPartLibrary on the same frame (MIT, body_front/LICENSE.txt).
const BODY_BASE: Texture2D = preload("res://assets/textures/ui/game/biomonitor/body_front/base.png")

const DISPLAY_ORDER: Array[StringName] = [&"thirst", &"hunger", &"sleep", &"warmth"]
## Optical correction after trimming transparent padding: the eye is denser than the others.
const OPTICAL_SCALE: Dictionary = {&"thirst": 1.00, &"hunger": 1.00, &"sleep": 0.88, &"warmth": 1.00}
## Every survival vital shows a trend: chevrons above the column rising, below it falling.
const TREND_IDS: Array[StringName] = [&"thirst", &"hunger", &"sleep", &"warmth"]

@export var bio_monitor: BioMonitorManager
@export var thermal_manager: ThermalManager

@export_group("Columns")
@export var column_width: float = 36.0
@export var column_height: float = 112.0
@export var column_gap: float = 16.0
@export var column_radius: float = 8.0
## Room under the columns for the falling chevrons.
@export var column_bottom: float = 18.0
@export var icon_size: float = 28.0
## Thirst, hunger and sleep thresholds; warmth uses the ThermalManager stages instead.
@export_range(0.0, 1.0, 0.01) var warning_progress_threshold: float = 0.66
@export_range(0.0, 1.0, 0.01) var critical_progress_threshold: float = 0.33
## Width of the band around a threshold over which colours blend instead of switching.
@export_range(0.0, 0.2, 0.01) var colour_band: float = 0.06
## How fast the drawn fill and colour follow the value, per second.
@export var display_rate: float = 4.0

@export_group("Motion")
## A change smaller than this is not a pulse, so steady drift stays quiet.
@export_range(0.0, 0.2, 0.005) var pulse_threshold: float = 0.01
@export_range(0.25, 0.4, 0.01) var morph_duration: float = 0.35
## A drain nudges the symbol down this far; a refill swells it.
@export var drain_push_px: float = 6.0
@export var drain_duration: float = 0.35
@export var refill_scale: float = 0.15
@export var refill_duration: float = 2.0

@export_group("Trend")
## Seconds over which a value must move to show a trend mark.
@export var trend_window: float = 1.5
## Smallest move within the window that counts as a trend, and the move that counts as fast.
@export var trend_epsilon: float = 0.002
@export var fast_trend_epsilon: float = 0.01
@export var trend_size: float = 6.0
@export var trend_gap: float = 6.0

@export_group("Readouts")
@export var body_font_size: int = 15
@export var feels_font_size: int = 14
@export var body_color: Color = Color(0.86, 0.86, 0.84, 0.75)
@export var feels_color: Color = Color(0.90, 0.92, 0.94, 0.9)

@export_group("Silhouette")
@export var silhouette_height: float = 96.0
@export_range(0.0, 1.0, 0.01) var silhouette_alpha: float = 0.11
@export var frost_color: Color = Color(0.48, 0.74, 1.0, 0.95)

@export_group("Colours")
@export var back_color: Color = Color(0.03, 0.03, 0.035, 0.8)
@export var normal_color: Color = Color(0.50, 0.66, 0.40, 0.92)
@export var warning_color: Color = Color(0.88, 0.68, 0.26, 0.92)
@export var critical_color: Color = Color(0.80, 0.24, 0.16, 0.95)

var cells: Dictionary = {}
## Latest value per id (vital ids plus &"wetness"), its value at the window start and its trend.
var _values: Dictionary = {}
var _window_start: Dictionary = {}
var _trends: Dictionary = {}
var _trend_strength: Dictionary = {}
var _window_left: float = 0.0
var _wetness: float = 0.0
## Per vital: shown fill and colour (eased), and its back, pigment and symbol nodes.
var _shown: Dictionary = {}
var _views: Dictionary = {}
var _overlay: Control
var _body_label: Label
var _feels_label: Label
var _body_base: TextureRect
var _frost: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	cells[&"warmth"] = VitalCell.new(&"warmth", Vector2(-1.0, -1.0), 3)
	cells[&"thirst"] = VitalCell.new(&"thirst", Vector2(1.0, -1.0), 1)
	cells[&"hunger"] = VitalCell.new(&"hunger", Vector2(1.0, 1.0), 0)
	cells[&"sleep"] = VitalCell.new(&"sleep", Vector2(-1.0, 1.0), 2)
	_build_views()
	_bind_bio_monitor()
	_bind_thermal()
	resized.connect(_layout)
	_layout()


func _process(delta: float) -> void:
	_window_left -= delta
	if _window_left <= 0.0:
		_window_left = trend_window
		for id: StringName in _values:
			var moved: float = float(_values[id]) - float(_window_start.get(id, _values[id]))
			_trends[id] = 0 if absf(moved) < trend_epsilon else int(signf(moved))
			_trend_strength[id] = 2 if absf(moved) >= fast_trend_epsilon else 1
			_window_start[id] = _values[id]
	_update_views(delta)
	_update_readouts()
	_overlay.queue_redraw()


## Rising, falling or steady (+1, -1, 0) over the last window. Ids: the vitals and wetness.
func get_trend(id: StringName) -> int:
	return int(_trends.get(id, 0))


## 1 for a steady change, 2 for a fast one (two chevrons); 0 while still.
func get_trend_strength(id: StringName) -> int:
	return int(_trend_strength.get(id, 1)) if get_trend(id) != 0 else 0


## Clothing wetness 0..1, tracked with its own trend for the HUD readouts.
func set_wetness(value: float) -> void:
	_wetness = clampf(value, 0.0, 1.0)
	_track(&"wetness", _wetness)


## Warning and critical levels for one vital: warmth follows the ThermalManager stages
## (CHILLED and HYPOTHERMIC), the others the exported progress thresholds.
func thresholds_for(id: StringName) -> Vector2:
	if id == &"warmth":
		if thermal_manager != null:
			return Vector2(thermal_manager.get_stage_threshold_normalised(ThermalManager.Stage.CHILLED),
				thermal_manager.get_stage_threshold_normalised(ThermalManager.Stage.HYPOTHERMIC))
		return Vector2(0.93, 0.58)
	return Vector2(warning_progress_threshold, critical_progress_threshold)


## Pigment colour at a level: green, yellow and red blended across a band at each threshold.
func state_color_for(id: StringName, level: float) -> Color:
	var limits: Vector2 = thresholds_for(id)
	var upper: Color = warning_color.lerp(normal_color, smoothstep(limits.x - colour_band, limits.x + colour_band * 0.7, level))
	return critical_color.lerp(upper, smoothstep(limits.y - colour_band, limits.y + colour_band, level))


## 0 shows the symbol in half-tone; 1 at and below the critical level.
func vividness_for(id: StringName, level: float) -> float:
	var limits: Vector2 = thresholds_for(id)
	return 1.0 - smoothstep(limits.y - 0.05, lerpf(limits.y, limits.x, 0.6), level)


func _track(id: StringName, value: float) -> void:
	if not _window_start.has(id):
		_window_start[id] = value
	_values[id] = value


## The composition root builds the thermal model; the cluster finds it here.
func on_world_ready(context: WorldContext) -> void:
	if thermal_manager == null:
		thermal_manager = context.get_system(THERMAL_SCRIPT) as ThermalManager
		_bind_thermal()


## Feeds one vital 0..1; a drain nudges and a refill swells its symbol.
func set_vital(id: StringName, value: float) -> void:
	var cell: VitalCell = cells.get(id)
	if cell == null:
		return
	_track(id, value)
	var previous_severity: int = cell.severity
	var pulse: int = cell.set_level(value, pulse_threshold)
	if cell.severity != previous_severity:
		_play_morph(cell)
	match pulse:
		VitalCell.Pulse.DRAIN:
			_play_drain(cell)
		VitalCell.Pulse.REFILL:
			_play_refill(cell)


func get_cell(id: StringName) -> VitalCell:
	return cells.get(id)


func _bind_bio_monitor() -> void:
	if bio_monitor == null:
		var player: Node = owner.get_parent() if owner != null else null
		if player != null:
			bio_monitor = player.get_node_or_null(^"BioMonitorManager") as BioMonitorManager
	if bio_monitor == null:
		return
	bio_monitor.hunger_level_changed.connect(func(v: float) -> void: set_vital(&"hunger", v))
	bio_monitor.thirst_level_changed.connect(func(v: float) -> void: set_vital(&"thirst", v))
	bio_monitor.energy_level_changed.connect(func(v: float) -> void: set_vital(&"sleep", v))
	_seed(&"hunger", bio_monitor.current_calories / maxf(bio_monitor.max_calories, 0.001))
	_seed(&"thirst", bio_monitor.current_hydration / maxf(bio_monitor.max_hydration, 0.001))
	_seed(&"sleep", bio_monitor.current_energy / maxf(bio_monitor.max_energy, 0.001))


func _bind_thermal() -> void:
	if thermal_manager == null or thermal_manager.body_temperature_changed.is_connected(_on_body_temperature):
		return
	thermal_manager.body_temperature_changed.connect(_on_body_temperature)
	thermal_manager.wetness_changed.connect(set_wetness)
	_seed(&"warmth", thermal_manager.get_body_temperature_normalised())
	set_wetness(thermal_manager.get_wetness())


func _on_body_temperature(_celsius: float, normalised: float) -> void:
	set_vital(&"warmth", normalised)


## Sets a level without playing an initial animation.
func _seed(id: StringName, value: float) -> void:
	var cell: VitalCell = cells.get(id)
	_track(id, value)
	if cell != null:
		cell.set_level(value, INF)
		cell.morph_frame = cell.target_morph_frame()
		if _shown.has(id):
			_shown[id]["level"] = cell.level


func _play_drain(cell: VitalCell) -> void:
	_restart_motion(cell)
	cell.pulse = VitalCell.Pulse.DRAIN
	cell.tween.tween_property(cell, ^"push", drain_push_px, drain_duration * 0.35) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	cell.tween.parallel().tween_property(cell, ^"flash", 1.0, drain_duration * 0.35)
	cell.tween.tween_property(cell, ^"push", 0.0, drain_duration * 0.65) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	cell.tween.parallel().tween_property(cell, ^"flash", 0.0, drain_duration * 1.5)


func _play_refill(cell: VitalCell) -> void:
	_restart_motion(cell)
	cell.pulse = VitalCell.Pulse.REFILL
	cell.tween.tween_property(cell, ^"grow", refill_scale, refill_duration * 0.2) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	cell.tween.parallel().tween_property(cell, ^"flash", 1.0, refill_duration * 0.2)
	cell.tween.tween_interval(refill_duration * 0.5)
	cell.tween.tween_property(cell, ^"grow", 0.0, refill_duration * 0.3) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	cell.tween.parallel().tween_property(cell, ^"flash", 0.0, refill_duration * 0.3)


func _play_morph(cell: VitalCell) -> void:
	if cell.morph_tween != null and cell.morph_tween.is_valid():
		cell.morph_tween.kill()
	cell.morph_tween = create_tween()
	cell.morph_tween.tween_property(cell, ^"morph_frame", cell.target_morph_frame(), morph_duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _restart_motion(cell: VitalCell) -> void:
	if cell.tween != null and cell.tween.is_valid():
		cell.tween.kill()
	cell.tween = create_tween()


## Back, pigment and symbol per vital, then the trend overlay, readouts and silhouette.
func _build_views() -> void:
	for id: StringName in DISPLAY_ORDER:
		var level: float = cells[id].level
		var back := _column_rect(back_color, 1.0, 0.05, 1.0, 0.0)
		var pigment := _column_rect(state_color_for(id, level), level, 0.0, 1.15, 1.0)
		var icon := TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.texture = _trimmed(_texture_for(id))
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var icon_material := ShaderMaterial.new()
		icon_material.shader = ICON_SHADER
		icon.material = icon_material
		add_child(icon)
		_views[id] = {"back": back, "pigment": pigment, "icon": icon}
		_shown[id] = {"level": level, "color": state_color_for(id, level)}
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_trends)
	add_child(_overlay)
	_body_label = _readout(body_font_size, body_color)
	_feels_label = _readout(feels_font_size, feels_color)
	_body_base = TextureRect.new()
	_body_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body_base.texture = BODY_BASE
	_body_base.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_body_base.modulate = Color(1.0, 1.0, 1.0, silhouette_alpha)
	add_child(_body_base)
	for part: BodyPartDefinition in BodyPartLibrary.shared().parts:
		var texture: Texture2D = part.silhouette_mask
		if texture == null:
			continue
		var image: Image = texture.get_image()
		var used: Rect2i = image.get_used_rect() if image != null else Rect2i(0, 0, 1, 1)
		var overlay := TextureRect.new()
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.texture = texture
		overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		var frost_material := ShaderMaterial.new()
		frost_material.shader = FROST_SHADER
		frost_material.set_shader_parameter(&"frost", frost_color)
		frost_material.set_shader_parameter(&"y0", float(used.position.y) / float(texture.get_height()))
		frost_material.set_shader_parameter(&"y1", float(used.end.y) / float(texture.get_height()))
		frost_material.set_shader_parameter(&"tip_at_top", 1.0 if part.frost_from_top else 0.0)
		overlay.material = frost_material
		add_child(overlay)
		_frost[part.id] = overlay


func _column_rect(tint: Color, fill: float, fade_start: float, fade_end: float, edge: float) -> ColorRect:
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column_material := ShaderMaterial.new()
	column_material.shader = COLUMN_SHADER
	column_material.set_shader_parameter(&"tint", tint)
	column_material.set_shader_parameter(&"fill", fill)
	column_material.set_shader_parameter(&"fade_start", fade_start)
	column_material.set_shader_parameter(&"fade_end", fade_end)
	column_material.set_shader_parameter(&"edge_line", edge)
	rect.material = column_material
	add_child(rect)
	return rect


func _readout(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", READOUT_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.03, 0.85))
	label.add_theme_constant_override("outline_size", 6)
	add_child(label)
	return label


## Columns sit on the bottom edge (above the chevron room); the silhouette stands over warmth.
func _layout() -> void:
	if _overlay == null:
		return
	var bottom: float = size.y - column_bottom
	for index: int in range(DISPLAY_ORDER.size()):
		var view: Dictionary = _views[DISPLAY_ORDER[index]]
		var x: float = float(index) * (column_width + column_gap)
		_place_column(view["back"], Rect2(x, bottom - column_height, column_width, column_height), column_radius)
		var inset: float = column_width * 0.17
		_place_column(view["pigment"], Rect2(x + inset, bottom - column_height, column_width - inset * 2.0,
			column_height - inset), column_radius * 0.6)
	_overlay.position = Vector2.ZERO
	_overlay.size = size
	var warm_x: float = _column_x(DISPLAY_ORDER.find(&"warmth"))
	var body_size := Vector2(silhouette_height * float(BODY_BASE.get_width()) / float(BODY_BASE.get_height()), silhouette_height)
	var body_origin := Vector2(warm_x + column_width * 0.5 - body_size.x * 0.5,
		bottom - column_height - trend_gap - trend_size * 3.0 - body_size.y)
	_body_base.position = body_origin
	_body_base.size = body_size
	for region: StringName in _frost:
		var overlay: TextureRect = _frost[region]
		overlay.position = body_origin
		overlay.size = body_size
	_body_label.position = Vector2(warm_x + column_width + 6.0, bottom - column_height * 0.62)
	_feels_label.position = Vector2(warm_x + column_width + 6.0, bottom - float(feels_font_size) - 8.0)


func _place_column(rect: ColorRect, area: Rect2, radius: float) -> void:
	rect.position = area.position
	rect.size = area.size
	var column_material := rect.material as ShaderMaterial
	column_material.set_shader_parameter(&"size", area.size)
	column_material.set_shader_parameter(&"radius", radius)


func _column_x(index: int) -> float:
	return float(index) * (column_width + column_gap)


func _update_views(delta: float) -> void:
	var follow: float = 1.0 - exp(-display_rate * delta)
	var bottom: float = size.y - column_bottom
	for index: int in range(DISPLAY_ORDER.size()):
		var id: StringName = DISPLAY_ORDER[index]
		var cell: VitalCell = cells[id]
		var shown: Dictionary = _shown[id]
		shown["level"] = lerpf(float(shown["level"]), cell.level, follow)
		shown["color"] = (shown["color"] as Color).lerp(state_color_for(id, cell.level), follow)
		var view: Dictionary = _views[id]
		var pigment_material := (view["pigment"] as ColorRect).material as ShaderMaterial
		pigment_material.set_shader_parameter(&"fill", shown["level"])
		pigment_material.set_shader_parameter(&"tint", shown["color"])
		var icon: TextureRect = view["icon"]
		var icon_material := icon.material as ShaderMaterial
		icon_material.set_shader_parameter(&"vivid", vividness_for(id, cell.level))
		icon_material.set_shader_parameter(&"tint", shown["color"])
		var side: float = icon_size * float(OPTICAL_SCALE.get(id, 1.0)) * (1.0 + cell.grow)
		icon.size = Vector2(side, side)
		icon.position = Vector2(_column_x(index) + (column_width - side) * 0.5,
			bottom - column_width * 0.35 - side + cell.push * 0.5)
	for region: StringName in _frost:
		var cold: float = thermal_manager.get_extremity_cold(region) if thermal_manager != null else 0.0
		((_frost[region] as TextureRect).material as ShaderMaterial).set_shader_parameter(&"amount", cold)


func _update_readouts() -> void:
	var shown: bool = thermal_manager != null
	_body_label.visible = shown
	_feels_label.visible = shown
	if not shown:
		return
	_body_label.text = tr("HUD_BODY_TEMPERATURE") % thermal_manager.get_body_temperature_c()
	_feels_label.text = tr("HUD_FEELS_LIKE") % TemperatureText.signed(thermal_manager.get_felt_temperature_c())


## Rising: chevrons above the column; falling: below it. Two chevrons for a fast change.
func _draw_trends() -> void:
	var bottom: float = size.y - column_bottom
	var top: float = bottom - column_height
	for index: int in range(DISPLAY_ORDER.size()):
		var id: StringName = DISPLAY_ORDER[index]
		var trend: int = get_trend(id)
		if trend == 0:
			continue
		var color: Color = _shown[id]["color"]
		color.a = 0.75
		var cx: float = _column_x(index) + column_width * 0.5
		var s: float = trend_size
		for k: int in range(get_trend_strength(id)):
			var y: float = top - trend_gap - float(k) * (s + 1.0) if trend > 0 else bottom + trend_gap + float(k) * (s + 1.0)
			var lift: float = s * 0.55 if trend > 0 else -s * 0.55
			_overlay.draw_polyline(PackedVector2Array([Vector2(cx - s, y + lift), Vector2(cx, y - lift),
				Vector2(cx + s, y + lift)]), color, 2.0, true)


## The production PNG cut to its painted area, so asset padding does not shrink the symbol.
func _trimmed(texture: Texture2D) -> Texture2D:
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		return texture
	var used: Rect2i = image.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return texture
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(used)
	return atlas


func _texture_for(id: StringName) -> Texture2D:
	match id:
		&"thirst":
			return THIRST_TEXTURE
		&"hunger":
			return HUNGER_TEXTURE
		&"sleep":
			return SLEEP_TEXTURE
		&"warmth":
			return WARMTH_TEXTURE
		_:
			return null
