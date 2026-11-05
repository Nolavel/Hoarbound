extends Node3D
class_name PlayerHealthSystem

# === ПАРАМЕТРЫ ЗДОРОВЬЯ ===
@export_group("Здоровье")
@export var max_health: float = 100.0
@export var current_health: float = 100.0
@export var regeneration_rate: float = 0.0  # очков в секунду
@export var regeneration_delay: float = 5.0  # задержка после урона

@export_group("Защита")
@export var armor: float = 0.0  # процент снижения урона
@export var damage_immunity_time: float = 0.5  # время неуязвимости после урона

@export_group("Эффекты урона")
@export var screen_shake_enabled: bool = true
@export var damage_feedback_enabled: bool = true
@export var fall_damage_enabled: bool = true
@export var fall_damage_threshold: float = 10.0
@export var fall_damage_multiplier: float = 0.5

# === СОСТОЯНИЕ ===
var _player: CharacterBody3D
var _is_dead: bool = false
var _is_immune: bool = false
var _immunity_timer: float = 0.0
var _regeneration_timer: float = 0.0
var _last_damage_time: float = 0.0
var _fall_velocity_history: Array[float] = []

# === СИГНАЛЫ ===
signal health_changed(current: float, max: float)
signal damage_taken(amount: float, source: String)
## A blow (take_damage), not a slow loss such as frostbite (drain): what startles Henry out of his pack.
signal hurt(amount: float, source: String)
signal healed(amount: float)
signal died
signal revived
signal armor_changed(new_armor: float)

func setup(player: CharacterBody3D) -> void:
	_player = player
	current_health = max_health
	_validate_parameters()
	health_changed.emit(current_health, max_health)

func _validate_parameters() -> void:
	max_health = max(max_health, 1.0)
	current_health = clamp(current_health, 0.0, max_health)
	armor = clamp(armor, 0.0, 0.95)  # максимум 95% защиты
	regeneration_rate = max(regeneration_rate, 0.0)
	regeneration_delay = max(regeneration_delay, 0.0)

func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	
	_update_immunity(delta)
	_update_regeneration(delta)
	_check_fall_damage()

func _update_immunity(delta: float) -> void:
	if _is_immune:
		_immunity_timer -= delta
		if _immunity_timer <= 0.0:
			_is_immune = false

func _update_regeneration(delta: float) -> void:
	if regeneration_rate > 0.0 and current_health < max_health:
		_regeneration_timer += delta
		if _regeneration_timer >= regeneration_delay:
			var heal_amount = regeneration_rate * delta
			heal(heal_amount, "regeneration")

func _check_fall_damage() -> void:
	if not fall_damage_enabled or not _player:
		return
	
	# Отслеживаем скорость падения
	if not _player.is_on_floor():
		_fall_velocity_history.push_back(abs(_player.velocity.y))
		if _fall_velocity_history.size() > 5:  # Храним только последние 5 значений
			_fall_velocity_history.pop_front()
	else:
		# Проверяем урон от падения при приземлении
		if _fall_velocity_history.size() > 0:
			var max_fall_velocity = _fall_velocity_history.max()
			if max_fall_velocity > fall_damage_threshold:
				var damage_amount = (max_fall_velocity - fall_damage_threshold) * fall_damage_multiplier
				take_damage(damage_amount, "fall")
			_fall_velocity_history.clear()

# === ОСНОВНЫЕ МЕТОДЫ ===
func take_damage(amount: float, source: String = "unknown") -> void:
	if _is_dead or _is_immune or amount <= 0.0:
		return
	
	# Применяем защиту
	var actual_damage = amount * (1.0 - armor)
	current_health = max(0.0, current_health - actual_damage)
	
	# Устанавливаем неуязвимость
	if damage_immunity_time > 0.0:
		_is_immune = true
		_immunity_timer = damage_immunity_time
	
	# Сбрасываем регенерацию
	_regeneration_timer = 0.0
	_last_damage_time = Time.get_time_dict_from_system()["second"]
	
	# Эмитим сигналы
	damage_taken.emit(actual_damage, source)
	hurt.emit(actual_damage, source)
	health_changed.emit(current_health, max_health)
	
	# Эффекты урона
	if damage_feedback_enabled:
		_trigger_damage_effects(actual_damage, source)
	
	# Проверяем смерть
	if current_health <= 0.0:
		die()

