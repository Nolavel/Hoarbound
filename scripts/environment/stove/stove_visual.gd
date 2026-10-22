class_name StoveVisual
extends Node3D

## A cast-iron wood stove around a HeatSource (the parent): legs, ash pan with a
## draught vent, a firebox with one log per fuel unit left, a slotted door that
## glows, a cooktop and a flue. Front is +X, where the feed prompt stands.

## Log slots built; the source's full load decides how many can show (6 h / 2 h = 3).
const LOG_VISUAL: GDScript = preload("res://scripts/environment/stove/stove_log_visual.gd")
const MAX_LOGS: int = 4
## How far the door swings open, degrees: folded back along the front, clear of the mouth.
const DOOR_OPEN_DEG: float = 160.0
const SIZE: Vector3 = Vector3(0.62, 0.0, 0.7)  # footprint depth (X) and width (Z)
const LEG_H: float = 0.14
const ASH_H: float = 0.12
const BOX_H: float = 0.5
const WALL: float = 0.03
const DOOR_W: float = 0.44
const DOOR_H: float = 0.34
const FLUE_H: float = 1.7
## Fire strength at the catch, before the warm-up grows it: the firebox shows a small
## flame at once, the room brightens with the burn (author request 2026-10-20).
const FIREBOX_CATCH_STRENGTH: float = 0.45
const ROOM_CATCH_STRENGTH: float = 0.2
## Shown strength follows the stepped simulation intensity at this rate, per second.
const STRENGTH_FOLLOW_RATE: float = 3.0
## Noise flicker: a slow swell (a little brighter, a little dimmer) over fast flame jitter.
const FLICKER_SLOW_HZ: float = 0.35
const FLICKER_FAST_HZ: float = 9.0
const FIREBOX_LIGHT_ENERGY: float = 1.9
const FIREBOX_LIGHT_RANGE: float = 2.2
const ROOM_LIGHT_ENERGY: float = 4.2
## Reaches the far wall (6.7 m) of the shelter; the flatter falloff keeps the light
## the door throws there readable against the room's fill.
const ROOM_LIGHT_RANGE: float = 9.0
const ROOM_LIGHT_FALLOFF: float = 0.5
## Covers the open door's corners (61 degrees off axis) as seen from the fire.
const ROOM_LIGHT_SPOT_ANGLE: float = 65.0
const EMBER_EMISSION_ENERGY: float = 3.0

@export var source: HeatSource

var _iron: StandardMaterial3D
var _embers: StandardMaterial3D
var _logs: Array[Node3D] = []
var _glow: OmniLight3D
var _flicker_t: float = 0.0
var _flicker_noise: FastNoiseLite
var _shown_t: float = 0.0
var _door: Node3D
var _flames: Array[MeshInstance3D] = []
## 0..1 while a lighting act catches: a weak flame that grows before the fire takes.
var _kindle: float = 0.0
var _acting: bool = false
## Visual cohorts only. HeatSource remains the sole fuel/count authority.
var _active_slots: Array[int] = []
var _burned: Dictionary = {}
var _catch_seconds: Dictionary = {}
var _previous_hours: float = -1.0
var _cooling_seconds: float = 0.0
var _was_burning: bool = false
var _door_tween: Tween


func _ready() -> void:
	if source == null:
		source = get_parent() as HeatSource
	_build()
	_flicker_noise = FastNoiseLite.new()
	_flicker_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_flicker_noise.frequency = 0.01
	_flicker_noise.fractal_octaves = 2
	_flicker_noise.seed = randi()
	if source != null:
		source.fuel_changed.connect(func(_f: float) -> void: _refresh())
		source.burning_changed.connect(func(_b: bool) -> void: _refresh())
		source.intensity_changed.connect(func(_v: float) -> void: _refresh())
	_build_door_control()
	_refresh()


## Logs a full load shows: burn_duration_h / hours_per_fuel_unit, capped by the slots built.
func get_capacity_logs() -> int:
	if source == null or source.hours_per_fuel_unit <= 0.0 or source.burn_duration_h <= 0.0:
		return MAX_LOGS
	return clampi(ceili(source.burn_duration_h / source.hours_per_fuel_unit - 0.001), 1, MAX_LOGS)


