extends SceneTree

## Five non-overlapping color pulses at black top/bottom edges in 6 seconds (180 rendered frames, 30 fps).
## Reuse the color-grade-blend workflow with the [ambient-glow] commit marker.

const SHADER: String = "res://shaders/ui/ambient_edge_glow.gdshader"
const OUTPUT: String = "res://docs/runtime_previews/ambient_glow"
const FRAMES: int = 180
const FPS: int = 30
const WIDTH: int = 960
const HEIGHT: int = 540
const REVIEW_FRAMES: Array[int] = [18, 54, 90, 126, 162]  # centers of yellow, white, red, green, blue

var _shader_material: ShaderMaterial
var _frames_directory: String


func _initialize() -> void:
    root.content_scale_size = Vector2i(WIDTH, HEIGHT)
    root.size = Vector2i(WIDTH, HEIGHT)
    var shader: Shader = load(SHADER) as Shader
    if shader == null:
        _fail("missing glow shader")
        return
    var glow: ColorRect = ColorRect.new()
    glow.name = "Glow"
    glow.position = Vector2.ZERO
    glow.size = Vector2(WIDTH, HEIGHT)
    glow.color = Color.WHITE
    glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _shader_material = ShaderMaterial.new()
    _shader_material.shader = shader
    glow.material = _shader_material
    root.add_child(glow)
    print("AMBIENT_GLOW_LAYOUT viewport=%s glow=%s" % [root.size, glow.size])
    _frames_directory = ProjectSettings.globalize_path(OUTPUT.path_join("frames"))
    var result: Error = DirAccess.make_dir_recursive_absolute(_frames_directory)
    if result != OK:
        _fail("cannot create frames directory")
        return
    _render_frames.call_deferred()

func _render_frames() -> void:
    for frame: int in range(FRAMES):
        _shader_material.set_shader_parameter("clock_seconds", float(frame) / float(FPS))
        await process_frame
        await RenderingServer.frame_post_draw
        var image: Image = root.get_texture().get_image()
        if image == null or image.get_width() != WIDTH or image.get_height() != HEIGHT:
            _fail("invalid viewport image at frame %d" % frame)
            return
        # Validate the requested behavior from real rendered pixels, not only
        # the existence of an MP4: black center, colored edges, sequential hues.
        if frame in REVIEW_FRAMES:
            var top: Color = image.get_pixel(WIDTH / 2, 12)
            var bottom: Color = image.get_pixel(WIDTH / 2, HEIGHT - 13)
            var center: Color = image.get_pixel(WIDTH / 2, HEIGHT / 2)
            var top_power: float = maxf(top.r, maxf(top.g, top.b))
            var bottom_power: float = maxf(bottom.r, maxf(bottom.g, bottom.b))
            var center_power: float = maxf(center.r, maxf(center.g, center.b))
            var phase: int = REVIEW_FRAMES.find(frame)
            print("AMBIENT_GLOW_PHASE index=%d top=%s bottom=%s center=%s" % [
                phase, top, bottom, center
            ])
            if minf(top_power, bottom_power) < 0.13 or center_power > 0.065:
                _fail("edge or black-center contrast failed for color index %d" % phase)
                return
            match phase:
                0: # Yellow: red + green, little blue.
                    if top.r < top.b * 2.0 or top.g < top.b * 1.6:
                        _fail("yellow pulse not visible")
                        return
                1: # Neutral grey-white rather than any saturated hue.
                    if maxf(absf(top.r - top.g), absf(top.g - top.b)) > 0.17:
                        _fail("grey-white pulse not visible")
                        return
                2:
                    if top.r < top.g * 1.55 or top.r < top.b * 1.55:
                        _fail("red pulse not visible")
                        return
                3:
                    if top.g < top.r * 1.5 or top.g < top.b * 1.25:
                        _fail("green pulse not visible")
                        return
                4:
                    if top.b < top.r * 1.3 or top.b < top.g * 1.3:
                        _fail("blue pulse not visible")
                        return
        var frame_path: String = _frames_directory.path_join("frame_%04d.png" % frame)
        if image.save_png(frame_path) != OK:
            _fail("PNG write failed at frame %d" % frame)
            return
        if frame in REVIEW_FRAMES:
            if image.save_png(ProjectSettings.globalize_path(OUTPUT.path_join("review_%04d.png" % frame))) != OK:
                _fail("review PNG write failed")
                return
    var video_path: String = ProjectSettings.globalize_path(OUTPUT.path_join("ambient_edge_glow_6s.mp4"))
    var args: PackedStringArray = PackedStringArray([
        "-hide_banner", "-loglevel", "error", "-y",
        "-framerate", str(FPS),
        "-i", _frames_directory.path_join("frame_%04d.png"),
        "-frames:v", str(FRAMES),
        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "19",
        "-movflags", "+faststart", video_path
    ])
    var output: Array = []
    var result: int = OS.execute("ffmpeg", args, output, true)
    if result != 0:
        _fail("ffmpeg exit %d: %s" % [result, str(output)])
        return
    var file: FileAccess = FileAccess.open(video_path, FileAccess.READ)
    if file == null or file.get_length() < 1024:
        _fail("encoded MP4 is missing or empty")
        return
    file.close()
    print("AMBIENT_GLOW_CAPTURE_OK frames=%d fps=%d seconds=6 size=%dx%d output=%s renderer=%s" % [
        FRAMES, FPS, WIDTH, HEIGHT, video_path, RenderingServer.get_current_rendering_driver_name()
    ])
    quit(0)


func _fail(message: String) -> void:
    push_error("AMBIENT_GLOW_CAPTURE_FAIL: " + message)
    quit(1)
