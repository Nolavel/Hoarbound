extends SceneTree

## Actual Godot runtime proof of one SHORT WALL RUN over a real collision gap:
## approach -> jump -> left-wall contact -> accelerated crossing -> far-side landing.
## Camera stays in first person, and UI reads the live movement component.
## PNG -> MP4 performed by the CI workflow (not a synthetic video).

const ACTOR = preload("res://tests/demos/wallrun/demo_actor.gd")
const FPS: int = 30
const FRAMES: int = 180
const NEAR_EDGE_Z: float = 1.5
const FAR_EDGE_Z: float = -9.5

var _out: String = "res://docs/runtime_previews/wallrun_demo"
var _actor
var _camera: Camera3D
var _state: Label
var _velocity_text: Label
var _status: Label
var _progress: ProgressBar
var _progress_label: Label
var _starts: int = 0
var _max_speed: float = 0.0
var _min_roll: float = 0.0


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var args := OS.get_cmdline_user_args()
    if not args.is_empty():
        _out = args[0]
    var frames_path := ProjectSettings.globalize_path(_out.path_join("frames"))
    DirAccess.make_dir_recursive_absolute(frames_path)
    Engine.physics_ticks_per_second = FPS
    _build_stage()
    _build_hud()
    _update_camera()

    for frame: int in range(FRAMES):
        await process_frame
        _update_camera()
        _update_hud()
        _max_speed = maxf(_max_speed, _actor.horizontal_speed())
        _min_roll = minf(_min_roll, _actor.camera_roll)
        await RenderingServer.frame_post_draw
        var error := root.get_texture().get_image().save_png(
            frames_path.path_join("f_%03d.png" % frame)
        )
        if error != OK:
            push_error("frame %d: PNG save failed (%d)" % [frame, error])
            quit(2)
            return

    var report := {
        "camera": "FIRST PERSON, left-wall roll from Arena_Stacktrace source sign",
        "walls": 1,
        "gap_m": NEAR_EDGE_Z - FAR_EDGE_Z,
        "frames": FRAMES,
        "fps": FPS,
        "duration_s": float(FRAMES) / FPS,
        "wall_runs_started": _starts,
        "wall_run_side": _actor.last_wall_run_side,
        "gap_entered": _actor.entered_gap,
        "crossed_far_edge": _actor.crossed_gap,
        "landed_on_far_platform": _actor.landed_far,
        "crossed_at_seconds": _actor.crossed_at,
        "landed_at_seconds": _actor.landed_at,
        "min_body_y_while_over_gap": _actor.min_height_over_gap,
        "max_speed_mps": _max_speed,
        "min_camera_roll_deg": _min_roll,
        "runtime": "CharacterBody3D, RayCast3D, ShortWallRun, move_and_slide, CanvasLayer",
    }
    var file := FileAccess.open(ProjectSettings.globalize_path(_out.path_join("report.json")), FileAccess.WRITE)
    if file != null:
        file.store_string(JSON.stringify(report, "  "))
        file.close()
    print("WALLRUN_GAP_REPORT ", JSON.stringify(report))

    # This is not a pass unless the real player crossed the gap and LANDED.
    if _starts != 1 or _actor.last_wall_run_side != -1 or not _actor.entered_gap or not _actor.crossed_gap or not _actor.landed_far or _max_speed < 13.0 or _min_roll > -8.0:
        push_error("wallrun over-gap proof failed; inspect the report / captured frames")
        quit(3)
        return
    quit(0)


func _build_stage() -> void:
    var stage := Node3D.new()
    stage.name = "SingleWallGapCrossing"
    root.add_child(stage)

    var env := WorldEnvironment.new()
    env.environment = Environment.new()
    env.environment.background_mode = Environment.BG_COLOR
    env.environment.background_color = Color(0.085, 0.12, 0.16)
    env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.environment.ambient_light_color = Color(0.62, 0.73, 0.85)
    env.environment.ambient_light_energy = 0.92
    env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    stage.add_child(env)

    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-45.0, -28.0, -5.0)
    sun.light_energy = 1.3
    sun.shadow_enabled = true
    stage.add_child(sun)

    # TWO separate platforms. There is no collision floor between z=1.5
    # and z=-9.5. The only traversable surface over the drop is the LEFT wall.
    _solid(stage, "Approach", Vector3(12.0, 0.4, 18.5), Vector3(4.65, -0.20, 10.75), Color(0.35, 0.43, 0.50), true)
    _solid(stage, "Destination", Vector3(12.0, 0.4, 28.5), Vector3(4.65, -0.20, -23.75), Color(0.32, 0.49, 0.47), true)

    # A deep visible pit floor is 10 m below the path. It is NOT a bridge.
    _solid(stage, "PitBottom_10mDown", Vector3(12.0, 0.2, 11.0), Vector3(4.65, -10.0, -4.0), Color(0.12, 0.15, 0.19), true)
    for i: int in range(7):
        _solid(stage, "DepthMark_%d" % i, Vector3(0.24, 0.06, 0.12),
            Vector3(4.0, -9.82, 0.5 - 1.5 * float(i)), Color(0.34, 0.45, 0.53), false)

    # One wall only. Face lies at x=-1.35, left of the running capsule.
    _solid(stage, "SingleLEFTwall", Vector3(0.60, 8.0, 58.0),
        Vector3(-1.65, 4.0, -9.0), Color(0.29, 0.44, 0.52), true)

    for index: int in range(27):
        var z := 18.0 - 1.8 * float(index)
        _solid(stage, "WallStripe_%02d" % index, Vector3(0.025, 1.40, 0.10),
            Vector3(-1.33, 1.6, z), Color(0.57, 0.73, 0.74), false)

    # Caution stripes marking the actual physical edges of the opening.
    for edge: float in [NEAR_EDGE_Z, FAR_EDGE_Z]:
        for strip: int in range(9):
            var x := -1.1 + float(strip) * 1.32
            _solid(stage, "GapRim", Vector3(1.05, 0.018, 0.14),
                Vector3(x, 0.020, edge + (0.12 if edge == NEAR_EDGE_Z else -0.12)),
                Color(0.96, 0.70, 0.30), false)

    # A green landing guide only exists on the far platform.
    for i: int in range(3):
        _solid(stage, "LandingGuide", Vector3(10.6, 0.014, 0.15),
            Vector3(4.5, 0.021, -11.0 - 0.32 * float(i)),
            Color(0.33, 0.82, 0.62), false)

    _actor = ACTOR.new()
    _actor.name = "PhysicalFpsRunner"
    stage.add_child(_actor)
    _actor.wall_run.wall_run_started.connect(_on_start)

    _camera = Camera3D.new()
    _camera.name = "EyesFirstPerson"
    _camera.current = true
    _camera.fov = 80.0
    stage.add_child(_camera)


