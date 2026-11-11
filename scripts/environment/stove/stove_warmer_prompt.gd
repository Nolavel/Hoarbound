class_name StoveWarmerPrompt
extends InteractiveArea

## The F target over the stove's cooking ring; StoveWarmer decides what F does.

var warmer: StoveWarmer


func _ready() -> void:
	if player_animation_action == &"":
		player_animation_action = &"interact"
	super()
	set_description("")
	refresh_label()


func can_interact() -> bool:
	return super() and warmer != null and warmer.can_interact_with(_player())


func refresh_label() -> void:
	if warmer != null and is_inside_tree():
		set_item_name(warmer.get_prompt_text(_player()))


func _on_interaction_performed() -> void:
	if warmer != null:
		warmer.interact_with(_player())
	refresh_label()


func _player() -> Node:
	return get_tree().get_first_node_in_group(&"player") if is_inside_tree() else null
