class_name ShelterCabinet
extends RefCounted
## Fade volume and set dressing for the First Exit hut cabinet, shared by every world that builds the hut.

const FADE_VOLUME_SCENE: PackedScene = preload("res://scenes/environment/visual_fx/FadeVolume.tscn")


## Adds the reusable Fade Volume to the hollow shelter cabinet. The shader's
## signed local-X contract is intentional: -X stays transparent at the opening,
## +X darkens toward the back wall. The same setup is suitable for cabinets,
## drawers/crates and other hollow props when their carrier box matches the cavity.
static func add_cabinet_fade_volume(house: Node3D) -> void:
	var cabinet := house.find_child("Cabinet", true, false) as Node3D
	if cabinet == null:
		push_warning("ShelterCabinet: shelter Cabinet not found for FadeVolume")
		return
	var volume := FADE_VOLUME_SCENE.instantiate() as MeshInstance3D
	if volume == null:
		push_warning("ShelterCabinet: FadeVolume failed to instantiate")
		return
	volume.name = "CabinetFadeVolume"
	## Cabinet local +Z is its opening. +90° maps volume -X to the opening and
	## +X to the back wall, matching the original Fade Volume reference.
	volume.position = Vector3(0.0, 0.45, -0.111)
	volume.rotation.y = PI * 0.5
	var source_box := volume.mesh as BoxMesh
	if source_box != null and source_box.material is ShaderMaterial:
		var material := (source_box.material as ShaderMaterial).duplicate() as ShaderMaterial
		var physical_box := BoxMesh.new()
		physical_box.size = Vector3(0.60, 0.78, 0.72)
		physical_box.material = material
		volume.mesh = physical_box
		volume.scale = Vector3.ONE
		material.set_shader_parameter(&"x_len", 0.60)
		material.set_shader_parameter(&"y_len", 0.78)
		material.set_shader_parameter(&"z_len", 0.72)
		material.set_shader_parameter(&"exponent", 1.0)
		material.set_shader_parameter(&"axis_sign", 1.0)
		material.set_shader_parameter(&"fade_color", Color(0.025, 0.035, 0.055, 0.58))
		material.set_shader_parameter(&"corner_radius", 0.07)
		material.set_shader_parameter(&"edge_softness", 0.025)
		volume.material_override = material
	cabinet.add_child(volume)
	_add_cabinet_set_dressing(cabinet)


## Static level-art silhouettes only: no focus prompt, pickup area or inventory
## state. They make the cabinet read as a used hollow object rather than a black box.
static func _add_cabinet_set_dressing(cabinet: Node3D) -> void:
	var stew := SurvivalItemVisual.make(&"tinned_stew")
	stew.name = "CabinetProp_StewTin"
	stew.position = Vector3(-0.20, 0.075, -0.02)
	stew.rotation.y = deg_to_rad(-12.0)
	cabinet.add_child(stew)

	var pineapple := SurvivalItemVisual.make(&"tinned_pineapple")
	pineapple.name = "CabinetProp_PineappleTin"
	pineapple.position = Vector3(0.16, 0.075, -0.04)
	pineapple.rotation.y = deg_to_rad(16.0)
	cabinet.add_child(pineapple)

	var mug := SurvivalItemVisual.make(&"mug")
	mug.name = "CabinetProp_Mug"
	mug.position = Vector3(0.10, 0.475, -0.02)
	mug.rotation.y = deg_to_rad(24.0)
	cabinet.add_child(mug)
