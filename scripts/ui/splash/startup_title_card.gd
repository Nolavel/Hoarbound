class_name StartupTitleCard
extends CanvasLayer

## A restrained startup card displayed only when the island is the actual
## project scene. Runtime capture tools instantiate the island themselves, so
## they skip the card instead of recording a black frame. The card stays up
## while boot work is pending (BootLoadCapability): the world shows finished.

@export_range(0.0, 2.0, 0.05) var fade_in_seconds: float = 0.35
@export_range(0.0, 5.0, 0.05) var hold_seconds: float = 1.35
@export_range(0.0, 2.0, 0.05) var fade_out_seconds: float = 0.65
## Longest the card waits on boot work before it shows the world anyway.
@export_range(0.0, 60.0, 1.0) var max_boot_wait_seconds: float = 30.0

@onready var _cover: Control = $Cover
@onready var _titles: VBoxContainer = $Cover/Center/Titles


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_titles.modulate.a = 0.0
	call_deferred("_play_if_project_scene")


func _play_if_project_scene() -> void:
	if get_tree().current_scene != get_parent():
		queue_free()
		return

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_titles, "modulate:a", 1.0, fade_in_seconds) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_interval(hold_seconds)
	await tween.finished
	var waited_ms: int = Time.get_ticks_msec()
	while BootLoadCapability.any_pending(get_tree()) \
			and Time.get_ticks_msec() - waited_ms < int(max_boot_wait_seconds * 1000.0):
		await get_tree().process_frame
	print("[Boot] world shown after %.1f s of boot work" % ((Time.get_ticks_msec() - waited_ms) / 1000.0))
	var fade := create_tween()
	fade.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	fade.tween_property(_cover, "modulate:a", 0.0, fade_out_seconds) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	await fade.finished
	queue_free()