## Only committed fuel appears in the firebox; the action owns preparation feedback.
func begin_act(lighting: bool, _seconds: float, _count: int = 1, _removing: bool = false) -> void:
	_acting = true
	_swing_door(true)
	if lighting:
		## Manual lighter interaction owns the pre-ignition feedback. The stove
		## itself stays dark until a successful strike actually catches.
		_kindle = 0.0
	_refresh()


func end_act(keep_door_open: bool = false) -> void:
	_acting = false
	_kindle = 0.0
	_swing_door(keep_door_open)
	_refresh()


func is_door_open() -> bool:
	return _door != null and _door.rotation.y > 0.1


func set_door_open(open: bool) -> void:
	_swing_door(open)


func _swing_door(open: bool) -> void:
	if _door == null:
		return
	var angle: float = deg_to_rad(DOOR_OPEN_DEG) if open else 0.0
	if not is_inside_tree():
		_door.rotation.y = angle
		return
	if _door_tween != null:
		_door_tween.kill()
	_door_tween = create_tween()
	_door_tween.set_trans(Tween.TRANS_SINE).tween_property(_door, ^"rotation:y", angle, 0.35)


func get_visible_log_count() -> int:
	var count: int = 0
	for log_node: Node3D in _logs:
		if log_node.visible:
			count += 1
	return count


func is_glowing() -> bool:
	return _glow != null and _glow.visible


func get_firebox_light_energy() -> float:
	return _glow.light_energy if _glow != null else 0.0


func get_room_light_energy() -> float:
	if source == null or source.flame_light == null:
		return 0.0
	return source.flame_light.light_energy


## Burn progress 0..1 from the source's warm-up (intensity 0.08 -> 1), eased so the
## fire grows slowly at first and settles into its nominal burn.
func _fire_growth() -> float:
	if _acting and _kindle > 0.0 and not _burning():
		return 0.0
	if source == null or not source.is_burning():
		return 0.0
	return smoothstep(0.0, 1.0, inverse_lerp(0.08, 1.0, clampf(source.get_intensity(), 0.08, 1.0)))


func _apply_fire_presentation(slow: float, fast: float) -> void:
	var lit: bool = _burning() or (_acting and _kindle > 0.0)
	var firebox: float = lerpf(FIREBOX_CATCH_STRENGTH, 1.0, _shown_t) if lit else 0.0
	var room: float = lerpf(ROOM_CATCH_STRENGTH, 1.0, _shown_t) if lit else 0.0
	_glow.light_energy = FIREBOX_LIGHT_ENERGY * (0.85 + 0.10 * slow + 0.05 * fast) * firebox
	_embers.emission_energy_multiplier = EMBER_EMISSION_ENERGY * (0.85 + 0.12 * slow + 0.02 * fast) * firebox
	var flame_scale: float = maxf(firebox, 0.35)
	for flame: MeshInstance3D in _flames:
		flame.scale.y = (0.86 + 0.08 * slow + 0.06 * fast) * flame_scale
	if source != null and source.flame_light != null and source.flame_light.visible:
		source.flame_light.light_energy = ROOM_LIGHT_ENERGY * (0.97 + 0.07 * slow + 0.03 * fast) * room


func _process(delta: float) -> void:
	_update_log_stages(delta)
	if _acting and _kindle > 0.0 and not _glow.visible:
		_glow.visible = true
		_embers.emission_enabled = true
	if not is_glowing():
		return
	_flicker_t += delta
	_shown_t = move_toward(_shown_t, _fire_growth(), STRENGTH_FOLLOW_RATE * delta)
	_apply_fire_presentation(_flicker(FLICKER_SLOW_HZ, 0.0), _flicker(FLICKER_FAST_HZ, 5000.0))


## Perlin layer in -1..1; the raw noise rarely leaves +-0.6, so it is rescaled.
func _flicker(hz: float, offset: float) -> float:
	return clampf(_flicker_noise.get_noise_1d(_flicker_t * hz * 100.0 + offset) * 1.6, -1.0, 1.0)


