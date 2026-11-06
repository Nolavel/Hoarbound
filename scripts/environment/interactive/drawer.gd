class_name Drawer
extends InteractiveArea

## A drawer that slides out of its furniture (a dresser's): F pulls it out or pushes it in. What it holds is an
## ItemContainer under `slide`, opening upward, that moves with it.

## Emitted when the drawer starts to move, true when it comes out.
signal toggled(open: bool)

const OPEN_KEY: String = "DRAWER_OPEN"
const CLOSE_KEY: String = "DRAWER_CLOSE"

@export_group("Drawer")
## The moving part: its box, its front and what it holds.
@export var slide: Node3D
## How far it comes out, in the slide's parent space, metres.
@export var travel: Vector3 = Vector3(0.0, 0.0, 0.3)
## Out, it is aimed at on its handle (or its front), so aiming into it offers what is inside instead.
@export var handle: Node3D
@export_range(0.0, 1.5, 0.05) var hand_delay: float = 0.3
@export_range(0.1, 2.0, 0.05) var slide_time: float = 0.35

var _open: bool = false
var _shut_at: Vector3 = Vector3.ZERO
var _tween: Tween


func _ready() -> void:
	if player_animation_action == &"":
		player_animation_action = &"interact"
	super()
	if slide != null:
		_shut_at = slide.position
	_update_prompt()


func is_open() -> bool:
	return _open


func get_focus_point(observer: Vector3) -> Vector3:
	if handle != null:
		return handle.global_position
	return super(observer)


func can_interact() -> bool:
	return super() and slide != null and not (_tween != null and _tween.is_running())


func _on_interaction_performed() -> void:
	_open = not _open
	_tween = create_tween()
	_tween.tween_interval(hand_delay)
	_tween.tween_property(slide, ^"position", _shut_at + travel if _open else _shut_at, slide_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.finished.connect(_update_prompt)
	toggled.emit(_open)


func _update_prompt() -> void:
	set_item_name(tr(CLOSE_KEY if _open else OPEN_KEY))
	set_description("")
