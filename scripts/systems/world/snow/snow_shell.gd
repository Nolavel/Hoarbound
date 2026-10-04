class_name SnowShell
extends Node3D

## Deformable snow around Henry. SnowField says how much snow lies where; an
## upward camera sees whatever presses into it and packs it down for good.

## A boot left its print: where, how deep it had sunk and how soft the snow was.
signal foot_lifted(side: int, position: Vector3, sink_m: float, softness: float)

const SURFACE_SHADER: Shader = preload("res://shaders/environment/snow/snow_ground.gdshader")
const CONTACT_SHADER: Shader = preload("res://shaders/environment/snow/snow_contact_depth.gdshader")
const ACCUMULATE_SHADER: Shader = preload("res://shaders/environment/snow/snow_accumulate.gdshader")
const SHAPE_SHADER: Shader = preload("res://shaders/environment/snow/snow_shape.gdshader")
const WEATHER_SCRIPT: GDScript = preload("res://scripts/systems/world/WeatherController.gd")
const TERRAIN_SCRIPT: GDScript = preload("res://scripts/systems/world/terrain/island_terrain.gd")
const PRESENTATION_SCRIPT: GDScript = preload("res://scripts/systems/world/snow/snow_presentation_system.gd")
const PICKUP_SCRIPT: GDScript = preload("res://scripts/environment/interactive/item_pickup.gd")
## Contact capture side on the medium tier; the packed field keeps its resolution.
const MEDIUM_CONTACT_RES: int = 512
## Change in storm share that is worth rebuilding the window for.
const STORM_REBUILD_STEP: float = 0.05
## Rebuild settled depth for weather accumulation even while Henry stands still.
const COVER_REBUILD_STEP: float = 0.02
## Colliders in this group are kept clear of snow, like swept steps.
const SWEPT_GROUP: StringName = &"snow_swept"
const SENSOR_SCRIPT: GDScript = preload("res://scripts/actors/player/henry/components/foot_contact_sensor.gd")
## Render layer 19 (snow_contact): meshes on it press into the snow.
const CONTACT_LAYER: int = RenderLayers.SNOW_CONTACT

@export_group("Window")
## Side of the square window around the player, in metres.
@export var window_m: float = 25.6
## Mesh spacing around Henry, where prints are read up close, in metres.
@export var near_spacing_m: float = 0.03
## Half width of that dense core; spacing grows towards the window edge.
@export var near_half_m: float = 2.75
## Mesh spacing at the window edge, in metres.
@export var far_spacing_m: float = 0.25
## Texels along one side of the settled field.
@export_range(32, 256) var field_res: int = 128
## Texels along one side of the packed-snow field.
@export_range(128, 2048) var packed_res: int = 896
## Texels along one side of the contact capture, rendered every frame.
@export_range(128, 2048) var contact_res: int = 1024
## The window moves in steps of this size, so the snow never swims.
@export var recentre_step_m: float = 3.2
## Frame budget for a window move while walking; the old window stays live meanwhile.
@export var rebuild_budget_usec: int = 4000
## Budget once Henry nears the window's faded rim, where prints stop showing.
@export var urgent_budget_usec: int = 12000
## The window is built this many seconds ahead of Henry's travel, so a rebuild
## finishes around him instead of behind him when he runs.
@export var lead_s: float = 0.9
@export var lead_max_m: float = 4.0

@export_group("Snow")
## Settled depth at snow_cover 0 and 1, in metres.
@export var cover_depth_m: Vector2 = Vector2(0.05, 0.25)
## Tallest wind drift and lee pile at snow_cover 1, in metres.
@export var drift_m: float = 0.3
@export var lee_m: float = 0.6
## Snow thins out towards this height and never lies below it.
@export var sea_level_m: float = 0.04
## Baked city wind field; used only over island terrain.
@export_file("*.png") var wind_field_path: String = "res://data/world/key_west/snow_wind.png"
## Share of the settled depth a foot or body packs down.
@export_range(0.0, 1.0) var max_pack: float = 0.85
## Slope a print's wall stands at in loose powder, degrees. Snow is cohesive:
## walls stay steep (Sumner et al. 1999 give snow 90); a 40° repose cone drew prints far too wide.
@export_range(20.0, 89.0) var repose_deg: float = 65.0
## Slope wind crust and settled snow walls stand at, degrees.
@export_range(40.0, 89.0) var crust_wall_deg: float = 84.0
## Share of the excess slope a wall sheds per frame; higher collapses faster.
@export_range(0.0, 0.045) var liquidity: float = 0.035
## 0 walls slump evenly, 1 they crumble in random bits.
@export_range(0.0, 1.0) var crumble: float = 0.6
## Share of the snow under a boot pushed onto the rim instead of compressed.
@export_range(0.0, 1.0) var displace_powder: float = 0.3
@export_range(0.0, 1.0) var displace_crust: float = 0.05
## Distance outside the sole where pushed-aside snow heaps highest, metres.
@export var rim_peak_m: float = 0.035
## Share of that heap thrown ahead of the boot rather than evenly round it.
@export_range(0.0, 0.9) var rim_forward_bias: float = 0.35
## Seconds for a planted boot to press ~63% of the way down: snow has weight to shift.
@export var sink_time_s: float = 0.22
## Running lands at up to ~2.5x body weight: at this speed the heel strike alone
## packs this share of the give at once, and the rest sinks twice as fast.
@export var impact_speed_mps: float = 5.0
@export_range(0.0, 0.9) var impact_share: float = 0.55
## Prints deeper than this shed clumps from their walls when the boot lifts, metres.
@export var collapse_depth_m: float = 0.1
## Share of a print's depth the fallen clumps fill back, at most.
@export_range(0.0, 0.5) var collapse_share: float = 0.18

@export_group("Fill")
## Seconds packed snow takes to fill back in with no snow falling.
@export var fill_calm_s: float = 900.0
## Seconds it takes in a whiteout.
@export var fill_whiteout_s: float = 45.0

