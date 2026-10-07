extends Node3D
class_name MovementController

# === ССЫЛКИ НА КОМПОНЕНТЫ ===
@export var stamina_manager: StaminaManager

# === ПАРАМЕТРЫ ДВИЖЕНИЯ ===
@export_group("Параметры движения")
## Real walking pace; a sortie is timed in human minutes.
@export var walk_speed: float = 1.5
## Deliberate low gait for thin ice and cramped shelter interiors.
@export var crouch_speed: float = 0.9
## A run in winter clothing, not a sprinter's burst.
@export var sprint_speed: float = 4.5
@export var gravity: float = 9.8
@export var max_floor_angle: float = 45.0  # НОВОЕ: максимальный угол подъёма (в градусах)
@export var floor_snap_length: float = 0.1  # НОВОЕ: "прилипание" к полу

# === ПАРАМЕТРЫ СПРИНТА ===
@export_group("Параметры спринта")
@export var sprint_ramp_time: float = 1.0
@export var sprint_inertia_time: float = 0.6
@export var sprint_release_boost: float = 0.5

# === ПАРАМЕТРЫ ПРЫЖКА НА УДЕРЖАНИЕ ===
@export_group("Прыжок на удержание")
@export var jump_velocity: float = 5.0

# === ЖИВОЙ РАЗГОН / ТОРМОЖЕНИЕ ===
@export_group("Живой разгон / торможение")
@export var accel_rate: float = 8.0
@export var decel_rate: float = 12.0
@export var slope_speed_multiplier: float = 1.3  # ИЗМЕНЕНО: множитель скорости на спуске
@export var slope_slowdown_multiplier: float = 0.7  # НОВОЕ: замедление при подъёме

@export_group("Carry load")
## A partly loaded pack still feels normal. Above this fraction weight begins
## changing gait; at the hard limit Henry is slower but never immobilised.
@export_range(0.0, 0.95, 0.05) var load_penalty_starts: float = 0.40
@export_range(0.5, 1.0, 0.01) var full_load_speed_multiplier: float = 0.78
@export_range(0.5, 1.0, 0.01) var full_load_accel_multiplier: float = 0.82

# === DEBUG ===
@export_group("Debug")
@export var debug_show_speed: bool = false
@export var debug_label_path: NodePath

# === СЛУЖЕБНЫЕ ПЕРЕМЕННЫЕ ===
## Set by SnowShell each physics frame from the snow depth; 1.0 on bare ground.
var snow_speed_multiplier: float = 1.0
## Set by SnowShell: deep snow is slow to get going in; 1.0 on bare ground.
var snow_accel_multiplier: float = 1.0
var _sprint_blend: float = 1.0
var _sprint_inertia_timer: float = 0.0
var _jump_hold_armed: bool = false
var _jump_release_fired_this_frame: bool = false
var _sprint_allowed: bool = true
var _debug_label: Label = null
var _was_on_floor_last_frame: bool = false
var _crouching: bool = false
var _carry_inventory: InventoryComponent
var _target_velocity: Vector3 = Vector3.ZERO
var _velocity_rate: float = 0.0
var _status_provider: Node

func _ready() -> void:
	if walk_speed <= 0.0:
		push_warning("Walk speed must be positive, setting to 4.0")
		walk_speed = 1.5
	if sprint_speed <= walk_speed:
		push_warning("Sprint speed must be greater than walk speed")
		sprint_speed = walk_speed * 2.0
		
	if stamina_manager:
		stamina_manager.sprint_allowed_changed.connect(_on_sprint_allowed_changed)

	if debug_show_speed and debug_label_path != NodePath():
		_debug_label = get_node_or_null(debug_label_path)
		if _debug_label == null:
			push_warning("Debug label path is invalid — speed display will not work.")