func _solid(stage: Node3D, label: String, size: Vector3, pos: Vector3, color: Color, collision: bool) -> void:
    var mesh := MeshInstance3D.new()
    mesh.name = label
    var geometry := BoxMesh.new()
    geometry.size = size
    mesh.mesh = geometry
    var mat := StandardMaterial3D.new()
    mat.albedo_color = color
    mat.roughness = 1.0
    mesh.material_override = mat
    if collision:
        var body := StaticBody3D.new()
        body.name = label
        body.collision_layer = 1
        body.collision_mask = 0
        body.position = pos
        var shape := CollisionShape3D.new()
        var box := BoxShape3D.new()
        box.size = size
        shape.shape = box
        body.add_child(shape)
        body.add_child(mesh)
        stage.add_child(body)
    else:
        mesh.position = pos
        stage.add_child(mesh)


func _build_hud() -> void:
    var canvas := CanvasLayer.new()
    canvas.name = "LiveWallRunHUD"
    root.add_child(canvas)

    var ui := Control.new()
    ui.size = root.get_visible_rect().size
    ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
    canvas.add_child(ui)
    var w := ui.size.x
    var h := ui.size.y

    var band := ColorRect.new()
    band.color = Color(0.035, 0.075, 0.11, 0.83)
    band.position = Vector2.ZERO
    band.size = Vector2(w, 134)
    ui.add_child(band)

    _label(ui, Vector2(36, 16), 46, Color(0.99, 0.93, 0.74), "SINGLE WALL / 11 m GAP")
    _label(ui, Vector2(37, 80), 26, Color(0.72, 0.87, 0.94), "FIRST PERSON   ·   REAL PHYSICS   ·   LEFT WALL ONLY")

    _progress_label = _label(ui, Vector2(w - 625, 23), 25, Color(0.95, 0.85, 0.66), "WALL CONTACT / TIME LEFT")
    _progress = ProgressBar.new()
    _progress.position = Vector2(w - 625, 68)
    _progress.size = Vector2(550, 28)
    _progress.min_value = 0.0
    _progress.max_value = 100.0
    _progress.show_percentage = false
    var empty := StyleBoxFlat.new()
    empty.bg_color = Color(0.17, 0.25, 0.29)
    var fill := StyleBoxFlat.new()
    fill.bg_color = Color(0.95, 0.67, 0.27)
    _progress.add_theme_stylebox_override("background", empty)
    _progress.add_theme_stylebox_override("fill", fill)
    ui.add_child(_progress)

    _state = _label(ui, Vector2(40, h - 148), 37, Color(0.99, 0.91, 0.72), "APPROACH / SPRINT")
    _velocity_text = _label(ui, Vector2(42, h - 94), 26, Color(0.81, 0.94, 0.94), "")
    _status = _label(ui, Vector2(w - 530, h - 94), 26, Color(0.87, 0.94, 0.76), "")


func _label(ui: Control, pos: Vector2, size: int, color: Color, value: String) -> Label:
    var txt := Label.new()
    txt.position = pos
    txt.text = value
    txt.add_theme_font_size_override("font_size", size)
    txt.add_theme_color_override("font_color", color)
    ui.add_child(txt)
    return txt


func _update_camera() -> void:
    # Correct sign from Arena_Stacktrace: with the wall on the LEFT, normal +X,
    # right.dot(normal)>0, so the intended camera roll is NEGATIVE.
    # The camera is at the runner's EYES, not trailing behind as in the old TPS clip.
    _camera.global_position = _actor.global_position + Vector3(0.0, 0.65, -0.08)
    _camera.rotation_degrees = Vector3(-14.0, 0.0, 0.0)
    _camera.rotate_object_local(Vector3.BACK, deg_to_rad(_actor.camera_roll))


func _update_hud() -> void:
    _state.text = _actor.phase_caption
    _velocity_text.text = "SPEED   %04.1f m/s     |     CAMERA ROLL   %+04.1f deg" % [
        _actor.horizontal_speed(), _actor.camera_roll
    ]
    _progress.value = _actor.remaining_ratio * 100.0
    _progress.visible = _actor.wall_run.is_running
    _progress_label.visible = _actor.wall_run.is_running
    if _actor.landed_far:
        _status.text = "GAP CLEARED / LANDED"
    elif _actor.crossed_gap:
        _status.text = "FAR EDGE REACHED"
    elif _actor.entered_gap:
        _status.text = "OVER THE DROP"
    else:
        _status.text = "11 METRES AHEAD"


func _on_start(side: int) -> void:
    _starts += 1
    print("WALLRUN_START side=%d at %.3fs z=%.3f" % [side, _actor.elapsed, _actor.global_position.z])