@export_group("Movement")
## Speed share left in the deepest snow Henry wades through.
@export_range(0.2, 1.0) var deep_snow_speed: float = 0.38
## Depth at which wading is slowest, in metres (about knee height).
@export var deep_snow_m: float = 0.5
## Each boot planted in deep snow has to break through it: speed dips by this
## share at full wade, then recovers over `step_surge_s`. Wading comes in surges.
@export_range(0.0, 0.8) var step_surge: float = 0.45
@export var step_surge_s: float = 0.22
## Deeper than this Henry wades: his whole body ploughs a trench. Shallower,
## only planted soles press, so steps stay separate prints.
@export var wade_depth_m: float = 0.3
## Henry starts leaning into the snow at the first depth and fully wades by the second.
@export var wade_gait_m: Vector2 = Vector2(0.3, 0.55)
## Width of one sole and how far it reaches past the heel and toe bones.
@export var sole_width_m: float = 0.11
@export var sole_margin_m: float = 0.05
## Width and length of the toe that drags through snow on a lifted foot.
@export var drag_size_m: Vector2 = Vector2(0.07, 0.14)
## Extra depth the heel digs on strike and the ball on push-off, metres: a
## walking print is deep at both ends and shallow under the arch.
@export var heel_dig_m: float = 0.02
@export var toe_dig_m: float = 0.03
## Heel rise over the stance, metres, at which the ball carries all the weight.
@export var heel_roll_m: float = 0.05
## Speed at which the toe-off throws the most powder, m/s.
@export var kick_speed_mps: float = 3.0
## Speed share left for acceleration in the deepest snow: it takes effort to get going.
@export_range(0.1, 1.0) var deep_snow_accel: float = 0.45

## Henry's live snow window (min corner, size, 1 when live), the same as the snow_window global.
static var live_window: Vector4 = Vector4.ZERO
## The shell under Henry's feet, for his rig to read the pressed snow from.
static var active: SnowShell

var field: SnowField = SnowField.new()

var _field_tex: ImageTexture
var _surface: ShaderMaterial
var _mesh: MeshInstance3D
var _contact: SubViewport
var _contact_cam: Camera3D
var _contact_quad: ShaderMaterial
var _accum: Array[SubViewport] = []
var _accum_mat: Array[ShaderMaterial] = []
var _shape: Array[SubViewport] = []
var _shape_mat: Array[ShaderMaterial] = []
var _parity: int = 0
var _warmup: int = 3
var _pending_shift: Vector2 = Vector2.ZERO
## Packed snow kept after it leaves the window, and its restore image for the window.
var tracks: SnowTrackStore = SnowTrackStore.new()
var _restore_tex: ImageTexture
var _restore_all: bool = false
var _base_y: float = 0.0
## The move a streamed rebuild is working on.
var _move_from: Vector2 = Vector2(INF, INF)
var _move_cover: float = 0.0
var _move_wind: Vector2 = Vector2(0, -1)
var _live_cover: float = -1.0
var _player: Node3D
var _mover: Node
var _weather: WeatherController
var _presentation: Node
var _terrain: IslandTerrain
var _city: Node3D
var _world_root: Node
var _sensor: FootContactSensor
## A sole is two pads, heel and forefoot: their union has the waist of a boot.
var _heels: Array[MeshInstance3D] = []
var _balls: Array[MeshInstance3D] = []
var _drags: Array[MeshInstance3D] = []
var _kicks: Array[GPUParticles3D] = []
var _speed: float = 0.0
var _sole_fwd: Array[Vector2] = [Vector2(0, -1), Vector2(0, -1)]
var _sole_len: Array[float] = [0.3, 0.3]
## Heel-over-ball height the clip had at the plant; its rise is the roll to the toe.
var _heel_rest: Array[float] = [0.0, 0.0]
## Displaced snow waiting for the next accumulation pass, per foot: metres at peak.
var _pending_rim: Array[float] = [0.0, 0.0]
## Seconds since a boot last planted, and how deep that plant was (0..1 wade).
var _since_plant: float = 10.0
var _plant_wade: float = 0.0
## Spray a boot ploughing through snow throws ahead of its toe, per foot.
var _ploughs: Array[GPUParticles3D] = []
var _last_toe: Array[Vector3] = [Vector3.INF, Vector3.INF]
## Per foot: seconds planted (-1 lifted), metres pressed, print centre and shape.
var _stance: Array[float] = [-1.0, -1.0]
var _sink: Array[float] = [0.0, 0.0]
var _foot_top: Array[float] = [-INF, -INF]
var _raise: Array[float] = [0.0, 0.0]
var _clumps: Array[GPUParticles3D] = []
## Collapse to apply on the next accumulation pass: uv centre, uv radius, share.
var _pending_collapse: Vector4 = Vector4.ZERO
var _sole_at: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var _sole_basis: Array[Basis] = [Basis.IDENTITY, Basis.IDENTITY]
var _wading: bool = false
var _gait: Node


func _ready() -> void:
	if not SnowField.high_quality():
		set_process(false)
		set_physics_process(false)
		return
	if SnowField.quality() == &"medium":
		contact_res = MEDIUM_CONTACT_RES
	field.window_m = window_m
	field.res = field_res
	field.sea_level_m = sea_level_m
	field.cover_depth_m = cover_depth_m
	field.drift_m = drift_m
	field.lee_m = lee_m
	field.ground_sampler = _sample_ground
	_build_surface()
	_build_capture()


func on_world_ready(context: WorldContext) -> void:
	if not SnowField.high_quality():
		return
	_player = context.player
	_world_root = context.world
	active = self
	_weather = context.get_system(WEATHER_SCRIPT) as WeatherController
	_presentation = context.get_system(PRESENTATION_SCRIPT)
	_terrain = context.find_in_scene(TERRAIN_SCRIPT) as IslandTerrain
	## Only the island has a sea; a test floor at y 0 is not water.
	field.sea_level_m = sea_level_m if _terrain != null else -INF
	if _terrain != null and not wind_field_path.is_empty():
		field.use_baked_baseline = field.load_wind_field(wind_field_path)
		_surface.set_shader_parameter("use_baked_baseline", field.use_baked_baseline)
		if field.use_baked_baseline:
			RenderingServer.global_shader_parameter_set(&"snow_wind", field.settled_wind)
			_surface.set_shader_parameter("wind_tex", field.wind_texture)
			_surface.set_shader_parameter("wind_origin", field.wind_field_origin)
			_surface.set_shader_parameter("wind_extent",
				Vector2(field.wind_field.get_width(), field.wind_field.get_height()) * field.wind_field_cell_m)
			_surface.set_shader_parameter("wind_max", field.wind_field_max)
	if _player != null:
		_mover = _player.get_node_or_null(^"MovementController")
		_gait = _player.find_child("Wade", true, false)
	_sensor = context.find_in_scene(SENSOR_SCRIPT) as FootContactSensor
	## Pickups press snow: tag the ones already placed once, then each as it spawns.
	if _world_root != null:
		for pickup: Node in _world_root.find_children("*", "", true, false):
			if is_instance_of(pickup, PICKUP_SCRIPT):
				tag_contact(pickup)
	if is_inside_tree() and not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)


