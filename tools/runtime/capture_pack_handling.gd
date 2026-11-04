extends SceneTree

## Hands in the open pack (3D inventory, stage 1), scripted as a player would:
## - The ring hovers items (rim and drop hint).
## - LMB takes the mug, drags it up and turns it with the wheel, then lets go.
## - RMB sweeps the heap; G throws the thermos out.
## - The pad's stick moves the ring; the boards are refused (red line).
## 30 fps PNG frames.
## Run: xvfb-run godot --path . --rendering-driver vulkan --fixed-fps 30 --script res://tools/runtime/capture_pack_handling.gd -- <out dir>

const FPS: int = 30
const ITEMS: Array[StringName] = [&"axe", &"frying_pan", &"hammer", &"water_flask", &"spov_can", &"mug"]
const PACK_AT: Vector3 = Vector3(0.0, 0.9, 0.0)

var _out: String = "user://shots/pack_handling"
var _frame: int = 0
var _caption: Label
var _interior: PackInterior
var _hands: PackHandling
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
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for id: StringName in ITEMS:
		_interior.add(id, Vector3(rng.randf_range(-0.06, 0.06), rng.randf_range(0.34, 0.4), rng.randf_range(0.09, 0.13)))
		for _f: int in 15:
			await physics_frame
	for _f: int in 90:
		await physics_frame
	_camera = Camera3D.new()
	_camera.fov = 40.0
	root.add_child(_camera)
	_camera.look_at_from_position(PACK_AT + Vector3(0.0, 0.85, 0.6), PACK_AT + Vector3(0.0, 0.17, 0.11))
	_camera.make_current()
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var ring := PackCursor.new()
	layer.add_child(ring)
	_caption = Label.new()
	_caption.position = Vector2(24, 20)
	_caption.add_theme_font_size_override("font_size", 30)
	layer.add_child(_caption)
	_hands = PackHandling.new()
	root.add_child(_hands)
	_hands.setup(_interior, _camera, ring)

	await _record(0.6, "КУРСОР-КОЛЬЦО")
	## Hover over each item in turn.
	for id: StringName in [&"axe", &"water_flask", &"frying_pan", &"hammer"]:
		await _glide_to(_screen_of(id), 0.5, "НАВЕДЕНИЕ")
		await _record(0.4, "НАВЕДЕНИЕ:", true)
	## Take what is under the ring (the hammer on top), lift and carry it, turn it.
	_hands.press(PackHandling.GRAB_ACTION, true)
	await _record(0.3, "ЛКМ: ВЗЯЛ (кольцо скрыто):", true)
	await _glide_by(Vector2(-60, -160), 0.8, "ТАЩУ")
	await _glide_by(Vector2(160, 40), 0.8, "ТАЩУ")
	for _n: int in 4:
		_hands.press(PackHandling.TURN_LEFT_ACTION, true)
		await _record(0.15, "КОЛЕСО: ВРАЩАЮ")
	await _record(0.5, "КОЛЕСО: ВРАЩАЮ")
	_hands.press(PackHandling.GRAB_ACTION, false)
	await _record(1.0, "ОТПУСТИЛ")
	## Sweep the heap with RMB.
	await _glide_to(_screen_of(&"spov_can"), 0.4, "ПКМ: РАСТАЛКИВАЮ")
	_hands.press(PackHandling.SHOVE_ACTION, true)
	await _glide_by(Vector2(-200, 30), 0.8, "ПКМ: РАСТАЛКИВАЮ")
	_hands.press(PackHandling.SHOVE_ACTION, false)
	await _record(0.8, "ПКМ: РАСТАЛКИВАЮ")
	## Throw the thermos out.
	await _glide_to(_screen_of(&"water_flask"), 0.5, "G: ВЫБРОСИТЬ")
	await _record(0.4, "G — ВЫБРОСИТЬ:", true)
	var thrown: StringName = _hovered_id()
	_hands.press(PackHandling.DROP_ACTION, true)
	await _record(0.8, "G: ВЫБРОШЕН %s" % thrown)
	## The pad's stick.
	var stick := InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_LEFT_X
	stick.axis_value = -0.8
	Input.parse_input_event(stick)
	await _record(0.8, "ГЕЙМПАД: СТИК")
	stick.axis_value = 0.0
	Input.parse_input_event(stick)
	await _glide_to(_screen_of(&"axe"), 0.4, "ГЕЙМПАД: подсказка Y")
	await _record(0.6, "ГЕЙМПАД: подсказка Y")
	## The boards held over the mouth: refused, red rim and the reason.
	var boards: Node3D = SurvivalItemVisual.make(&"boards")
	root.add_child(boards)
	boards.global_position = _interior.model.global_transform * Vector3(0.12, 0.42, 0.34)
	await _glide_to(_camera.unproject_position(boards.global_position), 0.4, "ДОСКИ")
	_interior.add(&"boards")
	_hands.show_refusal(PackInterior.TOO_BIG, boards)
	await _record(1.8, "ДОСКИ: отказ")
	print("[pack handling] frames ", _frame)
	quit(0)


func _hovered_id() -> StringName:
	return _interior.items[_hands.hovered]["id"] if _hands.hovered >= 0 else &"—"


## A screen point where the ring would pick item `id` (not something lying over it), searched round its centre.
func _screen_of(id: StringName) -> Vector2:
	for i: int in _interior.items.size():
		if _interior.items[i]["id"] != id:
			continue
		var centre: Vector2 = _camera.unproject_position(_interior.model.global_transform * _interior.extent(i).get_center())
		var to_pack: Transform3D = _interior.model.global_transform.affine_inverse()
		for r: float in [0.0, 12.0, 24.0, 36.0, 50.0, 70.0]:
			for k: int in 12:
				var at: Vector2 = centre + Vector2.from_angle(TAU * float(k) / 12.0) * r
				var origin: Vector3 = to_pack * _camera.project_ray_origin(at)
				var hit: Dictionary = _interior.pick(origin, origin + (to_pack.basis * _camera.project_ray_normal(at)).normalized() * 3.0)
				if not hit.is_empty() and int(hit["index"]) == i:
					return at
		return centre
	return _hands.cursor_at


func _glide_to(target: Vector2, seconds: float, caption: String) -> void:
	await _glide_by(target - _hands.cursor_at, seconds, caption)


func _glide_by(offset: Vector2, seconds: float, caption: String) -> void:
	var from: Vector2 = _hands.cursor_at
	var frames: int = maxi(roundi(seconds * FPS), 1)
	for f: int in frames:
		var t: float = smoothstep(0.0, 1.0, float(f + 1) / float(frames))
		_hands.set_cursor(from + offset * t)
		await _record(1.0 / FPS, caption)


## Records frames; `live` appends what is under (or in) the hand each frame, so the caption never lags it.
func _record(seconds: float, caption: String, live: bool = false) -> void:
	_caption.text = caption
	for _i: int in range(maxi(roundi(seconds * FPS), 1)):
		await process_frame
		if live:
			_caption.text = "%s %s" % [caption, _hovered_id()]
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out).path_join("f_%03d.png" % _frame))
		_frame += 1
