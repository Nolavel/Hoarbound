extends SceneTree

## Actual overlay shader + current card shader, over preserved game screenshots.
## Visual review only: the states are explicitly simulated, not gameplay events.
const Overlay = preload("res://scripts/ui/effects/edge_glow_overlay.gd")
const BG = preload("res://assets/materials/Shaders/BG_frame.gdshader")
const OUTDOOR = "res://docs/runtime_previews/key_west_727/approach_fort_st.png"
const INDOOR = "res://docs/runtime_previews/key_west_727/henry_by_stove_game_camera.png"
const ICONS = "res://assets/ui/hud/quick_access/icons/"
var _overlays: Array[Control] = []
var _back: TextureRect
var _caption: Label
var _out: String

func _initialize() -> void:
    _run.call_deferred()

func _run() -> void:
    root.size = Vector2i(960, 540)
    root.content_scale_size = Vector2i(960, 540)
    var args := OS.get_cmdline_user_args()
    if args.is_empty():
        quit(1)
        return
    _out = args[0]
    DirAccess.make_dir_recursive_absolute(_out)
    _back = TextureRect.new()
    _back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _back.stretch_mode = TextureRect.STRETCH_SCALE
    _back.size = Vector2(960, 540)
    root.add_child(_back)
    _caption = Label.new()
    _caption.position = Vector2(20, 15)
    _caption.add_theme_font_size_override("font_size", 20)
    _caption.add_theme_constant_override("outline_size", 6)
    root.add_child(_caption)
    _card(Vector2(172, 325), "Coat pocket", "inventory_2.svg", Color(0.36, 0.36, 0.36, 0.72), 0)
    _card(Vector2(388, 325), "HANDS", "water_bottle.svg", Color(0.70, 0.73, 0.76, 0.78), 4)
    _card(Vector2(604, 325), "Pack pocket", "lunch_dining.svg", Color(0.36, 0.36, 0.36, 0.72), 1)
    if not _background(OUTDOOR):
        quit(1)
        return
    _caption.text = "OUTDOOR / BASELINE - overlay off"
    await _snap("01_outdoor_off.png")
    _overlays[0].set_feedback_state(Overlay.STATE_UNSELECTED)
    _overlays[1].set_feedback_state(Overlay.STATE_HELD)
    _overlays[2].set_feedback_state(Overlay.STATE_UNSELECTED)
    _advance(1.0)
    _caption.text = "OUTDOOR / NEUTRAL + HELD"
    await _snap("02_outdoor_states.png")
    _overlays[2].show_refusal()
    _advance(0.12)
    _caption.text = "OUTDOOR / REJECTION EVENT"
    await _snap("03_outdoor_refusal.png")
    if not _background(INDOOR):
        quit(1)
        return
    _caption.text = "727 / REJECTION EVENT"
    await _snap("04_indoor_refusal.png")
    _advance(0.65)
    _caption.text = "727 / RECOVERED BASE STATE"
    await _snap("05_indoor_recovered.png")
    print("EDGE_GLOW_CAPTURE: PASS")
    quit(0)

func _background(path: String) -> bool:
    var img := Image.load_from_file(path)
    if img == null or img.is_empty():
        push_error("missing background " + path)
        return false
    _back.texture = ImageTexture.create_from_image(img)
    return true

func _card(at: Vector2, title: String, icon_file: String, tint: Color, direction: int) -> void:
    var card := Control.new()
    card.position = at
    card.size = Vector2(196, 62) if direction == 4 else Vector2(184, 58)
    root.add_child(card)
    var bg := ColorRect.new()
    bg.size = card.size
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var mat := ShaderMaterial.new()
    mat.shader = BG
    mat.set_shader_parameter("base_color", tint)
    mat.set_shader_parameter("fade_direction", direction)
    mat.set_shader_parameter("fade_start", 0.1 if direction == 4 else 0.3)
    mat.set_shader_parameter("fade_end", 1.0 if direction == 4 else 0.8)
    mat.set_shader_parameter("corner_radius", 0.1)
    bg.material = mat
    card.add_child(bg)
    var glow := Overlay.new()
    card.add_child(glow)
    glow.set_process(false)
    _overlays.append(glow)
    var icon := TextureRect.new()
    var img := Image.load_from_file(ICONS + icon_file)
    if img != null and not img.is_empty():
        icon.texture = ImageTexture.create_from_image(img)
    icon.position = Vector2(10, 11)
    icon.size = Vector2(36, 36)
    icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    card.add_child(icon)
    var label := Label.new()
    label.position = Vector2(54, 6)
    label.size = Vector2(122, 48)
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.add_theme_font_size_override("font_size", 14)
    label.add_theme_constant_override("outline_size", 3)
    label.text = title
    card.add_child(label)

func _advance(seconds: float) -> void:
    var frames := maxi(1, int(ceil(seconds * 60.0)))
    for i in frames:
        for glow in _overlays:
            glow._process(seconds / frames)

func _snap(name: String) -> void:
    await process_frame
    await RenderingServer.frame_post_draw
    var img := root.get_texture().get_image()
    if img == null or img.is_empty():
        push_error("missing capture " + name)
        return
    if img.get_width() != 960 or img.get_height() != 540:
        img.resize(960, 540)
    var err := img.save_png(_out.path_join(name))
    if err != OK:
        push_error("PNG save failed " + name)
    print("EDGE_GLOW_CAPTURE: " + name)