## Puts every mesh under `root` on the contact layer, so it presses into snow.
func tag_contact(root: Node, on: bool = true) -> void:
	if root is VisualInstance3D and not is_ancestor_of(root):
		var visual := root as VisualInstance3D
		visual.layers = (visual.layers | CONTACT_LAYER) if on else (visual.layers & ~CONTACT_LAYER)
	for child: Node in root.get_children():
		tag_contact(child, on)


func _physics_process(_delta: float) -> void:
	if _player == null:
		return
	if _city == null and _world_root != null:
		_city = _world_root.find_child("KeyWestCity", true, false) as Node3D
	var at: Vector3 = _player.global_position
	var travel := Vector2.ZERO
	if _player is CharacterBody3D:
		var v: Vector3 = (_player as CharacterBody3D).velocity
		travel = Vector2(v.x, v.z)
		_speed = travel.length()
	_follow(Vector2(at.x, at.z), (travel * lead_s).limit_length(lead_max_m))
	var depth: float = field.get_depth(at.x, at.z)
	_since_plant += _delta
	if _mover != null and &"snow_speed_multiplier" in _mover:
		var surge: float = step_surge * _plant_wade * exp(-_since_plant / maxf(step_surge_s, 0.01))
		_mover.set(&"snow_speed_multiplier", get_speed_multiplier(depth) * (1.0 - surge))
	if _mover != null and &"snow_accel_multiplier" in _mover:
		_mover.set(&"snow_accel_multiplier", get_accel_multiplier(depth))
	if _gait != null:
		_gait.set(&"wade", clampf(inverse_lerp(wade_gait_m.x, wade_gait_m.y, depth), 0.0, 1.0))
	var wading: bool = depth > wade_depth_m
	if wading != _wading:
		_wading = wading
		tag_contact(_player, wading)
	_place_soles(_delta)


## Sets a sole under each foot as it lands, then lowers it as the snow under the
## boot compacts: a step settles in over the stance, it never drops at once.
func _place_soles(delta: float) -> void:
	## Standing still both boots rest in their prints; the sensor only plants steps.
	var standing: bool = _speed < 0.15 and _player is CharacterBody3D and (_player as CharacterBody3D).is_on_floor()
	for side: int in range(_heels.size()):
		var foot: Dictionary = _sensor.get_foot(side) if _sensor != null else {}
		var planted: bool = not foot.is_empty() and (_sensor.is_planted(side) or standing)
		_place_drag(side, foot, planted)
		if not planted:
			if _stance[side] >= 0.0:
				_lift_off(side)
			_heels[side].visible = false
			_balls[side].visible = false
			_stance[side] = -1.0
			_sink[side] = 0.0
			_raise[side] = 0.0
			continue
		## A planted sole stays where it landed: the walk clip glides, a boot does not.
		if not _heels[side].visible:
			var heel: Vector3 = foot["heel"]
			var toe: Vector3 = foot["toe"]
			var along := Vector3(toe.x - heel.x, 0.0, toe.z - heel.z)
			if along.length_squared() < 0.0001:
				along = Vector3.FORWARD * 0.2
			_sole_basis[side] = Basis.looking_at(along.normalized(), Vector3.UP)
			_sole_fwd[side] = Vector2(along.x, along.z).normalized()
			_sole_len[side] = along.length() + sole_margin_m * 2.0
			_sole_at[side] = Vector2((heel.x + toe.x) * 0.5, (heel.z + toe.z) * 0.5)
			_heel_rest[side] = heel.y - (foot["ball"] as Vector3).y
			_stance[side] = 0.0
			if not standing:
				_since_plant = 0.0
				var here: float = field.get_depth(_sole_at[side].x, _sole_at[side].y)
				_plant_wade = clampf(inverse_lerp(wade_gait_m.x * 0.5, deep_snow_m, here), 0.0, 1.0)
			_heels[side].visible = true
			_balls[side].visible = true
		_stance[side] += delta
		var at: Vector2 = _sole_at[side]
		var top: float = field.get_snow_top(at.x, at.y)
		var depth: float = field.get_depth(at.x, at.y)
		var softness: float = field.get_softness(at.x, at.y)
		var give: float = depth * max_pack * softness
		var was: float = _sink[side]
		var impact: float = clampf(_speed / maxf(impact_speed_mps, 0.1), 0.0, 1.0)
		_sink[side] = sink_after(_stance[side], give, sink_time_s / (1.0 + impact), impact * impact_share)
		_foot_top[side] = top
		## The clip plants the boot on the ground; lift it to the pressed snow instead.
		## Read from the field, never from the boot, so the lift cannot feed on itself.
		_raise[side] = clampf(depth - _sink[side], 0.0, depth) if top > -INF else 0.0
		if top > -INF:
			_queue_rim(side, _sink[side] - was, softness)
		## Outside the window there is no snow to press: park the sole far below.
		var bottom: float = top - _sink[side] if top > -INF else -1000.0
		var dig: Vector2 = _roll_dig(side, foot, softness)
		var fwd := Vector3(_sole_fwd[side].x, 0.0, _sole_fwd[side].y)
		var centre := Vector3(at.x, 0.0, at.y)
		var length: float = _sole_len[side]
		_heels[side].global_transform = Transform3D(
			_sole_basis[side].scaled_local(Vector3(sole_width_m * 0.85, 0.3, length * 0.44)),
			centre - fwd * length * 0.28 + Vector3.UP * (bottom - dig.x + 0.15)
		)
		_balls[side].global_transform = Transform3D(
			_sole_basis[side].scaled_local(Vector3(sole_width_m, 0.3, length * 0.64)),
			centre + fwd * length * 0.17 + Vector3.UP * (bottom - dig.y + 0.15)
		)


