extends Node3D
class_name StaminaManager

# === СИГНАЛЫ ===
signal stamina_changed(current_stamina: float, max_stamina: float)
signal stamina_depleted()
signal stamina_recovered()
signal sprint_allowed_changed(is_allowed: bool)
signal jump_performed() 

# === ПАРАМЕТРЫ СТАМИНЫ ===
@export_group("Параметры стамины")
@export var max_stamina: float = 100.0
@export var stamina_deplete_rate: float = 5.0  # стамина в секунду при использовании
## Breath regained per second standing still once recovery is in full swing: 0 -> full in ~12 s.
@export var stamina_recover_rate: float = 8.5
## Seconds after the last exertion before breath starts coming back.
@export var stamina_recover_delay: float = 1.0
## Seconds over which recovery eases in after the delay, so it never starts with a jump.
@export var stamina_recover_ease_s: float = 0.8
## Once emptied, sprint stays off until breath is back to this share: no stutter at the bottom.
@export_range(0.0, 1.0, 0.05) var exhausted_until_ratio: float = 0.35
@export var min_stamina_for_action: float = 1.0  # минимум стамины для выполнения действия
@export var jump_stamina_cost: float = 5.0  # 10% от максимальной стамины

# === DEBUG ===
@export_group("Debug")
@export var debug_show_stamina: bool = false
@export var debug_label_path: NodePath

# === ВНУТРЕННИЕ ПЕРЕМЕННЫЕ ===
var current_stamina: float = 1.0
var stamina_recover_timer: float = 0.0
var is_consuming_stamina: bool = false
var was_depleted: bool = false
## How fast breath comes back right now, set each physics frame by MovementController
## from what Henry is doing (1 standing, less walking, 0 in the air), times his energy.
var recovery_scale: float = 1.0
var _exhausted: bool = false
var _debug_label: Label = null

func _ready() -> void:
	# Защита от некорректных значений
	if max_stamina <= 0.0:
		push_warning("Max stamina must be positive, setting to 1.0")
		max_stamina = 1.0
	
	if stamina_deplete_rate <= 0.0:
		push_warning("Stamina deplete rate must be positive, setting to 0.5")
		stamina_deplete_rate = 0.5
	
	if stamina_recover_rate <= 0.0:
		push_warning("Stamina recover rate must be positive, setting to 0.3")
		stamina_recover_rate = 0.3
	
	# Инициализация стамины
	current_stamina = max_stamina
	
	# Инициализация debug label
	if debug_show_stamina and debug_label_path != NodePath():
		_debug_label = get_node_or_null(debug_label_path)
		if _debug_label == null:
			push_warning("Debug stamina label path is invalid — stamina display will not work.")

func _process(delta: float) -> void:
	_update_stamina(delta)
	_update_debug_display()

func _update_stamina(delta: float) -> void:
	var previous_stamina: float = current_stamina
	var was_sprint_allowed: bool = is_sprint_allowed()
	
	if is_consuming_stamina and current_stamina > 0.0:
		# Тратим стамину
		current_stamina -= stamina_deplete_rate * delta
		current_stamina = max(current_stamina, 0.0)
		stamina_recover_timer = 0.0
		
		# Проверяем истощение стамины
		if current_stamina == 0.0 and not was_depleted:
			was_depleted = true
			_exhausted = true
			stamina_depleted.emit()
	else:
		## Breath comes back after a short pause, easing in, at a pace set by what Henry is doing.
		if current_stamina < max_stamina:
			stamina_recover_timer += delta
			var ease: float = smoothstep(0.0, maxf(stamina_recover_ease_s, 0.001), stamina_recover_timer - stamina_recover_delay)
			if ease > 0.0:
				var was_zero = current_stamina == 0.0
				current_stamina += stamina_recover_rate * maxf(recovery_scale, 0.0) * ease * delta
				current_stamina = min(current_stamina, max_stamina)
				
				# Сигнал о восстановлении стамины
				if was_zero and current_stamina > 0.0:
					was_depleted = false
					stamina_recovered.emit()
	if _exhausted and current_stamina >= max_stamina * exhausted_until_ratio:
		_exhausted = false
	
	# Уведомления об изменениях
	if abs(current_stamina - previous_stamina) > 0.001:
		stamina_changed.emit(current_stamina, max_stamina)
	
	var is_sprint_allowed_now: bool = is_sprint_allowed()
	if is_sprint_allowed_now != was_sprint_allowed:
		sprint_allowed_changed.emit(is_sprint_allowed_now)