## A slow loss such as frostbite: no armour, immunity window or damage feedback, but it
## stops regeneration and can still kill.
func drain(amount: float, source: String = "unknown") -> void:
	if _is_dead or amount <= 0.0:
		return
	current_health = maxf(0.0, current_health - amount)
	_regeneration_timer = 0.0
	damage_taken.emit(amount, source)
	health_changed.emit(current_health, max_health)
	if current_health <= 0.0:
		die()


func heal(amount: float, _source: String = "unknown") -> void:
	if _is_dead or amount <= 0.0:
		return
	
	var old_health = current_health
	current_health = min(max_health, current_health + amount)
	var actual_heal = current_health - old_health
	
	if actual_heal > 0.0:
		healed.emit(actual_heal)
		health_changed.emit(current_health, max_health)

func die() -> void:
	if _is_dead:
		return
	
	_is_dead = true
	current_health = 0.0
	died.emit()
	
	# Дополнительная логика смерти
	_on_death()

func revive(health_amount: float = 0.0) -> void:
	if not _is_dead:
		return
	
	_is_dead = false
	_is_immune = false
	_immunity_timer = 0.0
	_regeneration_timer = 0.0
	
	if health_amount > 0.0:
		current_health = min(max_health, health_amount)
	else:
		current_health = max_health
	
	revived.emit()
	health_changed.emit(current_health, max_health)

# === ЭФФЕКТЫ И РЕАКЦИИ ===
func _trigger_damage_effects(damage: float, source: String) -> void:
	# Здесь можно добавить визуальные/звуковые эффекты
	# Например, эффект красного экрана, звук урона и т.д.
	
	if screen_shake_enabled:
		_trigger_screen_shake(damage)
	
	# Можно добавить частицы крови, звуки и т.д.
	_play_damage_sound(source)

func _trigger_screen_shake(_damage: float) -> void:
	## Not wired to TpsCamera yet; intensity would be clamp(damage / max_health, 0.1, 1).
	pass

func _play_damage_sound(source: String) -> void:
	# Воспроизведение звука в зависимости от источника урона
	match source:
		"fall":
			pass # AudioManager.play_sound("fall_damage")
		"fire":
			pass # AudioManager.play_sound("fire_damage")
		_:
			pass # AudioManager.play_sound("generic_damage")

func _on_death() -> void:
	# Дополнительная логика при смерти
	# Например, дроп предметов, анимации и т.д.
	pass

# === МОДИФИКАТОРЫ ===
func add_armor(amount: float) -> void:
	armor = clamp(armor + amount, 0.0, 0.95)
	armor_changed.emit(armor)

func remove_armor(amount: float) -> void:
	armor = clamp(armor - amount, 0.0, 0.95)
	armor_changed.emit(armor)

func set_max_health(new_max: float) -> void:
	var old_max = max_health
	max_health = max(new_max, 1.0)
	
	# Пропорционально изменяем текущее здоровье
	if old_max > 0.0:
		var health_ratio = current_health / old_max
		current_health = max_health * health_ratio
	else:
		current_health = max_health
	
	health_changed.emit(current_health, max_health)

func apply_temporary_immunity(duration: float) -> void:
	_is_immune = true
	_immunity_timer = max(_immunity_timer, duration)

# === ГЕТТЕРЫ ===
func get_health_percentage() -> float:
	return current_health / max_health if max_health > 0.0 else 0.0

func get_current_health() -> float:
	return current_health

func get_max_health() -> float:
	return max_health

func is_dead() -> bool:
	return _is_dead

func is_immune() -> bool:
	return _is_immune

func get_armor() -> float:
	return armor

func is_at_full_health() -> bool:
	return current_health >= max_health

func is_critically_injured() -> bool:
	return get_health_percentage() <= 0.2  # 20% или меньше

# === ОТЛАДКА ===
func get_debug_info() -> Dictionary:
	return {
		"current_health": current_health,
		"max_health": max_health,
		"health_percentage": get_health_percentage(),
		"armor": armor,
		"is_dead": _is_dead,
		"is_immune": _is_immune,
		"immunity_timer": _immunity_timer,
		"regeneration_timer": _regeneration_timer
	}