## Extra depth under heel and ball as the clip rolls the foot: the heel carries
## the strike, the ball the push-off. Faster steps and softer snow dig deeper.
func _roll_dig(side: int, foot: Dictionary, softness: float) -> Vector2:
	var pace: float = clampf(_speed / kick_speed_mps, 0.4, 1.2) * softness
	var strike: float = heel_dig_m * exp(-_stance[side] / 0.1)
	var heel_rise: float = ((foot["heel"] as Vector3).y - (foot["ball"] as Vector3).y) - _heel_rest[side]
	var push: float = toe_dig_m * clampf(heel_rise / maxf(heel_roll_m, 0.001), 0.0, 1.0)
	return Vector2(strike, push) * pace


## Snow the boot pushes aside as it sinks `sunk` metres, heaped on the rim of an
## oval sole: height at the rim peak so its volume is the displaced share.
func _queue_rim(side: int, sunk: float, softness: float) -> void:
	if sunk <= 0.0:
		return
	var powder: float = smoothstep(0.45, 0.95, softness)
	var share: float = lerpf(displace_crust, displace_powder, powder)
	var a: float = _sole_len[side] * 0.5
	var b: float = sole_width_m * 0.5
	var perimeter: float = PI * (3.0 * (a + b) - sqrt((3.0 * a + b) * (a + 3.0 * b)))
	## A profile x·e^(1-x) over the rim peak distance holds e·peak per metre of edge.
	_pending_rim[side] += share * sunk * PI * a * b / (perimeter * exp(1.0) * maxf(rim_peak_m, 0.005))


## A boot leaving its print: powder flicks off the toe, and a deep print's walls
## break and tumble in.
func _lift_off(side: int) -> void:
	var top: float = _foot_top[side]
	if top == -INF:
		return
	var softness: float = field.get_softness(_sole_at[side].x, _sole_at[side].y)
	var fwd := Vector3(_sole_fwd[side].x, 0.0, _sole_fwd[side].y)
	var ball := Vector3(_sole_at[side].x, top - _sink[side] * 0.5, _sole_at[side].y) + fwd * _sole_len[side] * 0.3
	var throw: float = clampf(_speed / kick_speed_mps, 0.0, 1.0) * smoothstep(0.45, 0.95, softness)
	throw *= clampf(field.get_depth(_sole_at[side].x, _sole_at[side].y) / 0.15, 0.0, 1.0)
	if throw > 0.05:
		var kick: GPUParticles3D = _kicks[side]
		kick.global_transform = Transform3D(_sole_basis[side], ball)
		kick.amount_ratio = throw
		kick.restart()
	foot_lifted.emit(side, ball, _sink[side], softness)
	if _sink[side] > collapse_depth_m:
		_collapse(side)


## A boot leaving a deep print: clumps break off the walls and tumble in, and the
## floor rises in lumps where they land.
func _collapse(side: int) -> void:
	var at: Vector2 = _sole_at[side]
	var top: float = _foot_top[side]
	if top == -INF or field.origin.x == INF:
		return
	var clumps: GPUParticles3D = _clumps[side]
	clumps.global_position = Vector3(at.x, top - _sink[side] * 0.2, at.y)
	clumps.restart()
	_pending_collapse = Vector4((at.x - field.origin.x) / window_m, (at.y - field.origin.y) / window_m,
		(sole_width_m + 0.12) / window_m, collapse_share)


## Metres a boot has pressed after `t` seconds of stance into snow that gives `give`.
## `impact` is the share packed at once by a hard landing.
static func sink_after(t: float, give: float, time_s: float, impact: float = 0.0) -> float:
	var settle: float = 1.0 - exp(-maxf(t, 0.0) / maxf(time_s, 0.001))
	return give * lerpf(settle, 1.0, clampf(impact, 0.0, 1.0))


## How deep the `side` foot has pressed right now, metres (0 when lifted).
func get_foot_sink(side: int) -> float:
	return _sink[side]


## Metres the `side` boot sits above where the walk clip puts it (0 when lifted).
func get_foot_raise(side: int) -> float:
	return _raise[side]


## Undisturbed snow top under the `side` foot's print, or -INF when lifted.
func get_foot_snow_top(side: int) -> float:
	return _foot_top[side] if _stance[side] >= 0.0 else -INF


