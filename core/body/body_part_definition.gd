class_name BodyPartDefinition
extends Resource

## One part of Henry's body as data: what covers it, how exposed and sensitive it is to cold,
## where it sits on the HUD silhouette and which skeleton bones carry it.

## Stable id used by the cold model, saves and the HUD (&"head", &"hands", &"feet").
@export var id: StringName = &""
## Garment `body_region` that covers this part; empty means nothing can cover it.
@export var garment_region: StringName = &""

@export_group("Cold")
## Share of the wind chill that reaches this part (face 1, feet in boots and snow less).
@export_range(0.0, 1.0, 0.05) var wind_exposure: float = 1.0
## Multiplier on the cold load this part builds; above 1 frosts faster.
@export_range(0.25, 2.0, 0.05) var cold_sensitivity: float = 1.0
## Effective temperature at which load starts and where it is full, °C.
@export var safe_c: float = -5.0
@export var severe_c: float = -35.0

@export_group("Presentation")
## Mask aligned with the HUD silhouette base; frost fills it.
@export var silhouette_mask: Texture2D
## Frost creeps from the top of the mask (the crown) instead of the bottom (fingertips, toes).
@export var frost_from_top: bool = false
## Henry skeleton bones of this part, for later visual effects such as trembling hands.
@export var bones: PackedStringArray = PackedStringArray()
