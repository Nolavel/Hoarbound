class_name DeterministicSnowShell
extends "res://scripts/systems/world/snow/snow_shell.gd"

## Production contact layer for SnowShell.
##
## The base shell still owns the persistent packed field, snow material, item/body
## contact capture and track storage. This subclass fixes the discrete-foot path:
## accepted FootContactSensor plants become persistent GPU stamps, so a step cannot
## disappear merely because no rendered frame happened during the plant.

const CONTACT_WINDOW_M: float = 6.4
const CONTACT_RES: int = 256
const MAX_STAMPS_PER_PASS: int = 16
const MIN_STAMP_DEPTH_M: float = 0.012

var _plant_point: Array[Vector3] = [Vector3.INF, Vector3.INF]
var _plant_normal: Array[Vector3] = [Vector3.UP, Vector3.UP]
var _plant_forward: Array[Vector3] = [Vector3.FORWARD, Vector3.FORWARD]
var _foot_stamps: Array[Dictionary] = []
var _contact_origin: Vector2 = Vector2(INF, INF)


func _ready() -> void:
	## Build the actual contact target at the production candidate resolution.
	## The persistent packed field stays at SnowShell.packed_res (896 by default).
	contact_res = CONTACT_RES
	super()
	if _surface == null:
		return
	contact_res = CONTACT_RES
	_contact.size = Vector2i(CONTACT_RES, CONTACT_RES)
	_contact_cam.size = CONTACT_WINDOW_M
	for mat: ShaderMaterial in _accum_mat:
		mat.set_shader_parameter("field_window_m", window_m)
		mat.set_shader_parameter("contact_window_m", CONTACT_WINDOW_M)
		mat.set_shader_parameter("foot_stamp_count", 0)


func on_world_ready(context: WorldContext) -> void:
	super(context)
	if _surface == null:
		return
	if _sensor != null and not _sensor.foot_planted.is_connected(_on_foot_planted):
		_sensor.foot_planted.connect(_on_foot_planted)
	if _player != null:
		var at: Vector3 = _player.global_position
		_update_local_contact(Vector2(at.x, at.z))


func _physics_process(delta: float) -> void:
	## Base movement/rebuild logic still runs, but its _place_soles() call dispatches
	## to the tangent-plane implementation below.
	super(delta)
	if _player != null and _contact_cam != null:
		var at: Vector3 = _player.global_position
		_update_local_contact(Vector2(at.x, at.z))


func _process(delta: float) -> void:
	if _accum_mat.is_empty():
		return
	## Upload before SnowShell schedules this parity's accumulator pass. Uniforms
	## remain on the material until that SubViewport renders later in the frame.
	var consumed: int = _upload_pending_stamps(_accum_mat[_parity])
	super(delta)
	for _i: int in range(consumed):
		_foot_stamps.pop_front()


## FootContactSensor is the one authority for a discrete plant. The event is
## retained until an accumulator pass has consumed it; render cadence cannot lose it.
func _on_foot_planted(
	side: int, position: Vector3, normal: Vector3, forward: Vector3, speed_mps: float
) -> void:
	if side < 0 or side >= 2:
		return
	var up: Vector3 = normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	var toe: Vector3 = forward - up * forward.dot(up)
	if toe.length_squared() < 0.0001:
		toe = Vector3.FORWARD - up * Vector3.FORWARD.dot(up)
	toe = toe.normalized()
	_plant_point[side] = position
	_plant_normal[side] = up
	_plant_forward[side] = toe
	_foot_stamps.append({
		"side": side,
		"position": position,
		"normal": up,
		"forward": toe,
		"speed": speed_mps,
	})


func get_pending_foot_stamp_count() -> int:
	return _foot_stamps.size()


## A 6.4 m contact camera at 256² is 2.5 cm/texel: the old 25.6 m/1024²
## precision at one sixteenth the pixels. It follows Henry independently of the
## 25.6 m packed-field origin; the shader remaps world coordinates explicitly.
func _update_local_contact(centre: Vector2) -> void:
	if _contact_cam == null:
		return
	var half: float = CONTACT_WINDOW_M * 0.5
	var texel_m: float = CONTACT_WINDOW_M / float(CONTACT_RES)
	var wanted := Vector2(
		snappedf(centre.x - half, texel_m),
		snappedf(centre.y - half, texel_m)
	)
	_contact_origin = wanted
	_contact_cam.size = CONTACT_WINDOW_M
	_contact_cam.global_transform = Transform3D(
		Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN),
		Vector3(wanted.x + half, _base_y - 5.0, wanted.y + half)
	)
	for mat: ShaderMaterial in _accum_mat:
		mat.set_shader_parameter("contact_origin", wanted)
		mat.set_shader_parameter("contact_window_m", CONTACT_WINDOW_M)
		mat.set_shader_parameter("field_window_m", window_m)
		if field.origin.x != INF:
			mat.set_shader_parameter("field_origin", field.origin)