func _process(delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null and camera != _contact_cam:
		camera.cull_mask &= ~CONTACT_LAYER
	var density: float = 0.0
	if _weather != null:
		density = clampf(_weather.get_snowfall_density(), 0.0, 1.0)
	var fill: float = delta / lerpf(fill_calm_s, fill_whiteout_s, density)
	if _warmup > 0:
		fill = 1.0
		_warmup -= 1
	else:
		tracks.advance(fill)
		## A fresh window or a load takes every texel from the restored tiles.
		if _restore_all:
			_pending_shift = Vector2(4.0, 4.0)
			_restore_all = false
	var target: int = _parity
	var mat: ShaderMaterial = _accum_mat[target]
	mat.set_shader_parameter("shift_uv", _pending_shift)
	mat.set_shader_parameter("collapse", _pending_collapse)
	_pending_collapse = Vector4.ZERO
	_apply_rims(mat)
	mat.set_shader_parameter("erode_rate", liquidity)
	mat.set_shader_parameter("frame_seed", float(Engine.get_process_frames() % 1009))
	mat.set_shader_parameter("fill", fill)
	mat.set_shader_parameter("base_y", _base_y)
	_pending_shift = Vector2.ZERO
	_accum[target].render_target_update_mode = SubViewport.UPDATE_ONCE
	_shape_mat[0].set_shader_parameter("source", _accum[target].get_texture())
	for vp: SubViewport in _shape:
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_parity = 1 - _parity


## Moves the window so it is centred near a point and rebuilds the settled field.
func recentre_to(centre: Vector2) -> void:
	if _surface == null:
		return  # Low snow tier: no window.
	var wanted: Vector2 = _snapped_origin(centre)
	if field.origin.x != INF and wanted.is_equal_approx(field.origin):
		return
	var old: Vector2 = field.origin
	var cover: float = _cover()
	var wind: Vector2 = _wind()
	field.storm_share = _storm_share()
	field.rebuild(wanted, cover, wind)
	_apply_window(old, wanted, cover, wind)


## Speed share while wading through `depth_m` of settled snow.
func get_speed_multiplier(depth_m: float) -> float:
	var t: float = clampf((depth_m - cover_depth_m.x) / maxf(deep_snow_m - cover_depth_m.x, 0.01), 0.0, 1.0)
	return lerpf(1.0, deep_snow_speed, t)


## Acceleration share in `depth_m` of snow: deep snow is slow to get going in.
func get_accel_multiplier(depth_m: float) -> float:
	var t: float = clampf((depth_m - cover_depth_m.x) / maxf(deep_snow_m - cover_depth_m.x, 0.01), 0.0, 1.0)
	return lerpf(1.0, deep_snow_accel, t)


## Hands the displaced snow gathered since the last pass to the accumulator.
func _apply_rims(mat: ShaderMaterial) -> void:
	var names: Array[StringName] = [&"deposit_l", &"deposit_r"]
	for side: int in range(2):
		var a := Vector4.ZERO
		var b := Vector4.ZERO
		if _pending_rim[side] > 0.0 and field.origin.x != INF:
			var uv: Vector2 = (_sole_at[side] - field.origin) / window_m
			a = Vector4(uv.x, uv.y, _sole_fwd[side].x, _sole_fwd[side].y)
			b = Vector4(_sole_len[side] * 0.5 / window_m, sole_width_m * 0.5 / window_m,
				_pending_rim[side], rim_forward_bias)
		mat.set_shader_parameter(String(names[side]) + "_a", a)
		mat.set_shader_parameter(String(names[side]) + "_b", b)
		_pending_rim[side] = 0.0


func get_origin() -> Vector2:
	return field.origin


## Streams window moves while walking: a move is rebuilt a slice per frame and
## switched in whole. The first window and long jumps are rebuilt at once.
## `lead` shifts the target ahead of Henry's travel; nearing the faded rim a
## rebuild gets a bigger budget, since prints there fade into the chunk cover.
func _follow(henry: Vector2, lead: Vector2 = Vector2.ZERO) -> void:
	if _surface == null:
		return
	var budget: int = rebuild_budget_usec
	if field.origin.x != INF:
		var local: Vector2 = henry - field.origin
		var rim: float = minf(minf(local.x, local.y), minf(window_m - local.x, window_m - local.y))
		budget = int(lerpf(float(urgent_budget_usec), float(rebuild_budget_usec), clampf((rim - 6.0) / 3.0, 0.0, 1.0)))
	if field.is_rebuilding():
		if field.step_rebuild(budget):
			_apply_window(_move_from, field.origin, _move_cover, _move_wind)
		return
	var centre: Vector2 = henry + lead
	var wanted: Vector2 = _snapped_origin(centre)
	var storm: float = _storm_share()
	## A storm reshaping the drifts rebuilds the window where it stands.
	var restorm: bool = absf(storm - field.storm_share) >= STORM_REBUILD_STEP
	var cover: float = _cover()
	var reaccumulate: bool = absf(cover - _live_cover) >= COVER_REBUILD_STEP
	if field.origin.x != INF and wanted.is_equal_approx(field.origin) and not restorm and not reaccumulate:
		return
	if field.origin.x == INF or wanted.distance_to(field.origin) > window_m * 0.5:
		recentre_to(centre)
		return
	_move_from = field.origin
	_move_cover = cover
	_move_wind = _wind()
	field.storm_share = storm
	field.begin_rebuild(wanted, _move_cover, _move_wind)
	if field.step_rebuild(budget):
		_apply_window(_move_from, field.origin, _move_cover, _move_wind)


func _snapped_origin(centre: Vector2) -> Vector2:
	var half: float = window_m * 0.5
	return Vector2(snappedf(centre.x - half, recentre_step_m), snappedf(centre.y - half, recentre_step_m))


## Puts a freshly rebuilt field on screen: shader, packed-snow shift, globals.
func _apply_window(old: Vector2, wanted: Vector2, cover: float, wind: Vector2) -> void:
	var half: float = window_m * 0.5
	_live_cover = cover
	_keep_tracks(old, wanted)
	if old.x != INF:
		_pending_shift += (wanted - old) / window_m
	_base_y = _floor_y()
	## Chunk-wide snow reads the same settled depth as the local window.
	RenderingServer.global_shader_parameter_set(&"snow_settled_depth", field.settled_depth(cover))
	RenderingServer.global_shader_parameter_set(&"snow_drift_m", field.drift_amplitude(cover))
	var settled_wind: Vector2 = field.settled_wind if field.use_baked_baseline else wind
	RenderingServer.global_shader_parameter_set(&"snow_wind", settled_wind.normalized() if settled_wind.length_squared() > 0.0001 else Vector2(0, -1))
	_field_tex.set_image(field.image)
	_surface.set_shader_parameter("origin", wanted)
	_mesh.global_position = Vector3(wanted.x + half, 0.0, wanted.y + half)
	_contact_cam.global_transform = Transform3D(
		Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN),
		Vector3(wanted.x + half, _base_y - 5.0, wanted.y + half)
	)
	_contact_quad.set_shader_parameter("base_y", _base_y)
	## Switch the far-cover hole only after the new local texture and mesh are ready.
	live_window = Vector4(wanted.x, wanted.y, window_m, 1.0)
	RenderingServer.global_shader_parameter_set(&"snow_window", live_window)


func _build_surface() -> void:
	field.image = Image.create_empty(field_res, field_res, false, Image.FORMAT_RGBAF)
	_field_tex = ImageTexture.create_from_image(field.image)
	_surface = ShaderMaterial.new()
	_surface.shader = SURFACE_SHADER
	_surface.set_shader_parameter("field", _field_tex)
	_surface.set_shader_parameter("window_m", window_m)
	_surface.set_shader_parameter("packed_texel_m", window_m / float(packed_res))
	_surface.set_shader_parameter("use_baked_baseline", field.use_baked_baseline)
	_surface.set_shader_parameter("sea_level_m", sea_level_m)
	_surface.set_shader_parameter("repose_tan", tan(deg_to_rad(crust_wall_deg)))
	_mesh = MeshInstance3D.new()
	_mesh.name = "SnowShellMesh"
	_mesh.mesh = _graded_grid()
	_mesh.material_override = _surface
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.extra_cull_margin = 400.0
	add_child(_mesh)