func process_movement(
	player: CharacterBody3D,
	delta: float,
	input_dir: Vector3,
	jump_just_pressed: bool,
	jump_is_pressed: bool,
	jump_just_released: bool,
	sprint_is_pressed: bool,
	sprint_just_released: bool,
	movement_locked: bool = false
) -> void:
	_jump_release_fired_this_frame = false
	
	# Сохраняем состояние пола
	var was_on_floor = _was_on_floor_last_frame
	var on_floor_now = player.is_on_floor()
	_was_on_floor_last_frame = on_floor_now

	# === 1) Настройка физики CharacterBody3D ===
	player.floor_max_angle = deg_to_rad(max_floor_angle)
	player.floor_snap_length = floor_snap_length if on_floor_now else 0.0
	player.floor_stop_on_slope = true  # Предотвращает скольжение вниз

	# === 2) Гравитация ===
	if not on_floor_now:
		player.velocity.y -= gravity * delta
	else:
		# На полу - обнуляем вертикальную скорость (кроме прыжка)
		if player.velocity.y < 0:
			player.velocity.y = 0.0

	## Stationary actions stop inertia and pending jump release, but keep gravity.
	if movement_locked:
		player.velocity.x = 0.0
		player.velocity.z = 0.0
		_target_velocity = Vector3.ZERO
		_velocity_rate = INF
		_jump_hold_armed = false
		_sprint_blend = 1.0
		_sprint_inertia_timer = 0.0
		if stamina_manager != null and stamina_manager.is_consuming_stamina:
			stamina_manager.stop_consuming_stamina()
		return

	# === 3) Прыжок на удержание ===
	if on_floor_now:
		if jump_is_pressed and not _crouching:
			_jump_hold_armed = true
		if _jump_hold_armed and jump_just_released:
			if stamina_manager == null or stamina_manager.try_jump():
				player.velocity.y = jump_velocity
				_jump_release_fired_this_frame = true
				player.floor_snap_length = 0.0  # Отключаем snap при прыжке
			_jump_hold_armed = false
	if jump_just_released:
		_jump_hold_armed = false

	# === 4) Планарное направление движения ===
	var has_input: bool = input_dir.length() > 0.0
	var planar_dir: Vector3 = player.global_transform.basis * input_dir
	planar_dir.y = 0.0
	if planar_dir.length() > 1.0:
		planar_dir = planar_dir.normalized()

	# === 5) Влияние уклона (ИСПРАВЛЕНО) ===
	var slope_modifier: float = 1.0
	if on_floor_now and has_input:
		var floor_normal = player.get_floor_normal()
		var floor_angle_rad = acos(clamp(floor_normal.y, 0.0, 1.0))
		var floor_angle_deg = rad_to_deg(floor_angle_rad)
		
		# Проверяем, движемся ли мы вверх или вниз по склону
		if floor_angle_deg > 1.0:  # Есть наклон
			var movement_dot = planar_dir.normalized().dot(-floor_normal.slide(Vector3.UP).normalized())
			
			if movement_dot > 0.1:  # Движемся ВНИЗ по склону
				# Ускоряемся на спуске (чем круче, тем быстрее)
				var slope_factor = clamp(floor_angle_deg / max_floor_angle, 0.0, 1.0)
				slope_modifier = lerp(1.0, slope_speed_multiplier, slope_factor)
			elif movement_dot < -0.1:  # Движемся ВВЕРХ по склону
				# Замедляемся при подъёме (чем круче, тем медленнее)
				var slope_factor = clamp(floor_angle_deg / max_floor_angle, 0.0, 1.0)
				slope_modifier = lerp(1.0, slope_slowdown_multiplier, slope_factor)

	# === 6) Плавный спринт с системой стамины ===
	var sprint_multiplier: float = sprint_speed / max(walk_speed, 0.001)
	var should_sprint: bool = sprint_is_pressed and has_input and _sprint_allowed and not _crouching

	if should_sprint and stamina_manager:
		if not stamina_manager.is_consuming_stamina:
			stamina_manager.start_consuming_stamina()
	elif stamina_manager and stamina_manager.is_consuming_stamina:
		stamina_manager.stop_consuming_stamina()

	if should_sprint:
		var up_rate: float = delta / sprint_ramp_time
		_sprint_blend = lerp(_sprint_blend, sprint_multiplier, up_rate)
		_sprint_inertia_timer = 0.0
	elif _sprint_blend > 1.0:
		if sprint_just_released and has_input and on_floor_now:
			_sprint_inertia_timer = sprint_inertia_time
			if planar_dir.length() > 0.0 and sprint_release_boost > 0.0:
				var dir: Vector3 = planar_dir.normalized()
				player.velocity.x += dir.x * sprint_release_boost
				player.velocity.z += dir.z * sprint_release_boost

		if not _sprint_allowed and _sprint_inertia_timer <= 0.0:
			_sprint_inertia_timer = sprint_inertia_time * 1.5

		var down_rate: float = delta / (_sprint_inertia_timer if _sprint_inertia_timer > 0.0 else sprint_inertia_time)
		_sprint_blend = lerp(_sprint_blend, 1.0, down_rate)
		_sprint_inertia_timer = max(0.0, _sprint_inertia_timer - delta)
	else:
		var down_rate: float = delta / sprint_inertia_time
		_sprint_blend = lerp(_sprint_blend, 1.0, down_rate)

	# === 7) Целевая скорость С учётом уклона ===
	var base_speed: float = crouch_speed if _crouching else walk_speed
	var target_speed: float = base_speed * (_sprint_blend if not _crouching else 1.0) * slope_modifier * get_load_speed_multiplier() * get_status_speed_multiplier() * snow_speed_multiplier
	var target_vel: Vector3 = planar_dir * target_speed

	# === 8) Разгон / торможение ===
	var current_planar_speed: float = Vector3(player.velocity.x, 0.0, player.velocity.z).length()
	var rate: float = accel_rate * get_load_accel_multiplier() * snow_accel_multiplier if target_vel.length() > current_planar_speed else decel_rate

	# ВАЖНО: используем move_toward для более точного контроля
	var current_planar_vel = Vector3(player.velocity.x, 0.0, player.velocity.z)
	var new_planar_vel = current_planar_vel.move_toward(target_vel, rate * delta * max(walk_speed, 1.0))
	_target_velocity = target_vel
	_velocity_rate = rate * max(walk_speed, 1.0)
	
	player.velocity.x = new_planar_vel.x
	player.velocity.z = new_planar_vel.z

	# === 9) DEBUG: вывод скорости ===
	if debug_show_speed and _debug_label != null:
		var speed: float = Vector3(player.velocity.x, 0.0, player.velocity.z).length()
		var floor_angle: float = 0.0
		if on_floor_now:
			floor_angle = rad_to_deg(acos(clamp(player.get_floor_normal().y, 0.0, 1.0)))
		_debug_label.text = "Speed: %.2f | Angle: %.1f° | Slope: %.2fx" % [speed, floor_angle, slope_modifier]

