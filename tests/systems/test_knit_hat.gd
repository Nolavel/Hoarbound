extends SceneTree

## The approved three-piece hat must be Henry's default head garment and
## remain controlled by the existing equipment slot.
const PLAYER := preload("res://scenes/actors/player/player.tscn")
const PARTS: Array[StringName] = [&"KnitHat_Crown", &"KnitHat_Cuff", &"KnitHat_Pom"]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var player := PLAYER.instantiate() as CharacterBody3D
	root.add_child(player)
	for _i: int in 4:
		await process_frame
	var equipment := player.get_node("EquipmentComponent") as EquipmentComponent
	var visual := player.find_child("HenryUALVisual", true, false) as HenryUALAnimation
	var hat := visual.find_child("KnitHatAttachment", true, false) as BoneAttachment3D
	_check(equipment.get_equipped(&"head_outer") == &"knit_hat", "hat is not equipped at spawn")
	_check(hat != null and hat.visible, "new hat is not visible at spawn")
	if hat != null:
		_check(hat.bone_name == &"Head", "hat is not attached to the Head bone")
		var mesh_count: int = 0
		for node: Node in hat.find_children("*", "MeshInstance3D", true, false):
			mesh_count += 1
			_check(PARTS.has(StringName(node.name)), "unexpected merged or extra hat mesh: %s" % node.name)
			var mesh := node as MeshInstance3D
			_check(mesh.get_surface_override_material(0) is ShaderMaterial,
				"%s does not use the character NPR material" % node.name)
			if node.name != "KnitHat_Pom":
				var material := mesh.get_surface_override_material(0) as ShaderMaterial
				if material != null:
					_check(material.get_shader_parameter("use_albedo_texture") == true
						and material.get_shader_parameter("use_normal_texture") == true,
						"%s lost its baked knit maps" % node.name)
		_check(mesh_count == 3, "hat must have separate cuff, crown, and pom meshes")
	for old_name: StringName in [&"Outfit_Beanie", &"Outfit_BeanieCuff"]:
		var old := visual.find_child(String(old_name), true, false) as MeshInstance3D
		_check(old == null or not old.visible, "%s duplicates the new hat" % old_name)
	_check(equipment.unequip(&"head_outer") == &"knit_hat", "hat could not be removed")
	_check(hat != null and not hat.visible, "hat remained visible after removal")
	_check(equipment.equip(&"head_outer", &"knit_hat") == EquipmentComponent.Refusal.NONE,
		"hat could not be equipped again")
	_check(hat != null and hat.visible, "hat remained hidden after re-equipping")
	if _failures == 0:
		print("knit hat: all checks passed")
	quit(0 if _failures == 0 else 1)


func _check(ok: bool, message: String) -> void:
	if ok:
		return
	_failures += 1
	push_error("knit hat: %s" % message)