## A square grid, dense near the middle where Henry stands and coarser outwards.
## A lifted foot's toe follows the boot every frame and presses only as deep
## as it actually dips into the snow, so a low swing drags a furrow.
func _place_drag(side: int, foot: Dictionary, planted: bool) -> void:
	var drag: MeshInstance3D = _drags[side]
	drag.visible = not foot.is_empty() and not planted
	if not drag.visible:
		_ploughs[side].emitting = false
		_last_toe[side] = Vector3.INF
		return
	## The sensor reports the walk clip's foot, down on the ground under the snow;
	## the toe that drags is the visible one, lifted over the snow by SnowFeet.
	var lift: Vector3 = Vector3.UP * _visible_lift(side)
	var ball: Vector3 = foot["ball"] + lift
	var toe: Vector3 = foot["toe"] + lift
	var along := Vector3(toe.x - ball.x, 0.0, toe.z - ball.z)
	if along.length_squared() < 0.0001:
		along = Vector3.FORWARD
	var bottom: float = minf(ball.y, toe.y) - 0.02
	var centre := Vector3((ball.x + toe.x) * 0.5, bottom + 0.15, (ball.z + toe.z) * 0.5)
	var basis := Basis.looking_at(along.normalized(), Vector3.UP)
	drag.global_transform = Transform3D(
		basis.scaled_local(Vector3(drag_size_m.x, 0.3, drag_size_m.y)), centre
	)
	_plough(side, toe, basis)


## A swinging boot pushing forward below the snow top breaks the snow ahead of
## its toe: clods spray forward, more the deeper and faster it ploughs.
func _plough(side: int, toe: Vector3, basis: Basis) -> void:
	var spray: GPUParticles3D = _ploughs[side]
	var top: float = field.get_snow_top(toe.x, toe.z)
	var moved: float = 0.0
	if _last_toe[side] != Vector3.INF:
		moved = (toe - _last_toe[side]).dot(-basis.z) / maxf(get_physics_process_delta_time(), 0.001)
	_last_toe[side] = toe
	var buried: float = top - toe.y if top > -INF else 0.0
	var strength: float = clampf(buried / 0.15, 0.0, 1.0) * clampf(moved / 1.5, 0.0, 1.0)
	strength *= smoothstep(0.45, 0.95, field.get_softness(toe.x, toe.z)) * 0.6 + 0.4
	spray.emitting = strength > 0.08
	if spray.emitting:
		spray.amount_ratio = strength
		spray.global_transform = Transform3D(basis, Vector3(toe.x, minf(toe.y + 0.04, top), toe.z))


## World metres SnowFeet lifted the `side` boot above the walk clip last frame.
func _visible_lift(side: int) -> float:
	if _sensor == null or _sensor.visual == null or _sensor.visual.skeleton == null:
		return 0.0
	var feet := _sensor.visual.skeleton.get_node_or_null(^"SnowFeet") as SnowFootModifier
	return feet.get_lift(side) if feet != null else 0.0


func _graded_grid() -> ArrayMesh:
	var half: float = window_m * 0.5
	var side: PackedFloat32Array = [0.0]
	var at: float = 0.0
	var step: float = near_spacing_m
	while at < half:
		if at >= near_half_m:
			step = minf(step * 1.04, far_spacing_m)
		at = minf(at + step, half)
		side.append(at)
	var axis: PackedFloat32Array = []
	for i: int in range(side.size() - 1, 0, -1):
		axis.append(-side[i])
	axis.append_array(side)
	var n: int = axis.size()
	var verts := PackedVector3Array()
	verts.resize(n * n)
	for iz: int in range(n):
		for ix: int in range(n):
			verts[iz * n + ix] = Vector3(axis[ix], 0.0, axis[iz])
	var indices := PackedInt32Array()
	indices.resize((n - 1) * (n - 1) * 6)
	var k: int = 0
	for iz: int in range(n - 1):
		for ix: int in range(n - 1):
			var a: int = iz * n + ix
			indices[k] = a
			indices[k + 1] = a + 1
			indices[k + 2] = a + n
			indices[k + 3] = a + 1
			indices[k + 4] = a + n + 1
			indices[k + 5] = a + n
			k += 6
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _build_capture() -> void:
	_contact = _viewport("SnowContact", contact_res)
	_contact.disable_3d = false
	_contact.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_contact_cam = Camera3D.new()
	_contact_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_contact_cam.size = window_m
	_contact_cam.near = 0.05
	_contact_cam.far = 12.0
	_contact_cam.cull_mask = CONTACT_LAYER
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(1000.0, 0.0, 0.0)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_contact_cam.environment = env
	_contact.add_child(_contact_cam)
	_contact_quad = ShaderMaterial.new()
	_contact_quad.shader = CONTACT_SHADER
	var quad := MeshInstance3D.new()
	quad.mesh = QuadMesh.new()
	quad.material_override = _contact_quad
	quad.layers = CONTACT_LAYER
	quad.extra_cull_margin = 16384.0
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.position = Vector3(0, 0, -1)
	_contact_cam.add_child(quad)
	## Ovals with flat bottoms; heel and forefoot overlap into a boot outline.
	var oval := CylinderMesh.new()
	oval.top_radius = 0.5
	oval.bottom_radius = 0.5
	oval.height = 1.0
	oval.radial_segments = 20
	oval.rings = 1
	for i: int in range(2):
		for pad: String in ["Heel", "Ball"]:
			var sole := MeshInstance3D.new()
			sole.name = "Sole%s%d" % [pad, i]
			sole.mesh = oval
			sole.layers = CONTACT_LAYER
			sole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			sole.visible = false
			add_child(sole)
			if pad == "Heel":
				_heels.append(sole)
			else:
				_balls.append(sole)
		_kicks.append(_kick_burst("Kick%d" % i))
		_ploughs.append(_plough_spray("Plough%d" % i))
		var drag := MeshInstance3D.new()
		drag.name = "Drag%d" % i
		drag.mesh = oval
		drag.layers = CONTACT_LAYER
		drag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		drag.visible = false
		add_child(drag)
		_drags.append(drag)
		_clumps.append(_clump_burst("Clumps%d" % i))
	for i: int in range(2):
		var vp: SubViewport = _viewport("SnowPacked%d" % i, packed_res)
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var mat := ShaderMaterial.new()
		mat.shader = ACCUMULATE_SHADER
		mat.set_shader_parameter("contact_tex", _contact.get_texture())
		mat.set_shader_parameter("field", _field_tex)
		mat.set_shader_parameter("max_pack", max_pack)
		var tex_m: float = window_m / float(packed_res)
		mat.set_shader_parameter("talus_powder", tan(deg_to_rad(repose_deg)) * tex_m)
		mat.set_shader_parameter("talus_crust", tan(deg_to_rad(crust_wall_deg)) * tex_m)
		mat.set_shader_parameter("roughness", crumble)
		mat.set_shader_parameter("rim_uv", rim_peak_m / window_m)
		var rect := ColorRect.new()
		rect.size = Vector2(packed_res, packed_res)
		rect.material = mat
		vp.add_child(rect)
		_accum.append(vp)
		_accum_mat.append(mat)
	_restore_tex = ImageTexture.create_from_image(Image.create_empty(packed_res / 4, packed_res / 4, false, Image.FORMAT_RF))
	for mat: ShaderMaterial in _accum_mat:
		mat.set_shader_parameter("restore", _restore_tex)
	_accum_mat[0].set_shader_parameter("previous", _accum[1].get_texture())
	_accum_mat[1].set_shader_parameter("previous", _accum[0].get_texture())
	## What is drawn: walls dilated to the slope the snow holds along x, then y,
	## then softened. Powder slumps to repose, crust stands near vertical.
	var texel_m: float = window_m / float(packed_res)
	for i: int in range(3):
		var vp: SubViewport = _viewport("SnowShape%d" % i, packed_res)
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var mat := ShaderMaterial.new()
		mat.shader = SHAPE_SHADER
		mat.set_shader_parameter("pass", i)
		mat.set_shader_parameter("field", _field_tex)
		mat.set_shader_parameter("drop_powder", tan(deg_to_rad(repose_deg)) * texel_m)
		mat.set_shader_parameter("drop_crust", tan(deg_to_rad(crust_wall_deg)) * texel_m)
		mat.set_shader_parameter("reach", ceili(0.6 / (tan(deg_to_rad(repose_deg)) * texel_m)))
		if i > 0:
			mat.set_shader_parameter("source", _shape[i - 1].get_texture())
		var rect := ColorRect.new()
		rect.size = Vector2(packed_res, packed_res)
		rect.material = mat
		vp.add_child(rect)
		_shape.append(vp)
		_shape_mat.append(mat)
	_surface.set_shader_parameter("packed_field", _shape[2].get_texture())


