class_name EmbodiedLabTarget
extends InteractiveArea

## A can in the local lab. The lab owns the action and item state; this Area
## exposes the existing crosshair affordance without adding inventory items.
var case_index: int = -1
var available: bool = true


func can_interact() -> bool:
	return available and super.can_interact()