## Converts one world-space tangent-plane sole into two vec4s containing the
## inverse 2D footprint basis. The shader then tests an ellipse without assuming
## global UP, so road crown/camber does not push the print sideways.
static func stamp_uniforms(
	position: Vector3,
	normal: Vector3,
	forward: Vector3,
	half_length_m: float,
	half_width_m: float,
	field_origin: Vector2,
	field_window_m: float,
	depth_m: float
) -> Array[Vector4]:
	var up: Vector3 = normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	var toe: Vector3 = forward - up * forward.dot(up)
	if toe.length_squared() < 0.0001:
		toe = Vector3.FORWARD - up * Vector3.FORWARD.dot(up)
	toe = toe.normalized()
	var right: Vector3 = toe.cross(up)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	else:
		right = right.normalized()

	var centre_uv := (Vector2(position.x, position.z) - field_origin) / field_window_m
	var f := Vector2(toe.x, toe.z) * (half_length_m / field_window_m)
	var r := Vector2(right.x, right.z) * (half_width_m / field_window_m)
	var det: float = f.x * r.y - r.x * f.y
	if absf(det) < 1e-7:
		var f2 := Vector2(toe.x, toe.z)
		if f2.length_squared() < 1e-7:
			f2 = Vector2(0.0, -1.0)
		f2 = f2.normalized()
		var r2 := Vector2(-f2.y, f2.x)
		f = f2 * (half_length_m / field_window_m)
		r = r2 * (half_width_m / field_window_m)
		det = f.x * r.y - r.x * f.y
	var inv_det: float = 1.0 / det
	return [
		Vector4(centre_uv.x, centre_uv.y, r.y * inv_det, -r.x * inv_det),
		Vector4(-f.y * inv_det, f.x * inv_det, depth_m, 1.0),
	]


func _upload_pending_stamps(mat: ShaderMaterial) -> int:
	var consumed: int = mini(_foot_stamps.size(), MAX_STAMPS_PER_PASS)
	var a: Array[Vector4] = []
	var b: Array[Vector4] = []
	a.resize(MAX_STAMPS_PER_PASS)
	b.resize(MAX_STAMPS_PER_PASS)
	for i: int in range(MAX_STAMPS_PER_PASS):
		a[i] = Vector4.ZERO
		b[i] = Vector4.ZERO

	var active_count: int = 0
	if field.origin.x != INF:
		for i: int in range(consumed):
			var stamp: Dictionary = _foot_stamps[i]
			var position: Vector3 = stamp["position"]
			var depth: float = field.get_depth(position.x, position.z)
			var softness: float = field.get_softness(position.x, position.z)
			var give: float = depth * max_pack * softness
			if give <= 0.0001:
				continue
			var speed_mps: float = float(stamp["speed"])
			var impact: float = clampf(speed_mps / maxf(impact_speed_mps, 0.1), 0.0, 1.0)
			var press: float = maxf(MIN_STAMP_DEPTH_M, give * lerpf(0.35, impact_share, impact))
			press = minf(press, give)
			var side: int = int(stamp["side"])
			var half_length: float = maxf(_sole_len[side] * 0.5, 0.12)
			var encoded: Array[Vector4] = stamp_uniforms(
				position,
				stamp["normal"],
				stamp["forward"],
				half_length,
				sole_width_m * 0.5,
				field.origin,
				window_m,
				press
			)
			a[active_count] = encoded[0]
			b[active_count] = encoded[1]
			active_count += 1

	mat.set_shader_parameter("foot_stamp_count", active_count)
	mat.set_shader_parameter("foot_stamp_a", a)
	mat.set_shader_parameter("foot_stamp_b", b)
	return consumed


## Base SnowShell already owns sinking, rim displacement, particles and movement
## penalties. Only the plant anchor/basis changes: a moving step is pinned to the
## sensor's world-space event and tangent plane instead of being rediscovered from
## the skeleton after the fact.
func _place_soles(delta: float) -> void:
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
			_plant_point[side] = Vector3.INF
			continue

		if not _heels[side].visible:
			var heel: Vector3 = foot["heel"]
			var toe_bone: Vector3 = foot["toe"]
			var along := Vector3(toe_bone.x - heel.x, 0.0, toe_bone.z - heel.z)
			var use_event: bool = not standing and _plant_point[side] != Vector3.INF
			if use_event:
				var up: Vector3 = _plant_normal[side]
				var toe: Vector3 = _plant_forward[side]
				var right: Vector3 = toe.cross(up).normalized()
				_sole_basis[side] = Basis(right, up, -toe)
				_sole_fwd[side] = Vector2(toe.x, toe.z).normalized()
				_sole_at[side] = Vector2(_plant_point[side].x, _plant_point[side].z)
			else:
				if along.length_squared() < 0.0001:
					along = Vector3.FORWARD * 0.2
				_sole_basis[side] = Basis.looking_at(along.normalized(), Vector3.UP)
				_sole_fwd[side] = Vector2(along.x, along.z).normalized()
				_sole_at[side] = Vector2((heel.x + toe_bone.x) * 0.5, (heel.z + toe_bone.z) * 0.5)
			_sole_len[side] = heel.distance_to(toe_bone) + sole_margin_m * 2.0
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
		_raise[side] = clampf(depth - _sink[side], 0.0, depth) if top > -INF else 0.0
		if top > -INF:
			_queue_rim(side, _sink[side] - was, softness)
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
