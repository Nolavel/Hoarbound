# ✅ Script: DebugAccelerator.gd

extends Control
#Визуальный дебаггер работы аксселератора, в дальнейшем может
#быть использован для крафтовой системы и системы сна как прототипная механика
@export var perfomance_visible_display: bool = false

@export var accelerator: TimeAccelerator
@export var day_night_manager: DayNightManager
@export var duration_label: Label
@export var factor_label: Label
@export var elapsed_label: Label
@export var consumed_label: Label
@export var start_button: Button
@export var stop_button: Button

var base_game_hours_per_second := 1.0 
var acceleration_start_time: float = 0.0

func _ready():
	$".".visible = perfomance_visible_display
	start_button.pressed.connect(_on_start_pressed)
	stop_button.pressed.connect(_on_stop_pressed)
	accelerator.acceleration_started.connect(_on_acceleration_started)
	accelerator.acceleration_ended.connect(_on_acceleration_ended)
	day_night_manager.time_update.connect(_on_time_update)

func _process(delta):
	accelerator._process(delta)
	if accelerator.is_accelerating:
		start_button.disabled = true
		stop_button.disabled = false
		duration_label.text = "⏱ Duration: %.2f s" % accelerator.duration_seconds
		factor_label.text = "⚡ Accelerate: x%.2f" % accelerator.acceleration_factor
		elapsed_label.text = "⏳ Elapsed: %.2f s" % accelerator.elapsed_real_time
	else:
		start_button.disabled = false
		stop_button.disabled = true

func _on_start_pressed():
	accelerator.start_acceleration(base_game_hours_per_second)
	
func _on_stop_pressed():
	accelerator.stop_acceleration()

func _on_acceleration_started():
	pass

func _on_acceleration_ended(consumed_game_hours: float):
	acceleration_start_time = 0.0
	
func _on_time_update(current_hour: float):
	if accelerator.is_accelerating:
		if acceleration_start_time == 0.0:
			acceleration_start_time = current_hour
		
		var time_diff = current_hour - acceleration_start_time
		var minutes_passed = time_diff * 60.0
		
		if minutes_passed < 0:
			minutes_passed += 24 * 60.0  # добавить сутки
		
		if minutes_passed >= 60.0:
			var hours = int(minutes_passed / 60.0)
			var mins = int(fmod(minutes_passed, 60.0))
			consumed_label.text = "🕒 %dh %dm" % [hours, mins]
		else:
			consumed_label.text = "🕒 %dm" % int(minutes_passed)