func _burning() -> bool:
	return source != null and source.is_burning()


func _refresh() -> void:
	var burning: bool = _burning()
	var units: int = 0
	if source != null and source.hours_per_fuel_unit > 0.0:
		units = source.get_loaded_log_count()
	_sync_log_slots(clampi(units, 0, get_capacity_logs()))
	_glow.visible = burning or (_acting and _kindle > 0.0)
	for flame: MeshInstance3D in _flames:
		flame.visible = _glow.visible
	_embers.emission_enabled = burning or (_acting and _kindle > 0.0)
	_embers.albedo_color = Color(0.9, 0.35, 0.1) if burning else Color(0.18, 0.17, 0.16)
	if _glow.visible:
		## Successful ignition must be visible immediately, before the next frame.
		_apply_fire_presentation(0.0, 0.0)
	else:
		_shown_t = 0.0
		_glow.light_energy = 0.0
		_embers.emission_energy_multiplier = 0.0


func _sync_log_slots(count: int) -> void:
	var hours: float = source.get_remaining_hours() if source != null else 0.0
	if _previous_hours >= 0.0 and hours < _previous_hours and (_burning() or _was_burning) and source.hours_per_fuel_unit > 0.0:
		var spent: float = (_previous_hours - hours) / source.hours_per_fuel_unit
		for slot: int in _active_slots:
			var part: float = minf(spent, 1.0 - float(_burned.get(slot,0.0)))
			_burned[slot] = float(_burned.get(slot,0.0)) + part
			spent -= part
	_previous_hours = hours
	while _active_slots.size() > count:
		var slot: int = _active_slots.pop_front()
		_logs[slot].visible = false
		_burned.erase(slot)
		_catch_seconds.erase(slot)
	while _active_slots.size() < count:
		for slot: int in range(_logs.size()):
			if not _active_slots.has(slot):
				_active_slots.append(slot)
				_burned[slot] = 0.0
				_catch_seconds[slot] = 0.0
				break
	for slot: int in range(_logs.size()):
		_logs[slot].visible = _active_slots.has(slot)
	# Settle the surviving visual cohorts into the lowest available positions.
	# Identity/char stage stays with the node; this never changes authoritative fuel.
	for order: int in range(_active_slots.size()):
		var side: float = 1.0 if order % 2 == 0 else -1.0
		_logs[_active_slots[order]].position = Vector3(side*0.09-0.04,
			LEG_H+ASH_H+WALL+0.06+float(order/2)*0.07,0.0)
	if _was_burning and not _burning():
		_cooling_seconds = 6.0
	_was_burning = _burning()
	_update_log_stages(0.0)


func _update_log_stages(delta: float) -> void:
	_cooling_seconds = maxf(0.0,_cooling_seconds-delta)
	for slot: int in _active_slots:
		var progress: float = 0.0
		if _burning():
			_catch_seconds[slot] = float(_catch_seconds.get(slot,0.0)) + delta
			var growth: float = minf(float(_catch_seconds[slot])/maxf(source.warmup_seconds,1.0),1.0)
			progress = maxf(lerpf(0.06,0.35,growth),0.35+float(_burned.get(slot,0.0))*0.63) if float(_burned.get(slot,0.0)) > 0.01 else lerpf(0.06,0.35,growth)
		elif float(_catch_seconds.get(slot,0.0)) > 0.0:
			progress = lerpf(1.0,0.87,_cooling_seconds/6.0)
		_logs[slot].set_stage(progress)
	# Residual coals are visual only; never extend the HeatSource or room heating.
	if not _burning():
		_embers.emission_enabled = _cooling_seconds > 0.0
		_embers.emission_energy_multiplier = EMBER_EMISSION_ENERGY * _cooling_seconds/6.0 * 0.25


