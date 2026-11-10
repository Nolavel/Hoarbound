extends SceneTree
## Godot fullscreen overlay over actual, archived Hub screenshots.
## Scripted states; no claim of live gameplay integration.
const Overlay = preload("res://scripts/ui/effects/edge_glow_overlay.gd")
const HUB_FRAME = "res://docs/art/issue68/03_hub_full.png"
const CAMERA_FRAME = "res://docs/runtime_previews/hub_camera/after.png"
var _overlay: EdgeGlowOverlay
var _back: TextureRect
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
    var host := Control.new()
    host.size = Vector2(960, 540)
    root.add_child(host)
    _back = TextureRect.new()
    _back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _back.stretch_mode = TextureRect.STRETCH_SCALE
    _back.size = host.size
    host.add_child(_back)
    _overlay = Overlay.new()
    host.add_child(_overlay)
    _overlay.set_process(false)
    if not _background(HUB_FRAME):
        quit(1)
        return
    await _snap("01_hub_off.png")
    _overlay.set_hub_active(true)
    _advance(0.5)
    await _snap("02_hub_idle.png")
    _overlay.set_action_active(true)
    _advance(0.5)
    await _snap("03_hub_active.png")
    _overlay.show_result(true)
    _advance(0.12)
    await _snap("04_hub_success.png")
    _overlay.show_result(false)
    _advance(0.12)
    await _snap("05_hub_refusal.png")
    _overlay.set_action_active(false)
    _advance(0.9)
    await _snap("06_hub_recovered.png")
    if not _background(CAMERA_FRAME):
        quit(1)
        return
    _overlay.set_action_active(true)
    _advance(0.5)
    await _snap("07_camera_active.png")
    _overlay.show_result(true)
    _advance(0.12)
    await _snap("08_camera_success.png")
    _overlay.show_result(false)
    _advance(0.12)
    await _snap("09_camera_refusal.png")
    print("EDGE_GLOW_CAPTURE: PASS")
    quit(0)
func _background(path: String) -> bool:
    var img := Image.load_from_file(path)
    if img == null or img.is_empty():
        push_error("missing screenshot " + path)
        return false
    _back.texture = ImageTexture.create_from_image(img)
    return true
func _advance(seconds: float) -> void:
    var frames := maxi(1, int(ceil(seconds * 60.0)))
    for i in frames:
        _overlay._process(seconds / frames)
func _snap(name: String) -> void:
    await process_frame
    await RenderingServer.frame_post_draw
    var img := root.get_texture().get_image()
    if img == null or img.is_empty():
        push_error("missing capture " + name)
        return
    if img.get_width() != 960 or img.get_height() != 540:
        img.resize(960, 540)
    if img.save_png(_out.path_join(name)) != OK:
        push_error("PNG save failed " + name)
    print("EDGE_GLOW_CAPTURE: " + name)
