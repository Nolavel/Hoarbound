extends SceneTree

## Cheap, headless presentation contract. It does NOT claim rendered acceptance.
## Run: godot --headless --path . --script res://tests/systems/test_edge_glow_overlay.gd
var _failures: int = 0


func _initialize() -> void:
    _run.call_deferred()


func _run() -> void:
    var host := Control.new()
    host.size = Vector2(300, 120)
    root.add_child(host)
    var a := EdgeGlowOverlay.new()
    var b := EdgeGlowOverlay.new()
    host.add_child(a)
    host.add_child(b)
    await process_frame

    _check(a.mouse_filter == Control.MOUSE_FILTER_IGNORE, "overlay intercepts mouse input")
    _check(a.material is ShaderMaterial and b.material is ShaderMaterial, "missing shader")
    _check(a.material != b.material, "material shared across adjacent slots")
    var mat := a.material as ShaderMaterial
    a.set_feedback_state(EdgeGlowOverlay.STATE_HELD)
    a.set_reduced_motion(true)
    await process_frame
    _check(a.get_feedback_state() == EdgeGlowOverlay.STATE_HELD, "held state was lost")
    _check(float(mat.get_shader_parameter(&"glow_strength")) > 0.3, "held light is off")
    _check(is_zero_approx(float(mat.get_shader_parameter(&"motion_factor"))), "reduced motion still sweeps")

    a.show_refusal()
    await process_frame
    var tint: Color = mat.get_shader_parameter(&"glow_color")
    _check(tint.r > tint.g and tint.r > tint.b, "rejection event was not red")
    _check(a.get_feedback_state() == EdgeGlowOverlay.STATE_HELD, "rejection changed persistent state")
    a.set_feedback_enabled(false)
    await process_frame
    _check(is_zero_approx(float(mat.get_shader_parameter(&"glow_strength"))), "disabled overlay still visible")

    host.free()
    if _failures > 0:
        push_error("edge glow overlay: %d check(s) failed" % _failures)
        quit(1)
    else:
        print("edge glow overlay: all checks passed")
        quit(0)


func _check(ok: bool, detail: String) -> void:
    if not ok:
        _failures += 1
        push_error("edge glow overlay: %s" % detail)