func _build() -> void:
	_iron = _material(Color(0.13, 0.13, 0.14), 0.75, 0.6)
	_embers = _material(Color(0.9, 0.35, 0.1), 0.9, 0.0)
	_embers.emission = Color(1.0, 0.42, 0.12)
	var hx: float = SIZE.x * 0.5
	var hz: float = SIZE.z * 0.5
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_box(Vector3(0.05, LEG_H, 0.05), Vector3(sx * (hx - 0.05), LEG_H * 0.5, sz * (hz - 0.05)), _iron)
	## Ash pan: a drawer under the firebox with the draught vent in front.
	var ash_y: float = LEG_H + ASH_H * 0.5
	_box(Vector3(SIZE.x, ASH_H, SIZE.z), Vector3(0.0, ash_y, 0.0), _iron)
	for i: int in range(3):
		_box(Vector3(0.01, 0.025, 0.09), Vector3(hx + 0.004, ash_y, (i - 1) * 0.12), _material(Color(0.03, 0.03, 0.03), 1.0, 0.0))
	_box(Vector3(0.03, 0.02, 0.14), Vector3(hx + 0.02, ash_y - 0.035, 0.0), _iron)  # drawer pull
	## Firebox: floor, back, sides, a front frame around the door opening, cooktop.
	var floor_y: float = LEG_H + ASH_H
	var top_y: float = floor_y + BOX_H
	var mid_y: float = floor_y + BOX_H * 0.5
	_box(Vector3(SIZE.x, WALL, SIZE.z), Vector3(0.0, floor_y + WALL * 0.5, 0.0), _iron)
	_box(Vector3(WALL, BOX_H, SIZE.z), Vector3(-hx + WALL * 0.5, mid_y, 0.0), _iron)
	for sz: float in [-1.0, 1.0]:
		_box(Vector3(SIZE.x, BOX_H, WALL), Vector3(0.0, mid_y, sz * (hz - WALL * 0.5)), _iron)
	var post: float = (SIZE.z - DOOR_W) * 0.5
	for sz: float in [-1.0, 1.0]:
		_box(Vector3(WALL, BOX_H, post), Vector3(hx - WALL * 0.5, mid_y, sz * (hz - post * 0.5)), _iron)
	var sill: float = (BOX_H - DOOR_H) * 0.5
	_box(Vector3(WALL, sill, DOOR_W), Vector3(hx - WALL * 0.5, floor_y + sill * 0.5, 0.0), _iron)
	_box(Vector3(WALL, sill, DOOR_W), Vector3(hx - WALL * 0.5, top_y - sill * 0.5, 0.0), _iron)
	_box(Vector3(SIZE.x + 0.06, 0.03, SIZE.z + 0.06), Vector3(0.0, top_y + 0.015, 0.0), _iron)
	_cylinder(0.11, 0.012, Vector3(0.05, top_y + 0.036, -0.14), _material(Color(0.2, 0.2, 0.21), 0.6, 0.7))  # cooking ring
	## Ember bed and logs inside: one log per fuel unit, stacked two by two.
	_box(Vector3(SIZE.x - 0.12, 0.012, SIZE.z - 0.12), Vector3(0.0, floor_y + WALL + 0.006, 0.0), _material(Color(0.055,0.047,0.04),1.0,0.0))
	# Sparse coals instead of one uniformly emissive orange plate.
	for i: int in range(12):
		var x: float = (float(i / 4)-1.0)*0.12 + 0.013*sin(float(i)*3.1)
		var z: float = (float(i % 4)-1.5)*0.13 + 0.01*cos(float(i)*2.7)
		var coal := _cylinder(0.024,0.018,Vector3(x,floor_y+WALL+0.018,z),_embers)
		coal.scale = Vector3(1.0+0.2*sin(float(i)),1.0,0.7+0.2*cos(float(i)))
	for i: int in range(MAX_LOGS):
		var layer: int = i / 2
		var side: float = 1.0 if i % 2 == 0 else -1.0
		var log_node: Node3D = LOG_VISUAL.new()
		log_node.name = "FuelLog%d" % i
		log_node.position = Vector3(side * 0.09 - 0.04, floor_y + WALL + 0.06 + layer * 0.07, 0.0)
		add_child(log_node)
		_logs.append(log_node)
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.5, 0.2)
	_glow.omni_range = FIREBOX_LIGHT_RANGE
	_glow.position = Vector3(hx + 0.15, mid_y, 0.0)  # spills out through the door slots
	add_child(_glow)
	if source != null and source.flame_light != null:
		_place_room_light(source.flame_light, Vector3(hx - 0.15, floor_y + 0.24, 0.0))
	_build_door(Vector3(hx + 0.01, floor_y + sill, -DOOR_W * 0.5))
	## Flue: a collar on the cooktop at the back, a pipe to the roof.
	_cylinder(0.08, 0.06, Vector3(-hx + 0.15, top_y + 0.06, 0.0), _iron)
	_cylinder(0.065, FLUE_H, Vector3(-hx + 0.15, top_y + 0.06 + FLUE_H * 0.5, 0.0), _iron)