## A few lumps of snow that break off a print's rim and tumble into it.
func _clump_burst(node_name: String) -> GPUParticles3D:
	var lump := SphereMesh.new()
	lump.radius = 0.035
	lump.height = 0.05
	lump.radial_segments = 6
	lump.rings = 3
	var snow := StandardMaterial3D.new()
	snow.albedo_color = Color(0.86, 0.89, 0.94)
	snow.roughness = 0.9
	lump.material = snow
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	motion.emission_ring_axis = Vector3.UP
	motion.emission_ring_radius = 0.1
	motion.emission_ring_inner_radius = 0.06
	motion.emission_ring_height = 0.02
	## Off the rim, inward and down, like crust giving way.
	motion.radial_velocity_min = -0.35
	motion.radial_velocity_max = -0.15
	motion.gravity = Vector3(0.0, -6.0, 0.0)
	motion.scale_min = 0.5
	motion.scale_max = 1.4
	motion.angle_min = 0.0
	motion.angle_max = 360.0
	var fade := Curve.new()
	fade.add_point(Vector2(0.0, 1.0))
	fade.add_point(Vector2(0.7, 1.0))
	fade.add_point(Vector2(1.0, 0.0))
	var fade_tex := CurveTexture.new()
	fade_tex.curve = fade
	motion.scale_curve = fade_tex
	var burst := GPUParticles3D.new()
	burst.name = node_name
	burst.draw_pass_1 = lump
	burst.process_material = motion
	burst.amount = 6
	burst.lifetime = 0.7
	burst.one_shot = true
	burst.explosiveness = 0.8
	burst.randomness = 0.6
	burst.emitting = false
	burst.local_coords = false
	burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	burst.visibility_aabb = AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
	add_child(burst)
	return burst


## Loose powder a toe-off flicks ahead of the boot; its -Z faces the throw.
func _kick_burst(node_name: String) -> GPUParticles3D:
	var grain := SphereMesh.new()
	grain.radius = 0.012
	grain.height = 0.02
	grain.radial_segments = 4
	grain.rings = 2
	var snow := StandardMaterial3D.new()
	snow.albedo_color = Color(0.88, 0.91, 0.95)
	snow.roughness = 0.9
	grain.material = snow
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	motion.emission_sphere_radius = 0.05
	motion.direction = Vector3(0.0, 0.7, -1.0)
	motion.spread = 28.0
	motion.initial_velocity_min = 0.7
	motion.initial_velocity_max = 1.8
	motion.gravity = Vector3(0.0, -9.8, 0.0)
	motion.damping_min = 1.0
	motion.damping_max = 2.5
	motion.scale_min = 0.4
	motion.scale_max = 1.3
	var fade := Curve.new()
	fade.add_point(Vector2(0.0, 1.0))
	fade.add_point(Vector2(0.6, 0.9))
	fade.add_point(Vector2(1.0, 0.0))
	var fade_tex := CurveTexture.new()
	fade_tex.curve = fade
	motion.scale_curve = fade_tex
	var burst := GPUParticles3D.new()
	burst.name = node_name
	burst.draw_pass_1 = grain
	burst.process_material = motion
	burst.amount = 24
	burst.lifetime = 0.6
	burst.one_shot = true
	burst.explosiveness = 0.85
	burst.randomness = 0.5
	burst.emitting = false
	burst.local_coords = false
	burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	burst.visibility_aabb = AABB(Vector3(-1.0, -0.5, -1.5), Vector3(2.0, 1.5, 2.5))
	add_child(burst)
	return burst


## Continuous spray of clods a ploughing toe throws ahead; its -Z faces travel.
func _plough_spray(node_name: String) -> GPUParticles3D:
	var spray: GPUParticles3D = _kick_burst(node_name)
	spray.one_shot = false
	spray.explosiveness = 0.0
	spray.amount = 36
	spray.lifetime = 0.5
	var motion := spray.process_material as ParticleProcessMaterial
	motion.direction = Vector3(0.0, 0.9, -1.0)
	motion.spread = 35.0
	motion.initial_velocity_min = 0.5
	motion.initial_velocity_max = 1.3
	motion.scale_min = 0.7
	motion.scale_max = 2.2
	return spray


