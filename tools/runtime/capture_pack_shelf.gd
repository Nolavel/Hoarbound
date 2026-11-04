extends SceneTree

## Quick Access while the pack is open (3D inventory, stage 2), scripted as a player would:
## - The ring passes over the quick pockets' cards.
## - The SPoV tin is carried from the coat pocket into the pack.
## - A pack item is dragged into the free coat pocket.
## - The thermos is refused by a full pocket (red card, reason) and goes back.
## - G throws the mug off the carabiner.
## 30 fps PNG frames.
## Run: xvfb-run godot --path . --rendering-driver vulkan --fixed-fps 30 --script res://tools/runtime/capture_pack_shelf.gd -- <out dir>

const FPS: int = 30
const PACK_AT: Vector3 = Vector3(0.0, 0.9, 0.0)
const BODY: Array = [[&"worn_coat", &"coat_left"], [&"worn_coat", &"coat_right"], [&"work_trousers", &"thigh_left"],
	[&"backpack", &"pack_lid"]]
const OUTSIDE: Array = [[&"backpack", &"pack_side_left"], [&"backpack", &"pack_side_right_front"],
	[&"backpack", &"pack_side_right_back"], [&"backpack", &"pack_carabiner"], [&"backpack", &"pack_carabiner_left"]]

var _out: String = "user://shots/pack_shelf"
var _frame: int = 0
var _caption: Label
var _interior: PackInterior
var _hands: PackHandling
var _shelf: PackQuickShelf
var _camera: Camera3D


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_run()


func _run() -> void:
	await process_frame
	TranslationServer.set_locale("ru")
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.11, 0.11, 0.12)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.57, 0.62)
	env.environment.ambient_light_energy = 0.8
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62.0, -30.0, 0.0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	root.add_child(sun)
	var pack := BackpackModel.new()
	root.add_child(pack)
	pack.build()
	pack.global_position = PACK_AT
	pack.set_open(true)
	_interior = PackInterior.new()
	pack.add_child(_interior)
	_interior.setup(pack)
	_interior.set_open(true)
	for id: StringName in [&"axe", &"frying_pan", &"hammer"]:
		_interior.add(id, Vector3(0.0, 0.36, 0.11))
		for _f: int in 20:
			await physics_frame
	for _f: int in 60:
		await physics_frame
	_camera = Camera3D.new()
	_camera.fov = 46.0
	root.add_child(_camera)
	_camera.look_at_from_position(PACK_AT + Vector3(0.0, 0.85, 0.75), PACK_AT + Vector3(0.0, 0.2, 0.11))
	_camera.make_current()
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var ring := PackCursor.new()
	layer.add_child(ring)
	_caption = Label.new()
	_caption.position = Vector2(24, 20)
	_caption.add_theme_font_size_override("font_size", 30)
	layer.add_child(_caption)
	_shelf = PackQuickShelf.new()
	pack.add_child(_shelf)
	_shelf.setup(pack, _camera, BODY, OUTSIDE)
	_hands = PackHandling.new()
	root.add_child(_hands)
	_hands.setup(_interior, _camera, ring)
	_hands.setup_shelf(_shelf)
	var coat_left: int = _slot(&"coat_left")
	var coat_right: int = _slot(&"coat_right")
	var side: int = _slot(&"pack_side_left")
	var carabiner: int = _slot(&"pack_carabiner")
	_shelf.put(coat_left, &"spov_can")
	_shelf.put(side, &"water_flask")
	_shelf.put(carabiner, &"mug")
	await _record(0.8, "БЫСТРЫЙ ДОСТУП: карманы на теле слева, снаружи рюкзака справа")
	for k: int in [side, carabiner, coat_left]:
		await _glide(_card_screen(k), 0.5, "НАВЕДЕНИЕ НА КАРМАН")
		await _record(0.3, "НАВЕДЕНИЕ НА КАРМАН")
	_hands.press(PackHandling.GRAB_ACTION, true)
	await _record(0.3, "ЛКМ: ВЗЯЛ ИЗ КАРМАНА")
	await _glide(_camera.unproject_position(pack.global_transform * Vector3(0.0, 0.32, 0.11)), 0.8, "НЕСУ В РЮКЗАК")
	_hands.press(PackHandling.GRAB_ACTION, false)
	await _record(1.0, "ПОЛОЖИЛ В РЮКЗАК")
	await _glide(_screen_of_any(), 0.5, "БЕРУ ИЗ РЮКЗАКА")
	_hands.press(PackHandling.GRAB_ACTION, true)
	await _record(0.3, "БЕРУ ИЗ РЮКЗАКА")
	await _glide(_card_screen(coat_right), 0.9, "В СВОБОДНЫЙ КАРМАН")
	await _record(0.4, "В СВОБОДНЫЙ КАРМАН")
	_hands.press(PackHandling.GRAB_ACTION, false)
	await _record(0.8, "ПЕРЕЛОЖИЛ В КАРМАН")
	await _glide(_card_screen(side), 0.6, "ТЕРМОС В ЗАНЯТЫЙ КАРМАН")
	_hands.press(PackHandling.GRAB_ACTION, true)
	await _glide(_card_screen(coat_right), 0.9, "ТЕРМОС В ЗАНЯТЫЙ КАРМАН")
	await _record(0.4, "ТЕРМОС В ЗАНЯТЫЙ КАРМАН")
	_hands.press(PackHandling.GRAB_ACTION, false)
	await _record(1.4, "ОТКАЗ: вернулся на место")
	await _glide(_card_screen(carabiner), 0.6, "G: ВЫБРОСИТЬ КРУЖКУ")
	await _record(0.3, "G: ВЫБРОСИТЬ КРУЖКУ")
	_hands.press(PackHandling.DROP_ACTION, true)
	await _record(1.0, "G: ВЫБРОШЕНА")
	print("[pack shelf] frames ", _frame)
	quit(0)


func _slot(pocket_id: StringName) -> int:
	for k: int in _shelf.slots.size():
		if (_shelf.slots[k]["definition"] as EquipmentSlotDefinition).id == pocket_id:
			return k
	return -1


func _card_screen(k: int) -> Vector2:
	return _camera.unproject_position((_shelf.slots[k]["card"] as Node3D).global_position)


func _screen_of_any() -> Vector2:
	var to_pack: Transform3D = _interior.model.global_transform.affine_inverse()
	for i: int in _interior.items.size():
		var at: Vector2 = _camera.unproject_position(_interior.model.global_transform * _interior.extent(i).get_center())
		var origin: Vector3 = to_pack * _camera.project_ray_origin(at)
		var hit: Dictionary = _interior.pick(origin, origin + (to_pack.basis * _camera.project_ray_normal(at)).normalized() * 3.0)
		if not hit.is_empty() and int(hit["index"]) == i:
			return at
	return _hands.cursor_at


func _glide(target: Vector2, seconds: float, caption: String) -> void:
	var from: Vector2 = _hands.cursor_at
	var frames: int = maxi(roundi(seconds * FPS), 1)
	for f: int in frames:
		_hands.set_cursor(from.lerp(target, smoothstep(0.0, 1.0, float(f + 1) / float(frames))))
		await _record(1.0 / FPS, caption)


func _record(seconds: float, caption: String) -> void:
	_caption.text = caption
	for _i: int in range(maxi(roundi(seconds * FPS), 1)):
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out).path_join("f_%03d.png" % _frame))
		_frame += 1