## Planar velocity this tick steers toward, for animation that predicts the body.
func get_target_velocity() -> Vector3:
	return _target_velocity


## Planar acceleration of that approach, m/s^2 (INF when movement is locked).
func get_velocity_rate() -> float:
	return _velocity_rate


## Planar deceleration when the target speed drops, m/s^2.
func get_braking_rate() -> float:
	return decel_rate * maxf(walk_speed, 1.0)


## Smooth physical cost of carried weight. The hard pickup limit remains the
## final boundary; this makes the approach to it readable before refusal.
func get_load_speed_multiplier() -> float:
	var load: float = _carry_load_fraction()
	if load <= load_penalty_starts:
		return 1.0
	var t: float = smoothstep(load_penalty_starts, 1.0, load)
	return lerpf(1.0, full_load_speed_multiplier, t)


func get_status_speed_multiplier() -> float:
	if _status_provider == null and get_parent() != null:
		var candidate: Node = get_parent().get_node_or_null(^"AfflictionComponent")
		if candidate != null and candidate.has_method(&"get_multiplier"):
			_status_provider = candidate
	if _status_provider == null:
		return 1.0
	return maxf(float(_status_provider.call(&"get_multiplier", &"movement_speed_multiplier")), 0.0)


func get_load_accel_multiplier() -> float:
	var load: float = _carry_load_fraction()
	if load <= load_penalty_starts:
		return 1.0
	var t: float = smoothstep(load_penalty_starts, 1.0, load)
	return lerpf(1.0, full_load_accel_multiplier, t)


func _carry_load_fraction() -> float:
	if _carry_inventory == null and get_parent() != null:
		_carry_inventory = InventoryComponent.find_in(get_parent())
	return _carry_inventory.get_load_fraction() if _carry_inventory != null else 0.0


func set_crouching(active: bool) -> void:
	_crouching = active
	if _crouching:
		_sprint_blend = 1.0
		_sprint_inertia_timer = 0.0
		_jump_hold_armed = false


func is_crouching() -> bool:
	return _crouching


func get_crouch_speed_ratio(player_velocity: Vector3) -> float:
	var speed: float = Vector2(player_velocity.x, player_velocity.z).length()
	return clampf(speed / maxf(crouch_speed, 0.001), 0.0, 1.0)


func get_sprint_blend() -> float:
	var sprint_multiplier: float = sprint_speed / max(walk_speed, 0.001)
	var blend_progress: float = (_sprint_blend - 1.0) / (sprint_multiplier - 1.0)
	return clamp(blend_progress, 0.0, 1.0)

func is_currently_sprinting(player_velocity: Vector3) -> bool:
	return Input.is_action_pressed("sprint") and Vector2(player_velocity.x, player_velocity.z).length() > walk_speed

func get_jump_release_fired() -> bool:
	return _jump_release_fired_this_frame

func set_sprint_allowed(allowed: bool) -> void:
	_sprint_allowed = allowed

func get_stamina_ratio() -> float:
	if stamina_manager:
		return stamina_manager.get_stamina_ratio()
	return 1.0

func is_sprint_available() -> bool:
	if stamina_manager:
		return stamina_manager.is_sprint_allowed()
	return true

func is_stamina_recovering() -> bool:
	if stamina_manager:
		return stamina_manager.is_recovering()
	return false
	
func _on_sprint_allowed_changed(is_allowed: bool) -> void:
	_sprint_allowed = is_allowed