## Files the packing leaving the window and prepares what the new window restores.
func _keep_tracks(old: Vector2, wanted: Vector2) -> void:
	if _accum.is_empty():
		return
	if old.x != INF:
		var packed: Image = _accum[1 - _parity].get_texture().get_image()
		if packed != null and not packed.is_empty():
			tracks.store(packed, old, window_m, Rect2(wanted, Vector2.ONE * window_m))
	else:
		_restore_all = true
	_restore_tex.set_image(tracks.restore(wanted, window_m, packed_res / 4))


func get_save_key() -> StringName:
	return &"snow_tracks"


func get_save_data() -> Dictionary:
	if not _accum.is_empty() and field.origin.x != INF:
		var packed: Image = _accum[1 - _parity].get_texture().get_image()
		if packed != null and not packed.is_empty():
			tracks.store(packed, field.origin, window_m, Rect2())
	return tracks.get_save_data()


func load_save_data(data: Dictionary) -> void:
	tracks.load_save_data(data)
	if _restore_tex != null and field.origin.x != INF:
		_restore_tex.set_image(tracks.restore(field.origin, window_m, packed_res / 4))
		_restore_all = true


func _viewport(node_name: String, side: int) -> SubViewport:
	var vp := SubViewport.new()
	vp.name = node_name
	vp.size = Vector2i(side, side)
	vp.use_hdr_2d = true
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.msaa_3d = Viewport.MSAA_DISABLED
	add_child(vp)
	return vp


## Settled cover, never read back from RenderingServer (that stalls).
## Share of fresh storm snow, from the presentation system; 0.4 without one.
func _storm_share() -> float:
	if _presentation != null and _presentation.has_method(&"get_storm_share"):
		return clampf(float(_presentation.call(&"get_storm_share")), 0.0, 1.0)
	return field.storm_share


func _cover() -> float:
	if _presentation != null:
		return clampf(float(_presentation.call(&"get_settled_snow")), 0.0, 1.0)
	if _weather != null:
		return clampf(_weather.get_snow_cover(), 0.0, 1.0)
	return 0.5


func _wind() -> Vector2:
	if _weather == null:
		return Vector2(0, -1)
	var wind: Vector3 = _weather.get_wind_direction()
	return Vector2(wind.x, wind.z)


func _floor_y() -> float:
	if _player == null or not is_inside_tree():
		return 0.0
	var query := PhysicsRayQueryParameters3D.create(
		_player.global_position + Vector3.UP * 0.5, _player.global_position + Vector3.DOWN * 5.0
	)
	query.exclude = _exclude()
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	return (hit["position"] as Vector3).y if not hit.is_empty() else _player.global_position.y


func _exclude() -> Array[RID]:
	var out: Array[RID] = []
	if _player is CollisionObject3D:
		out.append((_player as CollisionObject3D).get_rid())
	return out


## Ground height and what covers it, for SnowField: 0 open, 1 a wall that
## shelters its lee, 2 under a roof (no snow, no lee pile).
func _sample_ground(at: Vector2) -> Vector2:
	var ground_y: float = _base_y
	if _terrain != null:
		ground_y = _terrain.get_height(at.x, at.y)
	if _terrain != null and _city != null and bool(_city.call(&"has_snow_obstacle_at", at)):
		return Vector2(ground_y, 1.0)
	if not is_inside_tree():
		return Vector2(ground_y, 0.0)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(at.x, ground_y + 6.0, at.y), Vector3(at.x, ground_y - 4.0, at.y)
	)
	query.exclude = _exclude()
	var hit: Dictionary = _intersect_without_city_collision(space, query)
	if hit.is_empty():
		return Vector2(ground_y, 0.0 if _terrain != null else 1.0)
	var hit_at: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	var collider: Object = hit.get("collider")
	if collider is Node and (collider as Node).is_in_group(SWEPT_GROUP):
		return Vector2(hit_at.y, 2.0)
	## Steep faces, and anything standing over a metre high, are walls: snow
	## drapes low decks and crates, never a house.
	if hit_at.y > ground_y + 0.3 and (
		normal.y < 0.7 or hit_at.y > ground_y + 1.0 or not _is_broad(space, hit_at)
	):
		return Vector2(ground_y, 1.0)
	## A floor, deck or crate top: snow lies on it unless a roof covers it.
	var up := PhysicsRayQueryParameters3D.create(hit_at + Vector3.UP * 0.2, hit_at + Vector3.UP * 12.0)
	up.exclude = _exclude()
	if not _intersect_without_city_collision(space, up).is_empty():
		return Vector2(hit_at.y, 2.0)
	if _terrain != null and hit_at.y <= ground_y + 0.3:
		return Vector2(ground_y, 0.0)
	return Vector2(hit_at.y, 0.0)


## Exact city footprints above own the static obstacle mask. A streamed city
## collision must not change a cached snow cell when its detail chunk arrives.
func _intersect_without_city_collision(space: PhysicsDirectSpaceState3D, query: PhysicsRayQueryParameters3D) -> Dictionary:
	for attempt: int in range(4):
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty() or _city == null:
			return hit
		var collider: Object = hit.get("collider")
		if not (collider is CollisionObject3D) or (collider as Node).name != &"CityCollision":
			return hit
		var excluded: Array[RID] = query.exclude
		excluded.append((collider as CollisionObject3D).get_rid())
		query.exclude = excluded
	return {}


## True when a raised surface is wide enough to hold snow, not a rail or post top.
func _is_broad(space: PhysicsDirectSpaceState3D, at: Vector3) -> bool:
	for offset: Vector3 in [Vector3(0.15, 0, 0), Vector3(-0.15, 0, 0), Vector3(0, 0, 0.15), Vector3(0, 0, -0.15)]:
		var query := PhysicsRayQueryParameters3D.create(
			at + offset + Vector3.UP * 0.5, at + offset + Vector3.DOWN * 0.2
		)
		query.exclude = _exclude()
		var hit: Dictionary = _intersect_without_city_collision(space, query)
		if hit.is_empty() or absf((hit["position"] as Vector3).y - at.y) > 0.05:
			return false
	return true


func _on_node_added(node: Node) -> void:
	if is_instance_of(node, PICKUP_SCRIPT):
		## Its visuals are built in _ready, after node_added fires.
		node.ready.connect(tag_contact.bind(node), CONNECT_ONE_SHOT)
