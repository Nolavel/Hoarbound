extends SceneTree
var _failures: int = 0
func _initialize() -> void:
    _run.call_deferred()
func _run() -> void:
    var host := Control.new()
    host.size = Vector2(960, 540)
    root.add_child(host)
    var a := EdgeGlowOverlay.new()
    host.add_child(a)
    await process_frame
    _check(a.mouse_filter == Control.MOUSE_FILTER_IGNORE, "overlay intercepts input")
    _check(not a.visible, "overlay visible outside Hub")
    var mat := a.material as ShaderMaterial
    _check(mat != null, "missing material")
    a.set_reduced_motion(true)
    a.set_hub_active(true)
    a.set_action_active(true)
    await process_frame
    await process_frame
    _check(a.visible and a.get_feedback_state() == EdgeGlowOverlay.STATE_ACTIVE, "active Hub state missing")
    _check(float(mat.get_shader_parameter(&"glow_strength")) > 0.3, "amber too weak")
    a.show_result(true)
    await process_frame
    await process_frame
    var green: Color = mat.get_shader_parameter(&"glow_color")
    _check(green.g > green.r and green.g > green.b, "success is not green")
    a.show_result(false)
    await process_frame
    await process_frame
    var red: Color = mat.get_shader_parameter(&"glow_color")
    _check(red.r > red.g and red.r > red.b, "rejection is not red")
    _check(a.get_feedback_state() == EdgeGlowOverlay.STATE_ACTIVE, "result changed base state")
    a.set_hub_active(false)
    _check(not a.visible and is_zero_approx(float(mat.get_shader_parameter(&"glow_strength"))), "closed Hub retains signal")
    host.free()
    print("test_edge_glow_overlay: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
    quit(1 if _failures > 0 else 0)
func _check(ok: bool, detail: String) -> void:
    if not ok:
        _failures += 1
        push_error("FAIL: " + detail)