## The room light sits in the fire and shines out through the door (+X). The
## firebox walls and door bars are its shadow mask: closed, it leaves only through the bars.
func _place_room_light(light: Light3D, fire: Vector3) -> void:
	light.global_transform = global_transform * Transform3D(Basis(Vector3.UP, -PI * 0.5), fire)
	light.shadow_enabled = true
	if light is SpotLight3D:
		var spot := light as SpotLight3D
		spot.spot_range = maxf(spot.spot_range, ROOM_LIGHT_RANGE)
		spot.spot_attenuation = ROOM_LIGHT_FALLOFF
		spot.spot_angle = ROOM_LIGHT_SPOT_ANGLE
	elif light is OmniLight3D:
		var omni := light as OmniLight3D
		omni.omni_range = maxf(omni.omni_range, ROOM_LIGHT_RANGE)
		omni.omni_attenuation = ROOM_LIGHT_FALLOFF


## A door hinged on its -Z edge: solid lower half, vertical bars above with gaps
## the fire shows through, and a knob.
func _build_door(hinge_at: Vector3) -> void:
	var hinge := Node3D.new()
	hinge.name = "DoorHinge"
	_door = hinge
	hinge.position = hinge_at
	add_child(hinge)
	var lower: float = DOOR_H * 0.45
	_box(Vector3(0.025, lower, DOOR_W), Vector3(0.0, lower * 0.5, DOOR_W * 0.5), _iron, hinge)
	_box(Vector3(0.025, 0.04, DOOR_W), Vector3(0.0, DOOR_H - 0.02, DOOR_W * 0.5), _iron, hinge)
	var bars: int = 6
	var bar_w: float = 0.035
	var gap_h: float = DOOR_H - lower - 0.04
	for i: int in range(bars):
		var z: float = bar_w * 0.5 + i * (DOOR_W - bar_w) / float(bars - 1)
		_box(Vector3(0.025, gap_h, bar_w), Vector3(0.0, lower + gap_h * 0.5, z), _iron, hinge)
	_cylinder(0.018, 0.04, Vector3(0.03, DOOR_H * 0.5, DOOR_W - 0.05), _material(Color(0.5, 0.45, 0.35), 0.5, 0.8), hinge)


func _box(size: Vector3, at: Vector3, material: Material, parent: Node3D = self) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	parent.add_child(node)
	return node


func _cylinder(radius: float, height: float, at: Vector3, material: Material, parent: Node3D = self) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.material = material
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	parent.add_child(node)
	return node


func _material(albedo: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.roughness = roughness
	material.metallic = metallic
	return material


func _build_door_control() -> void:
	var feed: HeatSourceFeed = source.find_child("Feed", true, false) as HeatSourceFeed if source != null else null
	if feed == null:
		return
	var control := StoveDoorControl.new()
	control.name = "DoorControl"
	control.feed = feed
	control.auto_detect_ground = false
	control.object_on_ground = false
	control.player_animation_action = &"none"
	control.position = Vector3(0.02, DOOR_H * 0.5, DOOR_W * 0.5)
	feed.door_control = control
	_door.add_child(control)
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.10, DOOR_H, DOOR_W)
	collider.shape = box
	control.add_child(collider)
	var anchor := Marker3D.new()
	control.add_child(anchor)
	control.focus_anchor = anchor
