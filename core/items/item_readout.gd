class_name ItemReadout
extends RefCounted

## What a hover shows about an item, from its data: its name, its weight, and the one number that matters most
## (a flask's water, food's calories, otherwise its size). Text is already localised.

const SIZE_KEYS: Array[String] = ["HUB_SIZE_POCKET", "HUB_SIZE_CARRIED", "HUB_SIZE_BULKY"]


## {"name": String, "weight": String, "detail": String, "kg": float} for `item_id`, or {} for an unknown id.
static func describe(item_id: StringName) -> Dictionary:
	var item: ItemResource = ItemCatalog.get_item(item_id)
	if item == null:
		return {}
	var detail: String = ""
	if item.water_capacity_ml > 0:
		detail = TranslationServer.translate(&"FLASK_SHORT_STATUS") % [item.water_remaining_ml, item.water_capacity_ml]
	elif item.consumable != null and item.consumable.calories > 0.0:
		detail = TranslationServer.translate(&"ITEM_CALORIES") % roundi(item.consumable.calories)
	elif int(item.size_class) < SIZE_KEYS.size():
		detail = TranslationServer.translate(StringName(SIZE_KEYS[int(item.size_class)]))
	return {
		"name": TranslationServer.translate(StringName(item.display_name)),
		"weight": TranslationServer.translate(&"ITEM_WEIGHT_KG") % item.weight if item.weight >= 1.0
			else TranslationServer.translate(&"ITEM_WEIGHT_G") % roundi(item.weight * 1000.0),
		"detail": detail,
		"kg": item.weight,
	}