func _update_debug_display() -> void:
	if debug_show_stamina and _debug_label != null:
		var percentage: float = (current_stamina / max_stamina) * 100.0
		_debug_label.text = "Stamina: %.1f%%" % percentage
		
		# Меняем цвет в зависимости от уровня стамины
		if current_stamina > max_stamina * 0.5:
			_debug_label.add_theme_color_override("font_color", Color.WHITE)
		elif current_stamina > max_stamina * 0.25:
			_debug_label.add_theme_color_override("font_color", Color.YELLOW)
		else:
			_debug_label.add_theme_color_override("font_color", Color.RED)

func try_jump() -> bool:
	var cost = max_stamina * (jump_stamina_cost / 100.0)
	if consume_stamina(cost):
		jump_performed.emit()
		return true
	return false

	
# === ПУБЛИЧНЫЕ МЕТОДЫ ===

## Начать тратить стамину
func start_consuming_stamina() -> void:
	if not is_consuming_stamina:
		is_consuming_stamina = true

## Прекратить тратить стамину
func stop_consuming_stamina() -> void:
	if is_consuming_stamina:
		is_consuming_stamina = false

## Проверить, достаточно ли стамины для действия
func has_stamina_for_action() -> bool:
	return current_stamina >= min_stamina_for_action

## Проверить, разрешен ли спринт: not while catching breath after running dry.
func is_sprint_allowed() -> bool:
	return current_stamina > 0.0 and not _exhausted


## True from running dry until breath is back to `exhausted_until_ratio`.
func is_exhausted() -> bool:
	return _exhausted

## Получить текущую стамину (0.0 - 1.0)
func get_stamina_ratio() -> float:
	return current_stamina / max_stamina

## Получить абсолютное значение стамины
func get_current_stamina() -> float:
	return current_stamina

## Получить максимальную стамину
func get_max_stamina() -> float:
	return max_stamina

## Мгновенно восстановить стамину (для читов/бонусов)
func restore_stamina(amount: float = -1.0) -> void:
	if amount < 0.0:
		current_stamina = max_stamina
	else:
		current_stamina = min(current_stamina + amount, max_stamina)
	
	if was_depleted and current_stamina > 0.0:
		was_depleted = false
		stamina_recovered.emit()
	if current_stamina >= max_stamina * exhausted_until_ratio:
		_exhausted = false
	stamina_changed.emit(current_stamina, max_stamina)

## Мгновенно потратить стамину
func consume_stamina(amount: float) -> bool:
	if current_stamina >= amount:
		current_stamina -= amount
		current_stamina = max(current_stamina, 0.0)
		
		if current_stamina == 0.0 and not was_depleted:
			was_depleted = true
			_exhausted = true
			stamina_depleted.emit()
		stamina_recover_timer = 0.0
		stamina_changed.emit(current_stamina, max_stamina)
		return true
	
	return false

## Установить параметры стамины во время выполнения
func set_stamina_parameters(
	new_max_stamina: float = -1.0,
	new_deplete_rate: float = -1.0,
	new_recover_rate: float = -1.0,
	new_recover_delay: float = -1.0
) -> void:
	if new_max_stamina > 0.0:
		var ratio: float = get_stamina_ratio()
		max_stamina = new_max_stamina
		current_stamina = max_stamina * ratio
	
	if new_deplete_rate > 0.0:
		stamina_deplete_rate = new_deplete_rate
	
	if new_recover_rate > 0.0:
		stamina_recover_rate = new_recover_rate
	
	if new_recover_delay >= 0.0:
		stamina_recover_delay = new_recover_delay

## Проверить, восстанавливается ли стамина сейчас
func is_recovering() -> bool:
	return not is_consuming_stamina and current_stamina < max_stamina and stamina_recover_timer >= stamina_recover_delay \
		and recovery_scale > 0.0
