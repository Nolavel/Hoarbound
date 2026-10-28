class_name TableFood
extends InteractiveArea

## One kind of food laid on a MealTable: F eats (or drinks) one of it through the
## player's ConsumptionController. The table rebuilds it as the stock changes.

const EAT_KEY: String = "TABLE_EAT"
const DRINK_KEY: String = "TABLE_DRINK"

## Catalog id of the food this stands for.
@export var item_id: StringName = &""
@export var count: int = 1


func _ready() -> void:
	if player_animation_action == &"":
		player_animation_action = &"none"  # the eat clip plays on `consumed`
	super()
	var item: ItemResource = ItemCatalog.get_item(item_id)
	var verb: String = tr(DRINK_KEY) if item != null and item.consumable != null \
		and item.consumable.calories <= 0.0 else tr(EAT_KEY)
	var label: String = tr(item.display_name) if item != null else String(item_id)
	set_item_name("%s: %s%s" % [verb, label, " ×%d" % count if count > 1 else ""])
	set_description("")


func _on_interaction_performed() -> void:
	var player: Node = get_tree().get_first_node_in_group(&"player")
	var eater: ConsumptionController = player.get_node_or_null(^"ConsumptionController") as ConsumptionController \
		if player != null else null
	if eater == null:
		return
	var refusal: ConsumptionController.Refusal = eater.consume(item_id)
	if refusal != ConsumptionController.Refusal.NONE:
		show_message(tr(ConsumptionController.describe_refusal(refusal)))


func can_interact() -> bool:
	return super() and get_parent() != null and not get_parent().is_queued_for_deletion()


func _get_interaction_text() -> String:
	var item: ItemResource = ItemCatalog.get_item(item_id)
	if item != null:
		set_description(item.get_status_text())
		if item.water_capacity_ml > 0:
			return "[%s] %s" % [_interact_key_label(), tr("FLASK_DRINK_ACTION")]
		if item.opens_into != &"":
			return "[%s] %s" % [_interact_key_label(), tr(ConsumptionController.open_action_key(item))]
	return "[%s] %s" % [_interact_key_label(), item_name]
