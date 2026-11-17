extends SceneTree

## Clothing rime: grows outdoors in frost (faster in a blizzard), holds in a cold shelter, melts by a fire
## and in warm air; clothes, the pack and its gear take it (plain materials as an overlay), the face does not.
## Run: godot --headless --script tests/systems/test_clothing_frost.gd

const DT: float = 1.0 / 30.0
const PLAYER: String = "res://scenes/actors/player/player.tscn"
const GEAR_SHADERS: Array[String] = [
	"res://shaders/items/backpack_canvas.gdshader",
	"res://shaders/items/carabiner.gdshader",
	"res://shaders/items/worn_tool.gdshader",
	"res://shaders/items/pack_strap_bend.gdshader",
	"res://shaders/items/garment_frost_overlay.gdshader",
]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_no_rime_above_freezing()
	_test_grows_faster_in_a_blizzard()
	_test_holds_in_a_cold_shelter_and_melts_by_fire()
	_test_warm_room_thaws_gradually()
	_test_shader_has_the_rime()
	await _test_gear_frosts_but_not_the_face()
	if _failures > 0:
		push_error("clothing frost: %d check(s) failed" % _failures)
		quit(1)
		return
	print("clothing frost: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("clothing frost: " + message)


func _run_for(frost: ClothingFrostComponent, seconds: float, air: float, sheltered: bool, fire: bool, snow: float, wind: float) -> void:
	for _i: int in range(int(round(seconds / DT))):
		frost.step(DT, air, sheltered, fire, snow, wind)


func _test_no_rime_above_freezing() -> void:
	var frost := ClothingFrostComponent.new()
	_run_for(frost, 300.0, 4.0, false, false, 1.0, 10.0)
	_check(frost.get_frost() == 0.0, "rime formed at +4 °C")
	_run_for(frost, 300.0, -1.0, false, false, 0.0, 0.0)
	_check(frost.get_frost() == 0.0, "rime formed at -1 °C, above the forming point")
	frost.free()


func _test_grows_faster_in_a_blizzard() -> void:
	var still := ClothingFrostComponent.new()
	_run_for(still, 120.0, -25.0, false, false, 0.0, 0.0)
	var storm := ClothingFrostComponent.new()
	_run_for(storm, 120.0, -25.0, false, false, 1.0, 12.0)
	_check(still.get_frost() > 0.2 and still.get_frost() < 0.6, "two still minutes at -25 °C gave %.2f, want a partial crust" % still.get_frost())
	_check(storm.get_frost() > still.get_frost() * 1.5, "a blizzard should frost faster (%.2f vs %.2f)" % [storm.get_frost(), still.get_frost()])
	_run_for(storm, 600.0, -25.0, false, false, 1.0, 12.0)
	_check(is_equal_approx(storm.get_frost(), 1.0), "a long blizzard should crust fully, got %.2f" % storm.get_frost())
	still.free()
	storm.free()


func _test_holds_in_a_cold_shelter_and_melts_by_fire() -> void:
	var frost := ClothingFrostComponent.new()
	_run_for(frost, 900.0, -25.0, false, false, 1.0, 12.0)
	var crusted: float = frost.get_frost()
	_run_for(frost, 120.0, -10.0, true, false, 0.0, 0.0)
	_check(is_equal_approx(frost.get_frost(), crusted), "rime changed in a -10 °C shelter (%.2f to %.2f)" % [crusted, frost.get_frost()])
	_run_for(frost, 30.0, -10.0, true, true, 0.0, 0.0)
	_check(frost.get_frost() < crusted and frost.get_frost() > 0.3, "by the fire it should thaw gradually, not at once (%.2f after 30 s)" % frost.get_frost())
	_run_for(frost, 90.0, -10.0, true, true, 0.0, 0.0)
	_check(frost.get_frost() == 0.0, "rime still on after 2 min by the fire (%.2f)" % frost.get_frost())
	frost.free()


func _test_warm_room_thaws_gradually() -> void:
	var mild := ClothingFrostComponent.new()
	mild.set_frost_value(0.85)
	_run_for(mild, 60.0, 5.0, true, false, 0.0, 0.0)
	_check(mild.get_frost() > 0.55, "a +5 °C room took the rime too fast (%.2f after 1 min)" % mild.get_frost())
	var warm := ClothingFrostComponent.new()
	warm.set_frost_value(0.85)
	_run_for(warm, 60.0, 15.0, true, false, 0.0, 0.0)
	_check(warm.get_frost() < mild.get_frost() - 0.1, "a warmer room should thaw faster (%.2f vs %.2f)" % [warm.get_frost(), mild.get_frost()])
	_run_for(mild, 300.0, 5.0, true, false, 0.0, 0.0)
	_check(mild.get_frost() == 0.0, "a +5 °C room left rime after 6 min (%.2f)" % mild.get_frost())
	mild.free()
	warm.free()


func _test_shader_has_the_rime() -> void:
	var material := StylizedEnvironmentMaterial.make_character(Color.WHITE, 1.0)
	var include: String = FileAccess.get_file_as_string("res://shaders/environment/materials/stylized_environment_body.gdshaderinc")
	_check(include.contains("garment_frost.gdshaderinc"), "the character shader does not take the rime")
	_check(material.shader != null, "no character shader")
	for path: String in GEAR_SHADERS:
		_check(FileAccess.get_file_as_string(path).contains("garment_frost.gdshaderinc"), "%s does not take the rime" % path)


func _test_gear_frosts_but_not_the_face() -> void:
	var player := (load(PLAYER) as PackedScene).instantiate() as Player
	root.add_child(player)
	for _i: int in range(10):
		await process_frame
	var frost := player.get_node(^"ClothingFrostComponent") as ClothingFrostComponent
	_check(is_equal_approx(frost.get_frost(), 0.85), "Henry should start frosted at 0.85, got %.2f" % frost.get_frost())
	_check(SaveParticipantCapability.get_key(frost) == &"clothing_frost", "the rime is not a save participant")
	frost.set_frost(0.33)
	var saved: Variant = SaveParticipantCapability.capture(frost)
	frost.set_frost(0.9)
	SaveParticipantCapability.restore(frost, saved as Dictionary)
	_check(is_equal_approx(frost.get_frost(), 0.33), "the rime did not come back from a save (%.2f)" % frost.get_frost())
	frost.set_frost(0.7)
	var frosted: Dictionary = {}
	var face_frosted: bool = false
	var overlays: int = 0
	for node: Node in player.find_children("*", "GeometryInstance3D", true, false):
		var geo := node as GeometryInstance3D
		var value: Variant = geo.get_instance_shader_parameter(&"garment_frost")
		var amount: float = float(value) if value != null else 0.0
		if String(geo.name).begins_with("Henry_Head"):
			face_frosted = face_frosted or amount > 0.0
		elif is_equal_approx(amount, 0.7):
			frosted[String(geo.name)] = true
		if geo.material_overlay == ClothingFrostComponent.OVERLAY:
			overlays += 1
	for name: String in ["Outfit_Jacket", "KnitHat_Crown", "Shell", "FrontPanel", "Pan_Body", "Ring", "Thermos_Body", "PackShoulderStraps", "Mug_KW_LOD0"]:
		_check(frosted.has(name), "%s took no rime" % name)
	_check(not face_frosted, "Henry's skin took the cloth rime")
	var head := player.find_child("Henry_Head", true, false) as GeometryInstance3D
	var flush: Variant = head.get_instance_shader_parameter(&"face_flush")
	var brows: Variant = head.get_instance_shader_parameter(&"face_frost")
	_check(flush != null and float(flush) >= 0.7, "the cheeks did not flush with the cold (%s)" % str(flush))
	_check(brows != null and is_equal_approx(float(brows), 0.7), "the brows took no breath rime (%s)" % str(brows))
	var head_material := (head as MeshInstance3D).get_active_material(0) as ShaderMaterial
	_check(head_material != null and head_material.get_shader_parameter("use_face_mask") == true, "the face mask is not on Henry's head")
	_check(overlays > 0, "no plain-material gear got the rime overlay")
	frost.set_frost(0.0)
	var left: int = 0
	for node: Node in player.find_children("*", "GeometryInstance3D", true, false):
		if (node as GeometryInstance3D).material_overlay == ClothingFrostComponent.OVERLAY:
			left += 1
	_check(left == 0, "%d rime overlays stayed after the rime melted" % left)
	player.queue_free()
