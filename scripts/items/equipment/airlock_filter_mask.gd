extends Node3D
class_name AFMPickup

@export var afm_mesh: MeshInstance3D
@export var afm_name: String = "Chest flashlight"
@export var description: String = "No description"
@export var highlight_color: Color = Color(1.0, 1.0, 0.0, 0.45)  # Цвет круга
@export var circle_radius: float = 1.0 

var mesh_instance: MeshInstance3D
var static_body: StaticBody3D
var collision_shape: CollisionShape3D

func _ready() -> void:
	pass

func get_interaction_data() -> Dictionary:
	return {
		"name": afm_name,
		"description": description,
		"highlight_color": highlight_color,
		"circle_radius": circle_radius
	}
