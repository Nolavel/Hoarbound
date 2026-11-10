# ✅ Script: TimeAccelerator.gd
extends Node
class_name TimeAccelerator
# метод использования в игре - крафт требует времени для создания определьнным предметов из присутствующих
# в инвентаре материалов. Запуск сборки-крафта предмета выражен в затрате игрового времени (старт - мы 
# запускаем процесс factor(времени) 5-10-20 секунд взависимости от сложности сборки крафта. consumed 
#- мы всегда показываем сколько времени игрового уйдет на крафт. ТАКЖЕ ЭТОТ ФУНКЦИОНАЛ НАПрЯМУЮ ДОЛЖЕН
# ИСПОЛЬЗОВАТЬСЯ В рЕЖИМЕ СНА ПЕрСОНАЖА, ЗАПУСКАТЬСЯ ПО ТАКОМУ ЖЕ ПрИНЦИПУ КАК И КрАФТ (у игрока будет
# выбор в режиме сна сколько персонаж будет во сне CONSUMED)

# В Крафте также необходима кнопка при уже включенном процесс изготовления
# предмета, можно сбросить прогресс stop_acceleration.

signal acceleration_started()
signal acceleration_ended(consumed_game_hours: float)

@export var acceleration_factor: float = 2.0
@export var duration_seconds: float = 5.0

var is_accelerating := false
var elapsed_real_time := 0.0
var consumed_game_hours := 0.0

var game_hours_per_second := 1.0
var start_game_time: float = 0.0
var end_game_time: float = 0.0

func start_acceleration(base_speed: float):
	var day_night := get_parent() as DayNightManager
	if day_night != null:
		start_game_time = day_night.get_current_hour_float()
	game_hours_per_second = base_speed
	is_accelerating = true
	elapsed_real_time = 0.0
	consumed_game_hours = 0.0
	emit_signal("acceleration_started")

func _process(delta: float) -> void:
	if not is_accelerating:
		return
	elapsed_real_time += delta
	var accelerated_game_hours = delta * game_hours_per_second * acceleration_factor
	consumed_game_hours += accelerated_game_hours
	if elapsed_real_time >= duration_seconds:
		var day_night := get_parent() as DayNightManager
		if day_night != null:
			end_game_time = day_night.get_current_hour_float()
		is_accelerating = false
		emit_signal("acceleration_ended", consumed_game_hours)
		
func stop_acceleration():
	if is_accelerating:
		is_accelerating = false
		emit_signal("acceleration_ended", consumed_game_hours)
